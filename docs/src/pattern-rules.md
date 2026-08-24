# Pattern Rules

When a Hacefile grows past a handful of near-identical tasks, patterns let a
single rule cover all of them. They are hacé's equivalent of make's implicit
rules (`%.o: %.c`).

## Defining patterns

Patterns live in a top-level `patterns:` section. Each entry is a template
with exactly one `%` in its output marking the *stem*:

```yaml
variables:
  CC: gcc

patterns:
  - outputs: ["%.o"]
    dependencies: ["%.c"]
    commands: |
      {{ CC }} -c {{ self["dependencies"][0] }} -o {{ self["outputs"][0] }}

tasks:
  app:
    default: true
    dependencies:
      - hello.o        # no explicit hello.o task needed!
    commands: |
      {{ CC }} -o {{ self["outputs"][0] }} {{ self["dependencies"] | join(" ") }}
```

## How instantiation works

When hacé needs a dependency that no explicit task produces, it tries each
pattern in declaration order. The first match whose dependencies can all be
resolved is turned into a concrete task:

- The stem (`hello` for `hello.o`) replaces every `%` in the pattern's
  dependencies and is available in commands as `{{ self["stem"] }}`
- Like any task, the synthesized one has `self["outputs"]`,
  `self["dependencies"]`, variables, and CLI overrides available:
  `hace app CC=clang` just works
- Instantiation happens even when the output file already exists, so editing
  `hello.c` correctly marks `hello.o` for rebuild (staleness is content
  based, not timestamp based)

## Chaining

Synthesized tasks go through the same resolution as everything else, so
patterns can stack:

```yaml
patterns:
  - outputs: ["%.c"]
    dependencies: ["%.tpl"]
    commands: |
      render --output {{ self["outputs"][0] }} {{ self["dependencies"][0] }}
  - outputs: ["%.o"]
    dependencies: ["%.c"]
    commands: |
      cc -c {{ self["dependencies"][0] }} -o {{ self["outputs"][0] }}
```

With only `greeting.tpl` on disk, requesting `greeting.o` first synthesizes
`greeting.c` from the template, then compiles it.

## Resolution rules

- **Explicit tasks always win.** A pattern never overrides a task you wrote,
  even for the same output name.
- **Prerequisites must be producible.** A pattern instantiates only if every
  dependency exists on disk, is produced by some task, or could itself be
  produced by another pattern. An existing file with no way to rebuild its
  prerequisites (say, a checked-in `artifact.o` with no `artifact.c`) is
  left alone as a plain file dependency.
- **Requested targets instantiate on demand.** `hace foo.o` builds `foo.o`
  through a pattern even when no other task mentions it.
- Self-referential pattern families (like `%.x` requiring `%.x.z`) are
  detected and simply do not instantiate; hacé terminates instead of looping.

## Listing

`hace --list` shows the instances your Hacefile would generate, with the
source pattern noted in the description column:

```text
TASK             DESCRIPTION                                       PHONY   DEFAULT
---------------- ------------------------------------------------- ------- -------
app              No description                                            ✓
hello.o          generated for hello.o (from pattern %.o)
```

Unlike make, intermediate files (such as a generated `.c` between a template
and an object file) are kept after the build.
