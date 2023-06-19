# Hacé

Hacé makes things like make, but not the same.

## Installation

If you have `crystal` and `shards` installed, you can do:

```sh
git clone git@github.com:ralsina/hace.git
cd hace
shards build --release
cp bin/hace ~/.local/bin  # or wherever you want it
```

At some point I'll provide binaries but not yet.

## Usage

You can use the `hace` command to run tasks from a `Hacefile.yml` in the current
directory.

```sh
> bin/hace --help
  hace - hace makes things, like make

  Usage:
    hace [flags] [arguments]

  Commands:
    help [command]  Help about any command.

  Flags:
    -h, --help         Help for this command.
    -B, --always-make  Unconditionally run all tasks.
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
    dependencies:
      - bar
    commands: |
      echo "make foo out of bar" > foo
      cat bar >> foo
```

This defines a task named `foo` that depends on `bar` and runs two commands.

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

**⚠️⚠️WARNING⚠️⚠️:** You can have two tasks with the same output, but you can't
have two tasks with the same name. If there are two tasks with the same
output, Hacé will try to do the right thing but it's going to be tricky
so consider this warning.

### Dependencies

Dependencies are files. If a dependency has changed since the last time
the task was run, the task runs again.

If a dependency is the output of another task, then that task will run
first if needed.

If a dependency is missing and the Hacefile doesn't describe how to
generate it, the task is not ready to run, and there will be an error.

### Default tasks

If a task has `default` set to `true`, it will run when no task is
specified on the command line. Currently all tasks are `default`
unless you set `default: false`, but that **will** change.

## Environment variables

Just an ordinary map of environment variables in the `env` top
key. The variables will be available to all tasks and you can
expand them using in commands `${PATH}` or any other usual
shell mechanism.

If you want to *unset* a variable, set it to `null`. If you want
it set to an empty value, use `""`.

```yaml
env:
  FOO: bar
  BAZ: null
```

## Variables

You can declare variables in the `vars` top key. They are
available to all tasks, which can use them in their commands
using a [Jinja](https://github.com/straight-shoota/crinja) template language syntax.

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
