<!-- Generated from runtime/async/task.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Tasks

Tasks: functions that run concurrently on a few worker threads, each on
its own small stack, switching only where they wait.

`run(body)` turns the calling thread into the first worker, starts the
others, and runs `body` as the first task. A task starts others with
`Task<T>.spawn_local` (on its own worker) or `spawn` (on any worker), and
gives its worker to the other tasks there whenever it waits: `sleep`,
`yield_now`, and `Task.join`, whenever a socket call would block, and
whenever it waits on a `Mutex`, `Condition` or `Channel`. Nothing
preempts a task, so a task that computes for a long time without waiting
keeps every other task on its worker waiting too.

A task is a green thread (a fiber): an ordinary function with its own
stack, so code that waits looks the same as code that does not, and a
function called in a task can wait without being marked in any way.

Source: `runtime/async/task.pep`

## TaskError

```pepper
struct TaskError
```

Why `Task.join` did not return the task's value.

### Fields

#### message

```pepper
const message: String
```

A description of what went wrong.

### Constructor

#### TaskError()

```pepper
construct(message: String)
```

Creates a task error.

**Parameters**
- `message` — a description of what went wrong

### Methods

#### is_cancelled

```pepper
is_cancelled(): bool
```

Returns whether the task was cancelled, or the task waiting for it was.

**Returns**
- true when cancellation ended the wait

#### is_timed_out

```pepper
is_timed_out(): bool
```

Returns whether a `timeout` around the `join` expired before the task
finished. The task itself carries on.

**Returns**
- true when a timeout ended the wait

## RuntimeOptions

```pepper
struct RuntimeOptions
```

Settings for `run_with`, built by chaining: `RuntimeOptions().stack_size(65536)`.

### Constructor

#### RuntimeOptions()

```pepper
construct()
```

Creates the default options: one worker per logical CPU, 256 KiB of
stack per task, the system's best I/O backend, and up to 64 threads
for `run_blocking`.

### Methods

#### workers

```pepper
workers(count: ulong): RuntimeOptions
```

Sets how many workers (threads that run tasks) the runtime has. The
thread that calls `run_with` is the first; the rest are new threads.
Tasks from `spawn_local` run on the worker that started them; tasks
from `spawn` run on whichever worker is free. The default is
`logical_cpus()`.

**Parameters**
- `count` — the number of workers

**Returns**
- these options

**Panics**
- if `count` is 0

#### blocking_threads

```pepper
blocking_threads(count: ulong): RuntimeOptions
```

Sets how many threads `run_blocking` may start. The runtime starts
them one at a time, when a blocking call finds none idle, and keeps
them until `run_with` returns. Once there are `count`, further calls
wait for one of them to be free. The default is 64.

**Parameters**
- `count` — the most threads for blocking calls

**Returns**
- these options

**Panics**
- if `count` is 0

#### backend

```pepper
backend(kind: Backend): RuntimeOptions
```

Sets which I/O backend the runtime waits on sockets with. The default,
`Backend.Automatic`, picks the system's best (or the one the
`PEPPER_IO_BACKEND` environment variable names).

**Parameters**
- `kind` — the backend

**Returns**
- these options

**Note**
- `run_with` panics if the system does not have the backend

#### stack_size

```pepper
stack_size(bytes: ulong): RuntimeOptions
```

Sets how much stack each task reserves. Only the pages a task touches
use memory; the rest is address space. A task that uses more than this
crashes the program, as a thread that overflows its stack does.

**Parameters**
- `bytes` — the stack size in bytes (rounded up to whole pages)

**Returns**
- these options

**Panics**
- if `bytes` is less than 16 KiB

## Task

```pepper
struct Task<T>
```

A task started with `spawn_local` or `spawn`, and the value its body
returns.

**Type parameters**
- `T` — the type of the body's result; `void` when there is none

**Example**
```pepper
import async;

main(): int {
    async.run(() => {
        var a = async.Task<int>.spawn_local(() => { return 20; });
        var b = async.Task<int>.spawn_local(() => { return 22; });
        print(a.join().value() + b.join().value());   # 42
    });
    return 0;
}
```

### Constructor

#### Task()

```pepper
construct(core: _TaskCore)
```

Wraps the scheduler's record of a task. Only `spawn_local` and `spawn`
have one; start tasks with those.

**Parameters**
- `core` — the scheduler's record of the task

### Static methods

#### spawn_local

```pepper
static spawn_local(body: () => T): Task<T>
```

Starts a task on the current worker that runs `body`. It runs the
next time the running task waits, and may use anything the running
task can, since it stays on this thread.

**Parameters**
- `body` — the task's code

**Returns**
- the task

**Panics**
- outside `run`

### Methods

#### join

```pepper
join(): Result<T, TaskError>
```

Waits for the task to finish and returns its value. Other tasks run
meanwhile.

**Returns**
- the body's result, or a `TaskError` if the task was cancelled before it finished, the task calling `join` was cancelled while it waited, or a `timeout` around the `join` expired first

**Panics**
- if a task joins itself, or if called outside `run` on a task that has not finished

#### cancel

```pepper
cancel()
```

Asks the task to stop: from now on `is_cancelled()` is true inside it,
`sleep` returns at once, and its `join` calls fail. A task is never
stopped by force; it finishes when its body returns.

#### is_finished

```pepper
is_finished(): bool
```

Returns whether the task's body has returned.

**Returns**
- true once the task has finished

## run

```pepper
run(body: () => void)
```

Runs `body` as the first task of a new runtime, and returns once `body`
has returned and every task it started has finished. The calling thread
is the first worker; the runtime starts one more thread per logical CPU
after it (see `RuntimeOptions.workers`). When `body` returns, the tasks
still running are cancelled (see `Task.cancel`), on every worker, and
`run` waits for them to finish.

**Parameters**
- `body` — the first task

**Panics**
- if called inside a task, or if every remaining task is waiting on another and none can continue

**Example**
```pepper
import async;

main(): int {
    async.run(() => {
        var t = async.Task<void>.spawn_local(() => {
            async.sleep(10);
            print("second");
        });
        print("first");
        t.join();
    });
    return 0;
}
```

## run_with

```pepper
run_with(options: RuntimeOptions, body: () => void)
```

Runs `body` like `run`, with the given settings.

**Parameters**
- `options` — the runtime's settings
- `body` — the first task

**Panics**
- if called inside a task, if every remaining task is waiting on another and none can continue, or if the system does not have the backend `options` asks for

## spawn

```pepper
spawn<T: Shared>(body: shared () => T): Task<T>
```

Starts a task that runs `body` on whichever worker is free first, and
returns it. Unlike `Task<T>.spawn_local`, the task may run on another
thread, in parallel with the calling task, so the body must be a
`shared` function (it may capture only thread-safe values) and its result
crosses threads, so `T` is constrained `Shared`: a thread-safe type such
as a number, a `[Shared]` struct, or a `shared` function type
(`spawn<String>` is a compile error at `String`).

A task, once started, stays on the worker that started it. Joining and
cancelling work as for `spawn_local`.

**Type parameters**
- `T` — the type of the body's result, which must be thread-safe (`T: Shared`); `void` when there is none

**Parameters**
- `body` — the task's code

**Returns**
- the task

**Panics**
- outside `run`

**Example**
```pepper
import async;

sum(from: long, to: long): long {
    var total: long = 0;
    var i = from;
    while (i < to) {
        total = total + i;
        i = i + 1;
    }
    return total;
}

main(): int {
    async.run(() => {
        var low = async.spawn<long>(() => { return sum(0, 500000); });
        var high = async.spawn<long>(() => { return sum(500000, 1000000); });
        print(low.join().value() + high.join().value());   # 499999500000
    });
    return 0;
}
```

## spawn_on_each_worker

```pepper
spawn_on_each_worker(body: shared () => void): Array<Task<void>>
```

Starts one task on every worker, each running `body`, and returns them in
worker order. Use it to give each worker its own copy of a loop, such as
a server's accept loop on an `io.SharedTcpListener`, so that every worker
takes part. Each task runs on its own worker, the calling task's worker
included; they are otherwise like tasks from `spawn`, and `body` must be
a `shared` function.

**Parameters**
- `body` — the code each worker runs

**Returns**
- one task per worker, the first on the first worker

**Panics**
- outside `run`

**Example**
```pepper
import async;
import io;

main(): int {
    async.run(() => {
        var listener = io.SharedTcpListener.bind(io.SocketAddress.parse("0.0.0.0:7000").value()).value();
        var loops = async.spawn_on_each_worker(() => {
            while (true) {
                var accepted = listener.accept();
                if (accepted.is_err()) {
                    return;
                }
                var (stream, peer) = accepted.value();
                async.Task<void>.spawn_local(() => {
                    stream.write_all("hello");
                });
            }
        });
        for (var loop in loops) {
            loop.join();
        }
    });
    return 0;
}
```

## run_blocking

```pepper
run_blocking<T: Shared>(body: shared () => T): T
```

Runs `body` on a separate thread and returns what it returns, parking
the calling task meanwhile so the worker keeps running other tasks. Use it
for work that would otherwise hold the worker up: a call that blocks in
the operating system (reading a file, resolving a host name, a C library
that waits) or a long computation.

The runtime keeps a pool of threads for these calls, started as needed up
to `RuntimeOptions.blocking_threads`. `body` runs on one of them, so it
must be a `shared` function and `T` is constrained `Shared`, as for
`spawn`.
On a pool thread, sockets block the thread, and `sleep` and the other task
functions behave as outside `run`.

`body` always runs to the end: cancelling the calling task, or a `timeout`
around the call expiring, takes effect once `run_blocking` has returned.
Outside a task, `run_blocking` just calls `body`.

**Type parameters**
- `T` — the type of the body's result, which must be thread-safe (`T: Shared`); `void` when there is none

**Parameters**
- `body` — the blocking code

**Returns**
- what `body` returns

**Example**
```pepper
import async;

main(): int {
    async.run(() => {
        var ticker = async.Task<void>.spawn_local(() => {
            async.sleep(10);
            print("the worker kept running");
        });
        var answer = async.run_blocking<int>(() => {
            async.Thread.sleep(50);   # blocks a pool thread, not the worker
            return 42;
        });
        print(answer);
        ticker.join();
    });
    return 0;
}
```

## yield_now

```pepper
yield_now()
```

Lets every other ready task run before the calling task continues. Does
nothing outside a task.

## sleep

```pepper
sleep(milliseconds: ulong)
```

Waits at least `milliseconds`. In a task, other tasks run meanwhile, and
a cancelled task returns at once, as does one whose `timeout` expires
first; outside a task, the thread sleeps.

**Parameters**
- `milliseconds` — how long to wait

## sleep

```pepper
sleep(duration: os.Duration)
```

Waits at least `duration`, the same as `sleep(milliseconds)`. A duration
that is not a whole number of milliseconds rounds up, so the wait is never
shorter than asked.

**Parameters**
- `duration` — how long to wait

**Example**
```pepper
async.sleep(os.Duration.from_seconds(1));
```

## is_cancelled

```pepper
is_cancelled(): bool
```

Returns whether the running task has been cancelled (see `Task.cancel`),
so a long computation can stop early. False outside a task.

**Returns**
- true when the running task was asked to stop

## Deadline

```pepper
struct Deadline
```

A time limit on the waits inside a `with` block, made by `timeout`.

While the block runs, a socket call that has to wait fails with an
`IoError` for which `is_timed_out()` holds once the limit passes,
`Task.join` fails with a `TaskError` for which `is_timed_out()` holds,
and `sleep` returns early. Code that does not wait is never interrupted.
Timeouts nest: an inner one cannot extend an outer one.

### Constructor

#### Deadline()

```pepper
construct(milliseconds: ulong)
```

Creates a limit `milliseconds` from now. Use `timeout` instead.

**Parameters**
- `milliseconds` — how long from now the limit passes

### Methods

#### enter

```pepper
enter(): Deadline
```

Starts applying the limit to the running task; a `with` block calls
it.

**Returns**
- this deadline

**Panics**
- outside a task

#### exit

```pepper
exit()
```

Stops applying the limit; the end of the `with` block calls it.

#### is_expired

```pepper
is_expired(): bool
```

Returns whether the limit has passed.

**Returns**
- true once the time is up

## timeout

```pepper
timeout(milliseconds: ulong): Deadline
```

Returns a time limit for a `with` block: the waits inside it give up
`milliseconds` from now (see `Deadline`).

**Parameters**
- `milliseconds` — how long the block's waits may take in all

**Returns**
- the limit, for a `with` header

**Example**
```pepper
import async;
import io;

main(): int {
    async.run(() => {
        var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        with (var deadline = async.timeout(50)) {
            var accepted = listener.accept();   # nobody connects
            assert(accepted.error().is_timed_out(), "timed out");
        }
    });
    return 0;
}
```

## current_backend

```pepper
current_backend(): Backend
```

Returns the I/O backend the running runtime waits on sockets with (see
`RuntimeOptions.backend`).

**Returns**
- the backend; never `Backend.Automatic`

**Panics**
- outside `run`
