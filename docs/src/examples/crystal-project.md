# Crystal Project Example

This example shows how to set up Hacé for a Crystal project, including development, testing, and deployment workflows.

## Project Structure

```
my-crystal-app/
├── src/
│   ├── my_app.cr
│   └── my_app/
│       ├── config.cr
│       ├── database.cr
│       └── handlers/
│           └── api.cr
├── spec/
│   ├── spec_helper.cr
│   └── my_app_spec.cr
├── config/
│   ├── database.yml
│   └── server.yml
├── bin/
├── lib/
├── shard.yml
├── Hacefile.yml
└── README.md
```

## Hacefile.yml

```yaml
variables:
  app_name: "my_app"
  source_dir: "src"
  build_dir: "bin"
  test_dir: "spec"
  config_dir: "config"
  shard_file: "shard.yml"
  crystal_version: "1.10.0"

env:
  CRYSTAL_ENV: "development"

tasks:
  # Install dependencies
  install:
    phony: true
    commands: |
      echo "Installing Crystal dependencies..."
      shards install
      echo "Dependencies installed successfully!"

  # Setup development environment
  setup:
    dependencies:
      - install
      - check-crystal
    commands: |
      echo "Setting up development environment..."
      mkdir -p {{ build_dir }}
      mkdir -p log
      mkdir -p tmp
      echo "Development environment ready!"

  # Check Crystal installation
  check-crystal:
    phony: true
    commands: |
      if ! command -v crystal &> /dev/null; then
        echo "Error: Crystal is not installed"
        echo "Please install Crystal from https://crystal-lang.org/install/"
        exit 1
      fi

      crystal_version=$(crystal --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
      echo "✓ Crystal version: $crystal_version"

  # Build development version
  build:
    default: true
    dependencies:
      - setup
      - "{{ source_dir }}/**/*.cr"
      - "{{ shard_file }}"
    outputs:
      - "{{ build_dir }}/{{ app_name }}"
    commands: |
      echo "Building {{ app_name }} for development..."
      crystal build {{ source_dir }}/{{ app_name }}.cr -o {{ build_dir }}/{{ app_name }}
      echo "Build completed: {{ build_dir }}/{{ app_name }}"

  # Build production version
  build-release:
    dependencies:
      - setup
      - "{{ source_dir }}/**/*.cr"
      - "{{ shard_file }}"
    outputs:
      - "{{ build_dir }}/{{ app_name }}"
    commands: |
      echo "Building {{ app_name }} for production..."
      crystal build {{ source_dir }}/{{ app_name }}.cr \
        --release \
        --no-debug \
        -o {{ build_dir }}/{{ app_name }}
      echo "Production build completed: {{ build_dir }}/{{ app_name }}"

  # Run development server
  dev:
    dependencies:
      - build
    phony: true
    commands: |
      echo "Starting development server..."
      CRYSTAL_ENV=development {{ build_dir }}/{{ app_name }}

  # Run the application
  run:
    dependencies:
      - build
    phony: true
    commands: |
      echo "Running {{ app_name }}..."
      {{ build_dir }}/{{ app_name }}

  # Run tests
  test:
    dependencies:
      - build
      - "{{ test_dir }}/**/*_spec.cr"
    phony: true
    commands: |
      echo "Running test suite..."
      crystal spec

  # Run specific test file
  test-file:
    phony: true
    commands: |
      if [ -z "$TEST_FILE" ]; then
        echo "Usage: hace test-file TEST_FILE=spec/my_spec.cr"
        exit 1
      fi
      crystal spec "$TEST_FILE"

  # Run tests with coverage
  test-coverage:
    dependencies:
      - build
      - "{{ test_dir }}/**/*_spec.cr"
    phony: true
    commands: |
      echo "Running test suite with coverage..."
      crystal spec --coverage

  # Format code
  format:
    phony: true
    commands: |
      echo "Formatting Crystal code..."
      crystal tool format {{ source_dir }}/ {{ test_dir }}/

  # Check code formatting
  check-format:
    phony: true
    commands: |
      echo "Checking code format..."
      crystal tool format --check {{ source_dir }}/ {{ test_dir }}/

  # Run static analysis
  analyze:
    phony: true
    commands: |
      echo "Running static analysis..."
      crystal tool format --check {{ source_dir }}/ {{ test_dir }}/
      echo "✓ Code formatting check passed"

  # Development workflow
  dev-check:
    dependencies:
      - build
      - test
      - analyze
    phony: true
    commands: |
      echo "✓ Development checks passed!"

  # Database setup (if applicable)
  db-setup:
    phony: true
    commands: |
      echo "Setting up database..."
      if [ -f "db/migrate.cr" ]; then
        crystal run db/migrate.cr
      else
        echo "No database migration script found"
      fi

  # Database seed
  db-seed:
    phony: true
    commands: |
      echo "Seeding database..."
      if [ -f "db/seed.cr" ]; then
        crystal run db/seed.cr
      else
        echo "No database seed script found"
      fi

  # Reset database
  db-reset:
    dependencies:
      - db-setup
      - db-seed
    phony: true
    commands: |
      echo "Database reset completed!"

  # Generate documentation
  docs:
    dependencies:
      - "{{ source_dir }}/**/*.cr"
    outputs:
      - "docs/index.html"
    commands: |
      echo "Generating documentation..."
      crystal docs {{ source_dir }}/

  # Serve documentation locally
  docs-serve:
    dependencies:
      - docs
    phony: true
    commands: |
      echo "Starting documentation server..."
      echo "Open http://localhost:3000 in your browser"
      crystal docs {{ source_dir }}/ --serve

  # Create release package
  package:
    dependencies:
      - build-release
      - docs
    outputs:
      - "releases/{{ app_name }}-{{ crystal_version }}.tar.gz"
    commands: |
      echo "Creating release package..."
      mkdir -p releases
      tar czf releases/{{ app_name }}-{{ crystal_version }}.tar.gz \
        {{ build_dir }}/{{ app_name }} \
        docs/ \
        config/ \
        README.md \
        shard.yml

  # Clean build artifacts
  clean:
    phony: true
    commands: |
      echo "Cleaning build artifacts..."
      rm -rf {{ build_dir }}/
      rm -rf docs/
      rm -rf log/
      rm -rf tmp/
      rm -rf lib/
      echo "Clean completed!"

  # Clean dependencies
  clean-all:
    dependencies:
      - clean
    phony: true
    commands: |
      echo "Cleaning all artifacts..."
      rm -rf releases/
      echo "Full clean completed!"

  # Show project information
  info:
    phony: true
    commands: |
      echo "{{ app_name | upper }} PROJECT INFORMATION"
      echo "==============================="
      echo "Name: {{ app_name }}"
      echo "Crystal version: {{ crystal_version }}"
      echo "Source directory: {{ source_dir }}"
      echo "Build directory: {{ build_dir }}"
      echo "Test directory: {{ test_dir }}"
      echo "Environment: $CRYSTAL_ENV"
      echo ""
      echo "Available tasks:"
      echo "  setup       - Setup development environment"
      echo "  build       - Build development version (default)"
      echo "  build-release - Build production version"
      echo "  dev         - Start development server"
      echo "  test        - Run test suite"
      echo "  format      - Format code"
      echo "  analyze     - Run static analysis"
      echo "  docs        - Generate documentation"
      echo "  package     - Create release package"
      echo "  clean       - Clean build artifacts"
      echo ""
      echo "Usage examples:"
      echo "  hace                    # Build (default task)"
      echo "  hace dev                # Start development server"
      echo "  hace test               # Run tests"
      echo "  hace build-release      # Production build"
      echo "  hace CRYSTAL_ENV=prod run # Run in production"
```

## Usage Examples

### Development Workflow

```bash
# Initial setup
hace setup

# Development build and run
hace build
hace run

# Start development server
hace dev

# Run tests
hace test

# Check code quality
hace analyze

# Format code
hace format
```

### Testing

```bash
# Run all tests
hace test

# Run specific test file
hace test-file TEST_FILE=spec/my_app_spec.cr

# Run tests with coverage
hace test-coverage
```

### Production

```bash
# Production build
hace build-release

# Run in production mode
CRYSTAL_ENV=production hace run

# Create release package
hace package
```

### Database (if applicable)

```bash
# Setup database
hace db-setup

# Seed database
hace db-seed

# Reset database
hace db-reset
```

### Documentation

```bash
# Generate docs
hace docs

# Serve docs locally
hace docs-serve
```

## Environment-Specific Configurations

### Development Configuration

```bash
# Development mode (default)
hace dev

# Or explicitly
CRYSTAL_ENV=development hace run
```

### Production Configuration

```bash
# Production mode
CRYSTAL_ENV=production hace build-release
CRYSTAL_ENV=production hace run
```

## Advanced Features

### Multi-Environment Deployment

```yaml
variables:
  app_name: "my_app"
  environment: "{{ '$CRYSTAL_ENV' | default('development') }}"

tasks:
  deploy:
    dependencies:
      - build-release
    phony: true
    commands: |
      {% if environment == 'production' %}
      echo "Deploying to production..."
      scp bin/{{ app_name }} user@prod-server:/opt/{{ app_name }}/
      {% elif environment == 'staging' %}
      echo "Deploying to staging..."
      scp bin/{{ app_name }} user@staging-server:/opt/{{ app_name }}/
      {% else %}
      echo "Unknown environment: {{ environment }}"
      exit 1
      {% endif %}
```

```bash
# Deploy to different environments
CRYSTAL_ENV=staging hace deploy
CRYSTAL_ENV=production hace deploy
```

### Performance Testing

```yaml
tasks:
  benchmark:
    dependencies:
      - build-release
    phony: true
    commands: |
      echo "Running performance benchmarks..."
      {{ build_dir }}/{{ app_name }} --benchmark

  profile:
    dependencies:
      - build
    phony: true
    commands: |
      echo "Profiling application..."
      crystal build src/{{ app_name }}.cr --profile -o {{ build_dir }}/{{ app_name }}-profile
      {{ build_dir }}/{{ app_name }}-profile
```

This example demonstrates a complete Crystal project setup with:

1. **Development workflow** with automatic dependency management
2. **Testing integration** with Crystal's built-in test framework
3. **Code quality tools** (formatting, static analysis)
4. **Documentation generation**
5. **Production deployment** preparation
6. **Environment-specific configurations**
7. **Database management** (if applicable)

You can customize this for your specific Crystal application needs.
