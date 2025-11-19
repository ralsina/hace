# Basic Build System Example

This example shows how to create a basic build system for a simple project using Hacé.

## Project Structure

```
my-project/
├── src/
│   ├── main.c
│   ├── utils.c
│   └── utils.h
├── tests/
│   └── test_main.c
├── docs/
│   └── README.md
├── Hacefile.yml
└── README.md
```

## Hacefile.yml

```yaml
# Basic C project build system
variables:
  src_dir: "src"
  build_dir: "build"
  test_dir: "tests"
  compiler: "gcc"
  cflags: "-Wall -Wextra -std=c99"
  executable: "myapp"

env:
  CC: "{{ compiler }}"

tasks:
  # Create build directory
  setup:
    commands: |
      mkdir -p {{ build_dir }}

  # Compile source files
  compile:
    default: true
    dependencies:
      - setup
      - "{{ src_dir }}/*.c"
      - "{{ src_dir }}/*.h"
    outputs:
      - "{{ build_dir }}/{{ executable }}"
    commands: |
      {{ compiler }} {{ cflags }} \
        {{ src_dir }}/*.c \
        -o {{ build_dir }}/{{ executable }}

  # Run the application
  run:
    dependencies:
      - compile
    phony: true
    commands: |
      echo "Running {{ executable }}..."
      {{ build_dir }}/{{ executable }}

  # Build and run tests
  test:
    dependencies:
      - compile
      - "{{ test_dir }}/*.c"
    outputs:
      - "{{ build_dir }}/test_runner"
    commands: |
      {{ compiler }} {{ cflags }} \
        {{ src_dir }}/*.c \
        {{ test_dir }}/*.c \
        -o {{ build_dir }}/test_runner
      echo "Running tests..."
      {{ build_dir }}/test_runner

  # Clean build artifacts
  clean:
    phony: true
    commands: |
      echo "Cleaning build directory..."
      rm -rf {{ build_dir }}

  # Install application (to /usr/local/bin)
  install:
    dependencies:
      - compile
    phony: true
    commands: |
      echo "Installing {{ executable }}..."
      cp {{ build_dir }}/{{ executable }} /usr/local/bin/
      echo "Installed to /usr/local/bin/{{ executable }}"

  # Uninstall application
  uninstall:
    phony: true
    commands: |
      echo "Uninstalling {{ executable }}..."
      rm -f /usr/local/bin/{{ executable }}

  # Show help
  help:
    phony: true
    commands: |
      echo "Available targets:"
      echo "  compile   - Build the application (default)"
      echo "  run       - Compile and run the application"
      echo "  test      - Compile and run tests"
      echo "  clean     - Remove build artifacts"
      echo "  install   - Install to system"
      echo "  uninstall - Remove from system"
      echo "  help      - Show this help message"
```

## Usage

```bash
# Build the project (default task)
hace

# Run the application
hace run

# Run tests
hace test

# Clean build files
hace clean

# Install to system
sudo hace install

# Show available tasks
hace help
```

## Advanced Features

### Debug Build

```yaml
variables:
  # Build mode (can be overridden from command line)
  build_mode: "release"

  # Conditional flags based on build mode
  debug_flags: "-g -DDEBUG"
  release_flags: "-O2 -DNDEBUG"

tasks:
  compile:
    # ... (same dependencies)
    commands: |
      {% set mode_flags = debug_flags if build_mode == 'debug' else release_flags %}
      {{ compiler }} {{ cflags }} {{ mode_flags }} \
        {{ src_dir }}/*.c \
        -o {{ build_dir }}/{{ executable }}
```

```bash
# Debug build
hace compile build_mode=debug

# Release build (default)
hace compile build_mode=release
```

### Multiple Executables

```yaml
variables:
  src_dir: "src"
  build_dir: "build"
  compiler: "gcc"
  cflags: "-Wall -Wextra -std=c99"

tasks:
  # Build main application
  build-main:
    dependencies:
      - setup
      - "{{ src_dir }}/main.c"
      - "{{ src_dir }}/utils.c"
    outputs:
      - "{{ build_dir }}/myapp"
    commands: |
      {{ compiler }} {{ cflags }} \
        {{ src_dir }}/main.c {{ src_dir }}/utils.c \
        -o {{ build_dir }}/myapp

  # Build utility tool
  build-tool:
    dependencies:
      - setup
      - "{{ src_dir }}/utils.c"
      - "{{ src_dir }}/tool.c"
    outputs:
      - "{{ build_dir }}/mytool"
    commands: |
      {{ compiler }} {{ cflags }} \
        {{ src_dir }}/tool.c {{ src_dir }}/utils.c \
        -o {{ build_dir }}/mytool

  # Build everything
  build-all:
    dependencies:
      - build-main
      - build-tool
    phony: true
    commands: |
      echo "All builds completed!"

  # Default build
  build:
    default: true
    dependencies:
      - build-all
    phony: true
```

### Dependency Management

```yaml
tasks:
  # Check for required tools
  check-deps:
    phony: true
    commands: |
      echo "Checking dependencies..."

      # Check compiler
      if ! command -v {{ compiler }} &> /dev/null; then
        echo "Error: {{ compiler }} is not installed"
        exit 1
      fi
      echo "✓ {{ compiler }} found"

      # Check make (optional)
      if command -v make &> /dev/null; then
        echo "✓ make found"
      else
        echo "⚠ make not found (optional)"
      fi

  # Install dependencies
  install-deps:
    phony: true
    commands: |
      echo "Installing dependencies..."

      # Example for Ubuntu/Debian
      if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y build-essential
      # Example for macOS
      elif command -v brew &> /dev/null; then
        brew install gcc
      else
        echo "Please install {{ compiler }} manually"
      fi

  # Build with dependency check
  build:
    dependencies:
      - check-deps
      - compile
    phony: true
```

This example demonstrates:

1. **Basic C compilation** with proper dependency tracking
2. **Phony tasks** for actions like clean and install
3. **Variable usage** for configurable paths and tools
4. **Default task** selection
5. **Error handling** and user feedback
6. **Advanced features** like debug/release modes and multi-executable builds

You can adapt this pattern for other languages and build requirements by changing the compiler commands and file patterns.
