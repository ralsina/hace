require "commander"
require "croupier"
require "yaml"

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

def run(options, arguments)
  if !File.exists?("Hacefile.yml")
    raise "No Hacefile.yml found"
  end
  Hace::HaceFile.from_yaml(File.read("Hacefile.yml")).gen_tasks
  TaskManager.run_tasks
end

cli = Commander::Command.new do |cmd|
  cmd.use = "hace"
  cmd.long = "hace makes things, like make"

  cmd.run do |options, arguments|
    run(options, arguments)
  end
end

Commander.run(cli, ARGV)
