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

Each thread that calls `set` stores its own value. When a thread exits, its
value is released.

For a thread-safe `T` (a number, a `[Shared]` struct), `get` returns the
calling thread's value (the default of `T`, zero or null, until that thread
sets one). For any other `T`, such as a `String`, the value is reached
through a `with` block, `with (var value = local.enter()) { ... }`, and
`get` is a compile error; `set` then takes a new value (a constructor call,
a string literal, `copy(x)`). Inside the block the value is kept apart
from the rest of the program, as for a `Mutex`.

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
get(): T
```

Returns the calling thread's value.

For a struct `T` the caller gets its own reference. Only for a
thread-safe `T`: for any other `T`, use `with (var value =
local.enter())`.

**Returns**
- the value this thread last stored, or the default of `T` (zero or null) if it has not stored one

#### set

```pepper
set([Move] value: T)
```

Stores `value` as the calling thread's value, replacing (and, for a
struct `T`, releasing) the one it held. Other threads' values are not
affected.

For a `T` that is not thread-safe, `value` must be a new value (a
constructor call, a string literal, `copy(x)`), which the compiler
checks.

**Parameters**
- `value` — the new value for this thread

#### enter

```pepper
enter(): ThreadLocalGuard<T>
```

Returns the guard that a `with` block enters to reach the calling
thread's value: `with (var value = local.enter()) { ... }`. The body
runs with the value bound; the `else` block runs when this thread has
no value (for a struct `T`).

**Returns**
- the guard; its `enter()` returns this thread's value

**Example**
```pepper
const names = async.ThreadLocal<Array<String>>();

remember(String name) {
    if (!names.is_set()) {
        names.set(Array<String>());
    }
    with (var list = names.enter()) {
        list.append(name.copy());
    }
}
```

#### is_set

```pepper
is_set(): bool
```

Reports whether the calling thread has stored a value since it started
or last called `clear()`.

**Returns**
- true if this thread has a value

#### clear

```pepper
clear()
```

Removes the calling thread's value, releasing it for a struct `T`.
`get()` returns the default of `T` afterwards.

## ThreadLocalGuard

```pepper
[Isolated] struct ThreadLocalGuard<T>
```

The access to a thread's `ThreadLocal<T>` value that a `with` block holds:
`enter()` returns the value. Get one from `ThreadLocal.enter()`.

A guard is `[Isolated]`: it can only be the scope of a `with` header, and
the compiler checks the block with the confinement rule (see `Mutex`).

**Type parameters**
- `T` — the type of the per-thread value

### Constructor

#### ThreadLocalGuard()

```pepper
construct(local: ThreadLocal<T>)
```

Creates the guard for the calling thread's value of `local`; the same
as `local.enter()`.

**Parameters**
- `local` — the thread-local variable

### Methods

#### enter

```pepper
enter(): T
```

Returns the calling thread's value, for the `with` header to bind.

**Returns**
- this thread's value, or the default of `T` (null for a struct) when it has none

#### exit

```pepper
exit()
```

Does nothing: the value stays with the thread.
