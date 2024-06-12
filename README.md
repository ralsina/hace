# Hacé

Hacé makes things like make, but not the same.

Its functionality is mostly derived from using
[Croupier](https://github.com/ralsina/croupier), a dataflow library.

[![Docs](https://github.com/ralsina/hace/actions/workflows/static.yml/badge.svg)](https://ralsina.github.io/hace/)
[![License](https://img.shields.io/badge/License-MIT-green)](https://github.com/ralsina/hace/blob/main/LICENSE)
[![Release](https://img.shields.io/github/release/ralsina/hace.svg)](https://GitHub.com/ralsina/hace/releases/)
[![News about Hace](https://img.shields.io/badge/News-About%20Hace-blue)](https://ralsina.me/categories/hace.html)

[![Tests](https://github.com/ralsina/hace/actions/workflows/ci.yml/badge.svg)](https://github.com/ralsina/hace/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ralsina/hace/branch/main/graph/badge.svg?token=YW23EDL5T5)](https://codecov.io/gh/ralsina/hace)
[![Mutation Tests](https://github.com/ralsina/hace/actions/workflows/mutation.yml/badge.svg)](https://github.com/ralsina/hace/actions/workflows/mutation.yml)

## Installation

If you have `crystal` and `shards` installed, you can do:

```sh
git clone git@github.com:ralsina/hace.git
cd hace
shards build --release
cp bin/hace ~/.local/bin  # or wherever you want it
```

Binaries for Linux in amd64 are available in [the releases page](https://github.com/ralsina/hace/releases).

## Usage

You can use the `hace` command to run tasks from a `Hacefile.yml` in the current
directory.

```console
$ ./bin/hace --help
  hace - hace makes things, like make

  Usage:
    hace [command] [flags] [arguments]

  Commands:
    auto            Run in auto mode
    help [command]  Help about any command.

  Flags:
    -n, --dry-run      Don't actually run any commands
    -f, --file         Read the file named as a Hacefile default: 'Hacefile.yml'
    -h, --help         Help for this command.
    -k, --keep-going   Continue as much as possible after an error.
        --question     Don't run anything, exit 0 if all tasks are up to date, 1 otherwise
    -q, --quiet        Don't log anything
    -B, --always-make  Unconditionally run all tasks.
    -v, --verbosity    Control the logging verbosity, 0 to 5  default: 3
```

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
    dependencies:
      - bar
    commands: |
      echo "make foo out of bar" > foo
      cat bar >> foo
```

This defines a task named `foo` that depends on `bar` and runs two commands.

Because it's marked as `default` it will be run if you don't specify any
tasks on the command line.

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

### Dependencies

Dependencies are files. Hacefile will try to run tasks only if a dependency
has changed since the last time the task was run.

If a dependency is the output of another task, then that task will run
first (if needed).

If a dependency is missing and the Hacefile doesn't describe how to
generate it, the task is not ready to run, and there will be an error.

Tasks without dependencies are always considered "out of date" and
will always run if you ask for them.

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
expand them using in commands with `${PATH}` or any other usual
shell mechanism.

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
$ hace foo VAR=VALUE
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
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

* [Roberto Alsina](https://github.com/ralsina) - creator and maintainer
