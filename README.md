# Hacé

Hacé makes things like make, but not the same.

Its functionality is mostly derived from using
[Croupier](https://github.com/ralsina/croupier), a dataflow library.

[![License](https://img.shields.io/badge/License-MIT-green)](https://github.com/ralsina/hace/blob/main/LICENSE)
[![Release](https://img.shields.io/github/release/ralsina/hace.svg)](https://GitHub.com/ralsina/hace/releases/)
[![News about Hace](https://img.shields.io/badge/News-About%20Hace-blue)](https://ralsina.me/categories/hace.html)

[![Tests](https://github.com/ralsina/hace/actions/workflows/ci.yml/badge.svg)](https://github.com/ralsina/hace/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ralsina/hace/branch/main/graph/badge.svg?token=YW23EDL5T5)](https://codecov.io/gh/ralsina/hace)
[![Mutation Tests](https://github.com/ralsina/hace/actions/workflows/mutation.yml/badge.svg)](https://github.com/ralsina/hace/actions/workflows/mutation.yml)

## Installation

### Pre-built Binaries (Recommended)

**GitHub Releases**: Static binaries for Linux are available from the [releases page](https://github.com/ralsina/hace/releases). No Crystal installation required.

```sh
# Linux amd64
wget https://github.com/ralsina/hace/releases/latest/download/hace-static-linux-amd64
chmod +x hace-static-linux-amd64
sudo mv hace-static-linux-amd64 /usr/local/bin/hace

# Linux ARM64
wget https://github.com/ralsina/hace/releases/latest/download/hace-static-linux-arm64
chmod +x hace-static-linux-arm64
sudo mv hace-static-linux-arm64 /usr/local/bin/hace
```

**Arch Linux (AUR)**: Available as the `hace` package in the [AUR](https://aur.archlinux.org/packages/hace):

```sh
yay -S hace  # Using yay AUR helper
# or
git clone https://aur.archlinux.org/hace.git && cd hace && makepkg -si
```

### Build from Source

If you have `crystal` and `shards` installed, you can build from source:

```sh
git clone git@github.com:ralsina/hace.git
cd hace
shards build
cp bin/hace ~/.local/bin  # or wherever you want it
```

## Usage

You can use the `hace` command to run tasks from a `Hacefile.yml` in the current
directory.

```console
$ ./bin/hace --help
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
  --convert                    Convert the file given with -f (a Makefile) to Hacefile
                               YAML and print it to stdout
  --completion=<shell>         Generate shell completion script (bash, fish, zsh)
  --version                    Display version information
  -h, --help                   Show this help message
```

## Using Makefiles

Hacé can run basic Makefiles directly, and can convert them into `Hacefile.yml`
files:

```console
# Run a project that only has a Makefile: hace detects it and converts it on
# the fly. Works with -f too: hace -f Makefile build
$ hace build

# Convert a Makefile into a Hacefile.yml, review it, and keep it:
$ hace --convert > Hacefile.yml
```

The supported subset covers what most small Makefiles use:

* Rules with prerequisites and tab-indented recipes; multiple targets in a
  rule become multiple outputs
* Variables (`=`, `:=`, `?=` and `+=`), including chained references.
  References in recipes become Jinja templates, so `$(CC)` behaves like
  `{{ CC }}` and can be overridden from the command line (`hace build CC=clang`)
* The automatic variables `$@`, `$<`, `$^`, `$*` and `$$` escaping
* `.PHONY` and `.DEFAULT_GOAL`; the first rule is the default task
* Pattern rules such as `%.o: %.c` become hacé pattern rules (see below)
* `export VAR=value` becomes an environment entry, a `SHELL` variable sets the
  shell, comments and backslash line continuations are handled

Make features that have no hacé equivalent (conditionals like `ifeq`,
functions like `$(wildcard ...)`, `include`, target-specific variables,
static pattern rules) are skipped with a warning naming the offending line,
so conversion never aborts: check the output for anything you need to port
by hand.

## Pattern rules

When a Hacefile grows past a handful of similar tasks, patterns let one rule
cover them all. A top-level `patterns:` section defines templates that hacé
instantiates on demand, like make's implicit rules:

```yaml
variables:
  CC: gcc

patterns:
  - outputs: ["%.o"]          # exactly one '%' marks the stem
    dependencies: ["%.c"]     # each '%' becomes the matched stem
    commands: |
      {{ CC }} -c {{ self["dependencies"][0] }} -o {{ self["outputs"][0] }}

tasks:
  app:
    dependencies:
      - hello.o               # no explicit hello.o task needed!
    commands: |
      {{ CC }} -o {{ self["outputs"][0] }} {{ self["dependencies"] | join(" ") }}
```

How it works:

* When a dependency is not produced by any explicit task, hacé tries the
  patterns in order; the first match whose dependencies all resolve creates
  a concrete task (`hello.o` above) with the stem substituted everywhere,
  exposed as `{{ self["stem"] }}`
* Patterns chain: a synthesized task's own dependencies go through the same
  resolution, so `%.c: %.tpl` can sit behind `%.o: %.c`
* Instantiation happens even if the output file already exists, so editing
  `hello.c` correctly rebuilds `hello.o` — staleness is content-based, not
  timestamp-based
* Explicit tasks always win over patterns; an existing file with no way to
  produce its prerequisites is left alone
* Targets requested on the command line work too: `hace foo.o` builds it via
  a pattern even when nothing else mentions it
* `--list` shows the instances a Hacefile would generate; unlike make,
  intermediate files are left in place after the build

Two deliberate simplifications to keep in mind:

* Variable values are resolved when the file is converted, so recursive
  variables must be defined before they are used (true of most real
  Makefiles).
* Rules without a recipe (pure dependency aggregators like `all: app`) become
  phony hacé tasks, which means `--question` always considers them stale.

The arguments are task names, and if you don't specify any, the default
tasks will execute.

That's easy, right? Well, that's because the complicated bit is the Hacefile 😃

## The Hacefile

The Hacefile is a [YAML file](https://spacelift.io/blog/yaml) that
describes the tasks you want to run.
Conceptually it's a lot like a Makefile, but the syntax and semantics are
quite different.

Here's a simple example, details to be explained below:

```yaml
tasks:
  foo:
    default: true
    dependencies:
      - bar
    commands: |
      echo "make foo out of bar" > foo
      cat bar >> foo
  phony:
    phony: true
    commands: echo "bat" > bat
```

## Tasks

A task is a named set of shell commands that are run in order, and they go
under the `tasks` toplevel key. For example:

```yaml
tasks:
  foo:
    default: true
    cwd: /tmp
    dependencies:
      - bar
    commands: |
      echo "make foo out of bar" > foo
      cat bar >> foo
```

This defines a task named `foo` that depends on `bar` and runs two commands.

Because it's marked as `default` it will be run if you don't specify any
tasks on the command line.

The optional `cwd` key sets the current working directory for the task.

### Commands

The commands are a string that can be multiple lines, and they are run in
order. If any command fails, the task fails.

Each line should be a valid shell command, and they are run in a shell. The
shell is `/bin/sh` on linux and `cmd.exe` on windows (please note that
nobody has ever tried this tool on windows AFAIK).

Commands are in fact templates using
[Jinja](https://github.com/straight-shoota/crinja) syntax,
see [Variables](#variables) below for more details and examples.

### Outputs

A task can have zero, one, or multiple outputs. If a task declares it has
outputs but fails to create them, it's considered to have failed.

In the example above, there is no explicit `outputs` key, so the task has
one output, named like the task itself: `foo`.

A task can declare it generates no outputs by tagging itself as `phony`:

```yaml
task2:
  dependencies:
    - bar
  phony: true
  commands: |
    notify-send "Done: $(cat bar)"
```

This example shows a notification on screen with the contents of the file
`bar` but doesn't actually create any files.

If a task generates multiple outputs, you can declare them like this:

```yaml
task3:
  dependencies:
    - bar
  outputs:
    - baz
    - bat
  commands: |
    echo "This is baz" > baz
    echo "This is bat" > bat
```

This task is **called** `task3` but it generates two files, `baz` and `bat`.

**⚠️WARNING:** You can have two tasks with the same output, but you can't
have two tasks with the same name.

**⚠Warning:** If there are two tasks with the same
output, Hacé will run them both, and the second one will overwrite the
first. This is a bug, and will be fixed.

Outputs can interpolate variables and environment variables.

### Dependencies

Dependencies are files or task names. Hacefile will try to run tasks only
if a dependency file has changed since the last time the task was run or
if a task dependency itself would run.

If a dependency is the output of another task, then that task will run
first (if needed).

If a dependency is missing and the Hacefile doesn't describe how to
generate it, the task is not ready to run, and there will be an error.

Tasks without dependencies are always considered "out of date" and
will always run if you ask for them.

Dependencies can interpolate variables and environment variables.

Dependencies will expand "globs", such as "*", "**" and "?"

### Default tasks

If a task has `default` set to `true`, it will run when no task is
specified on the command line. You have to set this explicitly if
you want it, otherwise no task will run unless explicitly required.

### Always Run

If a task has `always_run` set to `true`, it will run even if it's
not out of date. This is useful for tasks that don't have outputs.

## Environment variables

Just an ordinary map of environment variables in the `env` top
key. The variables will be available to all tasks and you can
expand them using in commands, dependencies and outputs with `${PATH}`

Any variables in the environment when the Hacefile is loaded will
also be in the environment.

Hacé also supports automatic loading of environment variables from
`.env` files. See the [Environment Variables Documentation](docs/src/environment.md)
for detailed information about dotenv support.

If you want to *unset* a variable, set it to `null`. If you want
it set to an empty value, use `""`.

```yaml
env:
  FOO: bar
  BAZ: null
```

## Variables

You can declare variables in the `variables` top level key. They are
available to all tasks, which can use them in their commands
using a [Jinja](https://github.com/straight-shoota/crinja) template language syntax.

A special variable is `self` which is the task itself, so you can
use the task itself to define parts of the commands it contains.

**⚠️⚠️WARNING⚠️⚠️** These are *not* [environment variables](#environment-variables).

```yaml
variables:
  i: 3
  s: "string"
  foo:
    bar: "bat"
    foo: 86
tasks:
  foo:
    dependencies:
      - bar
    commands: |
      echo "make foo out of {{ foo['bar'] }} at {{ i }}" > foo
      cat {{ self["dependencies"][0] }} >> foo
```

In that example, it's doing `cat bar >> foo` because that's in
`self["dependencies"]`. This may look a bit confusing but I expect
it will be useful.

Currently the available members of `self` are:

* commands: all commands
* dependencies: all dependencies, as an array
* phony: boolean
* default: boolean
* outputs: all outputs, as an array

You can also set variables from the command line. This example sets `VAR` to `VALUE`:

```sh
hace foo VAR=VALUE
```

Variables can interpolate environment variables:

```yaml
variables:
  dest_dir: "${HOME}/.local/bin"
```

Because we are using [templates](https://github.com/straight-shoota/crinja/blob/master/TEMPLATE_SYNTAX.md)
you can even do things like this:

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

## CLI Arguments Passthrough

You can pass arguments directly to task commands using the `--` separator:

```bash
hace spec -- --verbose --tag=fast
```

Arguments after `--` are available in your Hacefile as template variables:

* `{{CLI_ARGS}}` - Shell-quoted string of all passthrough arguments
* `{{CLI_ARGS_LIST}}` - Array for Jinja iteration

### Explicit Usage

Place `{{CLI_ARGS}}` where you want the arguments to appear:

```yaml
tasks:
  spec:
    phony: true
    commands: |
      crystal spec {{CLI_ARGS}}
```

Running `hace spec -- --verbose` executes: `crystal spec --verbose`

### Iterating Over Arguments

Use `{{CLI_ARGS_LIST}}` with Jinja loops:

```yaml
tasks:
  test-each:
    phony: true
    commands: |
      {% for arg in CLI_ARGS_LIST %}
      echo "Testing with: {{arg}}"
      crystal spec {{arg}}
      {% endfor %}
```

### Auto-Append Behavior

If your commands don't use `{{CLI_ARGS}}` explicitly, passthrough arguments
are automatically appended to the last command:

```yaml
tasks:
  spec:
    phony: true
    commands: |
      echo "Running tests..."
      crystal spec
```

Running `hace spec -- --verbose` executes:

1. `echo "Running tests..."`
1. `crystal spec --verbose` (arguments auto-appended to last command)

### Shell Quoting

Arguments containing spaces or special characters are automatically shell-quoted:

```bash
hace spec -- "--tag=slow test"
# Becomes: crystal spec '--tag=slow test'
```

## Development

See [TODO.md](TODO.md) for a list of things that are not done yet,
as well as things that were considered and decided against (TODON'T 😀)

Main things to consider if you want to contribute:

* Take tests seriously. When a project is small, it's easy to test
  everything.

  When it's big, it's impossible to test everything. So, start testing early
  and keep testing often.

* Take documentation seriously. If you don't document it, it doesn't exist.

## Contributing

1. Fork it (<https://github.com/ralsina/hace/fork>)
1. Create your feature branch (`git checkout -b my-new-feature`)
1. Commit your changes (`git commit -am 'Add some feature'`)
1. Push to the branch (`git push origin my-new-feature`)
1. Create a new Pull Request

## Contributors

* [Roberto Alsina](https://github.com/ralsina) - creator and maintainer
