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
# `_owner` holds the holder's id (`_async_holder_id`: the operating-system
# id of the thread, or a task's own id, since tasks on one worker share its
# thread; 0 when unlocked), so a second `lock()` by the holder panics
# instead of deadlocking, and `Condition.wait` can check that its caller
# holds the lock. Only the holder writes it while it holds the lock, so a
# caller reading its own id there knows it holds the lock.
#
# A task on a worker never blocks its thread on the platform lock: it tries
# it, and when it is busy parks in `_waiters` (see sync_wait.pep), trying
# again after each wake; every unlock wakes one waiting task. The platform
# lock is still what excludes, and a task locks and unlocks it on the one
# thread it runs on. `Condition` does the same with its own `_waiters`.

import "sync_wait";
import "sys_posix";
import "sys_windows";
import "task";
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
## In a task (see `run`), waiting for the lock parks the task, not its worker
## thread, so the other tasks there keep running, including one that holds
## the lock. Each task counts as its own holder, and a task may hold the
## lock across a wait of its own (a `sleep`, a socket call). A cancel does
## not end the wait for the lock.
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

    # The holder's id (see `_async_holder_id`), or 0 when the Mutex is
    # unlocked.
    const _owner: Atomic<ulong>;

    # How many holders sleep in `Condition.wait`, each keeping its `with`
    # binding: references to the value that a `PEP_CHECK_SYNC` census allows.
    const _waiting: Atomic<ulong>;

    # The tasks waiting for the lock.
    const _waiters: _SyncQueue;

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
        _waiting = Atomic<ulong>(0);
        _waiters = _SyncQueue();
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

    ## Reports whether the caller holds the lock: the calling task, in a task,
    ## or else the calling thread.
    ##
    ## @returns true between a `lock()` (or a successful `try_lock()`) by the caller and the guard's destruction
    is_held(): bool {
        return _owner.load() == _async_holder_id();
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
        var me = _async_holder_id();
        if (_owner.load() == me) {
            panic("Mutex.lock: the caller already holds this Mutex");
        }
        this._lock_platform();
        _owner.store(me);
    }

    # Waits for the platform lock: blocking the thread, or in a task,
    # parking the task.
    _lock_platform() {
        if (!_async_in_task()) {
            _async_sys_mutex_lock(_lock);
            return;
        }
        while (!_async_sys_mutex_try_lock(_lock)) {
            var waiter = _async_sync_waiter().value();
            _waiters._push(waiter);
            # An unlock between the first try and the push found no waiter,
            # so try again before parking.
            if (_async_sys_mutex_try_lock(_lock)) {
                # Not needed now; a wake it got is covered by this holder's
                # own unlock.
                if (waiter._state.compare_exchange(_WAITER_WAITING, _WAITER_ABANDONED)) {
                    _waiters._remove(waiter);
                }
                return;
            }
            _async_sync_park(_waiters, waiter, 0, false);
        }
    }

    # Takes the lock if it is free; true if the caller now holds it.
    _try_lock(): bool {
        var me = _async_holder_id();
        if (_owner.load() == me || !_async_sys_mutex_try_lock(_lock)) {
            return false;
        }
        _owner.store(me);
        return true;
    }

    _unlock() {
        _owner.store(0);
        _async_sys_mutex_unlock(_lock);
        # Always look: nothing orders a task's push with this unlock but the
        # queue's own lock (see sync_wait.pep).
        _waiters._wake_one_locked();
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
    bool locked;

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
            locked = true;
        } else {
            locked = source._try_lock();
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
        if (!locked) {
            return __default<T>();
        }
        return _source._slot()[0];
    }

    ## Unlocks the Mutex if the guard holds it. The destructor calls it;
    ## calling it again does nothing.
    exit() {
        if (locked) {
            locked = false;
            # With `PEP_CHECK_SYNC` set, check that nothing outside the
            # locked value refers into it (`_pep_check_sync`).
            __census<T>(_source._slot(), _source._waiting.load());
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
## In a task (see `run`), `wait()` parks the task, not its worker thread. A
## cancel does not end it, since the caller's loop would only wait again;
## `wait_for()` still returns when its time runs out.
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

    # The tasks waiting on this condition.
    const _waiters: _SyncQueue;

    ## Creates a condition variable that waits on `mutex`. `mutex.condition()`
    ## does the same.
    ##
    ## @param mutex the Mutex that waiters hold
    ## @panics if the operating system cannot create a condition variable
    construct(mutex: Mutex<T>) {
        _mutex = mutex;
        _handle = _async_sys_condition_create();
        _waiters = _SyncQueue();
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
        var me = _async_holder_id();
        if (_mutex._owner.load() != me) {
            panic("Condition.wait: the caller does not hold the Mutex");
        }
        _mutex._waiting.fetch_add(1);
        if (_async_in_task()) {
            this._wait_task(me, 0);
        } else {
            _mutex._owner.store(0);
            _async_sys_condition_wait(_handle, _mutex._lock);
            _mutex._owner.store(me);
        }
        _mutex._waiting.fetch_sub(1);
    }

    ## Like `wait()`, but gives up after about `milliseconds` milliseconds.
    ## The Mutex is locked again before it returns either way.
    ##
    ## @param milliseconds the longest time to sleep
    ## @returns true if the thread was woken (by a notification or spuriously), false if the time ran out
    ## @panics if the calling thread does not hold the Mutex
    wait_for(milliseconds: ulong): bool {
        var me = _async_holder_id();
        if (_mutex._owner.load() != me) {
            panic("Condition.wait_for: the caller does not hold the Mutex");
        }
        _mutex._waiting.fetch_add(1);
        var woken = false;
        if (_async_in_task()) {
            woken = this._wait_task(me, _async_sys_monotonic_milliseconds() + milliseconds);
        } else {
            _mutex._owner.store(0);
            woken = _async_sys_condition_wait_for(_handle, _mutex._lock, milliseconds);
            _mutex._owner.store(me);
        }
        _mutex._waiting.fetch_sub(1);
        return woken;
    }

    ## Waits while `predicate` holds for the Mutex's value: calls it with the
    ## value, and while it returns true, waits as `wait()` does and asks
    ## again. Returns once it returns false, with the Mutex still locked.
    ##
    ## Wakeups without a notification are handled here: the predicate is
    ## asked again after every wake.
    ##
    ## `predicate` is written at the call, as a closure: the compiler checks
    ## its body as it checks a `with` block's, with its parameter as the
    ## locked value, so it cannot keep any part of the value or bring in a
    ## value from outside.
    ##
    ## @param predicate called with the locked value; true to keep waiting
    ## @panics if the caller does not hold the Mutex
    ## @example
    ##     with (var queue = jobs.lock()) {
    ##         not_empty.wait_while((queue: Array<Job>): bool => queue.count() == 0);
    ##         var job = queue.remove_at(0);
    ##     }
    wait_while([Locked] predicate: (T) => bool) {
        this._check_holder("Condition.wait_while");
        while (predicate(_mutex._slot()[0])) {
            this.wait();
        }
    }

    ## Like `wait_while()`, but gives up after about `milliseconds`
    ## milliseconds. The Mutex is locked when it returns either way.
    ##
    ## @param milliseconds the longest time to wait
    ## @param predicate called with the locked value; true to keep waiting
    ## @returns true once `predicate` returned false, false if the time ran out first
    ## @panics if the caller does not hold the Mutex
    wait_while_for(milliseconds: ulong, [Locked] predicate: (T) => bool): bool {
        this._check_holder("Condition.wait_while_for");
        var deadline = _async_sys_monotonic_milliseconds() + milliseconds;
        while (predicate(_mutex._slot()[0])) {
            var now = _async_sys_monotonic_milliseconds();
            if (now >= deadline) {
                return false;
            }
            this.wait_for(deadline - now);
        }
        return true;
    }

    # Panics unless the caller holds the Mutex: the predicate reads its value.
    _check_holder(what: String) {
        if (_mutex._owner.load() != _async_holder_id()) {
            panic($"{what}: the caller does not hold the Mutex");
        }
    }

    ## Wakes one thread or task waiting on this condition, if any. The caller does
    ## not need to hold the Mutex, but usually does, having just changed the
    ## value.
    notify_one() {
        _async_sys_condition_notify_one(_handle);
        _waiters._wake_one();
    }

    ## Wakes every thread and task waiting on this condition. Each locks the Mutex in
    ## turn before its `wait()` returns.
    notify_all() {
        _async_sys_condition_notify_all(_handle);
        _waiters._wake_all();
    }

    # `wait` in a task: joins `_waiters` while still holding the Mutex (so a
    # notifier holding it cannot miss the task), unlocks, parks until woken
    # or `deadline` (0 for none) passes, and locks again. True if woken.
    _wait_task(me: ulong, deadline: ulong): bool {
        var waiter = _async_sync_waiter().value();
        _waiters._push(waiter);
        _mutex._unlock();
        var woken = _async_sync_park(_waiters, waiter, deadline, false);
        _mutex._lock_platform();
        _mutex._owner.store(me);
        return woken == _SYNC_WOKEN;
    }
}
