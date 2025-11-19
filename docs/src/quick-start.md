# Quick Start

This guide will get you up and running with Hacé in just a few minutes.

## 1. Create Your First Hacefile

Create a file named `Hacefile.yml` in your project directory:

```yaml
variables:
  source_dir: "src"
  build_dir: "build"

tasks:
  hello:
    commands: |
      echo "Hello from Hacé!"
      echo "This is your first task."

  build:
    default: true
    dependencies:
      - "{{ source_dir }}/**/*.cr"
    outputs:
      - "{{ build_dir }}/app"
    commands: |
      mkdir -p {{ build_dir }}
      crystal build {{ source_dir }}/main.cr -o {{ build_dir }}/app
```

## 2. Run Your Tasks

```bash
# Run the default task (build)
hace

# Run a specific task
hace hello

# See what would be executed without actually running it
hace --dry-run

# Check which tasks need to run
hace --question
```

## 3. Add Dependencies

Tasks can depend on other tasks or files:

```yaml
tasks:
  test:
    dependencies:
      - build
      - "spec/**/*.cr"
    phony: true
    commands: |
      {{ build_dir }}/app --test

  deploy:
    dependencies:
      - test
      - build
    phony: true
    commands: |
      echo "Deploying application..."
```

## 4. Use Environment Variables

```yaml
env:
  NODE_ENV: "production"
  API_URL: "https://api.example.com"

tasks:
  deploy:
    commands: |
      echo "Deploying to $NODE_ENV"
      echo "API URL: $API_URL"
```

## 5. Command-Line Variables

Override variables from the command line:

```bash
hace build VERSION=2.0.0 ENVIRONMENT=staging
```

## Common Patterns

### Development Workflow

```yaml
tasks:
  dev:
    phony: true
    dependencies:
      - install
      - build
    commands: |
      echo "Development environment ready!"

  install:
    commands: |
      shards install

  build:
    dependencies:
      - "src/**/*.cr"
      - "shard.yml"
    outputs:
      - "bin/myapp"
    commands: |
      crystal build src/main.cr -o bin/myapp

  test:
    dependencies:
      - build
    commands: |
      crystal spec
```

### Documentation Generation

```yaml
tasks:
  docs:
    dependencies:
      - "src/**/*.cr"
      - "docs/**/*.md"
    outputs:
      - "docs/book/index.html"
    commands: |
      mdbook build docs

  serve-docs:
    phony: true
    commands: |
      mdbook serve docs --open
```

### Multi-Target Build

```yaml
variables:
  version: "1.0.0"

tasks:
  build-linux:
    dependencies:
      - "src/**/*.cr"
    outputs:
      - "dist/myapp-linux-x64"
    commands: |
      crystal build src/main.cr --release -o dist/myapp-linux-x64

  build-macos:
    dependencies:
      - "src/**/*.cr"
    outputs:
      - "dist/myapp-macos-x64"
    commands: |
      crystal build src/main.cr --release -o dist/myapp-macos-x64

  build-all:
    dependencies:
      - build-linux
      - build-macos
    phony: true
    commands: |
      echo "All builds completed!"
```

## Next Steps

Now that you have the basics, explore these topics:

- [Hacefile.yml Format](hacefile-format.md) - Complete syntax reference
- [Tasks and Dependencies](tasks-dependencies.md) - Advanced dependency management
- [Variables and Templates](variables-templates.md) - Jinja templating power
- [Command Line Options](command-line.md) - All available CLI flags
