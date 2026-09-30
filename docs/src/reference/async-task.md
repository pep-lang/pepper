<!-- Generated from runtime/async/task.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Tasks

Tasks: functions that run concurrently on one thread, each on its own
small stack, switching only where they wait.

`run(body)` turns the calling thread into a worker and runs `body` as its
first task. A task starts others with `Task<T>.spawn_local`, and gives
the thread to the others whenever it waits: `sleep`, `yield_now`, and
`Task.join`, and whenever a socket call would block. Nothing preempts a task, so a task that computes for a long
time without waiting keeps every other task on its worker waiting too.

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

Creates the default options: 256 KiB of stack per task, and the
system's best I/O backend.

### Methods

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

A task started with `spawn_local`, and the value its body returns.

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

Wraps the scheduler's record of a task. Only `spawn_local` has one;
start tasks with `spawn_local`.

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

Runs `body` as the first task of a new runtime on the calling thread, and
returns once `body` has returned and every task it started has finished.
When `body` returns, the tasks still running are cancelled (see
`Task.cancel`), and `run` waits for them to finish.

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
