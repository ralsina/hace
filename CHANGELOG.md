# Changelog

All notable changes to this project will be documented in this file.

## [0.8.2] - 2026-03-04

### 🐛 Bug Fixes

* Switch to alpine 3.23

### 🖐️ Bump

* Release v0.8.2
* Release v0.8.2
* Release v0.8.2
* Release v0.8.2
* Release v0.8.2
* Release v0.8.2
* Release v0.8.2
* Release v0.8.2
* Release v0.8.2

### ⚙️ Miscellaneous Tasks

* Release script
* Updated deps

## [0.8.1] - 2026-02-14

### 🐛 Bug Fixes

* Compatibility with crinja master version

### 🖐️ Bump

* Release v0.8.1

### 🏛️ Build

* Use crinja master

### 📚 Documentation

* Fix doc build

### ⚙️ Miscellaneous Tasks

* Removing release workflow because doing it locally is better

## [0.8.0] - 2025-12-15

### 🚀 Features

* Add CLI args passthrough with `--` separator

### 🖐️ Bump

* Release v0.8.0

### 🚜 Refactor

* Simplify CLI_ARGS detection with regex

### 📚 Documentation

* Remove badge for API docs
* Updated installation
* Enhance installation documentation

### ⚙️ Miscellaneous Tasks

* Build bin/hace before running coverage tests
* Fix coverage workflow by building kcov from source
* Fix coverage workflow by removing kcov dependency
* Fix missing binary in test execution

## [0.7.0] - 2025-11-19

### 🚀 Features

* Implement shell selection and combined script execution

### 🐛 Bug Fixes

* Improve static build script for proper release process

### 🖐️ Bump

* Release v0.7.0

### 📚 Documentation

* Update TODO.md with current project status

### ⚙️ Miscellaneous Tasks

* Gitignore

## [0.6.0] - 2025-11-19

### 🚀 Features

* Enhance release-check to ignore irrelevant files in working directory
* Implement combined shell execution with environment variable persistence
* Add automatic .env file support with dotenv integration
* Add shell autocompletion support for bash, fish, and zsh
* Add parallel task execution and multithreading support

### 🐛 Bug Fixes

* Update do_release.sh to ignore irrelevant files in working directory
* Simplify release-dry-run task to avoid croupier dependency issues
* Improve release process reliability and fix circular dependency
* Make docs-serve always run as development server
* Improve documentation tasks and remove redundant API docs generation

### 🖐️ Bump

* Release v0.6.0
* Release v0.5.1

### 🚜 Refactor

* Temporarily disable cyclomatic complexity warning for gen_task method
* Remove environment variable usage for dry-run flag
* Rename documentation tasks for simpler workflow
* Break down large run() method for better maintainability

### 🎨 Styling

* Remove trailing empty line in shell_execution_spec.cr

### 🧪 Testing

* Add comprehensive parallel execution test suite

### ⚙️ Miscellaneous Tasks

* 0.5.0
* Fix static build

## [0.5.1] - 2025-11-19

### 🖐️ Bump

* Release v0.5.1

### ⚙️ Miscellaneous Tasks

* Release script

## [0.5.0] - 2025-11-19

### 🚀 Features

* Add release task for GitHub releases
* Add comprehensive documentation deployment workflow

### 🐛 Bug Fixes

* Make static binaries really static
* Added version command

### 🖐️ Bump

* Release v0.5.0

### 🚜 Refactor

* Migrate from Commander to docopt and enhance CLI

### 📚 Documentation

* Update command-line documentation with --list and current CLI

### ⚙️ Miscellaneous Tasks

* Clean up repository and fix formatting
* Deprecation
* Todo management

## [0.4.0] - 2024-09-04

### 🚀 Features

* New optional cwd key in tasks

### 🐛 Bug Fixes

* Support iterating over dependencies created from a wildcard or a variable
* Expand variables with array values correctly

### 🖐️ Bump

* Release v0.4.0
* Release v0.4.0

### 🧪 Testing

* Fix a test
* Fix coverage check

### ⚙️ Miscellaneous Tasks

* Deleted random files
* Marked task as done
* Mark a task as done

## [0.3.0] - 2024-08-28

### 🚀 Features

* Expand globs on dependencies

### 🖐️ Bump

* Release v0.3.0

### ⚙️ Miscellaneous Tasks

* Nicer changelog
* Fix gitignore

## [0.2.0] - 2024-08-27

### 🚀 Features

* Expand variables in outputs and dependencies, not just commands
* Improved envvar handling

### 🐛 Bug Fixes

* Quotes in command
* Support nil envvars

### 🖐️ Bump

* Release v0.2.0
* Release v0.2.0

### 🏛️ Build

* Make pre-commit hooks set automatically
* Handle missing shard.lock
* Improving the build system in general

### 📚 Documentation

* Clarify dependencies
* More TODO

### ⚙️ Miscellaneous Tasks

* Removed default options in Hacefile
* Updated changelog
* Added pre-commit hooks and git-cliff

## [0.1.0] - 2023-06-19

## Version v0.1.3

* Set variables from the command line
* Allow passing output files as arguments
* Auto mode works better
* Handle bogus arguments better
* Made `--question` more verbose, and only report stale tasks matching arguments
* New `-k` option to keep going after errors.
* Switched to croupier main, supports depending on directories
* Automatically build binaries for release
* General housekeeping
* Build itself using a Hacefile instead of a Makefile
* Reject if two tasks share outputs (limitation of croupier for now)

Bugs Fixed:

* Warn about unknown tasks used in command line
* Tasks with outputs passed wrong target to croupier
* Command output was not visible in the log.

## Version v0.1.2

* Make tasks not be `default` by default. This means that if you don't specify a task when invoking `hace`, nothing will happen. **This is a breaking change.**
* Added `self` to exposed variables in tasks. This can be used to achieve what you would use $@ or other automatic variables in Makefiles.
* Added `-f` option to specify a Hacefile to use.
* Added `-n` option to do a dry run.
* Added `always_run` flag for tasks which causes them to always run even if their dependencies are unchanged.
* Implemented `--question` flag to ask if a task should be run.
* Implemented `auto` command, which continuously rebuilds as needed reacting to filesystem changes.

## Version v0.1.1

First actual release. While the tool is not feature complete by any means,
it does *some* stuff and what it does it seems to do well.

For details on what it can and can't do, see the
[README.](https://github.com/ralsina/hace/blob/main/README.md)
