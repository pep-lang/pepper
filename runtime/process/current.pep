## The running process: its arguments, id, executable and working
## directory, and how it ends.
##
## Two functions are listed only here, since the module exports them under
## names the deprecated prelude functions still hold:
##
## - `arguments(): Array<String>` returns the program's command-line
##   arguments: element 0 is the program as it was started, and the
##   arguments typed after it follow in order. `main` receives the same array
##   when it is declared `main(args: String[]): int`. On Windows they are
##   read as UTF-16 and converted to valid UTF-8.
## - `exit(code: int)` ends the program at once with status `code` (only its
##   low 8 bits reach a POSIX parent), as C's `exit` does: the handlers
##   registered with C's `atexit` run, then standard output and the other C
##   output streams are flushed. Locals are not released and destructors do
##   not run; other threads keep running while the handlers run. In a copy
##   `fork()` started, the handlers, which are the parent's, are skipped.

import io;
import [Child] from "child";
import "sys_posix";
import "sys_wasi";
import "sys_windows";

## Returns the program's command-line arguments.
##
## Element 0 is the program as it was started (usually its path), and the
## arguments typed after it follow in order, as the shell passed them: a
## quoted argument with spaces is one element. Each call builds a new array.
##
## On Windows the arguments are read as UTF-16 and converted to UTF-8, so
## every character arrives whole and each element is valid UTF-8 (an
## unpaired surrogate becomes U+FFFD). On POSIX an argument is whatever
## bytes the parent passed; one that is not valid UTF-8 is returned as it
## is.
##
## `main` receives the same array when it is declared
## `main(args: String[]): int`; `arguments()` reads it anywhere else.
##
## @returns the program name followed by its arguments
## @example
##     import process;
##
##     verbose(): bool {
##         for (var argument in process.arguments()) {
##             if (argument == "-v") {
##                 return true;
##             }
##         }
##         return false;
##     }
_process_arguments(): Array<String> {
    return _pep_arguments();
}

## Ends the program at once with status `code`.
##
## Ends as C's `exit` does, and as returning from `main` does: the
## handlers registered with C's `atexit` run, then standard output and
## every other C output stream are flushed, so text printed so far is not
## lost. Nothing else runs: locals are not released and destructors do not
## run. Other threads keep running while the handlers run, then stop
## wherever they are when the process ends. Returning from `main` is the
## usual way to end; `exit` is for ending from deep inside a call.
##
## In the copy `fork()` starts, the `atexit` handlers, which are the
## parent's, do not run, whichever of the copy's threads calls `exit`: the
## streams are flushed and the copy ends, as C's `_exit` ends a forked
## child.
##
## @param code the exit status: 0 for success, anything else for failure
##   (only its low 8 bits reach a POSIX parent)
## @example
##     import process;
##
##     main(): int {
##         if (process.arguments().count < 2) {
##             print("usage: tool FILE");
##             process.exit(2);
##         }
##         return 0;
##     }
_process_exit(code: int) {
    _pep_exit(code);
}

## Starts a copy of the running process (POSIX `fork`): the copy has the
## same memory, open files and code, and both go on from here. In the
## parent, returns the copy as a `Child` to wait for; in the copy, returns
## none. The copy has only the calling thread, so fork before starting
## threads or tasks, and end the copy with `exit()`, which there skips the
## parent's `atexit` handlers.
##
## The C standard streams are flushed first, so what `print` buffered is
## written once. Not on Windows or WASI, which start processes only from a
## program: there it returns an error.
##
## @returns the child in the parent, none in the copy, or an error
## @example
##     import process;
##
##     main(): int {
##         var forked = process.fork();
##         if (forked.is_err()) {
##             return 0;
##         }
##         if (!forked.value().is_value()) {
##             process.exit(3);
##         }
##         var status = forked.value().value().wait().value();
##         return status.code().value() == 3 ? 0 : 1;
##     }
export fork(): io.IoResult<Child?> {
    return _process_sys_fork();
}

## Returns the running process's id, as the operating system knows it.
##
## @returns the process id (`getpid` on POSIX, `GetCurrentProcessId` on
##   Windows)
export id(): ulong {
    return _process_sys_id();
}

## Returns the path of the running program's executable file, as an
## absolute path with symbolic links resolved (on Linux the target of
## `/proc/self/exe`; on macOS `_NSGetExecutablePath`, resolved; on Windows
## `GetModuleFileNameW`). A tool installed alongside others finds them
## next to it with `executable_path().value().parent()`.
##
## @returns the executable's path, or an error when the system cannot
##   report it
## @example
##     import process;
##
##     main(): int {
##         var path = process.executable_path().value();
##         print(path.to_string());
##         return 0;
##     }
export executable_path(): io.IoResult<io.Path> {
    return _process_sys_executable_path();
}

## Returns the process's current directory, against which relative paths
## are resolved. The same as `io.Directory.current()`.
##
## @returns the current directory as an absolute path; an error when it
##   cannot be determined, such as `is_not_found()` on POSIX when the
##   directory has been removed
export working_directory(): io.IoResult<io.Path> {
    return io.Directory.current();
}

## Changes the process's current directory. This affects the whole
## process, every thread included. The same as `io.Directory.set_current`.
##
## @param path the new current directory; a relative path is resolved
##   against the old one
## @returns an Ok result; an error when the directory cannot be entered:
##   `is_not_found()` when it is missing, `is_not_a_directory()` when it is
##   a file, or `is_permission_denied()`
export change_working_directory(path: io.Path): io.IoResult<void> {
    return io.Directory.set_current(path);
}
