<!-- Generated from runtime/async/thread.pep by `pep-doc reference`. Do not edit. -->

# Thread

Threads: starting, naming, identifying and joining operating-system
threads.

Source: `runtime/async/thread.pep`

## ThreadId

```pepper
type ThreadId = ulong
```

Identifies a thread for as long as the program runs: every thread,
whether started with `Thread.spawn` or not, gets a distinct id the first
time it is asked for one, and ids are never reused.

Ids are assigned by the runtime in the order threads ask for them, starting
at 1; they are not the operating system's thread ids. A `ThreadId` is a
number, so it can be compared, hashed and used as a `HashMap` key.

**See also**
- `Thread.id`

## ThreadBody

```pepper
type ThreadBody = shared () => void
```

The type of a thread's body: a function that takes no arguments and
returns nothing. `Thread.spawn` runs one on a new thread.

It is a `shared` function type, because the body runs on another thread:
a named function, or a closure that captures only thread-safe values
(numbers, `Atomic<T>`, `[Shared]` structs, other `shared` function
values). A closure capturing a `String`, say, is a compile error.

**See also**
- `Thread.spawn`

## Thread

```pepper
[Shared] struct Thread
```

An operating-system thread.

Start one with `Thread.spawn`, which runs a function on a new thread and
returns its `Thread`, and wait for it to finish with `join()`. Every
thread, including the main thread, can get its own `Thread` with
`Thread.current()`.

A `Thread` is `[Shared]`: the thread that started it and the thread itself
can both hold it. Dropping every reference without joining detaches the
thread: it keeps running, and its resources are freed when it finishes.

The body runs until it returns; there is no way to stop a thread from the
outside. A `panic` or failed `assert` on any thread ends the whole program.

**Example**
```pepper
import async;

const total = async.Atomic<long>(0);

add_ten() {
    total.fetch_add(10);
}

main(): int {
    var a = async.Thread.spawn(add_ten, "adder a");
    var b = async.Thread.spawn(add_ten, "adder b");
    a.join();
    b.join();
    assert(total.load() == 20, "both threads ran");
    return 0;
}
```

### Constructor

#### Thread()

```pepper
construct(name: String, body: ThreadBody)
```

Creates a `Thread` value for a thread that is already running. Programs
get threads from `spawn` and `current()` instead; a `Thread` made
directly is not attached to any thread and cannot be joined.

**Parameters**
- `name` — the thread's name; empty for an unnamed thread
- `body` — the function the thread runs

### Static methods

#### spawn

```pepper
static spawn(body: ThreadBody, name: String = "", stack_size: ulong = 0): Thread
```

Starts a new thread that runs `body`.

The new thread starts right away and runs until `body` returns. Its
`Thread.current()` is the `Thread` returned here.

The stack the operating system gives a thread by default differs:
usually 8 MiB on Linux (`ulimit -s`), 1 MiB on Windows, and 512 KiB
on macOS. A thread that recurses deeply, such as one walking a
deeply nested tree, passes `stack_size` to get the same stack
everywhere. The stack is reserved address space; memory is used
only as the thread reaches it.

**Parameters**
- `body` — the function to run on the new thread
- `name` — a name for the thread, returned by `name()`; empty by default
- `stack_size` — the bytes of stack the thread gets, rounded up to 64 KiB; 0, the default, for the system's default

**Returns**
- the new thread, to `join()` or query

**Panics**
- if the operating system cannot create another thread, or refuses `stack_size`

**Example**
```pepper
var worker = Thread.spawn(do_work, "worker");
worker.join();
var deep = Thread.spawn(walk_tree, "walker", 8388608);   # 8 MiB
deep.join();
```

#### current

```pepper
static current(): Thread
```

Returns the `Thread` of the thread that calls it.

For a thread started with `spawn` this is the `Thread` that `spawn`
returned. Any other thread (the main thread, or one started by C code)
gets a `Thread` the first time it asks and the same one afterwards; the
main thread's is named `main`, the others are unnamed. Such a `Thread`
cannot be joined.

**Returns**
- the calling thread

**Example**
```pepper
var me = Thread.current();
print(me.name(), "\n");   # "main" on the main thread
```

#### sleep

```pepper
static sleep(milliseconds: ulong)
```

Pauses the calling thread for at least `milliseconds` milliseconds.

The operating system may sleep longer, but never shorter. In a task
(see `run`), it is `async.sleep`: the task waits and its worker thread
runs other tasks, and a cancel or the task's `timeout` ends the wait
early.

**Parameters**
- `milliseconds` — how long to sleep; 0 returns right away

### Methods

#### id

```pepper
id(): ThreadId
```

Returns the thread's id, which no other thread in the program has.

**Returns**
- the thread's id

#### name

```pepper
name(): String
```

Returns the name the thread was given.

**Returns**
- the name passed to `spawn`, `main` for the main thread, or an empty String for an unnamed thread

#### is_finished

```pepper
is_finished(): bool
```

Reports whether the thread's body has returned.

A thread that is not finished may finish at any moment, so a `false`
result can be out of date by the time it is used. Always false for a
`Thread` that was not started by `spawn`.

**Returns**
- true once the body has returned

#### is_joinable

```pepper
is_joinable(): bool
```

Reports whether `join()` can be called: the thread was started by
`spawn` and has not been joined yet.

**Returns**
- true if the thread can be joined

#### join

```pepper
join()
```

Waits for the thread's body to return.

Returns right away if it already has. A thread can be joined once; a
`Thread` from `current()` for a thread not started by `spawn` cannot be
joined at all. Everything the thread did before it finished is visible
to the caller after `join()` returns.

**Panics**
- if the thread cannot be joined (see `is_joinable()`), or if a thread tries to join itself
