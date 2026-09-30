# Tasks

A task is a function that runs alongside others on the same thread. Each task
has its own small stack, and tasks take turns: one runs until it waits (for
a timer, for another task, or by yielding), and then another runs. This is
the model of Go's goroutines and of libuv or tokio event loops, without
`async`/`await`: a function that waits looks like any other function, and
any function can wait, however deep in the call stack. A socket call that
has to wait parks only its task, so one thread can serve thousands of
connections.

Tasks live in the `async` module:

```pepper
{{#include ../../examples/tasks-basics.pep}}
```

- `async.run(body)` runs `body` as the first task and returns once it has
  returned and every task it started has finished. `run_with(options, body)`
  does the same with settings; `RuntimeOptions().stack_size(bytes)` sets how
  much stack each task reserves (256 KiB by default).
- `Task<T>.spawn_local(body)` starts a task and returns its `Task<T>`. The
  new task runs the next time the running task waits. `T` is the body's
  result type; use `Task<void>` for a body that returns nothing.
- `task.join()` waits for the task and returns a `Result<T, TaskError>`:
  the body's value, or an error if the task was cancelled.
- `async.yield_now()` lets every other ready task run first.
- `task.is_finished()` says whether the body has returned.

Because every task of a `run` stays on the thread that called it, a task may
use any value the others use, as the closures above share `log`. Nothing
needs to be thread-safe. For work on several threads at once, use
[threads](threads.md).

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

Outside a task, the same calls block the thread as before.

On Linux the runtime waits on sockets with epoll, on macOS with kqueue,
and on Windows with WSAPoll.
When no task is ready to run, it blocks in the driver until a socket is
ready or the next timer is due; while tasks are running, it also checks the
sockets every few dozen tasks, so a busy task cannot starve the network.

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
cancelled, and `run` waits for each to finish:

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

## Current status

- A runtime runs on one thread: `spawn_local` is the only way to start a
  task. Tasks that run on several threads at once, and `run_blocking` for
  work that would block the thread, are planned.
- On Windows, the runtime waits on sockets with WSAPoll, which looks at
  every waiting socket on each poll; an I/O completion port driver that
  scales to many connections is next. Files block the thread on every
  platform. io_uring on Linux comes later.
- On Windows, a `ThreadLocal` has a separate value in each task (it is
  built on fiber local storage); elsewhere the tasks of a thread share it.
- `Mutex`, `Channel`, `Condition` and `Thread.sleep` block the thread, and
  every task on it, when called in a task. Use `async.sleep` in tasks.

The [reference page](../reference/async-task.md) documents every function.
