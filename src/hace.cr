require "yaml"
require "croupier"

include Croupier

module Hace
  VERSION = "0.1.0"

  class CommandTask < Task
    @commands : Array(String)

    # @args : Array(String)

    def initialize(name, commands : String, output, inputs, no_save)
      @commands = commands.split("\n").map(&.strip).reject(&.empty?)
      @procs = @commands.map do |command|
        TaskProc.new { Process.run(
          command: command,
          shell: true,
        ).to_s }
      end
      super(
        name: name, output: output,
        inputs: inputs, no_save: no_save
      )
    end

    def to_s
      "Commands: \n  #{@commands.join("\n  ")}"
    end
  end

  def parse_file(path = "Hacefile.yml")
    config = File.open(path, "r") do |file|
      YAML.parse(file).as_h
    end
    config
  end

  # Create tasks out of config
  def create_tasks(config)
    # FIXME: use a proper type to parse this crap
    config["tasks"].as_h.each do |name, data|
      data = data.as_h
      output = data.fetch("output", name).as_s
      inputs = data.fetch("dependencies", YAML.parse("[]")).as_a.map(&.as_s)
      commands = data["commands"].as_s
      CommandTask.new(
        name: name.as_s,
        commands: commands,
        output: output,
        inputs: inputs,
        no_save: true,
      )
    end
  end
end
