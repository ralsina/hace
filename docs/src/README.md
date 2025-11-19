# Introduction to Hacé

**Hacé** is a task automation tool similar to `make` but with different syntax and semantics. It reads YAML configuration from `Hacefile.yml` files and executes shell commands based on file dependencies and build requirements.

## What is Hacé?

Hacé serves as a build automation and task runner that:

- Executes shell commands in a task-based workflow
- Manages file dependencies and rebuilds only when necessary
- Supports template variables using Jinja syntax
- Handles environment variables and custom variables
- Provides intelligent task scheduling based on file modification times
- Supports both regular tasks (with file outputs) and phony tasks (actions without outputs)

## Why use Hacé?

If you've ever found yourself writing complex shell scripts to automate your build process, or if you need a more modern alternative to `make` with better dependency management and templating capabilities, Hacé might be exactly what you need.

### Key Features

- **YAML Configuration**: Simple, human-readable configuration files
- **Jinja Templating**: Powerful variable expansion and templating
- **Intelligent Dependencies**: Only rebuilds what's necessary
- **Cross-Platform**: Works on Linux, macOS, and Windows
- **Flexible Tasks**: Supports both file-based and action-based tasks
- **Environment Management**: Easy control over environment variables
- **Auto-Monitoring**: Watch for file changes and rebuild automatically

## A Simple Example

Here's a basic Hacefile.yml to build a Crystal project:

```yaml
variables:
  source_dir: "src"
  build_dir: "build"

tasks:
  build:
    default: true
    dependencies:
      - "{{ source_dir }}/**/*.cr"
    outputs:
      - "{{ build_dir }}/myapp"
    commands: |
      mkdir -p {{ build_dir }}
      crystal build {{ source_dir }}/main.cr -o {{ build_dir }}/myapp

  clean:
    phony: true
    commands: |
      rm -rf {{ build_dir }}
```

Run it with:

```bash
hace          # Runs the default task (build)
hace clean    # Runs the clean task
```

## Next Steps

- [Quick Start](quick-start.md) - Get up and running quickly
- [Installation](installation.md) - Install Hacé on your system
- [Hacefile.yml Format](hacefile-format.md) - Learn the configuration syntax
