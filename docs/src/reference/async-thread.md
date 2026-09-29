<!-- Generated from runtime/async/thread.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

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
type ThreadBody = () => void
```

The type of a thread's body: a function that takes no arguments and
returns nothing. `Thread.spawn` runs one on a new thread.

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

    const total = Atomic<long>(0);

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

### Fields

#### Id

```pepper
const Id: ThreadId
```

The thread's id.

#### NameData

```pepper
const NameData: __ptr<char>
```

The name's UTF-8 bytes, NUL-terminated, or null for an unnamed thread.

#### NameSize

```pepper
const NameSize: ulong
```

The name's size in bytes.

#### NameLength

```pepper
const NameLength: ulong
```

The name's length in code points.

#### Body

```pepper
const Body: ThreadBody
```

The function the thread runs (a no-op for a thread that was not
started by `spawn`, such as the main thread).

#### Handle

```pepper
const Handle: Atomic<__ptr<void>>
```

The operating-system handle while the thread can still be joined or
detached (a `pthread_t` or a Windows `HANDLE`), else null.

#### Finished

```pepper
const Finished: Atomic<int>
```

1 once the body has returned, else 0.

### Constructor

#### Thread()

```pepper
construct(String name, ThreadBody body)
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
static Thread spawn(ThreadBody body, String name = "")
```

Starts a new thread that runs `body`.

The new thread starts right away and runs until `body` returns. Its
`Thread.current()` is the `Thread` returned here.

**Parameters**
- `body` — the function to run on the new thread
- `name` — a name for the thread, returned by `name()`; empty by default

**Returns**
- the new thread, to `join()` or query

**Panics**
- if the operating system cannot create another thread

**Example**
```pepper
    var worker = Thread.spawn(do_work, "worker");
    worker.join();
```

#### current

```pepper
static Thread current()
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
static void sleep(ulong milliseconds)
```

Pauses the calling thread for at least `milliseconds` milliseconds.

The operating system may sleep longer, but never shorter.

**Parameters**
- `milliseconds` — how long to sleep; 0 returns right away

### Methods

#### id

```pepper
ThreadId id()
```

Returns the thread's id, which no other thread in the program has.

**Returns**
- the thread's id

#### name

```pepper
String name()
```

Returns the name the thread was given.

**Returns**
- the name passed to `spawn`, `main` for the main thread, or an empty String for an unnamed thread

#### is_finished

```pepper
bool is_finished()
```

Reports whether the thread's body has returned.

A thread that is not finished may finish at any moment, so a `false`
result can be out of date by the time it is used. Always false for a
`Thread` that was not started by `spawn`.

**Returns**
- true once the body has returned

#### is_joinable

```pepper
bool is_joinable()
```

Reports whether `join()` can be called: the thread was started by
`spawn` and has not been joined yet.

**Returns**
- true if the thread can be joined

#### join

```pepper
void join()
```

Waits for the thread's body to return.

Returns right away if it already has. A thread can be joined once; a
`Thread` from `current()` for a thread not started by `spawn` cannot be
joined at all. Everything the thread did before it finished is visible
to the caller after `join()` returns.

**Panics**
- if the thread cannot be joined (see `is_joinable()`), or if a thread tries to join itself
