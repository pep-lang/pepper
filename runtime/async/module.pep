## Threads and concurrency, modeled on Rust's `std::thread` and C++
## `std::thread`, and tasks: green threads that take turns on one thread.
##
## Like `io`, `async` is a module: bring it in with `import async` (and write
## `async.Thread`, `async.logical_cpus()`) or import names directly with
## `import [Thread, ThreadLocal] from async`.
##
## - [Thread](async-thread.md): starting, naming and joining threads, `ThreadId` and `ThreadBody`
## - [ThreadLocal](async-thread_local.md): a variable with a separate value on every thread, and its `ThreadLocalGuard<T>`
## - [Processor counts](async-cpus.md): `logical_cpus()` and `physical_cpus()`
## - [Channel](async-channel.md): `Channel<T>`, a queue that carries values between threads, and its `ChannelIterator<T>`
## - [Mutex](async-mutex.md): `Mutex<T>`, the `MutexGuard<T>` a `with` block holds, and `Condition<T>`
## - [Once](async-once.md): `Once`, which runs a function once, and `Lazy<T>`, a value built on first use
## - [Tasks](async-task.md): `run`, `Task<T>`, `sleep`, `yield_now`, `timeout` and cancellation, for many tasks taking turns on one thread and parking on sockets
##
## Only thread-safe values can be shared between threads: numbers, `shared`
## function values (such as a thread's body), and `[Shared]` structs such as
## `Atomic<T>`, `Thread`, `ThreadLocal<T>`, `Channel<T>` and `Mutex<T>`. Any
## other value crosses threads only as a new value that nothing else
## references (`Channel.send(move(x))`, or `send(copy(x))`), or stays inside
## a `Mutex`, whose `with` blocks the compiler keeps apart from the rest of
## the program. `Lazy<T>` holds thread-safe
## values only. See the language guide's Threads chapter.
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

import "channel";
import "cpus";
import "mutex";
import "once";
import "task";
import "thread";
import "thread_local";

export ThreadId;
export ThreadBody;
export Thread;
export ThreadLocal;
export ThreadLocalGuard;
export logical_cpus;
export physical_cpus;
export Mutex;
export MutexGuard;
export Condition;
export Once;
export Lazy;
export Channel;
export ChannelIterator;
export Task;
export TaskError;
export RuntimeOptions;
export run;
export run_with;
export yield_now;
export sleep;
export is_cancelled;
export Deadline;
export timeout;
