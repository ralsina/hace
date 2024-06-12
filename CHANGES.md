# Changelog

## Main Branch

## Version v0.1.3

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

* Make tasks not be `default` by default. This means that if you
  don't specify a task when invoking `hace`, nothing will happen.

  **This is a breaking change.**
* Added `self` to exposed variables in tasks. This can be used
  to achieve what you would use $@ or other automatic variables
  in Makefiles.
* Added `-f` option to specify a Hacefile to use.
* Added `-n` option to do a dry run.
* Added `always_run` flag for tasks which causes them to always
  run even if their dependencies are unchanged.
* Implemented `--question` flag to ask if a task should be run.
* Implemented `auto` command, which continuously rebuilds as needed
  reacting to filesystem changes.

## Version v0.1.1

First actual release. While the tool is not feature complete by any means,
it does *some* stuff and what it does it seems to do well.

For details on what it can and can't do, see the
[README.](https://github.com/ralsina/hace/blob/main/README.md)
