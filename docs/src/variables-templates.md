# Variables and Templates

Hacé supports powerful variable expansion using Jinja2 templating syntax, allowing you to create dynamic and reusable build configurations.

## Variable Types

### Global Variables

Defined in the `variables` section of your Hacefile:

```yaml
variables:
  source_dir: "src"
  build_dir: "build"
  version: "2.1.0"
  author: "Your Name"
  project_name: "myapp"
```

### Environment Variables

Available through the standard shell syntax:

```yaml
tasks:
  build:
    commands: |
      echo "Building on $OSTYPE"
      echo "PATH: $PATH"
      echo "Home: $HOME"
```

### Command Line Variables

Passed from the command line:

```bash
hace build VERSION=3.0.0 ENVIRONMENT=staging
```

### Special Variables

#### `self` Variable

The `self` variable provides access to the current task's properties:

```yaml
tasks:
  debug_task:
    commands: |
      echo "Task name: {{ self.name }}"
      echo "Dependencies: {{ self.dependencies | join(', ') }}"
      echo "Outputs: {{ self.outputs | join(', ') }}"
      echo "Is phony: {{ self.phony }}"
      echo "Is default: {{ self.default }}"
```

#### Built-in Variables

- `hace.version`: Hacé version
- `hace.args.command_line`: Original command line arguments

## Jinja2 Template Syntax

### Basic Variable Substitution

```yaml
variables:
  source_dir: "src"
  build_dir: "build"

tasks:
  build:
    commands: |
      mkdir -p {{ build_dir }}
      crystal build {{ source_dir }}/main.cr -o {{ build_dir }}/app
```

### Filters

Apply transformations to variables:

```yaml
variables:
  project_name: "my-app"
  version: "1.0.0"

tasks:
  package:
    commands: |
      # Upper case
      echo "Building {{ project_name | upper }}"

      # Replace characters
      tar czf {{ project_name | replace('-', '_') }}-{{ version }}.tar.gz dist/

      # Default values
      echo "Author: {{ author | default('Unknown') }}"
```

Available filters:
- `upper`, `lower`: Case conversion
- `replace`: String replacement
- `default`: Default value if variable is undefined/empty
- `length`: Array/string length
- `join`: Array to string
- `split`: String to array

### Conditionals

```yaml
variables:
  environment: "production"

tasks:
  deploy:
    commands: |
      {% if environment == "production" %}
      echo "Deploying to production cluster"
      kubectl apply -f k8s/production/
      {% elif environment == "staging" %}
      echo "Deploying to staging cluster"
      kubectl apply -f k8s/staging/
      {% else %}
      echo "Unknown environment: {{ environment }}"
      {% endif %}
```

### Loops

```yaml
variables:
  targets:
    - "linux-x64"
    - "macos-x64"
    - "windows-x64"

tasks:
  build-all:
    commands: |
      {% for target in targets %}
      echo "Building for {{ target }}"
      crystal build src/main.cr --release -o dist/myapp-{{ target }}
      {% endfor %}
```

### Complex Expressions

```yaml
variables:
  version: "2.1.0"
  build_number: 42

tasks:
  package:
    commands: |
      # String concatenation
      echo "Version: {{ version }}-build{{ build_number }}"

      # Mathematical operations
      echo "Next build: {{ build_number + 1 }}"

      # Boolean expressions
      {% if version.startswith('2.') %}
      echo "Version 2.x detected"
      {% endif %}
```

## Variable Precedence

Variables are resolved in this order (highest to lowest):

1. **Command line variables** (e.g., `hace build VERSION=3.0.0`)
2. **Environment variables** (e.g., `$HOME`, `$PATH`)
3. **Task-level variables** (rare, custom extensions)
4. **Global variables** from `variables` section

## Practical Examples

### Multi-Environment Configuration

```yaml
variables:
  app_name: "myapp"
  version: "1.2.3"

tasks:
  build:
    commands: |
      echo "Building {{ app_name }} version {{ version }}"
      crystal build src/main.cr -o bin/{{ app_name }}

  deploy-staging:
    commands: |
      hace build ENVIRONMENT=staging
      scp bin/{{ app_name }} staging:/opt/{{ app_name }}/

  deploy-production:
    commands: |
      hace build ENVIRONMENT=production
      scp bin/{{ app_name }} production:/opt/{{ app_name }}/
```

### Dynamic File Operations

```yaml
variables:
  source_files:
    - "src/**/*.cr"
    - "lib/**/*.cr"
  output_dir: "build"

tasks:
  analyze:
    commands: |
      echo "Analyzing {{ source_files | length }} source files"
      {% for file_pattern in source_files %}
      echo "Processing: {{ file_pattern }}"
      find . -name "{{ file_pattern }}" | wc -l
      {% endfor %}
```

### Version Management

```yaml
variables:
  version_file: "VERSION"
  version: "{{ version_file | file_contents | default('1.0.0') }}"

tasks:
  bump-patch:
    commands: |
      {% if version is containing '.' %}
      {% set parts = version.split('.') %}
      {% set patch = parts[2] | int + 1 %}
      echo "{{ parts[0] }}.{{ parts[1] }}.{{ patch }}" > {{ version_file }}
      {% else %}
      echo "Invalid version format: {{ version }}"
      {% endif %}

  tag-release:
    commands: |
      git tag v{{ version }}
      git push origin v{{ version }}
```

## Template Escaping

Sometimes you need to include literal Jinja syntax in your commands:

```yaml
tasks:
  generate-template:
    commands: |
      # Use raw/endraw to escape Jinja syntax
      cat > template.html << EOF
      {% raw %}{{ title }}{% endraw %}
      {% raw %}{% if user %}{% endraw %}
      {% raw %}Hello {{ user.name }}!{% endraw %}
      {% raw %}{% endif %}{% endraw %}
      EOF
```

## Best Practices

1. **Use meaningful variable names**: `source_dir` instead of `src`
2. **Group related variables**: Prefix with category (`build_`, `deploy_`)
3. **Provide defaults**: Use `default` filter for optional variables
4. **Document complex templates**: Add comments explaining logic
5. **Test templates**: Use `--dry-run` to verify expansion

## Debugging Templates

Use the debug task to inspect variable values:

```yaml
tasks:
  debug-vars:
    commands: |
      echo "Global variables:"
      echo "  source_dir: {{ source_dir }}"
      echo "  build_dir: {{ build_dir }}"
      echo "  version: {{ version }}"
      echo ""
      echo "Environment variables:"
      echo "  HOME: $HOME"
      echo "  PATH: $PATH"
      echo ""
      echo "Self variables:"
      echo "  dependencies: {{ self.dependencies | join(', ') }}"
      echo "  outputs: {{ self.outputs | join(', ') }}"
```
