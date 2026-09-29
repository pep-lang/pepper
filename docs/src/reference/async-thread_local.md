<!-- Generated from runtime/async/thread_local.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# ThreadLocal

Per-thread values: `ThreadLocal<T>` gives every thread its own copy of a
variable.

Source: `runtime/async/thread_local.pep`

## ThreadLocal

```pepper
[Shared] struct ThreadLocal<T>
```

A variable with a separate value on every thread, like C++
`thread_local` or Rust's `thread_local!`.

Each thread that calls `set` stores its own value, and `get` returns the
calling thread's value (the default of `T`, zero or null, until that thread
sets one). When a thread exits, its value is released.

A `ThreadLocal` is `[Shared]`, so one object can be used from every
thread; it is usually a module-scope variable. `T` does not have to be
thread-safe, because each value stays on the thread that stored it.

Destroying a `ThreadLocal` releases the calling thread's value only. Values
that other threads still hold are released on Windows and leak elsewhere,
so destroy one only after the threads that used it have exited.

**Type parameters**
- `T` — the type of the per-thread value

**Example**
```pepper
    import async;

    const calls = async.ThreadLocal<int>();

    count_call() {
        calls.set(calls.get() + 1);
    }

    main(): int {
        count_call();
        count_call();
        assert(calls.get() == 2, "two calls on this thread");
        return 0;
    }
```

### Fields

#### Key

```pepper
const Key: ulong
```

The operating-system thread-local key.

### Constructor

#### ThreadLocal()

```pepper
construct()
```

Creates a thread-local variable. No thread has a value yet.

**Panics**
- if the operating system has no thread-local keys left

### Methods

#### get

```pepper
T get()
```

Returns the calling thread's value.

For a struct `T` the caller gets its own reference.

**Returns**
- the value this thread last stored, or the default of `T` (zero or null) if it has not stored one

#### set

```pepper
void set(T value)
```

Stores `value` as the calling thread's value, replacing (and, for a
struct `T`, releasing) the one it held. Other threads' values are not
affected.

**Parameters**
- `value` — the new value for this thread

#### is_set

```pepper
bool is_set()
```

Reports whether the calling thread has stored a value since it started
or last called `clear()`.

**Returns**
- true if this thread has a value

#### clear

```pepper
void clear()
```

Removes the calling thread's value, releasing it for a struct `T`.
`get()` returns the default of `T` afterwards.
