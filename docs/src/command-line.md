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

### `--dry-run`

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

### `--always-make`

Force all tasks to run, ignoring dependency timestamps.

```bash
hace --always-make
```

### `--auto`

Enable auto-monitoring mode. Hacé will watch for file changes and rebuild automatically.

```bash
hace auto
```

### `--quiet`

Suppress normal output, only show errors.

```bash
hace --quiet build
```

### `--verbosity <LEVEL>`

Control output verbosity (0-5).

- **0**: Silent mode (only errors)
- **1**: Minimal output (default)
- **2**: Normal output
- **3**: Verbose output
- **4**: Debug output
- **5**: Trace output

```bash
hace --verbosity 3 build
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
hace auto

# Or auto-monitor specific tasks
hace auto build test
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
