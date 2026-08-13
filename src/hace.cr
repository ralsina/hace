require "crinja"
require "crinja/yaml"
require "croupier"
require "log"
require "yaml"
require "dotenv"

include Croupier

module Hace
  VERSION     = {{ `shards version #{__DIR__}`.chomp.stringify }}
  VARIABLES   = {} of String => YAML::Any
  ENVIRONMENT = {} of String => String

  # Track which tasks explicitly use {{CLI_ARGS}} (detected before Crinja expansion)
  TASKS_WITH_CLI_ARGS = Set(String).new

  extend self

  # Clear the module-level mutable state (VARIABLES, ENVIRONMENT and the
  # CLI_ARGS tracking set). Intended for use between test scenarios so that
  # values injected by one run (CLI_ARGS, Hacefile variables, env entries) do
  # not leak into the next. Mirrors Croupier::TaskManager.cleanup.
  def self.reset_state
    VARIABLES.clear
    ENVIRONMENT.clear
    TASKS_WITH_CLI_ARGS.clear
  end

  # Convert YAML::Any values to Crinja-compatible values
  # This is needed because Crinja::Value.new(YAML::Any) doesn't properly
  # unwrap the value due to overload resolution favoring the Raw type
  def self.to_crinja_value(value : YAML::Any) : Crinja::Value
    Crinja.value(value)
  end

  def self.to_crinja_value(value) : Crinja::Value
    Crinja.value(value)
  end

  # Convert a Hash(String, YAML::Any) to Crinja::Variables
  def self.to_crinja_variables(hash : Hash(String, YAML::Any)) : Crinja::Variables
    Crinja::Variables.new.tap do |vars|
      hash.each do |key, value|
        vars[key] = to_crinja_value(value)
      end
    end
  end

  # Inject CLI_ARGS and CLI_ARGS_LIST into VARIABLES for template expansion
  def self.inject_cli_args(cli_args : Array(String))
    # CLI_ARGS: shell-quoted string for direct shell usage
    cli_args_string = cli_args.map { |arg| Process.quote(arg) }.join(" ")
    VARIABLES["CLI_ARGS"] = YAML::Any.new(cli_args_string)

    # CLI_ARGS_LIST: array for Jinja iteration
    cli_args_list = cli_args.map { |arg| YAML::Any.new(arg) }
    VARIABLES["CLI_ARGS_LIST"] = YAML::Any.new(cli_args_list)
  end

  # This parses only env and variables, not tasks
  class PartialHaceFile
    include YAML::Serializable
    property variables : Hash(String, YAML::Any) = {} of String => (YAML::Any)
  end

  # Parser for Hacefile.yml
  class HaceFile
    include YAML::Serializable
    include YAML::Serializable::Strict

    property tasks : Hash(String, CommandTask) = {} of String => CommandTask
    property variables : Hash(String, YAML::Any) = {} of String => YAML::Any
    property env = {} of String => String?
    property shell : String? = nil

    def self.load_file(filename)
      begin
        if !File.exists?(filename)
          raise "No Hacefile '#{filename}' found"
        end

        # Load .env file if it exists
        Hace.load_dotenv

        # The PartialFile contains data needed to render the file
        # which is actually a template
        data = File.read(filename)
        p = Hace::PartialHaceFile.from_yaml(data)

        # Detect which tasks explicitly use CLI_ARGS BEFORE Crinja expansion
        # This is needed because Crinja will replace {{CLI_ARGS}} with actual values
        detect_cli_args_usage(data)

        # Merge Hacefile variables with global VARIABLES (includes CLI_ARGS if already set)
        render_context = p.variables.merge(Hace::VARIABLES)

        # Render entire file at once to support multi-line Jinja control structures
        rendered_data = begin
          Crinja.render(data, Hace.to_crinja_variables(render_context))
        rescue
          data
        end

        f = Hace::HaceFile.from_yaml(rendered_data)
        ENV.each { |k, v| Hace::ENVIRONMENT[k] = v }
        f.env.each { |k, v|
          if v.nil?
            Hace::ENVIRONMENT.delete(k)
          else
            Hace::ENVIRONMENT[k] = v
          end
        }

        # Variables support ENV variable expansion
        f.variables.each { |k, v|
          VARIABLES[k] = YAML.parse(Hace.expand_string(v.to_yaml))
        }

        # Tasks support expansion
        f.tasks.each { |_, task| task.expand }
      rescue ex
        raise "Error parsing Hacefile '#{filename}': #{ex}"
      end
      f
    end

    # Detect which tasks explicitly use CLI_ARGS before Crinja expansion
    # Parses raw YAML to find task commands containing {{CLI_ARGS}} patterns
    private def self.detect_cli_args_usage(raw_data : String)
      Hace::TASKS_WITH_CLI_ARGS.clear

      begin
        yaml = YAML.parse(raw_data)
        tasks = yaml["tasks"]?
        return unless tasks

        tasks.as_h.each do |name, task|
          commands = task["commands"]?
          next unless commands

          cmd_str = commands.as_s
          if cmd_str.matches?(/\{\{\s*CLI_ARGS(_LIST)?\s*\}\}/)
            Hace::TASKS_WITH_CLI_ARGS.add(name.as_s)
            Log.debug { "detect_cli_args_usage: task '#{name}' uses CLI_ARGS" }
          end
        end
      rescue ex
        Log.debug { "detect_cli_args_usage: error parsing YAML: #{ex}" }
      end
    end

    # Configuration structure for task execution
    private struct ExecutionSetup
      def initialize(
        @hacefile : HaceFile,
        @arguments : Array(String),
        @filename : String,
        @cli_args : Array(String),
        @run_all : Bool,
        @dry_run : Bool,
        @question : Bool,
        @keep_going : Bool,
        @parallel : Bool,
      )
      end

      getter hacefile : HaceFile
      getter arguments : Array(String)
      getter filename : String
      getter cli_args : Array(String)
      getter? run_all : Bool
      getter? dry_run : Bool
      getter? question : Bool
      getter? keep_going : Bool
      getter? parallel : Bool

      def self.from_arguments(
        arguments : Array(String),
        filename : String,
        cli_args : Array(String),
        run_all : Bool,
        dry_run : Bool,
        question : Bool,
        keep_going : Bool,
        parallel : Bool,
      )
        # Inject CLI_ARGS BEFORE loading (so they're available during task expansion)
        Hace.inject_cli_args(cli_args)

        hacefile = HaceFile.load_file(filename)

        # Extract and apply variable assignments from arguments
        arguments, hacefile = extract_and_apply_variables(arguments, hacefile)

        # Generate tasks if not already done
        if TaskManager.tasks.empty?
          hacefile.gen_tasks(dry_run)
        end

        new(
          hacefile: hacefile,
          arguments: arguments,
          filename: filename,
          cli_args: cli_args,
          run_all: run_all,
          dry_run: dry_run,
          question: question,
          keep_going: keep_going,
          parallel: parallel
        )
      end

      private def self.extract_and_apply_variables(arguments : Array(String), hacefile : HaceFile)
        # Extract variable assignments from arguments (format: KEY=value)
        vars = arguments.select { |arg| arg =~ /^(\w+)=(.*)$/ }
        clean_arguments = arguments - vars

        # Apply variables to hacefile
        vars.each do |var|
          key, value = var.split("=", 2)
          hacefile.variables[key] = YAML::Any.new(value)
        end

        {clean_arguments, hacefile}
      end
    end

    def self.run(
      arguments = [] of String,
      filename = "Hacefile.yml",
      cli_args = [] of String,
      run_all : Bool = false,
      dry_run : Bool = false,
      question : Bool = false,
      keep_going : Bool = false,
      parallel : Bool = false,
    )
      setup = ExecutionSetup.from_arguments(
        arguments: arguments,
        filename: filename,
        cli_args: cli_args,
        run_all: run_all,
        dry_run: dry_run,
        question: question,
        keep_going: keep_going,
        parallel: parallel
      )

      # Handle question mode early since it has different execution path
      return handle_question_mode(setup) if setup.question?

      # Resolve targets and handle empty case
      targets = resolve_targets(setup)
      return handle_no_targets(setup) if targets.empty?

      # Execute the tasks
      execute_tasks(targets, setup)
    end

    private def self.resolve_targets(setup : ExecutionSetup)
      Log.debug { "Requested tasks: #{setup.arguments.join(", ")}" }

      # Process arguments to resolve task targets (handles default task logic internally)
      real_arguments = process_arguments(setup.hacefile, setup.arguments)
      Log.info { "Running tasks with targets: #{real_arguments.join(", ")}" }

      Set.new(real_arguments).to_a
    end

    private def self.handle_question_mode(setup : ExecutionSetup)
      targets = resolve_targets(setup)

      if targets.empty?
        Log.info { "No tasks to check" }
        return 0
      end

      stale_tasks = find_stale_tasks(targets)

      if stale_tasks.empty?
        Log.info { "No stale tasks found" }
        return 0
      end

      Log.info { "Stale tasks found:" }
      stale_tasks.each do |task|
        Log.info { "👉 #{task.id}" }
      end
      1
    end

    private def self.handle_no_targets(setup : ExecutionSetup)
      Log.info { "No tasks to run" }
      0
    end

    private def self.execute_tasks(targets : Array(String), setup : ExecutionSetup)
      Log.info { "Running tasks with parallel=#{setup.parallel?}" }

      TaskManager.run_tasks(
        targets,
        run_all: setup.run_all?,
        dry_run: setup.dry_run?,
        keep_going: setup.keep_going?,
        parallel: setup.parallel?
      )

      Log.info { "Finished" }
      0
    end

    private def self.find_stale_tasks(targets : Array(String))
      TaskManager.tasks.values
        .select(&.stale?)
        .select { |task|
          (targets.includes? task.id) || (!(targets & task.outputs).empty?)
        }
    end

    def self.process_arguments(hacefile, arguments : Array(String))
      # If no tasks are specified, run only default tasks
      if arguments.empty?
        Log.info { "Using default tasks" }
        hacefile.tasks.each do |name, task|
          if task.default?
            arguments << name
          end
        end
      end

      real_arguments = [] of String

      arguments.each do |arg|
        p_args = [] of String
        hacefile.tasks.each do |name, task|
          if arg == name
            # For non-phony tasks, use the outputs as arguments
            p_args += task.outputs
            # For phony tasks (no outputs) use the task name as argument
            p_args << name if task.phony?
            # If the argument is an output of a task, add the argument
          elsif task.outputs.includes?(arg)
            p_args << arg
          end
        end
        # Tasks that generate no argument don't exist
        if p_args.empty?
          Log.warn { "Task #{arg} not found" }
        end
        real_arguments += p_args
      end
      real_arguments = Set.new(real_arguments).to_a
    end

    def gen_tasks(dry_run : Bool = false)
      @tasks.each do |name, task|
        task.gen_task(name, self, dry_run)
      end
    end

    def self.auto(
      arguments = [] of String,
      filename = "Hacefile.yml",
      cli_args = [] of String,
    )
      # Inject CLI_ARGS BEFORE loading (so they're available during task expansion)
      Hace.inject_cli_args(cli_args)

      hacefile = load_file(filename)
      hacefile.gen_tasks
      begin
        real_arguments = process_arguments(hacefile, arguments)
        Log.info { "Running tasks: #{arguments.join(", ")}" }
        TaskManager.auto_run(real_arguments)
      rescue ex
        Log.error { ex }
        return 1
      end
      Log.info { "Running in auto mode, press Ctrl+C to stop" }
      loop do
        ::sleep 1.seconds
      end
    end
  end

  # A task that runs a shell command
  class CommandTask
    include YAML::Serializable
    include YAML::Serializable::Strict

    @commands : String
    @dependencies : Array(String) = [] of String
    @phony : Bool = false
    @default : Bool = false
    @outputs : Array(String) = [] of String
    @always_run : Bool = false
    @cwd : String? = nil
    @description : String? = nil
    @shell : String? = nil

    # Read-only accessors so callers don't have to reach into instance vars.
    getter commands : String
    getter dependencies : Array(String)
    getter outputs : Array(String)
    getter description : String?
    getter cwd : String?
    getter shell : String?
    getter? phony : Bool
    getter? default : Bool
    getter? always_run : Bool

    def to_hash
      # Yes, not pretty but this gives me the right types for merging
      # with variables, so I can use it in Crinja.render
      YAML.parse(to_yaml).as_h
    end

    # We want to support variables and environment variables also in things
    # like dependencies, outputs, etc. so we need to do some post-processing
    #
    # Besides the global VARIABLES, they also have access to self
    def expand
      # Build variables hash maintaining proper types for Crinja
      variables = Hace::VARIABLES.dup
      variables["self"] = YAML.parse(to_yaml)

      @outputs = @outputs.map { |outp| Hace.expand_string(outp, variables) }
      variables["self"] = YAML.parse(to_yaml)

      # Dependencies expand both variables and globs
      @dependencies = @dependencies.map { |dep| Hace.expand_string(dep, variables) }
      @dependencies = @dependencies.flat_map { |dep| Hace.expand_glob(dep) }
      variables["self"] = YAML.parse(to_yaml)
      @commands = Hace.expand_string(@commands, variables)
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def gen_task(name, hacefile : HaceFile, dry_run : Bool = false)
      # phony tasks have no outputs.
      # tasks where outputs are not specified have only one output, the task name

      if @phony && !@outputs.empty?
        Log.warn { "Task #{name} is phony but has outputs #{@outputs}. Outputs will be ignored." }
        @outputs = [] of String
      end
      @outputs = @phony ? [] of String : [name] if @outputs.empty?
      commands = @commands.split("\n").map(&.strip).reject(&.empty?)

      # In dry-run mode, show what would be executed before creating the task
      if dry_run
        puts "\n🔍 Task: #{name}".colorize(:cyan)
        puts "   Working Directory: #{@cwd || "current"}"
        puts "   Commands to execute:"
        commands.each_with_index do |command, i|
          puts "     #{i + 1}. #{command}".colorize(:yellow)
        end
        puts "   Dependencies: #{@dependencies.empty? ? "none" : @dependencies.join(", ")}"
        puts "   Outputs: #{@outputs.empty? ? "none" : @outputs.join(", ")}"
        puts "   Phony: #{@phony ? "yes" : "no"}"
        puts "   Always Run: #{@always_run ? "yes" : "no"}"
        puts ""
      end

      Task.new(
        outputs: @outputs,
        inputs: @dependencies,
        # Tasks with different outputs can be merged for parallel execution
        mergeable: true,
        no_save: true,
        always_run: @always_run,
        proc: TaskProc.new {
          Log.info { "Started task: #{name}" }
          cwd = @cwd.nil? ? Dir.current : @cwd.as(String)
          Dir.cd cwd do
            if dry_run
              # In dry-run mode, show each command that would be executed
              commands.each do |command|
                puts "Would run: #{command}".colorize(:yellow)
                Log.info { "DRY-RUN: Would run command: #{command}" }
              end
              "dry_run_success"
            else
              # Determine which shell to use
              task_shell = @shell || hacefile.shell || "/bin/sh"
              Log.debug { "Using shell: #{task_shell}" }

              # Build combined shell script
              combined_script = commands.join("\n")

              # Hybrid auto-append: if CLI_ARGS not explicitly used, append to last command
              # Uses pre-Crinja detection from TASKS_WITH_CLI_ARGS set
              uses_explicit_cli_args = Hace::TASKS_WITH_CLI_ARGS.includes?(name)
              if !uses_explicit_cli_args
                cli_args_list = Hace::VARIABLES["CLI_ARGS_LIST"]?.try(&.as_a?)
                if cli_args_list && !cli_args_list.empty?
                  quoted_args = cli_args_list.map { |arg| Process.quote(arg.as_s) }.join(" ")
                  lines = combined_script.split("\n")
                  lines[-1] = lines[-1] + " " + quoted_args
                  combined_script = lines.join("\n")
                  Log.debug { "Auto-appended CLI_ARGS to last command: #{quoted_args}" }
                end
              end

              # Log individual commands for debugging
              commands.each do |command|
                Log.info { "Running command: #{command}" }
              end

              # Parse shell and arguments (user is responsible for proper shell configuration)
              shell_parts = task_shell.split(" ")
              shell_cmd = shell_parts[0]
              shell_args = shell_parts.size > 1 ? shell_parts[1..-1] : [] of String

              # Add the script arguments
              if shell_args.empty?
                # If using default shell (/bin/sh), add -e for fail-fast, otherwise just -c
                if task_shell == "/bin/sh"
                  shell_args = ["-e", "-c", combined_script]
                else
                  shell_args = ["-c", combined_script]
                end
              else
                # User provided shell with args - add -c and script if not present
                c_index = shell_args.index("-c")
                if c_index
                  # Replace the -c with -c and the script as next argument
                  shell_args.insert(c_index + 1, combined_script)
                else
                  # No -c found, add it
                  shell_args << "-c" << combined_script
                end
              end

              # Execute combined script in shell process
              status = Process.run(
                command: shell_cmd,
                args: shell_args,
                env: Hace::ENVIRONMENT,
                input: Process::Redirect::Inherit,
                output: Process::Redirect::Inherit,
                error: Process::Redirect::Inherit,
              )
              unless status.success?
                # Simple error message - the combined script failed
                raise "Command failed: exit #{status.exit_code}"
              end
              status.to_s
            end
          end
          Log.info { "Finished task: #{name}" }
        },
        id: name,
      )
    end
  end

  def self.expand_string(str : String, variables = Hace::VARIABLES) : String
    # Expand variables
    str = Crinja.render(str, to_crinja_variables(variables))
    # Expand environment variables
    str = str.gsub(/\$\{?(\w+)\}?/) do |match|
      env_key = $1
      ENV.fetch(env_key) { match }
    end
  end

  def self.expand_glob(str : String) : Array(String)
    expanded = Dir.glob(str).to_a
    return expanded unless expanded.empty?
    [str]
  end

  def self.load_dotenv(dotenv_file = nil)
    if dotenv_file
      # Load specified dotenv file
      if File.exists?(dotenv_file)
        Log.info { "Loading environment from: #{dotenv_file}" }
        Dotenv.load(dotenv_file)
      else
        Log.warn { "Dotenv file not found: #{dotenv_file}" }
      end
    else
      # Look for .env file in current directory
      default_env = File.join(Dir.current, ".env")
      if File.exists?(default_env)
        Log.info { "Loading environment from: #{default_env}" }
        Dotenv.load(default_env)
      end
    end
  end
end
