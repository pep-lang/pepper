## The stack the compiler's stages run on. The parser and every stage after
## it recurse once or more per level of nesting, and `MAX_NESTING` bounds
## the levels, so a stack of `STACK_SIZE` holds the deepest source a file
## may have. Every thread that parses, checks or compiles source runs on
## one: a tool's `main` hands its work to `on_compiler_stack`.

import [Channel, Thread] from async;

## The bytes of stack each thread that parses, checks or compiles source
## gets, 8 MiB, the same on every system (a thread gets 1 MiB by default on
## Windows and 512 KiB on macOS). An unoptimized (`-O0`) build of the
## compiler needs up to about 11 KiB per level of nesting, so a build of
## source nested `MAX_NESTING` levels deep needs up to about 2.8 MiB; the
## compiler's and pep-lsp's tests check that the front end fits in half of
## this. The stack is reserved address space; memory is used only as a
## thread reaches it.
export const STACK_SIZE: ulong = 8388608;

## Runs `body` on a new thread with a stack of `STACK_SIZE`, waits for it,
## and returns what it returned. A tool that parses or compiles source runs
## its `main` through this, since the main thread's stack is the system's
## (1 MiB on Windows).
##
## @param body the tool's work, returning its exit status
## @returns what `body` returned
export on_compiler_stack(body: shared () => int): int {
    var status = Channel<int>();
    Thread.spawn(() => {
        status.send(body());
    }, "main", STACK_SIZE).join();
    return status.receive().value();
}
