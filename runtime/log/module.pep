## Leveled, structured logging: lines with a level, a message, key/value
## fields and the place of the call, written whole to standard error or
## to a `Writer` of your choice, from any thread or task.
##
## `log` is a module: bring it in with `import log` (and write
## `log.info("started")`).
##
## - `error`, `warning`, `info`, `debug` and `trace` write a line at their
##   `Level`. Each takes optional `fields` (made with `field`) and a
##   `target`, the part of the program the line is about.
## - `set_level` picks the least important level shown, for every target
##   or for one; `enabled` asks whether a line would be written.
## - `set_output` sends lines to a `Writer` (a file, a socket) in a
##   `Format`: readable text or JSON Lines.
##
## By default lines go to standard error as text, in color when it is a
## terminal (unless `NO_COLOR` is set), and info and above are shown. The
## `PEPPER_LOG` environment variable sets the levels when the program first
## logs: comma-separated items, each a level for every target or
## `target=level` for one, such as `PEPPER_LOG=warning,http=debug`. The
## levels are `off`, `error`, `warning` (or `warn`), `info`, `debug` and
## `trace`.
##
## A text line reads:
##
##     2026-10-17T23:40:01.123Z INFO  [http] request done status=200 path="/" (main.pep:5:5)
##
## @example
##     import log;
##
##     main(): int {
##         log.info("started");
##         log.warning("disk almost full", [log.field("free_mb", 120)], target = "storage");
##         log.debug("not shown unless PEPPER_LOG=debug");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "log";

export Level;
export Format;
export Field;
export field;
export set_level;
export set_output;
export enabled;
export error;
export warning;
export info;
export debug;
export trace;
