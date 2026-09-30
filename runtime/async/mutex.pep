## Mutual exclusion: `Mutex<T>` owns a value that one thread at a time can
## use, `MutexGuard<T>` is the lock a `with` block holds, and `Condition<T>`
## lets a thread holding a Mutex sleep until another thread changes its value.

# A Mutex is `[Shared]`: its fields are const, and the value lives in a raw
# heap slot (`const _value: __ptr<void>`, viewed as a `T` slot), so any `T`
# passes `check_shared_types`. A `T` that is not thread-safe counts its
# references plainly, so no two threads may touch its counts at once:
#
# - the value is reached only in a `with` block over `lock()`: `enter()`
#   takes its reference under the lock, and the binding is released before
#   the guard unlocks (see `lower_with_blocks`);
# - `MutexGuard` is `[Isolated]`, so `passes/check_confinement.rs` keeps the
#   block from letting a reference into the value outlive the lock, or a
#   reference from outside into it;
# - the constructor and `replace` take `[Move]` values: the caller hands
#   its one reference over (it keeps none), and `replace` moves it into the
#   slot under the lock, so no count step on the value happens outside it.
#
# `_owner` holds the operating-system id of the thread holding the lock (0
# when unlocked), so a second `lock()` on that thread panics instead of
# deadlocking, and `Condition.wait` can check that its caller holds the lock.
# Only the holder writes it while it holds the lock, so a thread reading its
# own id there knows it holds the lock.

import "sys_posix";
import "sys_windows";
import "thread";

## A value that one thread at a time can use, like Rust's `Mutex<T>` or a C++
## `std::mutex` paired with the data it protects.
##
## The Mutex owns its value, and the way to reach it is a `with` block:
## `with (var value = mutex.lock()) { ... }` waits until no other thread holds
## the lock, binds the value, and unlocks when the block ends by any path
## (falling off the end, `return`, `break`, `continue`). Everything a thread
## did while holding the lock is visible to the next thread that takes it.
##
## `T` is a struct type, such as `Array<String>` or a struct of your own. Inside
## the `with` block the compiler keeps the locked value and the rest of the
## program apart: a value that is not thread-safe (a `String`, an `Array`)
## cannot move from one to the other, and no part of the locked value can be
## returned from the block or stored outside it. Pass `copy(x)` to move a
## value either way; new values (a constructor call, a string literal, a call
## the compiler infers returns a fresh value) and thread-safe values such as
## numbers pass freely. `Mutex<int>` is a compile error: use `Atomic<int>`.
##
## A Mutex is `[Shared]`: keep it in a module-scope variable or pass it to
## threads. It is not re-entrant: locking it again on the thread that holds
## it panics instead of deadlocking. A panic while it is held ends the
## program, so a Mutex is never left "poisoned".
##
## @typeParam T the protected value's type, a struct type
## @example
##     import async;
##
##     [Shared]
##     struct Account {
##         const checking: Atomic<long>;
##         const savings: Atomic<long>;
##         construct(long checking = 0, long savings = 0) {
##             this.checking = Atomic<long>(checking);
##             this.savings = Atomic<long>(savings);
##         }
##     }
##
##     const account = async.Mutex<Account>(Account(100, 0));
##
##     save(long amount) {
##         with (var a = account.lock()) {
##             # No other thread sees the money in neither account.
##             a.checking.fetch_sub(amount);
##             a.savings.fetch_add(amount);
##         }
##     }
[Shared]
export struct Mutex<T> {
    # The platform lock: a heap block holding a `pthread_mutex_t`, or a
    # Windows `SRWLOCK`. It never moves, which a pthread mutex requires.
    const _lock: __ptr<void>;

    # A heap slot holding the value: `sizeof<T>()` bytes, one reference for
    # a struct `T`. Read and written only while the lock is held.
    const _value: __ptr<void>;

    # The operating-system id of the thread holding the lock, or 0 when the
    # Mutex is unlocked.
    const _owner: Atomic<ulong>;

    ## Creates an unlocked Mutex that owns `value`.
    ##
    ## `value` must be a new value, such as a constructor call, `copy(x)` or
    ## `move(x)`: nothing outside the Mutex may reference it. The caller hands
    ## its reference over, so nothing is copied.
    ##
    ## @param value the value to protect; a new value, which the compiler checks
    ## @panics if the operating system cannot create a mutex
    ## @example
    ##     const names = async.Mutex<Array<String>>(Array<String>());
    construct([Move] value: T) {
        _lock = _async_sys_mutex_create();
        _value = _pep_malloc(sizeof<T>());
        _owner = Atomic<ulong>(0);
        this._slot()[0] = move(value);
    }

    destruct {
        # No guard is alive (each holds a reference), so the lock is free.
        this._slot()[0] = __default<T>();
        _pep_free(_value);
        _async_sys_mutex_destroy(_lock);
    }

    ## Waits until the calling thread holds the lock, and returns the guard
    ## that a `with` block enters to reach the value.
    ##
    ## Use it as the scope of a `with` header: `with (var v = mutex.lock())`.
    ## The lock is released when the guard is destroyed, which for a guard
    ## created in the header is the end of the block. A guard kept anywhere
    ## else holds the lock until its last reference is released.
    ##
    ## @returns the guard; its `enter()` returns the value, and destroying it unlocks
    ## @panics if the calling thread already holds the lock
    ## @example
    ##     with (var account = accounts.lock()) {
    ##         account.balance.fetch_add(10);
    ##     }
    lock(): MutexGuard<T> {
        return MutexGuard<T>(this);
    }

    ## Takes the lock only if no thread holds it right now, without waiting.
    ##
    ## In `with (var v = mutex.try_lock()) { ... } else { ... }`, the body runs
    ## when the lock was taken and the `else` block runs when it was not. The
    ## calling thread already holding the lock counts as busy.
    ##
    ## @returns the guard; its `enter()` returns the value, or null when the lock was busy
    ## @example
    ##     with (var account = accounts.try_lock()) {
    ##         account.balance.fetch_add(10);
    ##     } else {
    ##         print("busy; try later\n");
    ##     }
    try_lock(): MutexGuard<T> {
        return MutexGuard<T>(this, false);
    }

    ## Replaces the whole value and returns the one the Mutex held, which the
    ## caller then owns outright: nothing else references it any more.
    ##
    ## Waits for the lock like `lock()`. `value` must be a new value, as for
    ## the constructor, and is handed over without a copy.
    ##
    ## @param value the new value; a new value, which the compiler checks
    ## @returns the value the Mutex held
    ## @panics if the calling thread already holds the lock
    ## @example
    ##     var done = pending.replace(Array<Job>());   # take every job at once
    replace([Move] value: T): T {
        this._lock();
        __ptr<T> slot = this._slot();
        # Both references change hands under the lock, with no count step:
        # the slot's goes to the caller, the caller's to the slot.
        T old = move(slot[0]);
        slot[0] = move(value);
        this._unlock();
        return move(old);
    }

    ## Reports whether the calling thread holds the lock.
    ##
    ## @returns true between a `lock()` (or a successful `try_lock()`) on this thread and the guard's destruction
    is_held(): bool {
        return _owner.load() == _async_sys_os_thread();
    }

    ## Returns a new condition variable that waits on this Mutex.
    ##
    ## Create it once and share it, as the Mutex is shared: every thread that
    ## waits or notifies must use the same Condition.
    ##
    ## @returns a new Condition bound to this Mutex
    ## @example
    ##     const queue = async.Mutex<Jobs>(Jobs());
    ##     const not_empty = queue.condition();
    condition(): Condition<T> {
        return Condition<T>(this);
    }

    # The value's slot, as a `T` slot.
    _slot(): __ptr<T> {
        __ptr<void> raw = _value;
        return raw;
    }

    # Waits for the lock and records the caller as its holder.
    _lock() {
        var me = _async_sys_os_thread();
        if (_owner.load() == me) {
            panic("Mutex.lock: the calling thread already holds this Mutex");
        }
        _async_sys_mutex_lock(_lock);
        _owner.store(me);
    }

    # Takes the lock if it is free; true if the caller now holds it.
    _try_lock(): bool {
        var me = _async_sys_os_thread();
        if (_owner.load() == me || !_async_sys_mutex_try_lock(_lock)) {
            return false;
        }
        _owner.store(me);
        return true;
    }

    _unlock() {
        _owner.store(0);
        _async_sys_mutex_unlock(_lock);
    }
}

## The lock on a `Mutex<T>` that a `with` block holds: `enter()` returns the
## Mutex's value, and destroying the guard unlocks.
##
## Get one from `Mutex.lock()` or `Mutex.try_lock()` in a `with` header. The
## block releases the guard on every path out, so the lock cannot be left
## held by mistake. A guard belongs to the thread that locked it; do not pass
## it to another thread.
##
## A guard is `[Isolated]`: it can only be the scope of a `with` header, so
## the lock cannot be kept past the block, and the compiler checks the block
## with the confinement rule (see `Mutex`).
##
## @typeParam T the protected value's type
## @example
##     with (var totals = stats.lock()) {
##         totals.requests.fetch_add(1);
##     }   # unlocked here
[Isolated]
export struct MutexGuard<T> {
    # The Mutex this guard locks.
    const _source: Mutex<T>;

    ## Whether the guard holds the lock: false once `exit()` has run, and for
    ## a `try_lock()` that found the lock busy.
    bool Locked;

    ## Locks `source` and creates the guard that holds it; the same as
    ## `source.lock()` (or `source.try_lock()` when `wait` is false).
    ##
    ## @param source the Mutex to lock
    ## @param wait true to wait for the lock; false to take it only if it is free right now
    ## @panics if `wait` is true and the calling thread already holds the lock
    construct(source: Mutex<T>, wait: bool = true) {
        _source = source;
        if (wait) {
            source._lock();
            Locked = true;
        } else {
            Locked = source._try_lock();
        }
    }

    destruct {
        this.exit();
    }

    ## Returns the Mutex's value, for the `with` header to bind.
    ##
    ## For a struct `T` the caller gets its own reference.
    ##
    ## @returns the protected value, or the default of `T` (null for a struct) when the guard does not hold the lock
    enter(): T {
        if (!Locked) {
            return __default<T>();
        }
        return _source._slot()[0];
    }

    ## Unlocks the Mutex if the guard holds it. The destructor calls it;
    ## calling it again does nothing.
    exit() {
        if (Locked) {
            Locked = false;
            # With `PEP_CHECK_SYNC` set, check that nothing outside the
            # locked value refers into it (`_pep_check_sync`).
            __census<T>(_source._slot());
            _source._unlock();
        }
    }
}

extend MutexGuard<T> with Scoped<T> {}

## Lets threads that hold a Mutex sleep until another thread changes the
## Mutex's value, like C++ `std::condition_variable`. Get one from
## `Mutex.condition()`.
##
## `wait()` must run while the calling thread holds the Mutex, normally inside
## `with (var v = mutex.lock())`. It unlocks, sleeps until notified, and locks
## again before returning. A waiter can also wake without a notification (a
## spurious wakeup), so always wait in a loop that re-checks the value.
##
## A thread that changes the value calls `notify_one()` or `notify_all()`,
## usually while it still holds the lock.
##
## A Condition is `[Shared]`, like its Mutex.
##
## @typeParam T the Mutex's value type
## @example
##     import async;
##
##     [Shared]
##     struct Jobs {
##         const waiting: Atomic<long>;
##         construct() { waiting = Atomic<long>(0); }
##     }
##
##     const jobs = async.Mutex<Jobs>(Jobs());
##     const has_work = jobs.condition();
##
##     take_job() {
##         with (var j = jobs.lock()) {
##             while (j.waiting.load() == 0) {
##                 has_work.wait();
##             }
##             j.waiting.fetch_sub(1);
##         }
##     }
##
##     add_job() {
##         with (var j = jobs.lock()) {
##             j.waiting.fetch_add(1);
##             has_work.notify_one();
##         }
##     }
[Shared]
export struct Condition<T> {
    # The Mutex this condition waits on.
    const _mutex: Mutex<T>;

    # The platform condition variable: a heap block holding a
    # `pthread_cond_t`, or a Windows `CONDITION_VARIABLE`.
    const _handle: __ptr<void>;

    ## Creates a condition variable that waits on `mutex`. `mutex.condition()`
    ## does the same.
    ##
    ## @param mutex the Mutex that waiters hold
    ## @panics if the operating system cannot create a condition variable
    construct(mutex: Mutex<T>) {
        _mutex = mutex;
        _handle = _async_sys_condition_create();
    }

    destruct {
        _async_sys_condition_destroy(_handle);
    }

    ## Unlocks the Mutex, sleeps until another thread calls `notify_one()` or
    ## `notify_all()`, and locks the Mutex again before returning.
    ##
    ## The thread may also wake without being notified, so call it in a loop
    ## that re-checks what it waits for.
    ##
    ## @panics if the calling thread does not hold the Mutex
    ## @example
    ##     with (var q = queue.lock()) {
    ##         while (q.waiting.load() == 0) {
    ##             not_empty.wait();
    ##         }
    ##     }
    wait() {
        var me = _async_sys_os_thread();
        if (_mutex._owner.load() != me) {
            panic("Condition.wait: the calling thread does not hold the Mutex");
        }
        _mutex._owner.store(0);
        _async_sys_condition_wait(_handle, _mutex._lock);
        _mutex._owner.store(me);
    }

    ## Like `wait()`, but gives up after about `milliseconds` milliseconds.
    ## The Mutex is locked again before it returns either way.
    ##
    ## @param milliseconds the longest time to sleep
    ## @returns true if the thread was woken (by a notification or spuriously), false if the time ran out
    ## @panics if the calling thread does not hold the Mutex
    wait_for(milliseconds: ulong): bool {
        var me = _async_sys_os_thread();
        if (_mutex._owner.load() != me) {
            panic("Condition.wait_for: the calling thread does not hold the Mutex");
        }
        _mutex._owner.store(0);
        var woken = _async_sys_condition_wait_for(_handle, _mutex._lock, milliseconds);
        _mutex._owner.store(me);
        return woken;
    }

    ## Wakes one thread waiting on this condition, if any. The caller does
    ## not need to hold the Mutex, but usually does, having just changed the
    ## value.
    notify_one() {
        _async_sys_condition_notify_one(_handle);
    }

    ## Wakes every thread waiting on this condition. Each locks the Mutex in
    ## turn before its `wait()` returns.
    notify_all() {
        _async_sys_condition_notify_all(_handle);
    }
}
