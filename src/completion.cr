require "colorize"
require "./hace"

module Hace
  # Shell completion script generation and Hacefile task discovery. Lives in
  # its own file so the CLI (src/main.cr) and the test suite require the
  # same code rather than duplicating stub implementations.
  module Completion
    extend self

    # Task names from the Hacefile, for completion scripts. Returns an
    # empty array when the Hacefile is missing or unparseable.
    def get_task_names(filename = "Hacefile.yml") : Array(String)
      hacefile = HaceFile.load_file(filename)
      hacefile.tasks.keys
    rescue
      [] of String
    end

    # Generate the completion script for *shell*, exiting with an error for
    # unsupported shells.
    def generate(shell : String)
      case shell.downcase
      when "bash"
        bash
      when "fish"
        fish
      when "zsh"
        zsh
      else
        puts "Error: Unsupported shell '#{shell}'. Supported shells: bash, fish, zsh".colorize(:red)
        exit(1)
      end
    end

    def bash
      <<-BASH
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
          local options="--file --dry-run --quiet --verbosity --always-make --keep-going --parallel --question --list --auto --convert --completion --version --help -f -n -q -v -B -k -h"
          COMPREPLY=($(compgen -W "$options" -- "$cur"))
      }

      complete -F _hace_completion hace
      BASH
    end

    def fish
      <<-FISH
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

      # Convert option completes Makefiles
      complete -c hace -l convert -d "Convert a Makefile to Hacefile YAML" -F

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

    def zsh
      <<-ZSH
      #compdef hace

      _hace() {
          local -a tasks
          local context state line
          typeset -A opt_args

          _arguments -C \
              '(-f --file)'{-f,-file=}'[Read the file named as a Hacefile]:file:_files' \
              '(-n --dry-run)'{-n,-dry-run}'[Don'''t actually run any commands]' \
              '(-q --quiet)'{-q,-quiet}'[Don'''t log anything]' \
              '(-v --verbosity)'{-v,-verbosity=}'[Control the logging verbosity, 0 to 5]:verbosity:(0 1 2 3 4 5)' \
              '(-B --always-make)'{-B,-always-make}'[Unconditionally run all tasks]' \
              '(-k --keep-going)'{-k,-keep-going}'[Continue as much as possible after an error]' \
              '(--parallel)--parallel[Run tasks in parallel when possible]' \
              '(--question)--question[Don'''t run anything, exit 0 if all tasks are up to date]' \
              '(--list)--list[List available tasks]' \
              '(--auto)--auto[Run in auto mode, watching for file changes]' \
              '(--convert)--convert[Convert a Makefile to Hacefile YAML]' \
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
  end
end
