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

WASI cannot switch stacks, so on WebAssembly (`--target wasm32-wasip1`)
starting tasks (`async.run`, `async.run_with`) panics (see [WebAssembly](platform-selection.md#webassembly)).

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
[thread](threads.md)'s body. Its result crosses threads too, so `spawn`
constrains it [`T: Shared`](generics.md#the-shared-constraint): a
[thread-safe type](threads.md#what-threads-can-share) such as a number, a
`[Shared]` struct, or a `shared` function type. `async.spawn<String>` is a
compile error at `String`. `join`, `cancel` and
`is_finished` work as for `spawn_local`, from the task that started it.

A task, once started, stays on its worker until it finishes, so the tasks it
starts with `spawn_local` share values with it safely. An idle worker takes
the next task that no worker has started yet. A task that computes without
waiting still holds up the other tasks on its own worker (not the other
workers), so a long computation should call `yield_now()` now and then.

`async.spawn_on_each_worker(body)` starts one task per worker, each on its
own worker, and returns them in worker order. It is how a server runs an
accept loop on every worker (see [Sockets](#sockets)).

## Blocking calls

Some work would hold a worker up: a call that blocks in the operating system
(reading a file, a C library that waits) or a long computation.
`async.run_blocking<T>(body)` runs `body` on a separate thread and parks
the calling task until it returns, so the worker keeps running its other
tasks meanwhile:

```pepper
{{#include ../../examples/tasks-blocking.pep}}
```

The runtime keeps a pool of threads for these calls. It starts one when a
call finds none idle, up to `RuntimeOptions().blocking_threads(count)` (64
by default); past that, calls wait for a free one. As for `spawn`, `body`
must be a `shared` function and `T` must be thread-safe. `body` always runs
to the end: cancelling the task, or a `timeout` around the call, takes
effect once the call has returned. Outside a task, `run_blocking` just
calls `body`.

## Waiting

`async.sleep` puts a task to sleep and runs the others meanwhile, so many
tasks can wait at the same time on one thread. It takes an `os.Duration`
(see [The operating system](os.md)), or a number of milliseconds; a duration
that is not a whole number of milliseconds rounds up:

```pepper
{{#include ../../examples/tasks-sleep.pep}}
```

Outside a task, `sleep` blocks the thread, and `yield_now` does nothing.

Tasks are never interrupted. A task that computes for a long time without
waiting keeps every other task waiting, so a long loop should call
`yield_now()` now and then.

`Thread.sleep` in a task is `async.sleep`.

## Mutexes, channels and conditions

The [synchronization types](threads.md) work in tasks too. When a task
has to wait for a `Mutex`, for a value from a `Channel` or for room in a
bounded one, or in `Condition.wait`, it parks and its worker runs other
tasks, just as it does for a socket. The task that holds the lock or will
send the value can be on the same worker, on another worker, or a plain
thread:

```pepper
{{#include ../../examples/tasks-sync.pep}}
```

- Each task counts as its own holder of a `Mutex`, so two tasks on one
  worker exclude each other, and a task may hold a lock across its own
  waits (a `sleep`, a socket call, another lock).
- A cancel, or a `timeout` around the call, ends a channel wait: `send`
  returns false and `receive` returns an error (and a `for` loop over the
  channel ends). A task waiting for a `Mutex` still gets the lock, and
  `Condition.wait` still waits for a notification, since the caller's loop
  would only wait again; `wait_for` returns when its own time runs out.
- A [`Select`](threads.md#waiting-on-several-channels-with-select) parks
  its task on every channel at once, and a cancel or `timeout` ends its
  wait with an error. `Condition.wait_while` parks like `wait`.
- Outside a task they block the thread, as before.

## Task-local values

A `TaskLocal<T>` is a variable with a separate value in every task, as a
[`ThreadLocal<T>`](threads.md#per-thread-values-with-threadlocal) has one
per thread. Tasks that take turns on one worker share its thread, so only a
`TaskLocal` can tell them apart:

```pepper
{{#include ../../examples/tasks-local.pep}}
```

- `set(value)` stores the calling task's value and `get()` returns it (the
  default of `T`, zero or null, until the task sets one). `is_set()` and
  `clear()` work as on a `ThreadLocal`.
- A task starts with no value, even one started by a task that has one,
  and its values are released when it finishes.
- Code outside any task (before `async.run`, or on a plain `Thread`) has
  one value per thread, like a `ThreadLocal`.
- For a `T` that is not thread-safe, such as a `String`, reach the value
  with `with (var value = local.enter()) { ... }`, as for a `ThreadLocal`;
  `get()` is then a compile error.

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

### Waiting on several sockets

To wait on whichever of several sockets is ready first, give each socket a
task that reads it and sends what it read to a channel, and wait on the
channels with a [`Select`](threads.md#waiting-on-several-channels-with-select).
Closing a channel when its socket closes lets the select stop waiting on it.
Tasks are cheap, so this costs little, and the reading code stays the
ordinary blocking-style loop:

```pepper
{{#include ../../examples/tasks-select-sockets.pep}}
```

### Files

`File.read`, `write` and `write_all` in a task park the task until the
system call is done, and the worker runs other tasks meanwhile. With the
`IoUring` backend the kernel does the read or write itself; with the others
a thread from `run_blocking`'s pool makes the blocking call. Opening,
seeking, `metadata` and the other `File` calls still block the thread, as
they are quick on local disks. A cancel or a `timeout` does not cut a read
or write short: it takes effect once the call returns.

The array a read fills or a write sends from is in use until the call
returns, so growing it from another task meanwhile panics ("Array: the
buffer is in use by an I/O operation"). A `String` passed to `write_all` is
copied first.

### Accepting on every worker

An `io.SharedTcpListener` is a listening socket that any thread can accept
on. Give each worker an accept loop with `spawn_on_each_worker`; each
connection goes to one of the waiting workers, and the stream it returns
belongs to that worker:

```pepper
{{#include ../../examples/tasks-accept.pep}}
```

The listener has no `close()`, since other workers may be waiting on it.
It closes when the last reference goes: here, once `run` has cancelled the
loops.

### Moving a stream to another worker

`stream.into_transfer()` moves a connection out of a `TcpStream` into an
`io.SocketTransfer`, a thread-safe token that a `shared` function can
capture or a `Channel` can carry, and `io.TcpStream.adopt(transfer)` takes
it out again on the receiving worker. The old stream is closed afterwards,
only the first `adopt` gets the connection, and a token no one adopts
closes the connection when it goes:

```pepper
{{#include ../../examples/tasks-transfer.pep}}
```

When no task is ready to run, a worker blocks until a socket is ready, the
next timer is due, or another worker wakes it; while tasks are running, it also checks the sockets
every few dozen tasks, so a busy task cannot starve the network.

### Backends

How the runtime waits for sockets is its I/O *backend*, an `async.Backend`:

| Backend | Where | How |
|---|---|---|
| `Epoll` | Linux | epoll, edge-triggered |
| `IoUring` | Linux 5.11 and later | io_uring: the kernel does stream sockets' receives and sends and files' reads and writes itself, submitted in batches, with deferred completion work; never picked automatically, since container seccomp profiles and hardened kernels often refuse it |
| `Kqueue` | macOS | kqueue, edge-triggered |
| `Iocp` | Windows | an I/O completion port, fed by AFD poll requests (as tokio and libuv do) |
| `Poll` | everywhere | `poll()` (`WSAPoll` on Windows), which looks at every waiting socket on each wait: fine for a few connections, slow for thousands |

`Backend.Automatic`, the default, picks epoll, kqueue or IOCP, whichever
the system has. `RuntimeOptions().backend(kind)` asks for one (and
`run_with` panics if the system does not have it), and the
`PEPPER_IO_BACKEND` environment variable (`epoll`, `io_uring`, `kqueue`,
`iocp` or `poll`) overrides the automatic choice without changing the
program, for testing and benchmarks. `async.current_backend()` says which one is running.

io_uring pays off as the amount of multiplexed I/O grows: many operations
in flight, submitted and completed in batches through the ring rather than
one system call each. With the `IoUring` backend, a stream socket's `read`
and `write` in a task go to the kernel as a receive or send request, which
it runs once the socket is ready; the worker submits every request queued
since its last look, and collects every completion, in one system call. In
our echo benchmark that makes about an eighth of epoll's system calls,
runs as fast as epoll from 64 to 1,024 connections (half again as fast as
io_uring used only for readiness), and stays about 10% behind at 4,096.

A cancel or a `timeout` asks the kernel to stop a request and waits for it
to finish, since the kernel is writing into or reading from the array
until then. A receive that got data before the cancel took effect returns
that data instead of failing, so no bytes are lost. As with files, growing
the array from another task meanwhile panics. Accepting, connecting, UDP
sockets, and a second task reading (or writing) a socket that one already
reads (or writes) still wait for readiness.

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
through a queue of messages each (a spawned task finished, was cancelled, or
was woken by a `Mutex`, `Condition` or `Channel`) and a *doorbell* that ends
a worker's wait in its backend from another thread: an eventfd with epoll
and io_uring, a user event with kqueue, a posted completion with IOCP, and a
pipe (on Windows, a loopback UDP socket that a second socket sends to) with
`poll()`. `run_blocking`'s pool threads are plain threads that report back
through the same messages.

## Current status

- `File` calls other than `read`, `write` and `write_all` (opening,
  seeking, `sync`, directories) block the thread in a task.
- On Windows, a `ThreadLocal` has a separate value in each task (it is
  built on fiber local storage); elsewhere the tasks of a thread share it.

The [reference page](../reference/async-task.md) documents every function.
