require "commander"
require "crinja"
require "croupier"
require "log"
require "yaml"

include Croupier

module Hace
  VERSION = "0.1.0"

  class HaceFile
    include YAML::Serializable
    include YAML::Serializable::Strict

    property tasks : Hash(String, CommandTask) = {} of String => CommandTask
    property variables : Hash(String, YAML::Any) = {} of String => YAML::Any
    property env : Process::Env = {} of String => String

    def self.run(arguments = [] of String, run_all : Bool = false)
      if !File.exists?("Hacefile.yml")
        raise "No Hacefile.yml found"
      end
      f = Hace::HaceFile.from_yaml(File.read("Hacefile.yml"))
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
      TaskManager.run_tasks(arguments, run_all: run_all)
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
    @default : Bool = true
    @outputs : Array(String) = [] of String

    def gen_task(name, variables, env)
      # phony tasks have no outputs.
      # tasks where outputs are not specified have only one output, the task name
      # FIXME: warn about phony tasks with outputs
      @outputs = @phony ? [] of String : [name] if @outputs.empty?

      commands = @commands.split("\n").map(&.strip).reject(&.empty?)

      Task.new(
        name: name,
        output: @outputs,
        inputs: @dependencies, no_save: true,
        proc: TaskProc.new {
          commands.map do |command|
            command = Crinja.render(command, variables)
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
