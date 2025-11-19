# Hacefile.yml Format

The `Hacefile.yml` is the heart of Hacé. This document covers the complete format and syntax.

## Basic Structure

```yaml
# Environment variables (optional)
env:
  PATH: "/custom/path"
  DEBUG_VAR: null

# Global variables (optional)
variables:
  source_dir: "src"
  build_dir: "build"
  version: "1.0.0"

# Task definitions
tasks:
  task_name:
    # Task properties
```

## Top-Level Sections

### Environment Variables

```yaml
env:
  # Set environment variables
  PATH: "/custom/path:$PATH"
  NODE_ENV: "production"

  # Unset environment variables (set to null)
  DEBUG_VAR: null

  # Set empty string
  EMPTY_VAR: ""
```

### Global Variables

```yaml
variables:
  source_dir: "src"
  build_dir: "build"
  version: "1.0.0"
  author: "Your Name"

  # Variables can reference other variables (limited)
  project_name: "myapp"
  full_name: "{{ author }}/{{ project_name }}"
```

## Task Properties

Each task in the `tasks` section can have the following properties:

### commands

**Required**: Commands to execute. Can be a single string or multi-line string.

```yaml
tasks:
  simple:
    commands: "echo 'Hello World'"

  multi-line:
    commands: |
      echo "Starting build..."
      mkdir -p {{ build_dir }}
      crystal build src/main.cr -o {{ build_dir }}/app
      echo "Build complete!"
```

### dependencies

**Optional**: Files or tasks this task depends on.

```yaml
tasks:
  compile:
    dependencies:
      # File patterns with glob support
      - "src/**/*.cr"
      - "lib/**/*.cr"
      - "shard.yml"

      # Other tasks (by name)
      - install_deps

      # Mixed
      - "config/*.json"
      - setup

  test:
    dependencies:
      # Depend on another task
      - compile
      # And on test files
      - "spec/**/*.cr"
```

### outputs

**Optional**: Files this task produces. If not specified, defaults to task name.

```yaml
tasks:
  # Single output (defaults to task name)
  build_app:
    # outputs: ["build_app"]  # implicit

  # Multiple outputs
  generate_docs:
    outputs:
      - "docs/index.html"
      - "docs/api.html"
      - "docs/guide.html"

  # No outputs (phony task)
  clean:
    phony: true
    # outputs: []
```

### phony

**Optional**: Boolean indicating if this task produces no files. Defaults to `false`.

```yaml
tasks:
  deploy:
    phony: true
    commands: |
      echo "Deploying to production..."

  build:
    # phony: false  # implicit
    outputs:
      - "bin/myapp"
```

### default

**Optional**: Boolean indicating if this task should run when no tasks are specified. Defaults to `false`.

```yaml
tasks:
  build:
    default: true
    commands: |
      crystal build src/main.cr

  test:
    # default: false  # implicit
    commands: |
      crystal spec
```

### always_run

**Optional**: Boolean indicating if this task should always run, even when dependencies are up-to-date. Defaults to `false`.

```yaml
tasks:
  publish_version:
    always_run: true
    commands: |
      echo "Publishing version {{ version }}"
```

### cwd

**Optional**: Working directory for this task's commands. Defaults to current directory.

```yaml
tasks:
  build_in_subdir:
    cwd: "build"
    commands: |
      pwd  # Will show build directory
      make
```

## Complete Example

```yaml
env:
  NODE_ENV: "production"
  API_KEY: null

variables:
  source_dir: "src"
  build_dir: "build"
  version: "2.1.0"

tasks:
  install_deps:
    phony: true
    commands: |
      shards install

  build:
    default: true
    dependencies:
      - install_deps
      - "{{ source_dir }}/**/*.cr"
      - "shard.yml"
    outputs:
      - "{{ build_dir }}/myapp"
    cwd: "."
    commands: |
      mkdir -p {{ build_dir }}
      crystal build {{ source_dir }}/main.cr -o {{ build_dir }}/myapp

  test:
    dependencies:
      - build
      - "spec/**/*.cr"
    phony: true
    commands: |
      {{ build_dir }}/myapp --test
      crystal spec

  package:
    dependencies:
      - build
      - test
    outputs:
      - "dist/myapp-{{ version }}.tar.gz"
    commands: |
      mkdir -p dist
      tar czf dist/myapp-{{ version }}.tar.gz {{ build_dir }}/myapp

  clean:
    phony: true
    commands: |
      rm -rf {{ build_dir }}
      rm -rf dist

  deploy:
    phony: true
    always_run: true
    dependencies:
      - package
    commands: |
      echo "Deploying myapp-{{ version }} to production..."
```

## File Naming

Hacé looks for configuration files in this order:

1. `Hacefile.yml`
2. `hacefile.yml`
3. `.hace.yml`
4. `Hacefile.yaml`
5. `hacefile.yaml`
6. `.hace.yaml`

You can specify a custom file with `-f` or `--file`:

```bash
hace -f custom-build.yml
```

## Validation

Hacé validates your Hacefile.yml for:

- Required properties
- Valid YAML syntax
- Circular dependencies (handled by Croupier)
- Unknown task references (warnings, not errors)

Common validation errors:

```yaml
# Missing commands property
invalid_task:
  dependencies:
    - "src/**/*.cr"

# Circular dependency (detected at runtime)
task_a:
  dependencies:
    - task_b

task_b:
  dependencies:
    - task_a
```
