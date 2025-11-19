# TODO, Bugs and stuff

* ✅ Need to refactor/cleanup `run()` which is getting a bit long
* Tasks with common outputs are problematic (hey, also in Makefiles)
* ✅ Make dry-run more interesting (show commands that would run)
* ✅ There is no way to get hace's version
* ✅ Mutation test fails becaus question mode is not tested
* ✅ `question` mode doesn't work
* ✅ Doesn't complain when an unknown task is requested
* ✅ Tests are broken (probably harness)
* ✅ auto mode doesn't really work
* ✅ Command output is not visible in the log
* ✅ Tasks with outputs fail with "ERROR: Unknown output taskname"
* ✅ Support variables in more values, not only commands
* ✅ Allow for parallel task execution
* ✅ Tasks with wildcard dependencies
* ✅ Something equivalent to static patterns:

  `$(objects): %o: %c`

  You can do this with a [task that has a variable as `outputs`.](https://github.com/ralsina/hace/blob/main/spec/testcases/expand-arrays/Hacefile.yml)
* ✅ Something like pattern rules: `%o : %c`

  You can do this by having wildcards as source and iterating:

  ```yaml
  tasks:
    foo:
      default: true
      outputs:
        - foo
      dependencies:
        - "*.c"
      commands: |
        {% for dep in self["dependencies"] %} gcc -c {{dep}} {% endfor %}
  ```
* ✅ Set variables from the command line
* ✅ Handle using both task names and targets in CLI
* ✅ Implemented -k to keep going after errors
* ✅ Use croupier's "auto mode"
* ✅ Implement make's `--question` option
* ✅ Tasks that always run
* ✅ Implement dry run
* ✅ Make default tasks opt-in instead of opt-out
* ✅ Add equivalent of make's `-f` option
* ✅ Automatic variables (like make's `$@`)
* ✅ Logging / Verbosity management
* ✅ Multiple outputs
* ✅ Mark some tasks as "default" which run when no task is specified
* ✅ Add -B --always-make option like make
* ✅ Environment variables
* ✅ Templated tasks~
* ✅ Real command line interface
* ✅ The equivalent of PHONY tasks
* ✅ Variables
* ✅ Shell selection and combined script execution

  Successfully implemented cross-platform shell selection with combined
  script execution for environment variable persistence. Users can specify
  any shell (bash, zsh, python, cmd.exe, etc.) with proper arguments.
  Default fail-fast behavior with user control.

## Things that may be a good idea to add

Note that some of these may not be possible to implement,
in which case they will move to the "bad ideas" section.

Or, they may require special support from Croupier, in which
case they will take a little longer.

Not ordered in any particular way.

* Have empty `outputs` be phony rather than defaulting to task name?
* Very basic Makefile parser when there is no Hacefile

* Add equivalent of make's `-i` option to
  ignore errors (Requires Croupier support)
* Support merging multiple Hacefiles from the CLI
* Embed JS in tasks using duktape.cr

## Things that look like bad ideas and why

* Implicit rules.

  make does things like automatically use `$(CC)` to build `.c` files.
  this is both confusing (runs random unconfigured commands)
  and of limited usefulness (if you want make, use make)
