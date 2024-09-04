# Changelog

All notable changes to this project will be documented in this file.

## [0.4.0] - 2024-09-04

### 🚀 Features

* New optional cwd key in tasks

### 🐛 Bug Fixes

* Support iterating over dependencies created from a wildcard or a variable
* Expand variables with array values correctly

### 🖐️ Bump

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
