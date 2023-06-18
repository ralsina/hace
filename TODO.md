# TODO

## Things that may be a good idea to add

* Makefile parser when there is no Hacefile
* Templated tasks
* Tasks with wildcard targets / dependencies
* Verbosity management
* Variables
* Automatic variables (like make's `$@`)
* Multiple outputs
* Something equivalent to static patterns:

  `$(objects): %o: %c`

* Something like pattern rules:

  `%o : %c`
* Shell selection
* Environment variables

* ~~Real command line interface~~
* ~~The equivalent of PHONY tasks~~

## Things that look like bad ideas and why

* Implicit rules.

  make does things like automatically use `$(CC)` to build `.c` files.
  this is both confusing (runs random unconfigured commands)
  and of limited usefulness (if you want make, use make)
