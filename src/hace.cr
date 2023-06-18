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
    property env : Hash(String, String) = {} of String => String

    def self.run(options = [] of String, arguments = [] of String)
      if !File.exists?("Hacefile.yml")
        raise "No Hacefile.yml found"
      end
      Hace::HaceFile.from_yaml(File.read("Hacefile.yml")).gen_tasks
      if arguments.empty?
        TaskManager.run_tasks
      else
        TaskManager.run_tasks(arguments)
      end
    end

    def gen_tasks
      @tasks.each do |name, task|
        task.gen_task(name, variables)
      end
    end
  end

  class CommandTask
    include YAML::Serializable
    include YAML::Serializable::Strict

    @commands : String
    @dependencies : Array(String) = [] of String
    @phony : Bool = false

    def gen_task(name, variables)
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
            ).to_s
          },
          id: @phony ? name : nil,
        )
      end
    end
  end
end
