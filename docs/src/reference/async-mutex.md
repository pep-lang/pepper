<!-- Generated from runtime/async/mutex.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Mutex and Condition

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

`T` is a struct type, such as `Array<String>` or a struct of your own. Inside
the `with` block the compiler keeps the locked value and the rest of the
program apart: a value that is not thread-safe (a `String`, an `Array`)
cannot move from one to the other, and no part of the locked value can be
returned from the block or stored outside it. Pass `copy(x)` to move a
value either way; new values (a constructor call, a string literal, a call
the compiler infers returns a fresh value) and thread-safe values such as
numbers pass freely. `Mutex<int>` is a compile error: use `Atomic<int>`.

A Mutex is `[Shared]`: keep it in a module-scope variable or pass it to
threads. It is not re-entrant: locking it again on the thread that holds
it panics instead of deadlocking. A panic while it is held ends the
program, so a Mutex is never left "poisoned".

In a task (see `run`), waiting for the lock parks the task, not its worker
thread, so the other tasks there keep running, including one that holds
the lock. Each task counts as its own holder, and a task may hold the
lock across a wait of its own (a `sleep`, a socket call). A cancel does
not end the wait for the lock.

**Type parameters**
- `T` — the protected value's type, a struct type

**Example**
```pepper
import async;

[Shared]
struct Account {
    const checking: Atomic<long>;
    const savings: Atomic<long>;
    construct(long checking = 0, long savings = 0) {
        this.checking = Atomic<long>(checking);
        this.savings = Atomic<long>(savings);
    }
}

const account = async.Mutex<Account>(Account(100, 0));

save(long amount) {
    with (var a = account.lock()) {
        # No other thread sees the money in neither account.
        a.checking.fetch_sub(amount);
        a.savings.fetch_add(amount);
    }
}
```

### Constructor

#### Mutex()

```pepper
construct([Move] value: T)
```

Creates an unlocked Mutex that owns `value`.

`value` must be a new value, such as a constructor call, `copy(x)` or
`move(x)`: nothing outside the Mutex may reference it. The caller hands
its reference over, so nothing is copied.

**Parameters**
- `value` — the value to protect; a new value, which the compiler checks

**Example**
```pepper
const names = async.Mutex<Array<String>>(Array<String>());
```

### Methods

#### lock

```pepper
lock(): MutexGuard<T>
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
    account.balance.fetch_add(10);
}
```

#### try_lock

```pepper
try_lock(): MutexGuard<T>
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
    account.balance.fetch_add(10);
} else {
    print("busy; try later\n");
}
```

#### replace

```pepper
replace([Move] value: T): T
```

Replaces the whole value and returns the one the Mutex held, which the
caller then owns outright: nothing else references it any more.

Waits for the lock like `lock()`. `value` must be a new value, as for
the constructor, and is handed over without a copy.

**Parameters**
- `value` — the new value; a new value, which the compiler checks

**Returns**
- the value the Mutex held

**Panics**
- if the calling thread already holds the lock

**Example**
```pepper
var done = pending.replace(Array<Job>());   # take every job at once
```

#### is_held

```pepper
is_held(): bool
```

Reports whether the caller holds the lock: the calling task, in a task,
or else the calling thread.

**Returns**
- true between a `lock()` (or a successful `try_lock()`) by the caller and the guard's destruction

#### condition

```pepper
condition(): Condition<T>
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
[Isolated] struct MutexGuard<T>
```

The lock on a `Mutex<T>` that a `with` block holds: `enter()` returns the
Mutex's value, and destroying the guard unlocks.

Get one from `Mutex.lock()` or `Mutex.try_lock()` in a `with` header. The
block releases the guard on every path out, so the lock cannot be left
held by mistake. A guard belongs to the thread that locked it; do not pass
it to another thread.

A guard is `[Isolated]`: it can only be the scope of a `with` header, so
the lock cannot be kept past the block, and the compiler checks the block
with the confinement rule (see `Mutex`).

**Type parameters**
- `T` — the protected value's type

**Example**
```pepper
with (var totals = stats.lock()) {
    totals.requests.fetch_add(1);
}   # unlocked here
```

### Fields

#### locked

```pepper
bool locked
```

Whether the guard holds the lock: false once `exit()` has run, and for
a `try_lock()` that found the lock busy.

### Constructor

#### MutexGuard()

```pepper
construct(source: Mutex<T>, wait: bool = true)
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
enter(): T
```

Returns the Mutex's value, for the `with` header to bind.

For a struct `T` the caller gets its own reference.

**Returns**
- the protected value, or the default of `T` (null for a struct) when the guard does not hold the lock

#### exit

```pepper
exit()
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

In a task (see `run`), `wait()` parks the task, not its worker thread. A
cancel does not end it, since the caller's loop would only wait again;
`wait_for()` still returns when its time runs out.

**Type parameters**
- `T` — the Mutex's value type

**Example**
```pepper
import async;

[Shared]
struct Jobs {
    const waiting: Atomic<long>;
    construct() { waiting = Atomic<long>(0); }
}

const jobs = async.Mutex<Jobs>(Jobs());
const has_work = jobs.condition();

take_job() {
    with (var j = jobs.lock()) {
        while (j.waiting.load() == 0) {
            has_work.wait();
        }
        j.waiting.fetch_sub(1);
    }
}

add_job() {
    with (var j = jobs.lock()) {
        j.waiting.fetch_add(1);
        has_work.notify_one();
    }
}
```

### Constructor

#### Condition()

```pepper
construct(mutex: Mutex<T>)
```

Creates a condition variable that waits on `mutex`. `mutex.condition()`
does the same.

**Parameters**
- `mutex` — the Mutex that waiters hold

### Methods

#### wait

```pepper
wait()
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
    while (q.waiting.load() == 0) {
        not_empty.wait();
    }
}
```

#### wait_for

```pepper
wait_for(milliseconds: ulong): bool
```

Like `wait()`, but gives up after about `milliseconds` milliseconds.
The Mutex is locked again before it returns either way.

**Parameters**
- `milliseconds` — the longest time to sleep

**Returns**
- true if the thread was woken (by a notification or spuriously), false if the time ran out

**Panics**
- if the calling thread does not hold the Mutex

#### wait_while

```pepper
wait_while([Locked] predicate: (T) => bool)
```

Waits while `predicate` holds for the Mutex's value: calls it with the
value, and while it returns true, waits as `wait()` does and asks
again. Returns once it returns false, with the Mutex still locked.

Wakeups without a notification are handled here: the predicate is
asked again after every wake.

`predicate` is written at the call, as a closure: the compiler checks
its body as it checks a `with` block's, with its parameter as the
locked value, so it cannot keep any part of the value or bring in a
value from outside.

**Parameters**
- `predicate` — called with the locked value; true to keep waiting

**Panics**
- if the caller does not hold the Mutex

**Example**
```pepper
with (var queue = jobs.lock()) {
    not_empty.wait_while((queue: Array<Job>): bool => queue.count == 0);
    var job = queue.remove_at(0);
}
```

#### wait_while_for

```pepper
wait_while_for(milliseconds: ulong, [Locked] predicate: (T) => bool): bool
```

Like `wait_while()`, but gives up after about `milliseconds`
milliseconds. The Mutex is locked when it returns either way.

**Parameters**
- `milliseconds` — the longest time to wait
- `predicate` — called with the locked value; true to keep waiting

**Returns**
- true once `predicate` returned false, false if the time ran out first

**Panics**
- if the caller does not hold the Mutex

#### notify_one

```pepper
notify_one()
```

Wakes one thread or task waiting on this condition, if any. The caller does
not need to hold the Mutex, but usually does, having just changed the
value.

#### notify_all

```pepper
notify_all()
```

Wakes every thread and task waiting on this condition. Each locks the Mutex in
turn before its `wait()` returns.
