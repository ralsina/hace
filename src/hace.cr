require "commander"
require "crinja"
require "croupier"
require "log"
require "yaml"

include Croupier

module Hace
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}

  # Parser for Hacefile.yml
  class HaceFile
    include YAML::Serializable
    include YAML::Serializable::Strict

    property tasks : Hash(String, CommandTask) = {} of String => CommandTask
    property variables : Hash(String, YAML::Any) = {} of String => YAML::Any
    property env = {} of String => String?

    def self.load_file(filename)
      begin
        if !File.exists?(filename)
          raise "No Hacefile '#{filename}' found"
        end
        f = Hace::HaceFile.from_yaml(File.read(filename))
        ENV.each { |k, v| f.env[k] = v }
      rescue ex
        raise "Error parsing Hacefile '#{filename}': #{ex}"
      end
      f
    end

    def self.run(
      arguments = [] of String,
      filename = "Hacefile.yml",
      run_all : Bool = false,
      dry_run : Bool = false,
      question : Bool = false,
      keep_going : Bool = false
    )
      hacefile = load_file(filename)

      # Extract variable assignments from arguments
      vars = arguments.select { |arg| arg =~ /^(\w+)=(.*)$/ }
      arguments -= vars

      # Set variables in hacefile
      vars.map do |var|
        key, value = var.split("=", 2)
        hacefile.variables[key] = YAML::Any.new(value)
      end

      if TaskManager.tasks.empty?
        hacefile.gen_tasks
      end

      Log.debug { "Requested tasks: #{arguments.join(", ")}" }
      real_arguments = process_arguments(hacefile, arguments)
      Log.info { "Running tasks with targets: #{real_arguments.join(", ")}" }

      if real_arguments.empty?
        # There are no requested, non-bogus or default tasks
        Log.info { "No tasks to run" }
        return 0
      end

      # FIXME: see if this works when given `arguments`
      if question
        stale_tasks = TaskManager.tasks.values.select(&.stale?).select { |task|
          (real_arguments.includes? task.id) || (!(real_arguments & task.outputs).empty?)
        }
        if stale_tasks.empty?
          Log.info { "No stale tasks found" }
          return 0
        end
        Log.info { "Stale tasks found:" }
        stale_tasks.each do |task|
          Log.info { "👉 #{task.id}" }
        end
        return 1
      end

      TaskManager.run_tasks(real_arguments, run_all: run_all, dry_run: dry_run, keep_going: keep_going)
      Log.info { "Finished" }
      0 # exit code
    end

    def self.process_arguments(hacefile, arguments : Array(String))
      # If no tasks are specified, run only default tasks
      if arguments.empty?
        Log.info { "Using default tasks" }
        hacefile.tasks.each do |name, task|
          if task.@default
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
            p_args += task.@outputs
            # For phony tasks (no outputs) use the task name as argument
            p_args << name if task.@phony
            # If the argument is an output of a task, add the argument
          elsif task.@outputs.includes?(arg)
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

    def gen_tasks
      @tasks.each do |name, task|
        task.gen_task(name, variables, env)
      end
    end

    def self.auto(
      arguments = [] of String,
      filename = "Hacefile.yml"
    )
      # TODO: implement the other flags and arguments
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
        sleep 1
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

    def to_hash
      # Yes, not pretty but this gives me the right types for merging
      # with variables, so I can use it in Crinja.render
      YAML.parse(self.to_yaml)
    end

    def gen_task(name, variables, env)
      # phony tasks have no outputs.
      # tasks where outputs are not specified have only one output, the task name

      if @phony && !@outputs.empty?
        Log.warn { "Task #{name} is phony but has outputs #{@outputs}. Outputs will be ignored." }
        @outputs = [] of String
      end
      @outputs = @phony ? [] of String : [name] if @outputs.empty?

      commands = @commands.split("\n").map(&.strip).reject(&.empty?)
      context = {"self" => self.to_hash}.merge variables

      Task.new(
        outputs: @outputs,
        inputs: @dependencies,
        # Marking task as not mergeable until we have a way to
        # handle tasks that share an output correctly
        mergeable: false,
        no_save: true,
        always_run: @always_run,
        proc: TaskProc.new {
          Log.info { "Started task: #{name}" }
          commands.map do |command|
            # Expand variables
            command = Crinja.render(command, context)
            # Expand environment variables
            command = command.gsub(/\$\{?(\w+)\}?/) do |match|
              env_key = $1
              env.fetch(env_key) { match }
            end
            Log.info { "Running command: #{command}" }
            status = Process.run(
              command: command,
              shell: true,
              env: env,
              input: Process::Redirect::Inherit,
              output: Process::Redirect::Inherit,
              error: Process::Redirect::Inherit,
            )
            raise "Command failed: exit #{status.exit_code} when running #{command}" unless status.success?
            status.to_s
          end
          Log.info { "Finished task: #{name}" }
        },
        id: name,
      )
    end
  end
end
