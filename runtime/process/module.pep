## Child processes, and what belongs to the running one, modeled on Rust's
## `std::process`.
##
## `process` is a module: bring it in with `import process` (and write
## `process.Command`) or import names directly with
## `import [Command, Stream] from process`. `arguments()` and `exit()` stay
## in the prelude, and the module passes them on as well.
##
## - [Command](process-command.md): `Command` describes a program to start;
##   `run()` waits for it and collects its output, `spawn()` starts it and
##   returns a `Child`, and `exec()` runs it in place of the running program
## - [Child](process-child.md): a running child process, its piped streams,
##   and its `ExitStatus`
## - [The running process](process-current.md): `id()` and
##   `executable_path()`
##
## @example
##     import process;
##
##     main(): int {
##         var output = process.Command("git").argument("--version").run();
##         if (output.is_err()) {
##             print("git is not installed");
##             return 1;
##         }
##         print(output.value().stdout);
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "child";
import "command";
import "current";
import "sys_posix";
import "sys_wasi";
import "sys_windows";

export Stream;
export Command;
export Output;
export Child;
export ExitStatus;
export id;
export executable_path;
export working_directory;
export change_working_directory;
# Declared under other names while the deprecated prelude functions keep
# these (top-level exports are unique program-wide until #244).
export _process_arguments as arguments;
export _process_exit as exit;
