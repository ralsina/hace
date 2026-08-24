# Using Makefiles

Hacé can run projects that only have a `Makefile`, and can convert basic
Makefiles into `Hacefile.yml` files so you can migrate incrementally.

## Running a Makefile directly

When no `Hacefile.yml` exists in the current directory, hacé looks for a
Makefile under its conventional names (`GNUmakefile`, `makefile`,
`Makefile`) and uses it transparently:

```bash
cd some-make-project
hace            # runs the default goal
hace clean      # runs any target by name
```

You can also point at it explicitly:

```bash
hace -f Makefile build
```

The Makefile is converted on the fly on every run and then processed exactly
like a native Hacefile, so variables, dependency tracking, parallel execution
and everything else behave normally.

## Converting once with --convert

To migrate a project, convert the file, review it, and keep what you like:

```bash
hace --convert > Hacefile.yml
$EDITOR Hacefile.yml
```

`--convert` prints the converted YAML to standard output; nothing is written
or overwritten automatically.

## Supported subset

The converter covers what most small Makefiles use:

- Rules with prerequisites and tab-indented recipes; multiple targets in one
  rule become multiple outputs
- Variables (`=`, `:=`, `?=` and `+=`), including chained references.
  References in recipes become Jinja templates, so `$(CC)` behaves like
  `{{ CC }}` and can be overridden from the command line:
  `hace build CC=clang`
- Automatic variables: `$@`, `$<`, `$^`, `$*` and `$$` escaping
- Pattern rules such as `%.o: %.c`, which become hacé pattern rules (see
  [Pattern Rules](pattern-rules.md))
- `.PHONY` and `.DEFAULT_GOAL`; the first rule becomes the default task
- Rules without a recipe (pure aggregators like `all: app`) become phony
  tasks
- `export VAR=value` becomes an environment entry; a `SHELL` variable sets
  the shell
- Comments, backslash line continuations, duplicate rule merging, and the
  `@`/`-` recipe prefixes (`-` is approximated with `|| true`)

## What is not supported

Features without a hacé equivalent are skipped with a warning naming the
offending line; conversion never aborts because of them:

- Conditionals (`ifeq`, `ifdef`, ...)
- Functions (`$(wildcard ...)`, `$(patsubst ...)`, ...). These are left in
  place literally, so remove or replace them by hand
- `include` / `-include`
- Target-specific variables (`target: VAR = value`)
- Static pattern rules (`objs: %.o: %.c`)
- Order-only prerequisites (everything after `|` is dropped)

Always check the conversion output (and the warnings) before trusting a
migrated file.

## Deliberate simplifications

- Variable values are resolved when the file is converted, so recursive
  variables must be defined before they are used. This matches simply
  expanded (`:=`) make variables and how virtually all real Makefiles are
  written.
- Undefined variables expand to nothing, exactly like in make.
- Rules without a recipe become phony tasks, so `--question` always
  considers them stale even when everything they depend on is fresh.
