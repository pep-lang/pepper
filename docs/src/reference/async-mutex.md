<!-- Generated from runtime/async/mutex.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# async/mutex.pep

Mutual exclusion: `Mutex<T>` owns a value that one thread at a time can
use, `MutexGuard<T>` is the lock a `with` block holds, and `Condition<T>`
lets a thread holding a Mutex sleep until another thread changes its value.

Source: `runtime/async/mutex.pep`

## Mutex

```pepper
[Shared] struct Mutex<T>
```

A value that one thread at a time can use, like Rust's `Mutex<T>` or a C++
`std::mutex` paired with the data it protects.

The Mutex owns its value, and the way to reach it is a `with` block:
`with (var value = mutex.lock()) { ... }` waits until no other thread holds
the lock, binds the value, and unlocks when the block ends by any path
(falling off the end, `return`, `break`, `continue`). Everything a thread
did while holding the lock is visible to the next thread that takes it.

`T` must be thread-safe (a number, a `[Shared]` struct, a `shared` function
type); `Mutex<String>` is a compile error. Use a Mutex to keep several
updates together: a `[Shared]` struct whose `Atomic` fields must change as
a unit, or state behind a raw pointer. For a single number, `Atomic<T>` is
simpler and faster.

A Mutex is `[Shared]`: keep it in a module-scope variable or pass it to
threads. It is not re-entrant: locking it again on the thread that holds
it panics instead of deadlocking. A panic while it is held ends the
program, so a Mutex is never left "poisoned".

**Type parameters**
- `T` — the protected value's type, which must be thread-safe

**Example**
```pepper
    import async;

    [Shared]
    struct Account {
        const Checking: Atomic<long>;
        const Savings: Atomic<long>;
        construct(long checking = 0, long savings = 0) {
            Checking = Atomic<long>(checking);
            Savings = Atomic<long>(savings);
        }
    }

    const account = async.Mutex<Account>(Account(100, 0));

    save(long amount) {
        with (var a = account.lock()) {
            # No other thread sees the money in neither account.
            a.Checking.fetch_sub(amount);
            a.Savings.fetch_add(amount);
        }
    }
```

### Fields

#### Lock

```pepper
const Lock: __ptr<void>
```

The platform lock: a heap block holding a `pthread_mutex_t`, or a
Windows `SRWLOCK`. It never moves, which a pthread mutex requires.

#### Value

```pepper
const Value: __ptr<T>
```

A heap slot holding the value: `sizeof<T>()` bytes, one reference for
a struct `T`. Read and written only while the lock is held.

#### Owner

```pepper
const Owner: Atomic<ulong>
```

The operating-system id of the thread holding the lock, or 0 when the
Mutex is unlocked.

### Constructor

#### Mutex()

```pepper
construct(T value)
```

Creates an unlocked Mutex that owns `value`.

For a struct `T` the Mutex acquires a reference to `value`, and
releases it when the Mutex is destroyed.

**Parameters**
- `value` — the value to protect

**Panics**
- if the operating system cannot create a mutex

### Methods

#### lock

```pepper
MutexGuard<T> lock()
```

Waits until the calling thread holds the lock, and returns the guard
that a `with` block enters to reach the value.

Use it as the scope of a `with` header: `with (var v = mutex.lock())`.
The lock is released when the guard is destroyed, which for a guard
created in the header is the end of the block. A guard kept anywhere
else holds the lock until its last reference is released.

**Returns**
- the guard; its `enter()` returns the value, and destroying it unlocks

**Panics**
- if the calling thread already holds the lock

**Example**
```pepper
    with (var account = accounts.lock()) {
        account.Balance.fetch_add(10);
    }
```

#### try_lock

```pepper
MutexGuard<T> try_lock()
```

Takes the lock only if no thread holds it right now, without waiting.

In `with (var v = mutex.try_lock()) { ... } else { ... }`, the body runs
when the lock was taken and the `else` block runs when it was not. The
calling thread already holding the lock counts as busy.

**Returns**
- the guard; its `enter()` returns the value, or null when the lock was busy

**Example**
```pepper
    with (var account = accounts.try_lock()) {
        account.Balance.fetch_add(10);
    } else {
        print("busy; try later\n");
    }
```

#### is_held

```pepper
bool is_held()
```

Reports whether the calling thread holds the lock.

**Returns**
- true between a `lock()` (or a successful `try_lock()`) on this thread and the guard's destruction

#### condition

```pepper
Condition<T> condition()
```

Returns a new condition variable that waits on this Mutex.

Create it once and share it, as the Mutex is shared: every thread that
waits or notifies must use the same Condition.

**Returns**
- a new Condition bound to this Mutex

**Example**
```pepper
    const queue = async.Mutex<Jobs>(Jobs());
    const not_empty = queue.condition();
```

## MutexGuard

```pepper
struct MutexGuard<T>
```

The lock on a `Mutex<T>` that a `with` block holds: `enter()` returns the
Mutex's value, and destroying the guard unlocks.

Get one from `Mutex.lock()` or `Mutex.try_lock()` in a `with` header. The
block releases the guard on every path out, so the lock cannot be left
held by mistake. A guard belongs to the thread that locked it; do not pass
it to another thread.

**Type parameters**
- `T` — the protected value's type

**Example**
```pepper
    with (var totals = stats.lock()) {
        totals.Requests.fetch_add(1);
    }   # unlocked here
```

### Fields

#### Source

```pepper
const Source: Mutex<T>
```

The Mutex this guard locks.

#### Locked

```pepper
bool Locked
```

Whether the guard holds the lock: false once `exit()` has run, and for
a `try_lock()` that found the lock busy.

### Constructor

#### MutexGuard()

```pepper
construct(Mutex<T> source, bool wait = true)
```

Locks `source` and creates the guard that holds it; the same as
`source.lock()` (or `source.try_lock()` when `wait` is false).

**Parameters**
- `source` — the Mutex to lock
- `wait` — true to wait for the lock; false to take it only if it is free right now

**Panics**
- if `wait` is true and the calling thread already holds the lock

### Methods

#### enter

```pepper
T enter()
```

Returns the Mutex's value, for the `with` header to bind.

For a struct `T` the caller gets its own reference.

**Returns**
- the protected value, or the default of `T` (null for a struct) when the guard does not hold the lock

#### exit

```pepper
void exit()
```

Unlocks the Mutex if the guard holds it. The destructor calls it;
calling it again does nothing.

## Condition

```pepper
[Shared] struct Condition<T>
```

Lets threads that hold a Mutex sleep until another thread changes the
Mutex's value, like C++ `std::condition_variable`. Get one from
`Mutex.condition()`.

`wait()` must run while the calling thread holds the Mutex, normally inside
`with (var v = mutex.lock())`. It unlocks, sleeps until notified, and locks
again before returning. A waiter can also wake without a notification (a
spurious wakeup), so always wait in a loop that re-checks the value.

A thread that changes the value calls `notify_one()` or `notify_all()`,
usually while it still holds the lock.

A Condition is `[Shared]`, like its Mutex.

**Type parameters**
- `T` — the Mutex's value type

**Example**
```pepper
    import async;

    [Shared]
    struct Jobs {
        const Waiting: Atomic<long>;
        construct() { Waiting = Atomic<long>(0); }
    }

    const jobs = async.Mutex<Jobs>(Jobs());
    const has_work = jobs.condition();

    take_job() {
        with (var j = jobs.lock()) {
            while (j.Waiting.load() == 0) {
                has_work.wait();
            }
            j.Waiting.fetch_sub(1);
        }
    }

    add_job() {
        with (var j = jobs.lock()) {
            j.Waiting.fetch_add(1);
            has_work.notify_one();
        }
    }
```

### Fields

#### Mutex

```pepper
const Mutex: Mutex<T>
```

The Mutex this condition waits on.

#### Handle

```pepper
const Handle: __ptr<void>
```

The platform condition variable: a heap block holding a
`pthread_cond_t`, or a Windows `CONDITION_VARIABLE`.

### Constructor

#### Condition()

```pepper
construct(Mutex<T> mutex)
```

Creates a condition variable that waits on `mutex`. `mutex.condition()`
does the same.

**Parameters**
- `mutex` — the Mutex that waiters hold

**Panics**
- if the operating system cannot create a condition variable

### Methods

#### wait

```pepper
void wait()
```

Unlocks the Mutex, sleeps until another thread calls `notify_one()` or
`notify_all()`, and locks the Mutex again before returning.

The thread may also wake without being notified, so call it in a loop
that re-checks what it waits for.

**Panics**
- if the calling thread does not hold the Mutex

**Example**
```pepper
    with (var q = queue.lock()) {
        while (q.Waiting.load() == 0) {
            not_empty.wait();
        }
    }
```

#### wait_for

```pepper
bool wait_for(ulong milliseconds)
```

Like `wait()`, but gives up after about `milliseconds` milliseconds.
The Mutex is locked again before it returns either way.

**Parameters**
- `milliseconds` — the longest time to sleep

**Returns**
- true if the thread was woken (by a notification or spuriously), false if the time ran out

**Panics**
- if the calling thread does not hold the Mutex

#### notify_one

```pepper
void notify_one()
```

Wakes one thread waiting on this condition, if any. The caller does
not need to hold the Mutex, but usually does, having just changed the
value.

#### notify_all

```pepper
void notify_all()
```

Wakes every thread waiting on this condition. Each locks the Mutex in
turn before its `wait()` returns.
