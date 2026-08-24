require "crinja"
require "crinja/yaml"
require "croupier"
require "digest"
require "log"
require "yaml"
require "dotenv"
require "./makefile"

include Croupier

module Hace
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}

  # A variable value. Variables may be defined as any scalar or nested
  # structure in the Hacefile, so this recursive union is the single typed
  # representation used everywhere past the YAML parsing boundary.
  alias Value = Bool? | Int64 | Float64 | String | Array(Value) | Hash(String, Value)

  VARIABLES   = {} of String => Value
  ENVIRONMENT = {} of String => String

  # Track which tasks explicitly use CLI_ARGS (detected before Crinja expansion)
  TASKS_WITH_CLI_ARGS = Set(String).new

  # Environment variable names that already produced a deprecation warning
  # (${NAME} expansion, brace-less $NAME in non-command fields), so each is
  # reported at most once per run.
  DEPRECATED_ENV_WARNED = Set(String).new

  # Shells that understand POSIX fail-fast (-e). When a task or Hacefile
  # selects one of these shells *without* explicit arguments, hace runs the
  # commands with "-e -c" so multi-command tasks stop at the first failure,
  # matching the default /bin/sh behavior. Other shells (python, cmd.exe, ...)
  # only get the script passed via -c.
  FAIL_FAST_SHELLS = %w[sh bash zsh dash ash ksh mksh]

  extend self

  # Raised when the user requests a task that is not defined in the Hacefile.
  # Exiting non-zero on typos matters for scripts and CI pipelines.
  class UnknownTaskError < Exception
    def initialize(unknown_tasks : Array(String), available_tasks : Array(String))
      super(
        "Unknown task(s): #{unknown_tasks.join(", ")}. " \
        "Available tasks: #{available_tasks.join(", ")}"
      )
    end
  end

  # Recipe stamps make the rendered recipe part of the staleness model.
  #
  # Croupier only considers missing outputs, input file hashes and upstream
  # staleness, so editing a task's commands in the Hacefile would never
  # trigger a rebuild. To fix that, every task gets an extra input: a small
  # file whose content is the SHA1 of its commands, shell and working
  # directory. When the recipe changes, the stamp content changes, and the
  # regular input-hash comparison marks the task stale.
  RECIPE_STAMP_DIR = ".hace"

  def self.recipe_stamp_path(task_name : String) : String
    File.join(RECIPE_STAMP_DIR, Digest::SHA1.hexdigest(task_name))
  end

  # Record the current recipe signature for *task_name* and return the stamp
  # path. Writing is skipped when the content is unchanged so the file's
  # mtime stays stable (mtime-based staleness modes would otherwise see it
  # as modified on every run). Failures degrade gracefully: the returned
  # path then simply does not exist, which scan_inputs skips, giving the
  # old behavior without recipe sensitivity.
  def self.stamp_recipe(task_name : String, signature : String) : String
    Dir.mkdir_p(RECIPE_STAMP_DIR)
    path = recipe_stamp_path(task_name)
    digest = Digest::SHA1.hexdigest(signature)
    previous = File.exists?(path) ? File.read(path) : nil
    File.write(path, digest) unless previous == digest
    path
  rescue ex
    Log.warn { "Could not record recipe stamp for '#{task_name}': #{ex.message}" }
    File.join(RECIPE_STAMP_DIR, "unwritable")
  end

  # Clear the module-level mutable state (VARIABLES, ENVIRONMENT, the
  # CLI_ARGS tracking set and the env-deprecation warning set). Intended for
  # use between test scenarios so that values injected by one run (CLI_ARGS,
  # Hacefile variables, env entries) do not leak into the next. Mirrors
  # Croupier::TaskManager.cleanup.
  def self.reset_state
    VARIABLES.clear
    ENVIRONMENT.clear
    TASKS_WITH_CLI_ARGS.clear
    DEPRECATED_ENV_WARNED.clear
  end

  # Convert a parsed YAML node into the typed Value representation.
  # This is the single place where YAML::Any is allowed to exist.
  def self.from_yaml_any(any : YAML::Any) : Hace::Value
    case raw = any.raw
    when Nil, Bool, Int64, Float64
      raw
    when String
      raw
    when Array(YAML::Any)
      raw.map { |item| Hace.from_yaml_any(item) }
    when Hash(YAML::Any, YAML::Any)
      converted = {} of String => Hace::Value
      raw.each do |key, val|
        # Nested map keys are stringified so the structure stays Hash(String, Value)
        key_string = key.raw.is_a?(String) ? key.as_s : key.to_s
        converted[key_string] = Hace.from_yaml_any(val)
      end
      converted
    else
      raise "Unsupported variable value: #{any.inspect}"
    end
  end

  # Expand the deprecated ${ENV_VAR} references inside a value and
  # everything nested in it, leaving non-string values untouched. Warns when
  # a brace-less $ENV_VAR reference would have expanded before (only names
  # that resolve in the merged environment, to keep noise down).
  def self.expand_env_in_value(value : Hace::Value) : Hace::Value
    case value
    when String
      Hace.warn_braceless_env_ref(value)
      Hace.expand_env_vars(value)
    when Array(Hace::Value)
      value.map { |item| Hace.expand_env_in_value(item) }
    when Hash(String, Hace::Value)
      value.transform_values { |val| Hace.expand_env_in_value(val) }
    else
      value
    end
  end

  def self.to_crinja_value(value : Hace::Value) : Crinja::Value
    case value
    when Nil, Bool, Int64, Float64, String
      Crinja.value(value)
    when Array(Hace::Value)
      Crinja.value(value.map { |item| Hace.to_crinja_value(item) })
    when Hash(String, Hace::Value)
      converted = {} of String => Crinja::Value
      value.each do |key, val|
        converted[key] = Hace.to_crinja_value(val)
      end
      Crinja.value(converted)
    else
      raise "Unsupported variable value: #{value.inspect}"
    end
  end

  # Convert a Hash(String, Value) to Crinja::Variables
  def self.to_crinja_variables(hash : Hash(String, Value)) : Crinja::Variables
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
    VARIABLES["CLI_ARGS"] = cli_args_string

    # CLI_ARGS_LIST: array for Jinja iteration
    cli_args_list = cli_args.map { |arg| arg.as(Hace::Value) }
    VARIABLES["CLI_ARGS_LIST"] = cli_args_list
  end

  # This parses only env and variables, not tasks
  class PartialHaceFile
    include YAML::Serializable
    property variables : Hash(String, YAML::Any) = {} of String => (YAML::Any)
    property env = {} of String => String?
  end

  # Bridges the recursive Value union through YAML::Serializable so HaceFile
  # keeps strict deserialization while exposing typed variables.
  class ValueConverter
    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Hash(String, Hace::Value)
      value = Hace.from_yaml_any(YAML::Any.new(ctx, node))
      unless value.is_a?(Hash(String, Hace::Value))
        node.raise "Expected a mapping of variable names to values"
      end
      value
    end

    def self.to_yaml(variables : Hash(String, Hace::Value), builder : YAML::Nodes::Builder)
      builder.mapping do
        variables.each do |key, value|
          builder.scalar(key)
          write_value(value, builder)
        end
      end
    end

    private def self.write_value(value : Hace::Value, builder : YAML::Nodes::Builder)
      case value
      when Array(Hace::Value)
        builder.sequence do
          value.each { |item| write_value(item, builder) }
        end
      when Hash(String, Hace::Value)
        builder.mapping do
          value.each do |key, val|
            builder.scalar(key)
            write_value(val, builder)
          end
        end
      else
        builder.scalar(value)
      end
    end
  end

  # Parser for Hacefile.yml
  class HaceFile
    include YAML::Serializable
    include YAML::Serializable::Strict

    property tasks : Hash(String, CommandTask) = {} of String => CommandTask

    property patterns : Array(PatternRule) = [] of PatternRule

    @[YAML::Field(converter: Hace::ValueConverter)]
    property variables : Hash(String, Value) = {} of String => Value

    property env = {} of String => String?
    property shell : String? = nil

    # Config file to use when none was given explicitly: prefer Hacefile.yml,
    # falling back to a Makefile in the current directory so hace works out
    # of the box in make-based projects.
    def self.default_filename : String
      return "Hacefile.yml" if File.exists?("Hacefile.yml")
      MakefileConverter::MAKEFILE_NAMES.each do |name|
        return name if File.exists?(name)
      end
      "Hacefile.yml"
    end

    def self.load_file(filename, variable_overrides : Hash(String, String) = {} of String => String)
      # Checked outside the rescue below so the message stays accurate
      # instead of being wrapped as a parsing failure.
      raise "No Hacefile '#{filename}' found" unless File.exists?(filename)

      begin
        # Load .env file if it exists
        Hace.load_dotenv

        # The PartialFile contains data needed to render the file
        # which is actually a template
        data = File.read(filename)

        # A Makefile is converted to Hacefile YAML up front; from here on it
        # flows through exactly the same pipeline as a native Hacefile.
        if MakefileConverter.looks_like_makefile?(filename)
          Log.info { "'#{filename}' looks like a Makefile, converting on the fly" }
          data = MakefileConverter.convert(data)
        end

        # Seed the merged environment view from the process environment
        # (including anything dotenv just loaded). It is exposed as the `env`
        # template namespace ({{ env.NAME }}) BEFORE any rendering, so
        # {{ env.NAME }} resolves everywhere: whole-file render, variables
        # and task fields.
        Hace::ENVIRONMENT.clear
        ENV.each { |key, value| Hace::ENVIRONMENT[key] = value }

        p = Hace::PartialHaceFile.from_yaml(data)

        # Detect which tasks explicitly use CLI_ARGS BEFORE Crinja expansion
        # This is needed because Crinja will replace {{CLI_ARGS}} with actual values
        detect_cli_args_usage(data)

        # Convert the raw variables section, then merge with global VARIABLES
        # (includes CLI_ARGS and KEY=value overrides if already set). Globals
        # win, so command-line overrides take precedence over Hacefile defaults.
        file_variables = {} of String => Hace::Value
        p.variables.each do |key, any_value|
          file_variables[key] = Hace.from_yaml_any(any_value)
        end
        if file_variables.has_key?("env") || variable_overrides.has_key?("env")
          Log.warn { "Variable name 'env' is reserved for environment access ({{ env.NAME }}); user-defined 'env' is ignored" }
        end

        # env: values are templates rendered against the PRE-merge view, so
        # PATH: "/opt/bin:{{ env.PATH }}" prepends to the inherited value
        # instead of referencing itself. The rendered values are merged into
        # ENVIRONMENT before anything else is expanded; afterwards the `env`
        # namespace always reflects the final merged view.
        rendered_env = merge_env_section(p.env, file_variables)
        render_context = file_variables.merge(Hace::VARIABLES)

        # Render entire file at once to support multi-line Jinja control
        # structures. Content referencing the task-scoped 'self' variable
        # (e.g. Makefiles converted with $@/$</$^ translations) can only be
        # expanded per task, so the whole-file render is skipped for it.
        # If the whole-file render fails (e.g. a variable value holds
        # template syntax meant for the later per-string expansion) fall
        # back to raw YAML; real template errors will resurface there.
        if data.includes?("{{") && data.includes?("self[")
          Log.debug { "Skipping whole-file template render: content references task-scoped 'self'" }
          rendered_data = data
        else
          begin
            rendered_data = Crinja.render(data, Hace.to_crinja_variables(render_context))
          rescue ex : Crinja::Error
            Log.warn { "Whole-file template render failed, using raw YAML: #{ex.message}" }
            rendered_data = data
          end
        end

        f = Hace::HaceFile.from_yaml(rendered_data)

        # The whole-file render expanded the env: section against the final
        # view (whose values already include the rendered overrides, e.g.
        # "pre:{{ env.PATH }}" would become "pre:pre:..."), so discard that
        # text and keep the values rendered against the pre-merge view above.
        f.env = rendered_env

        # Variables support the deprecated ${ENV} expansion (warns) and
        # brace-less $ENV references stay literal (warns when the name
        # resolves). The reserved 'env' name never overwrites the namespace.
        f.variables.each do |key, value|
          next if key == "env"
          VARIABLES[key] = Hace.expand_env_in_value(value)
        end

        # Command-line KEY=value overrides win over Hacefile defaults, so
        # they are applied last, before any task template gets expanded.
        variable_overrides.each do |key, value|
          next if key == "env"
          VARIABLES[key] = value
        end

        # Tasks support expansion. The task name is passed along because
        # tasks without explicit outputs default to it, and templates may
        # reference outputs via self (e.g. Makefile $@ translations).
        f.tasks.each { |name, task| task.expand(name) }
      rescue ex
        raise "Error parsing Hacefile '#{filename}': #{ex}"
      end
      f
    end

    # Render the raw env: section values as templates against the pre-merge
    # environment view and merge them into ENVIRONMENT (nil unsets). Updates
    # the `env` template namespace to the final merged view, and returns the
    # rendered values so the caller can replace the whole-file-rendered env:
    # text (which would otherwise apply the overrides twice).
    private def self.merge_env_section(
      raw_env : Hash(String, String?),
      file_variables : Hash(String, Hace::Value),
    ) : Hash(String, String?)
      VARIABLES["env"] = Hace.env_namespace
      pre_merge_context = file_variables.merge(Hace::VARIABLES)
      rendered_env = {} of String => String?
      raw_env.each do |key, value|
        rendered_env[key] = value.nil? ? nil : Hace.expand_string(value, pre_merge_context)
      end
      rendered_env.each do |key, value|
        if value.nil?
          Hace::ENVIRONMENT.delete(key)
        else
          Hace::ENVIRONMENT[key] = value
        end
      end
      VARIABLES["env"] = Hace.env_namespace
      rendered_env
    end

    # Detect which tasks explicitly use CLI_ARGS before Crinja expansion.
    # Any mention of CLI_ARGS or CLI_ARGS_LIST counts, so both interpolation
    # ({{ CLI_ARGS }}) and statement usage ({% for arg in CLI_ARGS_LIST %})
    # are covered; a literal "CLI_ARGS" inside a command is unlikely enough
    # that a simple substring check is the most robust option here.
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
          if cmd_str.includes?("CLI_ARGS")
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

        # Extract KEY=value variable assignments from the arguments. They are
        # merged into VARIABLES right away and also passed to load_file,
        # which re-applies them after Hacefile defaults so overrides win.
        variable_overrides, arguments = extract_variable_assignments(arguments)
        Hace::VARIABLES.merge!(variable_overrides)

        hacefile = HaceFile.load_file(filename, variable_overrides)

        # Generate tasks if not already done. Arguments are passed along so
        # pattern rules can instantiate tasks for CLI-requested targets.
        if TaskManager.tasks.empty?
          hacefile.gen_tasks(dry_run, arguments)
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

      # Split KEY=value arguments out of *arguments*, returning the overrides
      # and the remaining task names.
      private def self.extract_variable_assignments(arguments : Array(String))
        overrides = {} of String => String
        remaining = [] of String
        arguments.each do |arg|
          if arg =~ /^(\w+)=(.*)$/
            key, value = arg.split("=", 2)
            overrides[key] = value
          else
            remaining << arg
          end
        end
        {overrides, remaining}
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

      # Staleness is content-based: compare current inputs against the state
      # saved by the previous run. Without this scan the modified set is empty
      # and question mode only ever notices missing outputs.
      TaskManager.mark_stale_inputs

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
        .select do |task|
          (targets.includes? task.id) || (!(targets & task.outputs).empty?)
        end
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
      unknown_tasks = [] of String

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
        # Tasks that generate no argument don't exist. Collect them all so
        # the error can report every typo at once.
        unknown_tasks << arg if p_args.empty?
        real_arguments += p_args
      end

      unless unknown_tasks.empty?
        raise UnknownTaskError.new(unknown_tasks, hacefile.tasks.keys)
      end

      real_arguments = Set.new(real_arguments).to_a
    end

    # Synthesize concrete tasks from `patterns` for dependencies that no
    # explicit task produces, mirroring make's implicit rule behavior. Runs
    # to a fixpoint so patterns can chain (e.g. "%.c: %.tpl" behind
    # "%.o: %.c"). *requested* holds targets named on the command line, which
    # also get a chance to be instantiated even if nothing depends on them.
    def resolve_patterns(requested : Array(String) = [] of String) : HaceFile
      @patterns.each_with_index { |pattern, index| pattern.validate!(index) }
      return self if @patterns.empty?

      # A name counts as covered when it is an output of some task *or* the
      # name of an explicit task, so patterns can never clobber user rules.
      covered = Set(String).new
      @tasks.each_value { |task| covered.concat(task.outputs) }
      @tasks.each_key { |name| covered << name }
      attempted = Set(String).new
      pending = [] of String
      @tasks.each_value { |task| pending.concat(task.dependencies) }
      pending.concat(requested)

      until pending.empty?
        candidate = pending.shift
        next if covered.includes?(candidate) || attempted.includes?(candidate)
        attempted << candidate

        instantiation = try_instantiate(candidate, covered)
        next unless instantiation

        synthesized, prerequisites = instantiation
        @tasks[candidate] = synthesized
        covered << candidate
        pending.concat(prerequisites)
      end

      self
    end

    # Try every pattern in declaration order against *name*; the first one
    # whose output matches and whose substituted dependencies all resolve is
    # instantiated into a real CommandTask. Returns it with its dependencies,
    # or nil when no pattern applies.
    private def try_instantiate(name : String, covered : Set(String)) : {CommandTask, Array(String)}?
      @patterns.each do |pattern|
        stem = pattern.match_stem(name) || next
        prerequisites = pattern.dependencies_for(stem)
        unless prerequisites.all? { |prereq| resolvable?(prereq, covered, Set{name}) }
          next
        end

        synthesized = CommandTask.new(
          commands: pattern.commands,
          outputs: [name],
          dependencies: prerequisites,
          shell: pattern.shell,
          description: "generated for #{name} (from pattern #{pattern.outputs[0]})",
          stem: stem,
        )
        synthesized.expand(name)
        return {synthesized, prerequisites}
      end

      nil
    end

    # A prerequisite grounds an instantiation when the file exists, is
    # produced by a known task, or could itself be synthesized by another
    # pattern whose own prerequisites bottom out. The seen set terminates
    # self-referential pattern families like "%.x: %.x.z".
    private def resolvable?(name : String, covered : Set(String), seen : Set(String)) : Bool
      return true if File.exists?(name) || covered.includes?(name)
      return false if seen.includes?(name)
      seen << name

      @patterns.any? do |pattern|
        stem = pattern.match_stem(name) || next false
        pattern.dependencies_for(stem).all? do |prereq|
          resolvable?(prereq, covered, seen)
        end
      end
    end

    def gen_tasks(dry_run : Bool = false, requested : Array(String) = [] of String)
      resolve_patterns(requested)
      @tasks.each do |name, task|
        task.gen_task(name, self, dry_run)
      end
      prune_recipe_stamps
    end

    # Remove stamp files of tasks that no longer exist so the stamp
    # directory does not grow without bound across Hacefile edits.
    private def prune_recipe_stamps
      return unless Dir.exists?(Hace::RECIPE_STAMP_DIR)

      valid = Set.new(@tasks.keys.map { |name| Digest::SHA1.hexdigest(name) })
      Dir.children(Hace::RECIPE_STAMP_DIR).each do |child|
        next if valid.includes?(child)
        File.delete?(File.join(Hace::RECIPE_STAMP_DIR, child))
      end
    rescue ex
      Log.debug { "Could not prune recipe stamps: #{ex.message}" }
    end

    def self.auto(
      arguments = [] of String,
      filename = "Hacefile.yml",
      cli_args = [] of String,
    )
      # Inject CLI_ARGS BEFORE loading (so they're available during task expansion)
      Hace.inject_cli_args(cli_args)

      hacefile = load_file(filename)
      hacefile.gen_tasks(requested: arguments.map(&.as(String)))
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

  # A template rule that synthesizes concrete tasks for dependencies not
  # covered by explicit tasks, mirroring make's pattern rules ("%.o: %.c").
  # Patterns live in the Hacefile under a top-level `patterns:` key and are
  # expanded at load time, before the task graph is built.
  class PatternRule
    include YAML::Serializable
    include YAML::Serializable::Strict

    property outputs : Array(String) = [] of String
    property dependencies : Array(String) = [] of String
    property commands : String = ""
    property shell : String? = nil

    getter outputs : Array(String)
    getter dependencies : Array(String)
    getter commands : String
    getter shell : String?

    def initialize(@commands : String, @outputs : Array(String) = [] of String,
                   @dependencies : Array(String) = [] of String, @shell : String? = nil)
    end

    # Structural checks that YAML parsing cannot express. Raises with a
    # message identifying the offending pattern.
    def validate!(index : Int32) : Nil
      unless @outputs.size == 1
        raise "patterns[#{index}]: exactly one output pattern is required"
      end
      unless @outputs[0].count('%') == 1
        raise "patterns[#{index}]: output '#{@outputs[0]}' must contain exactly one '%'"
      end
      @dependencies.each do |dependency|
        if dependency.count('%') > 1
          raise "patterns[#{index}]: dependency '#{dependency}' must contain at most one '%'"
        end
      end
      if @commands.strip.empty?
        raise "patterns[#{index}]: commands cannot be empty"
      end
    end

    # The stem with which *name* matches this pattern's output, or nil when
    # there is no match. Empty stems are rejected so "%.o" does not match
    # a file literally named ".o".
    def match_stem(name : String) : String?
      prefix, suffix = @outputs[0].split("%", limit: 2)
      minimum_size = prefix.size + suffix.size + 1
      return if name.size < minimum_size
      return unless name.starts_with?(prefix) && name.ends_with?(suffix)

      name[prefix.size, name.size - prefix.size - suffix.size]
    end

    # Dependencies with '%' placeholders replaced by *stem*. Dependencies
    # without a placeholder pass through unchanged.
    def dependencies_for(stem : String) : Array(String)
      @dependencies.map { |dependency| dependency.includes?('%') ? dependency.sub('%', stem) : dependency }
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
    @stem : String? = nil

    # Read-only accessors so callers don't have to reach into instance vars.
    getter commands : String
    getter dependencies : Array(String)
    getter outputs : Array(String)
    getter description : String?
    getter cwd : String?
    getter shell : String?
    getter stem : String?
    getter? phony : Bool
    getter? default : Bool
    getter? always_run : Bool

    # Plain keyword constructor used when synthesizing tasks from patterns.
    # It coexists with the YAML::Serializable-generated parser initializer.
    def initialize(@commands : String, @outputs : Array(String) = [] of String,
                   @dependencies : Array(String) = [] of String, @phony : Bool = false,
                   @default : Bool = false, @always_run : Bool = false,
                   @cwd : String? = nil, @description : String? = nil,
                   @shell : String? = nil, @stem : String? = nil)
    end

    # The task's own state as template variables, so commands can reference
    # e.g. {{ self["dependencies"] }}. Built from the live fields on every
    # use, replacing the old YAML serialize/parse roundtrip.
    private def template_context : Hash(String, Value)
      context = {} of String => Value
      context["commands"] = @commands
      context["dependencies"] = @dependencies.map { |dependency| dependency.as(Value) }
      context["outputs"] = @outputs.map { |output| output.as(Value) }
      context["phony"] = @phony
      context["default"] = @default
      context["always_run"] = @always_run
      context["cwd"] = @cwd
      context["description"] = @description
      context["shell"] = @shell
      context["stem"] = @stem
      context
    end

    private def expansion_variables : Hash(String, Value)
      variables = Hace::VARIABLES.dup
      variables["self"] = template_context
      variables
    end

    # We want to support variables and environment variables also in things
    # like dependencies, outputs, etc. so we need to do some post-processing
    #
    # Besides the global VARIABLES, they also have access to self, which is
    # rebuilt after each stage so it always reflects the current state.
    def expand(task_name : String)
      # Tasks without explicit outputs default to a single output named
      # after the task; do it here so templates expanding during this pass
      # already see the final outputs.
      @outputs = [task_name] if @outputs.empty? && !@phony

      @outputs = @outputs.map { |outp| expand_field(outp, expansion_variables) }

      # Dependencies expand both variables and globs
      @dependencies = @dependencies.map { |dep| expand_field(dep, expansion_variables) }
      @dependencies = @dependencies.flat_map { |dep| Hace.expand_glob(dep) }
      @commands = Hace.expand_string(@commands, expansion_variables)
    end

    # Expand a non-command field (outputs, dependencies). Unlike commands,
    # these never reach a shell, so brace-less $WORD references are warned
    # about instead of silently staying literal.
    private def expand_field(str : String, variables)
      Hace.warn_braceless_env_ref(str)
      Hace.expand_string(str, variables)
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

      # The stamp captures everything that defines how the recipe runs, so a
      # Hacefile edit invalidates previously built outputs. CLI_ARGS are
      # deliberately excluded: they vary per invocation by design.
      task_shell = @shell || hacefile.shell || "/bin/sh"
      recipe_signature = "#{task_shell}\u{0}#{@cwd}\u{0}#{commands.join("\n")}"
      recipe_stamp = Hace.stamp_recipe(name, recipe_signature)

      # Tasks without dependencies are always stale (Croupier treats empty
      # inputs that way), which hacé relies on for aggregator-style tasks;
      # only stamp tasks that have something to be stale *relative to*.
      task_inputs = @dependencies.empty? ? @dependencies : @dependencies + [recipe_stamp]

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
        inputs: task_inputs,
        # Tasks with different outputs can be merged for parallel execution
        mergeable: true,
        no_save: true,
        always_run: @always_run,
        proc: TaskProc.new do
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
                cli_args_list = Hace::VARIABLES["CLI_ARGS_LIST"]?.as?(Array(Hace::Value)) || [] of Hace::Value
                if !cli_args_list.empty?
                  quoted_args = cli_args_list.map { |arg| Process.quote(arg.as(String)) }.join(" ")
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
              shell_args = shell_parts.size > 1 ? shell_parts[1..] : [] of String

              # Add the script arguments
              if shell_args.empty?
                # A bare POSIX-style shell gets fail-fast (-e) so multi-command
                # tasks stop at the first failure, matching the /bin/sh default.
                # Non-POSIX shells (python, cmd.exe, ...) just get the script.
                if Hace::FAIL_FAST_SHELLS.includes?(File.basename(shell_cmd))
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
        end,
        id: name,
      )
    end
  end

  # Snapshot the merged environment view as template variables, backing the
  # `env` namespace ({{ env.NAME }}). It matches what task shells see for
  # $NAME: process environment (including dotenv) plus env: overrides.
  def self.env_namespace : Hash(String, Value)
    view = {} of String => Value
    ENVIRONMENT.each { |key, value| view[key] = value }
    view
  end

  # Expand the deprecated braced ${ENV_VAR} references from the merged
  # environment view. Actual substitutions log a deprecation warning, once
  # per variable name per run; undefined references stay literal (matching
  # both the old behavior and post-removal shell passthrough).
  def self.expand_env_vars(str : String) : String
    str.gsub(/\$\{(\w+)\}/) do |_match|
      env_key = $1
      value = ENVIRONMENT.fetch(env_key, nil)
      if value
        warn_deprecated_env_var(env_key)
        value
      else
        _match
      end
    end
  end

  private def self.warn_deprecated_env_var(name : String)
    return if DEPRECATED_ENV_WARNED.includes?("${#{name}}")
    DEPRECATED_ENV_WARNED << "${#{name}}"
    Log.warn { "\"${#{name}}\" expansion is deprecated and will be removed; use \"{{ env.#{name} }}\" instead" }
  end

  # Warn about brace-less $WORD references in non-command fields: hace no
  # longer expands them, so a value like "$HOME" stays literal. Only names
  # that resolve in the merged environment warn, since only those could
  # have relied on the old expansion.
  def self.warn_braceless_env_ref(str : String)
    str.scan(/\$([A-Za-z_]\w*)/) do |match|
      name = match[1]
      next unless ENVIRONMENT.has_key?(name)
      key = "$#{name}"
      next if DEPRECATED_ENV_WARNED.includes?(key)
      DEPRECATED_ENV_WARNED << key
      Log.warn { "Brace-less '$#{name}' is not expanded by hace in this field; if you meant the environment variable, use \"{{ env.#{name} }}\"" }
    end
  end

  def self.expand_string(str : String, variables = Hace::VARIABLES) : String
    # Expand variables
    str = Crinja.render(str, to_crinja_variables(variables))
    # Expand deprecated environment variable references
    Hace.expand_env_vars(str)
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
