require "./hace"
require "./completion"
require "colorize"
require "docopt"

DOC = <<-DOC
  hace makes things, like make.

  Usage:
    hace [options] [<task>...] [-- <args>...]
    hace --convert [options]
    hace --completion=<shell>
    hace --help

  Options:
    -f <file>, --file=<file>     Read the file named as a Hacefile (default: Hacefile.yml,
                                 falling back to a Makefile when no Hacefile exists)
    -n, --dry-run                Don't actually run any commands
    -q, --quiet                  Don't log anything
    -v <level>, --verbosity=<level>  Control the logging verbosity, 0 to 5
                                     (default: 3, or HACE_DEFAULT_VERBOSITY)
    -B, --always-make            Unconditionally run all tasks
    -k, --keep-going             Continue as much as possible after an error
    --parallel                   Run tasks in parallel when possible
    --question                   Don't run anything, exit 0 if all tasks are up to date, 1 otherwise
    --list                       List available tasks
    --auto                       Run in auto mode, watching for file changes
    --convert                    Convert the Makefile given with -f (default: Makefile,
                                 falling back to GNUmakefile/makefile/Makefile) to
                                 Hacefile YAML and print it to stdout
    --completion=<shell>         Generate shell completion script (bash, fish, zsh)
    --version                    Display version information
    -h, --help                   Show this help message
  DOC

# Docopt returns "<task>" as an Array(String) when tasks are named on the
# command line and nil when none are. Normalize to a plain Array(String) so
# the --list, --auto and plain run paths share one extraction.
alias DocoptValues = Nil | String | Int32 | Bool | Array(String)

def requested_task_names(args : Hash(String, DocoptValues)) : Array(String)
  args["<task>"].as?(Array) || [] of String
end

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
      ][[verbosity.clamp(0..), 5].min]
    end
    Log.setup(
      _verbosity,
      Log::IOBackend.new(io: STDERR, formatter: LogFormat)
    )
  end
end

begin
  # Split ARGV at -- separator for CLI args passthrough
  dash_index = ARGV.index("--")
  hace_args, passthrough_args = dash_index ? {ARGV[0...dash_index].to_a, ARGV[(dash_index + 1)..].to_a} : {ARGV.to_a, [] of String}

  # With exit: false, docopt raises Docopt::DocoptExit for usage errors
  # (handled below) instead of exiting the process with a success status.
  args = Docopt.docopt(DOC, argv: hace_args, version: "Hacé version #{Hace::VERSION}", help: true, exit: false)

  # Extract options from docopt result with safe casting
  quiet = args["--quiet"].as?(Bool) || false
  verbosity_str = args["--verbosity"].as?(String) || ENV["HACE_DEFAULT_VERBOSITY"]? || "3"
  verbosity = verbosity_str.to_i
  file = args["--file"].as?(String) || Hace::HaceFile.default_filename
  dry_run = args["--dry-run"].as?(Bool) || false
  always_make = args["--always-make"].as?(Bool) || false
  keep_going = args["--keep-going"].as?(Bool) || false
  parallel = args["--parallel"].as?(Bool) || false
  question = args["--question"].as?(Bool) || false
  list = args["--list"].as?(Bool) || false
  auto = args["--auto"].as?(Bool) || false
  completion_shell = args["--completion"].as?(String)

  # Help/version/completion exit before any logging matters; everything else
  # gets a backend configured from --quiet/--verbosity (docopt already exited
  # for --help and --version inside Docopt.docopt).
  LogFormat.setup(quiet, verbosity)

  # Handle --completion option
  if completion_shell
    begin
      completion_script = Hace::Completion.generate(completion_shell)
      puts completion_script
      exit(0)
    rescue ex
      puts "Error generating completion script: #{ex.message}".colorize(:red)
      exit(1)
    end
  end

  # Handle --convert option: print Makefile converted to Hacefile YAML.
  # The source file comes from -f/--file; when not given, look for a
  # Makefile under its usual names.
  if args["--convert"] == true
    makefile = args["--file"].as?(String)
    makefile ||= Hace::MakefileConverter::MAKEFILE_NAMES.find { |name| File.exists?(name) }
    makefile ||= "Makefile"
    begin
      unless File.exists?(makefile)
        puts "Error: Makefile '#{makefile}' not found".colorize(:red)
        exit(1)
      end
      puts Hace::MakefileConverter.convert(File.read(makefile))
      exit(0)
    rescue ex
      puts "Error converting '#{makefile}': #{ex.message}".colorize(:red)
      exit(1)
    end
  end

  # Handle --list option
  if list
    begin
      hacefile = Hace::HaceFile.load_file(file)
      # Resolve pattern rules so instances requested on the command line or
      # needed by explicit tasks show up in the listing too.
      hacefile.resolve_patterns(requested_task_names(args))
      # Display tasks in a formatted table
      puts "TASK             DESCRIPTION                                        PHONY     DEFAULT   ALWAYS "
      puts "---------------- -------------------------------------------------- --------  --------  ------- "

      hacefile.tasks.each do |name, task|
        phony_mark = task.phony? ? "✓" : " "
        default_mark = task.default? ? "✓" : " "
        always_mark = task.always_run? ? "✓" : " "
        description = task.description || "No description"

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
    task_args = requested_task_names(args)
    # Hace::HaceFile.auto never returns on the success path: it enters its
    # own keep-alive loop so Croupier's file-watcher fibers keep running.
    # On failure it returns 1; load_file/gen_tasks errors propagate and are
    # caught here.
    begin
      exit(Hace::HaceFile.auto(
        arguments: task_args,
        filename: file,
        cli_args: passthrough_args,
      ))
    rescue ex
      Log.error { ex }
      exit(1)
    end
  end

  # Normal mode
  task_args = requested_task_names(args)
  exit(
    Hace::HaceFile.run(
      filename: file,
      arguments: task_args,
      cli_args: passthrough_args,
      run_all: always_make,
      dry_run: dry_run,
      question: question,
      keep_going: keep_going,
      parallel: parallel,
    )
  )
rescue ex : Docopt::DocoptExit
  # Usage error: show the reason (if any) plus the usage line, exit non-zero
  if message = ex.message
    puts message unless message.empty?
  end
  puts Docopt::DocoptExit.usage
  exit(1)
rescue ex : Docopt::DocoptLanguageError
  puts "Error: invalid command definition: #{ex.message}".colorize(:red)
  exit(1)
rescue ex
  puts "Error: #{ex.message}".colorize(:red)
  exit(1)
end
