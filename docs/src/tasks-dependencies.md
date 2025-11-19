# Tasks and Dependencies

Dependency management is at the heart of Hacé. This guide covers how to define tasks and their relationships.

## Understanding Dependencies

Hacé uses file timestamps to determine when tasks need to run. A task runs when:

1. It has never been run before
2. Any of its dependencies are newer than its outputs
3. It's marked as `always_run: true`
4. It's a phony task (always runs unless dependencies fail)

## Task Types

### File-Based Tasks

Tasks that produce files:

```yaml
tasks:
  compile:
    dependencies:
      - "src/**/*.cr"
      - "shard.yml"
    outputs:
      - "bin/myapp"
    commands: |
      crystal build src/main.cr -o bin/myapp
```

### Phony Tasks

Tasks that perform actions without producing files:

```yaml
tasks:
  clean:
    phony: true
    commands: |
      rm -rf bin/
      rm -rf build/

  deploy:
    phony: true
    dependencies:
      - build
    commands: |
      echo "Deploying application..."
```

## Dependency Types

### File Dependencies

Files that the task depends on:

```yaml
tasks:
  build:
    dependencies:
      # Single files
      - "src/main.cr"
      - "shard.yml"

      # Glob patterns
      - "src/**/*.cr"
      - "lib/**/*.cr"

      # Multiple specific patterns
      - "config/*.json"
      - "templates/*.html"
```

### Task Dependencies

Dependencies on other tasks:

```yaml
tasks:
  install-deps:
    commands: |
      shards install

  build:
    dependencies:
      - install-deps  # Depends on this task completing first
      - "src/**/*.cr"
    commands: |
      crystal build src/main.cr

  test:
    dependencies:
      - build  # Will run build first if needed
    commands: |
      crystal spec
```

### Mixed Dependencies

Combining file and task dependencies:

```yaml
tasks:
  integration-test:
    dependencies:
      # Task dependencies
      - build
      - setup-test-env

      # File dependencies
      - "test/fixtures/**/*"
      - "test/integration/**/*.cr"
    commands: |
      crystal spec test/integration/
```

## Dependency Resolution

### Timestamp-Based

Hacé compares modification times:

```yaml
tasks:
  generate-config:
    dependencies:
      - "config.template.yml"
    outputs:
      - "config/production.yml"
    commands: |
      envsubst < config.template.yml > config/production.yml

  deploy:
    dependencies:
      - generate-config  # Only runs if config is newer
    commands: |
      kubectl apply -f config/production.yml
```

### Force Execution

Use `always_run` to ignore timestamps:

```yaml
tasks:
  publish-version:
    always_run: true
    commands: |
      echo "Publishing current version..."
      # Always runs, regardless of timestamps
```

## Advanced Dependency Patterns

### Conditional Dependencies

Use Jinja templates for conditional dependencies:

```yaml
variables:
  environment: "production"

tasks:
  deploy:
    dependencies:
      - build
      {% if environment == "production" %}
      - security-scan
      - load-testing
      {% endif %}
    commands: |
      echo "Deploying to {{ environment }}"
```

### Dynamic Dependencies

Generate dependencies based on variables:

```yaml
variables:
  modules:
    - auth
    - payments
    - notifications

tasks:
  build-modules:
    dependencies:
      {% for module in modules %}
      - "modules/{{ module }}/**/*.cr"
      {% endfor %}
    commands: |
      {% for module in modules %}
      crystal build modules/{{ module }}/main.cr -o bin/{{ module }}
      {% endfor %}
```

### Cross-Project Dependencies

Dependencies on files in other directories:

```yaml
tasks:
  build-app:
    dependencies:
      - "src/**/*.cr"
      - "../shared/lib/**/*.cr"
      - "../common/config/*.yml"
    commands: |
      crystal build src/main.cr -o bin/app
```

## Circular Dependencies

Hacé (via Croupier) detects and prevents circular dependencies:

```yaml
# This will cause an error:
tasks:
  task_a:
    dependencies:
      - task_b
    commands: |
      echo "Task A"

  task_b:
    dependencies:
      - task_a  # Circular!
    commands: |
      echo "Task B"
```

Error message: `Circular dependency detected: task_a -> task_b -> task_a`

## Dependency Graph

Hacé builds a dependency graph to determine execution order:

```yaml
tasks:
  test:
    dependencies:
      - build

  build:
    dependencies:
      - compile
      - generate-docs

  compile:
    dependencies:
      - install-deps

  install-deps:
    commands: |
      shards install

  generate-docs:
    dependencies:
      - "src/**/*.cr"
```

Execution order: `install-deps` → `compile` → `generate-docs` → `build` → `test`

## Best Practices

### Granular Tasks

Break large tasks into smaller, focused ones:

```yaml
# Good: Granular tasks
tasks:
  install-deps:
    commands: shards install

  compile:
    dependencies:
      - install-deps
    commands: crystal build src/main.cr

  run-tests:
    dependencies:
      - compile
    commands: crystal spec

# Less good: Monolithic task
tasks:
  build-and-test:
    commands: |
      shards install
      crystal build src/main.cr
      crystal spec
```

### Clear Dependencies

Make dependencies explicit and minimal:

```yaml
# Good: Specific dependencies
tasks:
  build:
    dependencies:
      - "src/**/*.cr"
      - "lib/**/*.cr"

# Less good: Too broad
tasks:
  build:
    dependencies:
      - "**/*"  # Rebuilds on any file change
```

### Phony Tasks for Actions

Use phony tasks for actions that don't produce files:

```yaml
# Good: Phony task for actions
tasks:
  deploy:
    phony: true
    dependencies:
      - build
    commands: |
      scp bin/app server:/opt/app/

# Less good: Fake output file
tasks:
  deploy:
    outputs:
      - ".deployed"  # Hacky workaround
    commands: |
      scp bin/app server:/opt/app/
      touch .deployed
```

## Debugging Dependencies

Use built-in tools to debug dependency issues:

```bash
# Check what would run without executing
hace --dry-run

# Check if tasks are stale
hace --question

# Verbose output to see dependency resolution
hace --verbosity 4 build
```

Create a debug task to inspect dependencies:

```yaml
tasks:
  debug-deps:
    commands: |
      echo "Dependencies for all tasks:"
      # This would require custom implementation
      # to show the full dependency graph
```
