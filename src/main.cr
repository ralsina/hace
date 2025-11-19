require "./hace"
require "colorize"
require "docopt"

DOC = <<-DOC
hace makes things, like make.

Usage:
  hace [options] [<task>...]
  hace --completion=<shell>
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
  --completion=<shell>         Generate shell completion script (bash, fish, zsh)
  --version                    Display version information
  -h, --help                   Show this help message
DOC

# Get task names from Hacefile for completion
def get_task_names(filename = "Hacefile.yml") : Array(String)
  hacefile = Hace::HaceFile.load_file(filename)
  hacefile.tasks.keys
rescue ex
  # If Hacefile doesn't exist or is invalid, return empty array
  [] of String
end

# Generate shell completion script
def generate_completion(shell : String)
  case shell.downcase
  when "bash"
    generate_bash_completion
  when "fish"
    generate_fish_completion
  when "zsh"
    generate_zsh_completion
  else
    puts "Error: Unsupported shell '#{shell}'. Supported shells: bash, fish, zsh".colorize(:red)
    exit(1)
  end
end

def generate_bash_completion
  <<-'BASH'
#!/bin/bash
_hace_completion() {
    local cur prev words cword
    _init_completion || return

    # Complete options
    case "$prev" in
        -f|--file)
            _filedir -y
            return
            ;;
        -v|--verbosity)
            COMPREPLY=($(compgen -W "0 1 2 3 4 5" -- "$cur"))
            return
            ;;
        --completion)
            COMPREPLY=($(compgen -W "bash fish zsh" -- "$cur"))
            return
            ;;
    esac

    # Complete task names if not an option
    if [[ "$cur" != -* ]]; then
        local tasks
        if hacefile="${HACEFILE:-Hacefile.yml}"; [[ -f "$hacefile" ]]; then
            tasks=$(hace --list 2>/dev/null | awk 'NR>3 && NF>0 {print $1}' | grep -v '^TASK\\|^---\\|^Legends')
        else
            tasks=()
        fi
        COMPREPLY=($(compgen -W "$tasks" -- "$cur"))
        return
    fi

    # Complete options
    local options="--file --dry-run --quiet --verbosity --always-make --keep-going --parallel --question --list --auto --completion --version --help -f -n -q -v -B -k -h"
    COMPREPLY=($(compgen -W "$options" -- "$cur"))
}

complete -F _hace_completion hace
BASH
end

def generate_fish_completion
  <<-'FISH'
function __hace_task_names
    set -l hacefile $HACEFILE
    test -z "$hacefile"; and set hacefile Hacefile.yml

    if test -f "$hacefile"
        hace --list 2>/dev/null | awk 'NR>3 && NF>0 && !/^TASK|^---|^Legends/ {print $1}'
    end
end

function __hace_no_subcommand
    # Check if any argument matches a known task name
    for arg in (commandline -opc)
        if contains $arg (__hace_task_names) 2>/dev/null
            return 1  # Found a task, so we're not in "no subcommand" state
        end
    end
    return 0  # No task found, we're in "no subcommand" state
end

complete -c hace -f

# File completion for --file/-f
complete -c hace -n '__fish_contains_opt -s f file' -F

# Verbosity completion for --verbosity/-v
complete -c hace -n '__fish_contains_opt -s v verbosity' -k -a "0 1 2 3 4 5"

# Shell completion for --completion
complete -c hace -n '__fish_contains_opt completion' -k -a "bash fish zsh" -d "Shell to generate completion for"

# Task name completion - only offer tasks if no task has been specified yet
complete -c hace -n '__hace_no_subcommand' -a "(__hace_task_names)" -d "Task name"

# Option completions
complete -c hace -s f -l file -d "Read the file named as a Hacefile"
complete -c hace -s n -l dry-run -d "Don't actually run any commands"
complete -c hace -s q -l quiet -d "Don't log anything"
complete -c hace -s v -l verbosity -d "Control the logging verbosity, 0 to 5"
complete -c hace -s B -l always-make -d "Unconditionally run all tasks"
complete -c hace -s k -l keep-going -d "Continue as much as possible after an error"
complete -c hace -l parallel -d "Run tasks in parallel when possible"
complete -c hace -l question -d "Don't run anything, exit 0 if all tasks are up to date"
complete -c hace -l list -d "List available tasks"
complete -c hace -l auto -d "Run in auto mode, watching for file changes"
complete -c hace -l completion -d "Generate shell completion script"
complete -c hace -l version -d "Display version information"
complete -c hace -s h -l help -d "Show this help message"
FISH
end

def generate_zsh_completion
  <<-'ZSH'
#compdef hace

_hace() {
    local -a tasks
    local context state line
    typeset -A opt_args

    _arguments -C \
        '(-f --file)'{-f,-file=}'[Read the file named as a Hacefile]:file:_files' \
        '(-n --dry-run)'{-n,-dry-run}'[Don'\''t actually run any commands]' \
        '(-q --quiet)'{-q,-quiet}'[Don'\''t log anything]' \
        '(-v --verbosity)'{-v,-verbosity=}'[Control the logging verbosity, 0 to 5]:verbosity:(0 1 2 3 4 5)' \
        '(-B --always-make)'{-B,-always-make}'[Unconditionally run all tasks]' \
        '(-k --keep-going)'{-k,-keep-going}'[Continue as much as possible after an error]' \
        '(--parallel)--parallel[Run tasks in parallel when possible]' \
        '(--question)--question[Don'\''t run anything, exit 0 if all tasks are up to date]' \
        '(--list)--list[List available tasks]' \
        '(--auto)--auto[Run in auto mode, watching for file changes]' \
        '(--completion)'{--completion=}'[Generate shell completion script]:shell:(bash fish zsh)' \
        '(--version)--version[Display version information]' \
        '(-h --help)'{-h,-help}'[Show this help message]' \
        '*:: :->task_args' && return 0

    case "$state" in
        task_args)
            if compset -P 1; then
                _message "no more arguments"
            else
                local hacefile=${HACEFILE:-Hacefile.yml}
                if [[ -f "$hacefile" ]]; then
                    tasks=($(hace --list 2>/dev/null | awk 'NR>3 && NF>0 && !/^TASK|^---|^Legends/ {print $1}'))
                fi
                _describe 'task' tasks
            fi
            ;;
    esac
}

_hace "$@"
ZSH
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
  completion_shell = args["--completion"].as?(String)

  # Only set up logging if not in quiet mode and not just checking version/help
  if !quiet && ARGV.size > 0 && !ARGV.includes?("--version") && !ARGV.includes?("--help") && !ARGV.includes?("--completion")
    LogFormat.setup(false, verbosity)
  end

  # Handle --completion option
  if completion_shell
    begin
      completion_script = generate_completion(completion_shell)
      puts completion_script
      exit(0)
    rescue ex
      puts "Error generating completion script: #{ex.message}".colorize(:red)
      exit(1)
    end
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
