## `-v`: what a build prints on standard error for a user whose build went
## wrong: the compiler, toolchain and runtime used, the build's folders,
## each external command it runs, and the output it writes. Off, each
## costs one check of a flag.

import async;
import [File] from io;
import process;

# 1 once `-v` turned it on, for the rest of the process (`async.Atomic<bool>`
# does not compile yet).
const _verbose = async.Atomic<int>(0);

## Turns `-v`'s lines on for the rest of the process.
export set_verbose() {
    _verbose.store(1);
}

## Whether `-v` is on.
##
## @returns true after `set_verbose`
export is_verbose(): bool {
    return _verbose.load() != 0;
}

## Prints `line` on standard error when `-v` is on.
##
## @param line the line, without its newline
export print_verbose(line: String) {
    if (is_verbose()) {
        File.stderr().write_all(line + "\n");
    }
}

## Prints the command line of `command`, which the build is about to run,
## when `-v` is on.
##
## @param command the command
export print_running(command: process.Command) {
    if (is_verbose()) {
        File.stderr().write_all($"running: {command.to_string()}\n");
    }
}
