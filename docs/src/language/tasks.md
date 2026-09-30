# Tasks

A task is a function that runs alongside others. Each task has its own small
stack, and the tasks on a thread take turns: one runs until it waits (for a
timer, for another task, or by yielding), and then another runs. A runtime
has a few such threads, its *workers*, so tasks also run in parallel. This is
the model of Go's goroutines and of libuv or tokio event loops, without
`async`/`await`: a function that waits looks like any other function, and
any function can wait, however deep in the call stack. A socket call that
has to wait parks only its task, so one worker can serve thousands of
connections.

Tasks live in the `async` module:

```pepper
{{#include ../../examples/tasks-basics.pep}}
```

- `async.run(body)` runs `body` as the first task and returns once it has
  returned and every task it started has finished. `run_with(options, body)`
  does the same with settings; `RuntimeOptions().stack_size(bytes)` sets how
  much stack each task reserves (256 KiB by default).
- `Task<T>.spawn_local(body)` starts a task on the running task's worker and
  returns its `Task<T>`. The new task runs the next time the running task
  waits. `T` is the body's result type; use `Task<void>` for a body that
  returns nothing.
- `task.join()` waits for the task and returns a `Result<T, TaskError>`:
  the body's value, or an error if the task was cancelled.
- `async.yield_now()` lets every other ready task run first.
- `task.is_finished()` says whether the body has returned.

A task from `spawn_local` stays on the thread of the task that started it,
so it may use any value that task uses, as the closures above share `log`.
Nothing needs to be thread-safe.

## Several workers

`run` turns the calling thread into the first worker and starts one more
thread per logical CPU after it (`RuntimeOptions().workers(count)` sets how
many workers in all). `async.spawn<T>(body)` starts a task that whichever
worker is free first runs, in parallel with the others:

```pepper
{{#include ../../examples/tasks-spawn.pep}}
```

Because such a task may run on another thread, its body must be a `shared`
function: it may capture only thread-safe values, as a
[thread](threads.md)'s body. Its result crosses threads too, so `T` must be
thread-safe (a number, a `[Shared]` struct, or a `shared` function type);
`async.spawn<String>` is a compile error. `join`, `cancel` and
`is_finished` work as for `spawn_local`, from the task that started it.

A task, once started, stays on its worker until it finishes, so the tasks it
starts with `spawn_local` share values with it safely. An idle worker takes
the next task that no worker has started yet. A task that computes without
waiting still holds up the other tasks on its own worker (not the other
workers), so a long computation should call `yield_now()` now and then.

## Waiting

`async.sleep(milliseconds)` puts a task to sleep and runs the others
meanwhile, so many tasks can wait at the same time on one thread:

```pepper
{{#include ../../examples/tasks-sleep.pep}}
```

Outside a task, `sleep` blocks the thread, and `yield_now` does nothing.

Tasks are never interrupted. A task that computes for a long time without
waiting keeps every other task waiting, so a long loop should call
`yield_now()` now and then.

## Sockets

A socket call in a task that would have to wait (for a connection, for data,
or for room to send) parks the task and lets the others run until the
socket is ready. The socket API is the same one a plain program uses; only
the waiting differs:

```pepper
{{#include ../../examples/tasks-echo.pep}}
```

Outside a task, the same calls block the thread as before. A socket belongs
to the worker whose task made it: tasks started with `spawn_local` can share
it, and each spawned task makes its own.

When no task is ready to run, a worker blocks until a socket is ready, the
next timer is due, or another worker wakes it; while tasks are running, it also checks the sockets
every few dozen tasks, so a busy task cannot starve the network.

### Backends

How the runtime waits for sockets is its I/O *backend*, an `async.Backend`:

| Backend | Where | How |
|---|---|---|
| `Epoll` | Linux | epoll, edge-triggered |
| `Kqueue` | macOS | kqueue, edge-triggered |
| `Iocp` | Windows | an I/O completion port, fed by AFD poll requests (as tokio and libuv do) |
| `Poll` | everywhere | `poll()` (`WSAPoll` on Windows), which looks at every waiting socket on each wait: fine for a few connections, slow for thousands |

`Backend.Automatic`, the default, picks the first of the three that the
system has. `RuntimeOptions().backend(kind)` asks for one (and `run_with`
panics if the system does not have it), and the `PEPPER_IO_BACKEND`
environment variable (`epoll`, `kqueue`, `iocp` or `poll`) overrides the
automatic choice without changing the program, for testing and
benchmarks. `async.current_backend()` says which one is running.

## Timeouts

`async.timeout(milliseconds)` limits how long the waits inside a `with`
block may take:

```pepper
{{#include ../../examples/tasks-timeout.pep}}
```

Once the limit passes, a socket call that has to wait fails with an
`IoError` for which `is_timed_out()` holds, `join` fails with a `TaskError`
for which `is_timed_out()` holds (the task it waited for carries on), and
`sleep` returns early. Code that does not wait is never interrupted. The
limit ends with the block. Timeouts nest, and an inner one cannot extend an
outer one. `deadline.is_expired()` says whether the limit has passed.
`timeout` panics outside a task.

## Cancelling

`task.cancel()` asks a task to stop. Nothing stops it by force: from then on
`async.is_cancelled()` is true inside it, `sleep` returns at once, and
`join` on it fails with a `TaskError` whose `is_cancelled()` is true. A
task waiting in `join` returns the same error when it is cancelled itself,
and a socket call waiting in a cancelled task fails with an `IoError` whose
`is_cancelled()` is true.
When the first task of a `run` returns, every task still running is
cancelled, on every worker, and `run` waits for each to finish:

```pepper
{{#include ../../examples/tasks-cancel.pep}}
```

If every task is waiting for another task and none can continue, `run`
panics instead of waiting forever.

## How it works

Each task runs on a fiber: a stack of its own and a saved set of
registers. Switching tasks saves the running task's registers on its stack
and restores the other's, a few instructions of assembly on Linux and macOS
(the `__switch_context` intrinsic) and the Fibers API on Windows. A task's
stack is reserved address space with a guard page below it; only the pages
the task touches use memory, and a task that overflows its stack crashes the
program as a thread would. Stacks are reused for later tasks.

Each worker has its own ready queue, timers and backend. Workers talk
through a queue of messages each (a spawned task finished, or was
cancelled) and a *doorbell* that ends a worker's wait in its backend from
another thread: an eventfd with epoll, a user event with kqueue, a posted
completion with IOCP, and a pipe (a loopback UDP socket on Windows) with
`poll()`.

## Current status

- `run_blocking`, which runs work that would block the thread on a pool of
  threads while the task waits, is planned, as are listeners that accept on
  every worker and handing a socket to another worker.
- Files block the thread on every platform. io_uring on Linux, and
  asynchronous files, come later.
- On Windows, a `ThreadLocal` has a separate value in each task (it is
  built on fiber local storage); elsewhere the tasks of a thread share it.
- `Mutex`, `Channel`, `Condition` and `Thread.sleep` block the thread, and
  every task on it, when called in a task. Use `async.sleep` in tasks.

The [reference page](../reference/async-task.md) documents every function.
