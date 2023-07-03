require "./hace"
require "colorize"

struct LogFormat < Log::StaticFormatter
  @@colors = {
    "FATAL" => :red,
    "ERROR" => :red,
    "WARN"  => :yellow,
    "INFO"  => :green,
    "DEBUG" => :blue,
    "TRACE" => :light_blue,
  }

  def run
    string "[#{Time.local}] #{@entry.severity.label}: #{@entry.message}".colorize(@@colors[@entry.severity.label])
  end

  def self.setup(quiet : Bool, verbosity)
    if quiet
      _verbosity = Log::Severity::Fatal
    else
      _verbosity = [
        Log::Severity::Fatal,
        Log::Severity::Error,
        Log::Severity::Warn,
        Log::Severity::Info,
        Log::Severity::Debug,
        Log::Severity::Trace,
      ][[verbosity, 5].min]
    end
    Log.setup(
      _verbosity,
      Log::IOBackend.new(io: STDERR, formatter: LogFormat)
    )
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
    flag.persistent = false
  end

  cmd.flags.add do |flag|
    flag.name = "quiet"
    flag.short = "-q"
    flag.long = "--quiet"
    flag.description = "Don't log anything"
    flag.default = false
    flag.persistent = true
  end

  cmd.flags.add do |flag|
    flag.name = "verbosity"
    flag.short = "-v"
    flag.long = "--verbosity"
    flag.description = "Control the logging verbosity, 0 to 5 "
    flag.default = 2
    flag.persistent = true
  end

  cmd.flags.add do |flag|
    flag.name = "file"
    flag.short = "-f"
    flag.long = "--file"
    flag.description = "Read the file named as a Hacefile"
    flag.default = "Hacefile.yml"
    flag.persistent = true
  end

  cmd.flags.add do |flag|
    flag.name = "dry_run"
    flag.short = "-n"
    flag.long = "--dry-run"
    flag.description = "Don't actually run any commands"
    flag.default = false
    flag.persistent = false
  end

  cmd.flags.add do |flag|
    flag.name = "question"
    flag.long = "--question"
    flag.description = "Don't run anything, exit 0 if all tasks are up to date, 1 otherwise"
    flag.default = false
    flag.persistent = false
  end

  cmd.run do |options, arguments|
    begin
      LogFormat.setup(options.@bool["quiet"], options.@int["verbosity"])
      exit(
        Hace::HaceFile.run(
          filename: options.@string["file"],
          arguments: arguments,
          run_all: options.@bool["run_all"],
          dry_run: options.@bool["dry_run"],
          question: options.@bool["question"],
        )
      )
    rescue ex
      Log.error { ex.message }
      exit(1)
    end
  end

  cmd.commands.add do |command|
    command.use = "auto"
    command.short = "Run in auto mode"
    command.long = "Run in auto mode, monitoring files for changes"
    command.run do |options, arguments|
      LogFormat.setup(options.@bool["quiet"], options.@int["verbosity"])
      Hace::HaceFile.auto(
        arguments: arguments,
        filename: options.@string["file"],
      )
    end
  end
end

Commander.run(cli, ARGV)
