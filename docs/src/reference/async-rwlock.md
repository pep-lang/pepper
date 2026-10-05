<!-- Generated from runtime/async/rwlock.pep by `pep-doc reference`. Do not edit. -->

# RwLock

Reader/writer locking: `RwLock<T>` owns a thread-safe value that many
threads may read at once or one thread may write, with
`RwLockReadGuard<T>` and `RwLockWriteGuard<T>` as the locks a `with`
block holds.

Source: `runtime/async/rwlock.pep`

## RwLock

```pepper
[Shared] struct RwLock<T: Shared>
```

A thread-safe value that many threads may read at once or one thread may
write, like Rust's `RwLock<T>` or C++ `std::shared_mutex`.

`with (var v = lock.read()) { ... }` waits until no writer holds or is
waiting for the lock, then binds the value; any number of threads may be
reading at once. `with (var v = lock.write()) { ... }` waits until no
other thread holds the lock at all. Both unlock when the block ends by
any path, and everything a writer did is visible to the threads that lock
after it.

`T` must be thread-safe, as for `Atomic<T>`: typically a `[Shared]` struct
whose `Atomic` fields a writer changes together, so readers never see
them half changed. A value that is not thread-safe, such as an
`Array<String>`, is a compile error: readers holding it at once would
race on its reference counts. Use a `Mutex<T>` for such a value.

Writers come first: while a writer waits, new readers wait too, so
readers cannot keep a writer out forever. A thread that already reads
must not ask to read again, since a writer may be waiting between the two.
Asking to write while holding the lock in either mode panics instead of
deadlocking.

In a task (see `run`), waiting for the lock parks the task, not its worker
thread.

**Type parameters**
- `T` — the protected value's type, which must be thread-safe (`T: Shared`)

**Example**
```pepper
import async;

[Shared]
struct Range {
    const low: Atomic<long>;
    const high: Atomic<long>;
    construct() {
        low = Atomic<long>(0);
        high = Atomic<long>(0);
    }
}

const range = async.RwLock<Range>(Range());

widen(by: long) {
    with (var r = range.write()) {
        r.low.fetch_sub(by);
        r.high.fetch_add(by);
    }
}

width(): long {
    with (var r = range.read()) {
        return r.high.load() - r.low.load();   # never half widened
    }
    return 0;
}
```

### Constructor

#### RwLock()

```pepper
construct(value: T)
```

Creates an unlocked RwLock holding `value`.

**Parameters**
- `value` — the value to protect

### Methods

#### read

```pepper
read(): RwLockReadGuard<T>
```

Waits until no writer holds or waits for the lock, takes it for
reading, and returns the guard that a `with` block enters to reach the
value. Other threads may read at the same time.

**Returns**
- the guard; its `enter()` returns the value, and destroying it unlocks

**Panics**
- if the calling thread holds the lock for writing

**Example**
```pepper
with (var config = settings.read()) {
    print($"{config.port.load()}\n");
}
```

#### try_read

```pepper
try_read(): RwLockReadGuard<T>
```

Takes the lock for reading only if that needs no wait: no writer holds
it or waits for it.

In `with (var v = lock.try_read()) { ... } else { ... }`, the body runs
when the lock was taken and the `else` block runs when it was not.

**Returns**
- the guard; its `enter()` returns the value, or null when the lock was not free for reading

#### write

```pepper
write(): RwLockWriteGuard<T>
```

Waits until no other thread holds the lock, takes it for writing, and
returns the guard that a `with` block enters to reach the value.

**Returns**
- the guard; its `enter()` returns the value, and destroying it unlocks

**Panics**
- if the calling thread already holds the lock for writing

**Example**
```pepper
with (var config = settings.write()) {
    config.port.store(8080);
}
```

#### try_write

```pepper
try_write(): RwLockWriteGuard<T>
```

Takes the lock for writing only if no thread holds it right now,
without waiting.

**Returns**
- the guard; its `enter()` returns the value, or null when the lock was busy

#### replace

```pepper
replace(value: T): T
```

Replaces the whole value under the write lock and returns the one the
RwLock held.

**Parameters**
- `value` — the new value

**Returns**
- the value the RwLock held

**Panics**
- if the calling thread already holds the lock for writing

## RwLockReadGuard

```pepper
struct RwLockReadGuard<T: Shared>
```

The read lock on an `RwLock<T>` that a `with` block holds: `enter()`
returns the value, and destroying the guard unlocks. Get one from
`RwLock.read()` or `RwLock.try_read()` in a `with` header.

**Type parameters**
- `T` — the protected value's type

**Example**
```pepper
with (var stats = counters.read()) {
    total = stats.hits.load() + stats.misses.load();
}   # unlocked here
```

### Fields

#### locked

```pepper
bool locked
```

Whether the guard holds the lock: false once `exit()` has run, and for
a `try_read()` that could not take it.

### Constructor

#### RwLockReadGuard()

```pepper
construct(source: RwLock<T>, wait: bool = true)
```

Takes `source` for reading and creates the guard that holds it; the
same as `source.read()` (or `source.try_read()` when `wait` is false).

**Parameters**
- `source` — the RwLock to lock
- `wait` — true to wait for the lock; false to take it only if that needs no wait

**Panics**
- if `wait` is true and the calling thread holds the lock for writing

### Methods

#### enter

```pepper
enter(): T
```

Returns the RwLock's value, for the `with` header to bind.

**Returns**
- the protected value, or the default of `T` (null for a struct) when the guard does not hold the lock

#### exit

```pepper
exit()
```

Unlocks if the guard holds the lock. The destructor calls it; calling
it again does nothing.

## RwLockWriteGuard

```pepper
struct RwLockWriteGuard<T: Shared>
```

The write lock on an `RwLock<T>` that a `with` block holds: `enter()`
returns the value, and destroying the guard unlocks. Get one from
`RwLock.write()` or `RwLock.try_write()` in a `with` header.

**Type parameters**
- `T` — the protected value's type

**Example**
```pepper
with (var stats = counters.write()) {
    stats.hits.store(0);
    stats.misses.store(0);
}   # unlocked here
```

### Fields

#### locked

```pepper
bool locked
```

Whether the guard holds the lock: false once `exit()` has run, and for
a `try_write()` that found the lock busy.

### Constructor

#### RwLockWriteGuard()

```pepper
construct(source: RwLock<T>, wait: bool = true)
```

Takes `source` for writing and creates the guard that holds it; the
same as `source.write()` (or `source.try_write()` when `wait` is
false).

**Parameters**
- `source` — the RwLock to lock
- `wait` — true to wait for the lock; false to take it only if it is free right now

**Panics**
- if `wait` is true and the calling thread already holds the lock for writing

### Methods

#### enter

```pepper
enter(): T
```

Returns the RwLock's value, for the `with` header to bind.

**Returns**
- the protected value, or the default of `T` (null for a struct) when the guard does not hold the lock

#### exit

```pepper
exit()
```

Unlocks if the guard holds the lock. The destructor calls it; calling
it again does nothing.
