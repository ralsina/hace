require "yaml"
require "croupier"

include Croupier

module Hace
  VERSION = "0.1.0"

  class HaceFile
    include YAML::Serializable
    include YAML::Serializable::Strict

    property tasks : Hash(String, CommandTask)

    def gen_tasks
      @tasks.each do |name, task|
        task.gen_task(name)
      end
    end
  end

  class CommandTask
    include YAML::Serializable
    include YAML::Serializable::Strict

    property commands : String
    property dependencies : Array(String)

    def gen_task(name)
      commands = @commands.split("\n").map(&.strip).reject(&.empty?)
      commands.map do |command|
        Task.new(
          name: name, output: name,
          inputs: @dependencies, no_save: true,
          proc: TaskProc.new { Process.run(
            command: command,
            shell: true,
          ).to_s }
        )
      end
    end
  end
end
