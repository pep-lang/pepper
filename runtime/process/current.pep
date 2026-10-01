## The running process: its arguments, id, executable and working
## directory, and how it ends.
##
## Two functions are listed only here, since the module exports them under
## names the deprecated prelude functions still hold:
##
## - `arguments(): Array<String>` returns the program's command-line
##   arguments: element 0 is the program as it was started, and the
##   arguments typed after it follow in order. `main` receives the same array
##   when it is declared `main(args: String[]): int`. On Windows they are in
##   the process's ANSI code page.
## - `exit(code: int)` ends the program at once with status `code` (only its
##   low 8 bits reach a POSIX parent), after flushing standard output and the
##   other C output streams. Nothing else runs: locals are not released and
##   destructors do not run.

import io;
import "sys_posix";
import "sys_windows";

## Returns the program's command-line arguments.
##
## Element 0 is the program as it was started (usually its path), and the
## arguments typed after it follow in order, as the shell passed them: a
## quoted argument with spaces is one element. Each call builds a new array.
##
## On Windows the arguments are in the process's ANSI code page, so text
## outside it is not preserved.
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
export _process_arguments(): Array<String> {
    return _pep_arguments();
}

## Ends the program at once with status `code`.
##
## Flushes standard output and every other C output stream first, so text
## printed so far is not lost. Nothing else runs: locals are not released,
## destructors do not run, and other threads stop where they are. Returning
## from `main` is the usual way to end; `exit` is for ending from deep inside
## a call.
##
## @param code the exit status: 0 for success, anything else for failure
##   (only its low 8 bits reach a POSIX parent)
## @example
##     import process;
##
##     main(): int {
##         if (process.arguments().count() < 2) {
##             print("usage: tool FILE");
##             process.exit(2);
##         }
##         return 0;
##     }
export _process_exit(code: int) {
    _pep_exit(code);
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
