# Changelog

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
