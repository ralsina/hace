require "yaml"

module Hace
  VERSION = "0.1.0"

  def parse_file(path = "Hacefile.yml")
    config = File.open(path, "r") do |file|
      YAML.parse(file).as_h
    end
    config.each do |key, value|
      p! key
    end
    config
  end
end
