<!-- Generated from runtime/async/task.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Tasks

Tasks: functions that run concurrently on one thread, each on its own
small stack, switching only where they wait.

`run(body)` turns the calling thread into a worker and runs `body` as its
first task. A task starts others with `Task<T>.spawn_local`, and gives
the thread to the others whenever it waits: `sleep`, `yield_now`, and
`Task.join`. Nothing preempts a task, so a task that computes for a long
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

Returns whether the task was cancelled, or the task waiting for it was
(the only reason so far).

**Returns**
- true when cancellation ended the wait

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

Creates the default options: 256 KiB of stack per task.

### Methods

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
- the body's result, or a `TaskError` if the task was cancelled before it finished or the task calling `join` was cancelled while it waited

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
- if called inside a task, or if every remaining task is waiting on another and none can continue

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
a cancelled task returns at once; outside one, the thread sleeps.

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
