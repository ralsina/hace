# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Hacé Project Guide

## Project Overview

**Hacé** is a task automation tool similar to `make` but with different syntax and semantics. It reads YAML configuration from `Hacefile.yml` files and executes shell commands based on file dependencies and build requirements.

## Core Purpose

Hacé serves as a build automation and task runner that:
- Executes shell commands in a task-based workflow
- Manages file dependencies and rebuilds only when necessary  
- Supports template variables using Jinja syntax
- Handles environment variables and custom variables
- Provides intelligent task scheduling based on file modification times
- Supports both regular tasks (with file outputs) and phony tasks (actions without outputs)

## Architecture

### Key Components

1. **`HaceFile` class** (`src/hace.cr`): Central parser and controller for Hacefile.yml
2. **`CommandTask` class** (`src/hace.cr`): Represents individual tasks with commands and dependencies
3. **Main entry point** (`src/main.cr`): CLI parsing and command delegation
4. **Test Infrastructure** (`spec/`): Comprehensive test suite with scenario-based testing

### External Dependencies

- **Croupier**: Dataflow library for task dependency management
- **Commander**: CLI parsing and command handling  
- **Crinja**: Jinja template engine for variable expansion
- **Log**: Crystal's logging library with custom color formatting
- **YAML**: YAML parsing for Hacefile.yml

### Task Properties

Each task supports:
- `commands`: Multi-line shell commands (Jinja templates supported)
- `dependencies`: File paths or task names with glob expansion (`*`, `**`, `?`)
- `outputs`: Generated files (defaults to task name if not specified)
- `phony`: Boolean for tasks without file outputs (notification-style tasks)
- `default`: Boolean for default tasks when no arguments given
- `always_run`: Boolean to run even when dependencies are up-to-date
- `cwd`: Working directory for the task

## Development Workflow

### Essential Commands

```bash
# Install dependencies
shards install

# Build the project (no --release flag per preferences)
shards build

# Run the test suite
crystal spec

# Run linting and auto-fix issues
ameba --fix

# Check for linting issues without fixing
ameba

# Full development workflow: test, lint, build
crystal spec && ameba --fix && shards build
```

### Project Structure

```
hace/
├── src/                 # Main source code
│   ├── main.cr         # Entry point and CLI setup
│   ├── hace.cr         # Core Hace functionality
│   └── run_tests.cr    # Test runner
├── spec/               # Test suite
│   ├── spec_helper.cr  # Test helpers
│   ├── hace_spec.cr    # Main test file
│   └── testcases/      # Test scenario files
├── lib/                # External dependencies (vendored)
├── bin/                # Compiled binaries
├── shard.yml           # Project configuration
├── .ameba.yml          # Linter configuration
└── README.md           # Comprehensive documentation
```

## Hacefile.yml Format

### Basic Structure

```yaml
# Environment variables (can be null to unset)
env:
  PATH: "/custom/path"
  DEBUG_VAR: null

# Global variables (available to all tasks)
variables:
  source_dir: "src"
  build_dir: "build"
  version: "1.0.0"

# Task definitions
tasks:
  build:
    default: true
    dependencies:
      - "{{ source_dir }}/**/*.cr"
    outputs:
      - "{{ build_dir }}/app"
    commands: |
      mkdir -p {{ build_dir }}
      crystal build {{ source_dir }}/main.cr -- {{ build_dir }}/app
  
  clean:
    phony: true
    commands: |
      rm -rf {{ build_dir }}/*
  
  test:
    phony: true
    dependencies:
      - build
    commands: |
      {{ build_dir }}/app --test
```

### Variable Expansion

Supports two types of variable expansion:

1. **Jinja Templates** (global variables): `{{ variable_name }}`
2. **Environment Variables**: `${ENV_VAR_NAME}`

Special `self` variable provides access to task properties:
- `self["dependencies"]`: Array of dependencies
- `self["outputs"]`: Array of output files
- `self["phony"]`: Boolean indicating if task is phony
- `self["default"]`: Boolean indicating if task is default

### Command Line Usage

```bash
# Run default tasks
hace

# Run specific tasks
hace build test

# Set variables from command line
hace build VERSION=2.0.0

# Dry run (don't execute commands)
hace --dry-run

# Question mode (check if tasks are stale)
hace --question

# Always run all tasks
hace --always-make

# Custom Hacefile
hace -f custom.yml

# Quiet mode
hace --quiet

# Verbosity control (0-5)
hace --verbosity 1

# Auto mode (monitor files for changes)
hace auto
```

## Development Conventions

### Code Style

1. **No `not_nil!`**: Avoid using `not_nil!` in favor of proper nil handling
2. **Descriptive Names**: Use descriptive parameter names in blocks instead of single letters
3. **Template Safety**: Proper variable expansion and escaping in Jinja templates
4. **Error Handling**: Graceful handling of missing files, failed commands, and circular dependencies

### Testing Philosophy

- **Comprehensive Coverage**: Extensive test suite covering all functionality
- **Scenario-Based Testing**: Tests use isolated scenarios with proper cleanup
- **Helper Functions**: `with_scenario()` function for setting up test environments
- **Integration Testing**: Tests cover real-world usage patterns and edge cases

### Development Process

1. **Always run tests before declaring task finished**
2. **Fix linting issues automatically** with `ameba --fix`
3. **Build the project** after changes to verify it compiles
4. **Follow docopt pattern** for CLI interfaces (user preference)

### External Libraries

- **`lib/` contains external dependencies** that cannot be modified
- Dependencies are vendored for offline development and reproducibility
- Key libraries: Croupier (core), Commander (CLI), Crinja (templating)

## Special Features

### File Dependencies and Globbing

```yaml
tasks:
  compile:
    dependencies:
      - "*.cr"              # Current directory .cr files
      - "src/**/*.cr"       # Recursive in src directory
      - "lib/{ameba,crinja}/**/*.cr"  # Multiple directories
```

### Multiple Outputs

```yaml
tasks:
  generate:
    outputs:
      - "output1.txt"
      - "output2.txt"
    commands: |
      echo "first" > output1.txt
      echo "second" > output2.txt
```

### Environment Variable Handling

```yaml
env:
  # Set variables
  PATH: "/custom/path"
  # Unset variables
  DEBUG_VAR: null
  # Set empty string
  EMPTY_VAR: ""
```

### Error Scenarios

- Missing Hacefile: Raises clear error message
- Failed commands: Stops execution with descriptive error
- Unknown tasks: Warns and continues with available tasks
- Circular dependencies: Detected and reported by Croupier

This codebase demonstrates mature Crystal development practices with a focus on reliability, testability, and user experience in the build automation domain.

## Important User Preferences

- Use **docopt** for command line interfaces (already implemented)
- **Don't use `not_nil!`** - avoid at all costs, use proper nil handling instead
- **Don't use `--release`** flag when building
- Code in **`lib/` cannot be modified** - contains external libraries and tools
- Prefer **descriptive names** for parameters in blocks instead of single letters
- **Always fix linting issues** with `ameba --fix` before declaring tasks complete
- **Build after changes** to verify code compiles
- **Run tests** before declaring tasks finished
- If project has multiple binaries, check that **ALL binaries build** before completion
