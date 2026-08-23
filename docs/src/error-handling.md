# Error Handling

Hacé tries to fail loudly and early, in ways that are safe for scripts
and CI pipelines.

## Exit codes

- **0**: success. In `--question` mode, it also means "nothing is stale".
- **1**: any failure: a task command returned a non-zero status, the
  Hacefile is missing or invalid, a requested task does not exist,
  `--question` found stale tasks, or the command line is malformed.

## Unknown tasks

Requesting a task that is not defined is an error, not a warning:

```console
$ hace buidl
Error: Unknown task(s): buidl. Available tasks: build, test, lint
```

All unknown names are reported at once, along with the tasks that do
exist, so typos are easy to spot. The exit code is 1.

## Command failures

Commands run through a shell with fail-fast semantics by default (see the
[shell documentation](hacefile-format.md#global-shell-configuration)):
as soon as one command in a task fails, the rest of that task's commands
are skipped and the task fails with an error like:

```text
Command failed: exit 2
```

Dependent tasks don't run when their dependencies fail, unless
`--keep-going` is used, which runs as much as possible before reporting
failure.

## Hacefile problems

A missing Hacefile produces:

```text
No Hacefile 'Hacefile.yml' found
```

Invalid YAML or template errors produce a message that includes the
underlying cause, for example:

```text
Error parsing Hacefile 'Hacefile.yml': undefined_var is undefined.
```

In both cases the exit code is 1 and nothing is executed.
