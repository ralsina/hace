# Command Line Options

Hacé provides a rich set of command line options for controlling its behavior.

## Basic Usage

```bash
hace [OPTIONS] [TASKS...] [VARIABLES...]
```

## Options

### `-f, --file <FILE>`

Specify a custom Hacefile.

```bash
hace -f custom-build.yml
hace --file production.yml build
```

### `-n, --dry-run`

Show what would be executed without actually running commands.

```bash
hace --dry-run build
```

### `--question`

Check if tasks are stale (need to run) without executing them.

```bash
hace --question
# Output: build: stale
# Output: test: up-to-date
```

### `-B, --always-make`

Force all tasks to run, ignoring dependency timestamps.

```bash
hace --always-make
```

### `--list`

List all available tasks with their descriptions and properties in a formatted table.

```bash
hace --list
```

The table shows:

- **TASK**: Task name
- **DESCRIPTION**: Brief description of what the task does
- **PHONY**: ✓ if task has no file outputs
- **DEFAULT**: ✓ if task runs by default when no tasks specified
- **ALWAYS**: ✓ if task always runs regardless of dependencies

### `--auto`

Enable auto-monitoring mode. Hacé will watch for file changes and rebuild automatically.

```bash
hace --auto
```

### `-q, --quiet`

Suppress normal output, only show errors.

```bash
hace --quiet build
```

### `-k, --keep-going`

Continue as much as possible after an error.

```bash
hace --keep-going build test deploy
```

### `--parallel`

Run independent tasks in parallel when possible. This can significantly speed up
builds when you have multiple tasks that don't depend on each other.

```bash
hace --parallel build test
```

**Note:** For best results with parallel execution:

- Tasks should have distinct outputs (no file conflicts)
- Tasks should be independent (no shared dependencies)
- Hacé is built with multithreading support by default (`-Dpreview_mt`)

### `-v <level>, --verbosity <LEVEL>`

Control output verbosity (0-5).

- **0**: Silent mode (only errors)
- **1**: Error messages only
- **2**: Warnings and errors
- **3**: Info messages (default)
- **4**: Verbose output
- **5**: Debug output

```bash
hace --verbosity 4 build
hace -v 2 test
```

### `--version`

Show version information.

```bash
hace --version
```

### `--help`

Show help information.

```bash
hace --help
```

## Task Selection

### Running Specific Tasks

```bash
# Run specific tasks
hace build test deploy

# Run tasks in dependency order
hace test  # Will run build first if it's a dependency
```

### Default Task

If no tasks are specified, Hacé runs all tasks with `default: true`.

```bash
hace  # Runs default task(s)
```

## Variable Override

You can override or set variables from the command line:

```bash
hace build VERSION=2.0.0 ENVIRONMENT=staging
```

These variables are available in your Hacefile.yml:

```yaml
variables:
  version: "1.0.0"  # Default value

tasks:
  build:
    commands: |
      echo "Building version {{ version }}"
      echo "Environment: {{ environment }}"
```

## Common Usage Patterns

### Development Workflow

```bash
# Install dependencies first
hace install_deps

# Build with verbose output
hace --verbosity 3 build

# Run tests
hace test

# Clean everything
hace clean

# Full rebuild
hace --always-make clean build test
```

### Parallel Builds

```bash
# Run multiple independent tasks in parallel
hace --parallel build test lint

# Faster CI/CD pipelines
hace --parallel --always-make test build package

# Combined with other options
hace --parallel --verbosity 4 build test docs
```

### Shell Completion

```bash
# Generate completion script for your shell
hace --completion=bash   # For bash
hace --completion=fish   # For fish
hace --completion=zsh    # For zsh
```

**Installation Instructions:**

#### Bash

```bash
# Add to ~/.bashrc or ~/.bash_completion.d/hace
hace --completion=bash >> ~/.bash_completion.d/hace
source ~/.bash_completion.d/hace
```

#### Fish

```bash
# Save to fish completions directory
hace --completion=fish > ~/.config/fish/completions/hace.fish
```

#### Zsh

```bash
# Save to zsh completions directory
hace --completion=zsh > ~/.local/share/zsh/site-functions/_hace
compinit
```

**Completion Features:**

- **Task names**: Tab-complete available tasks from your Hacefile
- **Options**: Complete CLI flags and arguments
- **File paths**: Complete file names for `-f/--file` option
- **Verbosity levels**: Complete numbers 0-5 for `-v/--verbosity`
- **Dynamic**: Updates automatically when you modify your Hacefile

### Continuous Integration

```bash
# CI script
hace --quiet install_deps
hace --quiet build
hace test
```

### Development with Auto-Monitor

```bash
# Watch for changes and rebuild automatically
hace --auto

# Or auto-monitor specific tasks
hace --auto build test
```

### Debugging

```bash
# See what would run without executing
hace --dry-run build

# Check what's stale
hace --question

# Verbose output for debugging
hace --verbosity 4 build
```

### Production Deploy

```bash
# Force full rebuild and deploy
hace --always-make build package deploy

# With environment variables
hace deploy ENVIRONMENT=production VERSION=2.1.0
```

## Exit Codes

- **0**: Success
- **1**: General error (command failed, missing Hacefile, etc.)
- **2**: Invalid command line arguments

## Environment Variables

Hacé respects these environment variables:

- `HACE_DEFAULT_VERBOSITY`: Default verbosity level
- `HACE_AUTO_RESCAN_INTERVAL`: Auto-monitor rescan interval (seconds)

```bash
export HACE_DEFAULT_VERBOSITY=2
hace build  # Will use verbosity 2 by default
```
