## Stack walking, panic backtraces, and talking to a debugger.
##
## `debug` is a module: bring it in with `import debug` (and write
## `debug.capture()`).
##
## - [Backtraces](debug-backtrace.md): `capture()` records the calls that
##   led to the current point, cheaply; `Backtrace.frames()` resolves each
##   return address to its function and, in a `-g` build, its source line.
##   `print_backtrace()` writes the current stack to standard error.
## - [The debugger](debug-debugger.md): `output()` writes to the platform's
##   debugger channel, `is_debugger_attached()` asks whether a debugger is
##   watching, and `breakpoint()` stops in it.
##
## A panic prints a backtrace after its message in a build without `-O`;
## the `PEPPER_BACKTRACE` environment variable turns that on (`1`) or off
## (`0`) in any build (see `print_backtrace`).
##
## @example
##     import debug;
##
##     main(): int {
##         var trace = debug.capture();
##         var frames = trace.frames();
##         assert(frames.count > 0, "main is on the stack");
##         debug.output("captured a backtrace");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "backtrace";
import "debugger";

export StackFrame;
export Backtrace;
export capture;
export print_backtrace;

export output;
export is_debugger_attached;
export breakpoint;

# For the prelude's `panic` only (internals.pep).
export _debug_panic_backtrace;
