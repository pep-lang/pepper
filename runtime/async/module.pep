## Threads and concurrency, modeled on Rust's `std::thread` and C++
## `std::thread`.
##
## Like `io`, `async` is a module: bring it in with `import async` (and write
## `async.Thread`, `async.logical_cpus()`) or import names directly with
## `import [Thread, ThreadLocal] from async`.
##
## - [Thread](async-thread.md): starting, naming and joining threads, `ThreadId` and `ThreadBody`
## - [ThreadLocal](async-thread_local.md): a variable with a separate value on every thread
## - [Processor counts](async-cpus.md): `logical_cpus()` and `physical_cpus()`
##
## Only thread-safe values can be shared between threads: numbers, `shared`
## function values (such as a thread's body), and `[Shared]` structs such as
## `Atomic<T>`, `Thread` and `ThreadLocal<T>`. See the language guide's
## Threads chapter.
##
## @example
##     import async;
##
##     const hits = Atomic<long>(0);
##
##     work() {
##         hits.fetch_add(1);
##     }
##
##     main(): int {
##         var workers = Array<async.Thread>();
##         var n = async.logical_cpus();
##         var i: ulong = 0;
##         while (i < n) {
##             workers.append(async.Thread.spawn(work));
##             i = i + 1;
##         }
##         for (var worker in workers) {
##             worker.join();
##         }
##         assert(hits.load() == n as long, "every worker ran");
##         return 0;
##     }

# This file only gathers the module's public API from its other files. The
# platform layer (`_async_sys_*` in sys_posix.pep / sys_windows.pep) and the
# `_async_*` helpers are exported between the async files but not from the
# module.

import "thread";
import "thread_local";
import "cpus";

export ThreadId;
export ThreadBody;
export Thread;
export ThreadLocal;
export logical_cpus;
export physical_cpus;
