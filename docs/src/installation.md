# Installation

Hacé is written in Crystal and can be installed in several ways.

## Prerequisites

You need Crystal installed on your system. See the [Crystal installation guide](https://crystal-lang.org/install/) for instructions.

## Install from Source

1. Clone the repository:
```bash
git clone https://github.com/ralsina/hace.git
cd hace
```

2. Install dependencies:
```bash
shards install
```

3. Build the project:
```bash
shards build
```

4. Install to system (optional):
```bash
sudo cp bin/hace /usr/local/bin/
```

## Install using Crystal Shards

Add Hacé to your project's dependencies in `shard.yml`:

```yaml
dependencies:
  hace:
    github: ralsina/hace
```

Then run:
```bash
shards install
```

## Verify Installation

Check that Hacé is installed correctly:

```bash
hace --version
hace --help
```

## Building from Latest Source

To get the latest features and bug fixes:

```bash
git clone https://github.com/ralsina/hace.git
cd hace
shards install
shards build
```

## Development Setup

If you want to contribute to Hacé or modify it:

1. Clone the repository
2. Install dependencies: `shards install`
3. Run tests: `crystal spec`
4. Build: `shards build`
5. Run the built binary: `./bin/hace`

See the [Contributing](contributing.md) guide for more details.
