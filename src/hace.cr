require "commander"
require "crinja"
require "croupier"
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
      Hace::HaceFile.from_yaml(File.read("Hacefile.yml")).gen_tasks
      if arguments.empty?
        TaskManager.run_tasks(run_all: run_all)
      else
        TaskManager.run_tasks(arguments, run_all: run_all)
      end
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

    def gen_task(name, variables, env)
      commands = @commands.split("\n").map(&.strip).reject(&.empty?)
      commands.map do |command|
        Task.new(
          name: name,
          output: @phony ? [] of String : name,
          inputs: @dependencies, no_save: true,
          proc: TaskProc.new {
            Process.run(
              command: Crinja.render(command, variables),
              shell: true,
              env: env,
            ).to_s
          },
          id: @phony ? name : nil,
        )
      end
    end
  end
end
