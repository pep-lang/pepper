## Mutual exclusion: `Mutex<T>` owns a value that one thread at a time can
## use, `MutexGuard<T>` is the lock a `with` block holds, and `Condition<T>`
## lets a thread holding a Mutex sleep until another thread changes its value.

# A Mutex is `[Shared]`: its fields are const, and the value lives in a raw
# heap slot (`const Value: __ptr<T>`). A `[Shared]` struct's pointer field
# must point at a thread-safe type, so `check_shared_types` accepts only a
# thread-safe `T` (`Mutex<String>` is a compile error), exactly as for
# `Atomic<T>`. A later phase lifts that by keeping the compiler from letting
# references into the value escape the `with` block.
#
# `Owner` holds the operating-system id of the thread holding the lock (0
# when unlocked), so a second `lock()` on that thread panics instead of
# deadlocking, and `Condition.wait` can check that its caller holds the lock.
# Only the holder writes it while it holds the lock, so a thread reading its
# own id there knows it holds the lock.

import "thread";
import "sys_posix";
import "sys_windows";

## A value that one thread at a time can use, like Rust's `Mutex<T>` or a C++
## `std::mutex` paired with the data it protects.
##
## The Mutex owns its value, and the way to reach it is a `with` block:
## `with (var value = mutex.lock()) { ... }` waits until no other thread holds
## the lock, binds the value, and unlocks when the block ends by any path
## (falling off the end, `return`, `break`, `continue`). Everything a thread
## did while holding the lock is visible to the next thread that takes it.
##
## `T` must be thread-safe (a number, a `[Shared]` struct, a `shared` function
## type); `Mutex<String>` is a compile error. Use a Mutex to keep several
## updates together: a `[Shared]` struct whose `Atomic` fields must change as
## a unit, or state behind a raw pointer. For a single number, `Atomic<T>` is
## simpler and faster.
##
## A Mutex is `[Shared]`: keep it in a module-scope variable or pass it to
## threads. It is not re-entrant: locking it again on the thread that holds
## it panics instead of deadlocking. A panic while it is held ends the
## program, so a Mutex is never left "poisoned".
##
## @typeParam T the protected value's type, which must be thread-safe
## @example
##     import async;
##
##     [Shared]
##     struct Account {
##         const Checking: Atomic<long>;
##         const Savings: Atomic<long>;
##         construct(long checking = 0, long savings = 0) {
##             Checking = Atomic<long>(checking);
##             Savings = Atomic<long>(savings);
##         }
##     }
##
##     const account = async.Mutex<Account>(Account(100, 0));
##
##     save(long amount) {
##         with (var a = account.lock()) {
##             # No other thread sees the money in neither account.
##             a.Checking.fetch_sub(amount);
##             a.Savings.fetch_add(amount);
##         }
##     }
[Shared]
export struct Mutex<T> {
    ## The platform lock: a heap block holding a `pthread_mutex_t`, or a
    ## Windows `SRWLOCK`. It never moves, which a pthread mutex requires.
    const Lock: __ptr<void>;

    ## A heap slot holding the value: `sizeof<T>()` bytes, one reference for
    ## a struct `T`. Read and written only while the lock is held.
    const Value: __ptr<T>;

    ## The operating-system id of the thread holding the lock, or 0 when the
    ## Mutex is unlocked.
    const Owner: Atomic<ulong>;

    ## Creates an unlocked Mutex that owns `value`.
    ##
    ## For a struct `T` the Mutex acquires a reference to `value`, and
    ## releases it when the Mutex is destroyed.
    ##
    ## @param value the value to protect
    ## @panics if the operating system cannot create a mutex
    construct(T value) {
        Lock = _async_sys_mutex_create();
        Value = _pep_malloc(sizeof<T>());
        Value[0] = value;
        Owner = Atomic<ulong>(0);
    }

    destruct {
        # No guard is alive (each holds a reference), so the lock is free.
        Value[0] = __default<T>();
        _pep_free(Value);
        _async_sys_mutex_destroy(Lock);
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
    ##         account.Balance.fetch_add(10);
    ##     }
    MutexGuard<T> lock() {
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
    ##         account.Balance.fetch_add(10);
    ##     } else {
    ##         print("busy; try later\n");
    ##     }
    MutexGuard<T> try_lock() {
        return MutexGuard<T>(this, false);
    }

    ## Reports whether the calling thread holds the lock.
    ##
    ## @returns true between a `lock()` (or a successful `try_lock()`) on this thread and the guard's destruction
    bool is_held() {
        return Owner.load() == _async_sys_os_thread();
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
    Condition<T> condition() {
        return Condition<T>(this);
    }

    # Waits for the lock and records the caller as its holder.
    void _lock() {
        var me = _async_sys_os_thread();
        if (Owner.load() == me) {
            panic("Mutex.lock: the calling thread already holds this Mutex");
        }
        _async_sys_mutex_lock(Lock);
        Owner.store(me);
    }

    # Takes the lock if it is free; true if the caller now holds it.
    bool _try_lock() {
        var me = _async_sys_os_thread();
        if (Owner.load() == me || !_async_sys_mutex_try_lock(Lock)) {
            return false;
        }
        Owner.store(me);
        return true;
    }

    void _unlock() {
        Owner.store(0);
        _async_sys_mutex_unlock(Lock);
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
## @typeParam T the protected value's type
## @example
##     with (var totals = stats.lock()) {
##         totals.Requests.fetch_add(1);
##     }   # unlocked here
export struct MutexGuard<T> {
    ## The Mutex this guard locks.
    const Source: Mutex<T>;

    ## Whether the guard holds the lock: false once `exit()` has run, and for
    ## a `try_lock()` that found the lock busy.
    bool Locked;

    ## Locks `source` and creates the guard that holds it; the same as
    ## `source.lock()` (or `source.try_lock()` when `wait` is false).
    ##
    ## @param source the Mutex to lock
    ## @param wait true to wait for the lock; false to take it only if it is free right now
    ## @panics if `wait` is true and the calling thread already holds the lock
    construct(Mutex<T> source, bool wait = true) {
        Source = source;
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
    T enter() {
        if (!Locked) {
            return __default<T>();
        }
        return Source.Value[0];
    }

    ## Unlocks the Mutex if the guard holds it. The destructor calls it;
    ## calling it again does nothing.
    void exit() {
        if (Locked) {
            Locked = false;
            Source._unlock();
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
##         const Waiting: Atomic<long>;
##         construct() { Waiting = Atomic<long>(0); }
##     }
##
##     const jobs = async.Mutex<Jobs>(Jobs());
##     const has_work = jobs.condition();
##
##     take_job() {
##         with (var j = jobs.lock()) {
##             while (j.Waiting.load() == 0) {
##                 has_work.wait();
##             }
##             j.Waiting.fetch_sub(1);
##         }
##     }
##
##     add_job() {
##         with (var j = jobs.lock()) {
##             j.Waiting.fetch_add(1);
##             has_work.notify_one();
##         }
##     }
[Shared]
export struct Condition<T> {
    ## The Mutex this condition waits on.
    const Mutex: Mutex<T>;

    ## The platform condition variable: a heap block holding a
    ## `pthread_cond_t`, or a Windows `CONDITION_VARIABLE`.
    const Handle: __ptr<void>;

    ## Creates a condition variable that waits on `mutex`. `mutex.condition()`
    ## does the same.
    ##
    ## @param mutex the Mutex that waiters hold
    ## @panics if the operating system cannot create a condition variable
    construct(Mutex<T> mutex) {
        Mutex = mutex;
        Handle = _async_sys_condition_create();
    }

    destruct {
        _async_sys_condition_destroy(Handle);
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
    ##         while (q.Waiting.load() == 0) {
    ##             not_empty.wait();
    ##         }
    ##     }
    void wait() {
        var me = _async_sys_os_thread();
        if (Mutex.Owner.load() != me) {
            panic("Condition.wait: the calling thread does not hold the Mutex");
        }
        Mutex.Owner.store(0);
        _async_sys_condition_wait(Handle, Mutex.Lock);
        Mutex.Owner.store(me);
    }

    ## Like `wait()`, but gives up after about `milliseconds` milliseconds.
    ## The Mutex is locked again before it returns either way.
    ##
    ## @param milliseconds the longest time to sleep
    ## @returns true if the thread was woken (by a notification or spuriously), false if the time ran out
    ## @panics if the calling thread does not hold the Mutex
    bool wait_for(ulong milliseconds) {
        var me = _async_sys_os_thread();
        if (Mutex.Owner.load() != me) {
            panic("Condition.wait_for: the calling thread does not hold the Mutex");
        }
        Mutex.Owner.store(0);
        var woken = _async_sys_condition_wait_for(Handle, Mutex.Lock, milliseconds);
        Mutex.Owner.store(me);
        return woken;
    }

    ## Wakes one thread waiting on this condition, if any. The caller does
    ## not need to hold the Mutex, but usually does, having just changed the
    ## value.
    void notify_one() {
        _async_sys_condition_notify_one(Handle);
    }

    ## Wakes every thread waiting on this condition. Each locks the Mutex in
    ## turn before its `wait()` returns.
    void notify_all() {
        _async_sys_condition_notify_all(Handle);
    }
}
