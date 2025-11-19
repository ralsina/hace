require "./hace"
require "colorize"
require "docopt"

DOC = <<-DOC
hace makes things, like make.

Usage:
  hace [options] [<task>...]
  hace --help

Options:
  -f <file>, --file=<file>     Read the file named as a Hacefile [default: Hacefile.yml]
  -n, --dry-run                Don't actually run any commands
  -q, --quiet                  Don't log anything
  -v <level>, --verbosity=<level>  Control the logging verbosity, 0 to 5 [default: 3]
  -B, --always-make            Unconditionally run all tasks
  -k, --keep-going             Continue as much as possible after an error
  --parallel                   Run tasks in parallel when possible
  --question                   Don't run anything, exit 0 if all tasks are up to date, 1 otherwise
  --list                       List available tasks
  --auto                       Run in auto mode, watching for file changes
  --version                    Display version information
  -h, --help                   Show this help message
DOC

# Log formatter for Hace
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

begin
  args = Docopt.docopt(DOC, argv: ARGV, version: "Hacé version #{Hace::VERSION}", help: true, exit: true)

  # Extract options from docopt result with safe casting
  quiet = args["--quiet"].as?(Bool) || false
  verbosity_str = args["--verbosity"].as?(String) || "3"
  verbosity = verbosity_str.to_i
  file = args["--file"].as?(String) || "Hacefile.yml"
  dry_run = args["--dry-run"].as?(Bool) || false
  always_make = args["--always-make"].as?(Bool) || false
  keep_going = args["--keep-going"].as?(Bool) || false
  parallel = args["--parallel"].as?(Bool) || false
  question = args["--question"].as?(Bool) || false
  list = args["--list"].as?(Bool) || false
  auto = args["--auto"].as?(Bool) || false

  # Only set up logging if not in quiet mode and not just checking version/help
  if !quiet && ARGV.size > 0 && !ARGV.includes?("--version") && !ARGV.includes?("--help")
    LogFormat.setup(false, verbosity)
  end

  # Handle --list option
  if list
    LogFormat.setup(false, verbosity) unless quiet
    begin
      hacefile = Hace::HaceFile.load_file(file)
      # Display tasks in a formatted table
      puts "TASK             DESCRIPTION                                        PHONY     DEFAULT   ALWAYS "
      puts "---------------- -------------------------------------------------- --------  --------  ------- "

      hacefile.tasks.each do |name, task|
        phony_mark = task.@phony ? "✓" : " "
        default_mark = task.@default ? "✓" : " "
        always_mark = task.@always_run ? "✓" : " "
        description = task.@description || "No description"

        # Truncate description if too long
        description = description[0, 49] + "…" if description.size > 50

        printf("%-16s %-50s %-9s %-9s %-7s\n",
          name,
          description,
          phony_mark,
          default_mark,
          always_mark)
      end

      puts "\nLegends:"
      puts "  PHONY    - Task has no file outputs"
      puts "  DEFAULT  - Task runs by default when no tasks specified"
      puts "  ALWAYS   - Task always runs regardless of dependencies"

      exit(0)
    rescue ex
      puts "Error: #{ex.message}".colorize(:red)
      exit(1)
    end
  end

  # Handle --auto option
  if auto
    task_args_array = args["<task>"].as?(Array) || [] of String
    task_args = task_args_array.map(&.as(String))
    begin
      Hace::HaceFile.auto(
        arguments: task_args,
        filename: file,
      )
      Log.info { "Running in auto mode, press Ctrl+C to stop" }
      loop do
        ::sleep 1.seconds
      end
    rescue ex
      Log.error { ex }
      exit(1)
    end
  end

  # Normal mode
  task_args_array = args["<task>"].as?(Array) || [] of String
  task_args = task_args_array.map(&.as(String))
  exit(
    Hace::HaceFile.run(
      filename: file,
      arguments: task_args,
      run_all: always_make,
      dry_run: dry_run,
      question: question,
      keep_going: keep_going,
      parallel: parallel,
    )
  )
rescue ex
  # Handle docopt help/version and general errors
  message = ex.message
  if message && (message.includes?("Usage:") || message.includes?("Version:"))
    # Docopt is showing help or version, just exit cleanly
    puts message
    exit(0)
  else
    # Just print the error since we can't access args here
    puts "Error: #{message}".colorize(:red)
    exit(1)
  end
end
