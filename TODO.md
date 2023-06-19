# TODO

## Things that may be a good idea to add

* Makefile parser when there is no Hacefile
* Tasks with wildcard targets / dependencies
* Automatic variables (like make's `$@`)
* Something equivalent to static patterns:

  `$(objects): %o: %c`

* Something like pattern rules: `%o : %c`
* Logging / Verbosity management
* Make default tasks opt-in instead of opt-out

* ~~Multiple outputs~~
* ~~Mark some tasks as "default" which run when no task is specified~~
* ~~Add -B --always-make option like make~~
* ~~Environment variables~~
* ~~Templated tasks~~
* ~~Real command line interface~~
* ~~The equivalent of PHONY tasks~~
* ~~Variables~~

## Things that look like bad ideas and why

* Implicit rules.

  make does things like automatically use `$(CC)` to build `.c` files.
  this is both confusing (runs random unconfigured commands)
  and of limited usefulness (if you want make, use make)

* Shell selection

  Apparently `Process.run()` uses `/bin/sh` on linux and `cmd.exe` on
  windows and changing it while supporting things like redirection and
  whatnot is not trivial.

  Since `/bin/sh` is the standard shell, I'll just use that. It's a feature
  now.
