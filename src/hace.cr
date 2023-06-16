require "yaml"
require "croupier"

include Croupier

module Hace
  VERSION = "0.1.0"

  def parse_file(path = "Hacefile.yml")
    config = File.open(path, "r") do |file|
      YAML.parse(file).as_h
    end
    config
  end

  # Create tasks out of config
  def create_tasks(config)
    config["tasks"].as_h.each do |name, data|
      data = data.as_h
      output = data.fetch("output", name).as_s
      inputs = data.fetch("dependencies", YAML.parse("[]")).as_a.map(&.as_s)
      Task.new(name:name.as_s, output:output, inputs: inputs)
    end
  end
end
