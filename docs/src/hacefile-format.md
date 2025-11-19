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

# Global shell configuration (optional)
shell: "bash -e"

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

### Global Shell Configuration

```yaml
# Default shell for all tasks
shell: "bash -e -c"

# You can use any shell
shell: "sh -c"           # Standard POSIX shell
shell: "bash -e -c"       # Bash with fail-fast
shell: "zsh -e -c"        # Zsh with fail-fast
shell: "python -c"        # Python for scripts
shell: "cmd.exe /c"       # Windows Command Prompt
shell: "powershell -c"    # PowerShell
```

> **Note**: Users are responsible for providing correct shell arguments. Hacé adds the script to the shell arguments (after any existing `-c` flag or at the end).

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

### shell

**Optional**: Shell for executing this task's commands. Overrides global shell configuration. Defaults to global shell or `/bin/sh -e -c`.

```yaml
tasks:
  build_with_fail_fast:
    shell: "bash -e -c"
    commands: |
      echo "Building with fail-fast..."
      make
      echo "Build completed!"

  build_continue_on_error:
    shell: "sh -c"
    commands: |
      echo "Building without fail-fast..."
      make  # might fail, but execution continues
      echo "Build attempted!"

  python_script:
    shell: "python -c"
    commands: |
      import os
      print("Python script executing...")
      os.system("make")
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
# Global configuration
env:
  NODE_ENV: "production"
  API_KEY: null

variables:
  source_dir: "src"
  build_dir: "build"
  version: "2.1.0"

# Default shell with fail-fast behavior
shell: "bash -e -c"

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
    shell: "sh -c"  # Continue testing even if some specs fail
    dependencies:
      - build
      - "spec/**/*.cr"
    phony: true
    commands: |
      echo "Running tests..."
      {{ build_dir }}/myapp --test || echo "Some tests failed, but continuing..."
      crystal spec || echo "Spec suite had issues"

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

## Shell Execution Model

Hacé uses **combined script execution** which means:

1. **All commands in a task run in a single shell process**
2. **Environment variables persist across commands** within the same task
3. **Shell state is maintained** (working directory, variables, functions)
4. **Better performance** than spawning separate shells for each command

```yaml
tasks:
  setup:
    commands: |
      export BUILD_ID=$(date +%s)
      echo "Build ID: $BUILD_ID"     # Environment variable persists
      cd {{ build_dir }}              # Working directory change persists
      echo "Current dir: $(pwd)"       # Shows the changed directory
      make -j$(nproc)                 # Uses the same shell state
```

### Fail-Fast Behavior

- **Default shell** (`/bin/sh`): Automatically uses `-e` flag for fail-fast
- **User-specified shells**: No automatic fail-fast, user controls behavior
- **Task override**: Task-specific shell overrides global shell configuration

```yaml
# Global fail-fast (recommended for builds)
shell: "bash -e -c"

tasks:
  build:
    # Inherits fail-fast behavior from global shell
    commands: |
      make           # If this fails, execution stops
      make test       # Won't run if make failed

  test:
    shell: "sh -c"       # Override: no fail-fast
    commands: |
      make test || echo "Some tests failed, but continuing..."
      make coverage   # Will run even if tests failed
```

### Cross-Platform Shell Support

Users can specify any shell or interpreter:

```yaml
tasks:
  unix_task:
    shell: "bash -e -c"
    commands: |
      echo "Unix-specific commands"

  windows_task:
    shell: "cmd.exe /c"
    commands: |
      echo Windows batch commands

  python_script:
    shell: "python -c"
    commands: |
      import subprocess
      print("Python script running")
      subprocess.run(["make", "test"])

  ruby_script:
    shell: "ruby -e"
    commands: |
      puts "Ruby script executing"
      system("make", "build")
```

> **Important**: Users are responsible for providing correct shell syntax and arguments. Hacé passes the combined script to the specified shell and lets it handle execution.

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
