require "./hace"
require "colorize"

struct LogFormat < Log::StaticFormatter
  @colors = {
    "FATAL" => :red,
    "ERROR" => :red,
    "WARN"  => :yellow,
    "INFO"  => :green,
    "DEBUG" => :blue,
    "TRACE" => :light_blue,
  }

  def run
    string "[#{Time.local}] #{@entry.severity.label}: #{@entry.message}".colorize(@colors[@entry.severity.label])
  end
end

cli = Commander::Command.new do |cmd|
  cmd.use = "hace"
  cmd.long = "hace makes things, like make"

  cmd.flags.add do |flag|
    flag.name = "run_all"
    flag.short = "-B"
    flag.long = "--always-make"
    flag.description = "Unconditionally run all tasks."
    flag.default = false
    flag.persistent = true
  end

  cmd.flags.add do |flag|
    flag.name = "quiet"
    flag.short = "-q"
    flag.long = "--quiet"
    flag.description = "Don't log anything"
    flag.default = false
    flag.persistent = true
  end

  cmd.run do |options, arguments|
    begin
      if options.@bool["quiet"]
        Log.setup(:fatal, Log::IOBackend.new(formatter: LogFormat))
      else
        Log.setup(:error, Log::IOBackend.new(formatter: LogFormat))
      end
      Hace::HaceFile.run(
        arguments,
        run_all: options.@bool["run_all"]
      )
    rescue ex
      Log.error { ex.message }
      exit(1)
    end
  end
end

Commander.run(cli, ARGV)
