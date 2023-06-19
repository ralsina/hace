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

    def self.run(
      arguments = [] of String,
      filename = "Hacefile.yml",
      run_all : Bool = false,
      dry_run : Bool = false,
    )
      begin
        if !File.exists?(filename)
          raise "No Hacefile '#{filename}' found"
        end
        f = Hace::HaceFile.from_yaml(File.read(filename))
      rescue ex
        raise "Error parsing Hacefile '#{filename}': #{ex}"
      end
      f.gen_tasks
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
    end

    def gen_tasks
      @tasks.each do |name, task|
        task.gen_task(name, variables, env)
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
        name: name,
        output: @outputs,
        inputs: @dependencies,
        no_save: true,
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
