require "commander"
require "crinja"
require "croupier"
require "log"
require "yaml"

include Croupier

module Hace
  VERSION = "0.1.1"

  class HaceFile
    include YAML::Serializable
    include YAML::Serializable::Strict

    property tasks : Hash(String, CommandTask) = {} of String => CommandTask
    property variables : Hash(String, YAML::Any) = {} of String => YAML::Any
    property env : Process::Env = {} of String => String

    def self.load_file(filename)
      begin
        if !File.exists?(filename)
          raise "No Hacefile '#{filename}' found"
        end
        f = Hace::HaceFile.from_yaml(File.read(filename))
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
      question : Bool = false
    )
      f = load_file(filename)
      f.gen_tasks

      # FIXME: see if this works when given `arguments`
      if question
        stale_tasks = TaskManager.tasks.values.select(&.stale?)
        if stale_tasks.empty?
          Log.info { "No stale tasks found" }
          return 0
        end
        Log.info { "Stale tasks found:" }
        return 1
      end

      # If no tasks are specified, run only default tasks
      if arguments.empty?
        f.tasks.each do |name, task|
          if task.@default
            arguments += task.@outputs
            arguments << name if task.@phony
          end
        end
      end

      Log.info { "Running tasks: #{arguments.join(", ")}" }
      TaskManager.run_tasks(arguments, run_all: run_all, dry_run: dry_run)
      Log.info { "Finished" }
      0 # exit code
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
      f = load_file(filename)
      f.gen_tasks
      begin
        Log.info { "Running tasks: #{arguments.join(", ")}" }
        TaskManager.auto_run(arguments)
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
        no_save: true,
        always_run: @always_run,
        proc: TaskProc.new {
          commands.map do |command|
            command = Crinja.render(command, context)
            Log.info { "Running command: #{command}" }
            status = Process.run(
              command: command,
              shell: true,
              env: env,
            )
            raise "Command failed: exit #{status.exit_code} when running #{command}" unless status.success?
            status.to_s
          end
        },
        id: @phony ? name : nil,
      )
    end
  end
end
