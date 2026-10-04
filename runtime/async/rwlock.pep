## Reader/writer locking: `RwLock<T>` owns a thread-safe value that many
## threads may read at once or one thread may write, with
## `RwLockReadGuard<T>` and `RwLockWriteGuard<T>` as the locks a `with`
## block holds.

# `T` must be thread-safe (`T: Shared`), the rule `Atomic<T>` has. Several
# readers holding the value at once each copy a reference to it, and a value
# that is not thread-safe counts its references plainly, so two readers
# would race on its counts; exclusive locking alone is what makes
# `Mutex<T>` sound for such a `T`. Keeping readers from copying any
# reference instead would take a borrowed reference, which the reference
# model rules out.
#
# The lock is a `Mutex` over a struct of counts, with one `Condition` that
# readers sleep on and one that writers sleep on, so in a task every wait
# parks the task (see mutex.pep). Writers come first: once a writer waits,
# new readers wait behind it, so a stream of readers cannot starve writers.
#
# The value lives in a raw slot (`const _value: __ptr<T>`) so that `replace`
# can swap it under the write lock; readers copy their reference out of it
# only while no writer holds the lock.

import "atomic";
import "mutex";
import "task";

## A thread-safe value that many threads may read at once or one thread may
## write, like Rust's `RwLock<T>` or C++ `std::shared_mutex`.
##
## `with (var v = lock.read()) { ... }` waits until no writer holds or is
## waiting for the lock, then binds the value; any number of threads may be
## reading at once. `with (var v = lock.write()) { ... }` waits until no
## other thread holds the lock at all. Both unlock when the block ends by
## any path, and everything a writer did is visible to the threads that lock
## after it.
##
## `T` must be thread-safe, as for `Atomic<T>`: typically a `[Shared]` struct
## whose `Atomic` fields a writer changes together, so readers never see
## them half changed. A value that is not thread-safe, such as an
## `Array<String>`, is a compile error: readers holding it at once would
## race on its reference counts. Use a `Mutex<T>` for such a value.
##
## Writers come first: while a writer waits, new readers wait too, so
## readers cannot keep a writer out forever. A thread that already reads
## must not ask to read again, since a writer may be waiting between the two.
## Asking to write while holding the lock in either mode panics instead of
## deadlocking.
##
## In a task (see `run`), waiting for the lock parks the task, not its worker
## thread.
##
## @typeParam T the protected value's type, which must be thread-safe (`T: Shared`)
## @example
##     import async;
##
##     [Shared]
##     struct Range {
##         const low: Atomic<long>;
##         const high: Atomic<long>;
##         construct() {
##             low = Atomic<long>(0);
##             high = Atomic<long>(0);
##         }
##     }
##
##     const range = async.RwLock<Range>(Range());
##
##     widen(by: long) {
##         with (var r = range.write()) {
##             r.low.fetch_sub(by);
##             r.high.fetch_add(by);
##         }
##     }
##
##     width(): long {
##         with (var r = range.read()) {
##             return r.high.load() - r.low.load();   # never half widened
##         }
##         return 0;
##     }
[Shared]
export struct RwLock<T: Shared> {
    # The value's slot: one reference for a struct `T`, `sizeof<T>()` bytes
    # otherwise. Written only under the write lock.
    const _value: __ptr<T>;

    # Who holds the lock and who waits for it.
    const _state: Mutex<_RwLockState>;

    # Signalled when readers may go on: the last writer left with no writer
    # waiting.
    const _readers_go: Condition<_RwLockState>;

    # Signalled when a writer may go on: the lock became free.
    const _writer_go: Condition<_RwLockState>;

    # The holder's id (see `_async_holder_id`) while a writer holds the
    # lock, else 0.
    const _writer: Atomic<ulong>;

    ## Creates an unlocked RwLock holding `value`.
    ##
    ## @param value the value to protect
    construct(value: T) {
        ulong size = __is_pod<T>() ? sizeof<T>() : 8;
        _value = _pep_malloc(size);
        _value[0] = value;
        _state = Mutex<_RwLockState>(_RwLockState());
        _readers_go = _state.condition();
        _writer_go = _state.condition();
        _writer = Atomic<ulong>(0);
    }

    destruct {
        # No guard is alive (each holds a reference), so nothing reads.
        _value[0] = __default<T>();
        _pep_free(_value);
    }

    ## Waits until no writer holds or waits for the lock, takes it for
    ## reading, and returns the guard that a `with` block enters to reach the
    ## value. Other threads may read at the same time.
    ##
    ## @returns the guard; its `enter()` returns the value, and destroying it unlocks
    ## @panics if the calling thread holds the lock for writing
    ## @example
    ##     with (var config = settings.read()) {
    ##         print($"{config.port.load()}\n");
    ##     }
    read(): RwLockReadGuard<T> {
        return RwLockReadGuard<T>(this);
    }

    ## Takes the lock for reading only if that needs no wait: no writer holds
    ## it or waits for it.
    ##
    ## In `with (var v = lock.try_read()) { ... } else { ... }`, the body runs
    ## when the lock was taken and the `else` block runs when it was not.
    ##
    ## @returns the guard; its `enter()` returns the value, or null when the lock was not free for reading
    try_read(): RwLockReadGuard<T> {
        return RwLockReadGuard<T>(this, false);
    }

    ## Waits until no other thread holds the lock, takes it for writing, and
    ## returns the guard that a `with` block enters to reach the value.
    ##
    ## @returns the guard; its `enter()` returns the value, and destroying it unlocks
    ## @panics if the calling thread already holds the lock for writing
    ## @example
    ##     with (var config = settings.write()) {
    ##         config.port.store(8080);
    ##     }
    write(): RwLockWriteGuard<T> {
        return RwLockWriteGuard<T>(this);
    }

    ## Takes the lock for writing only if no thread holds it right now,
    ## without waiting.
    ##
    ## @returns the guard; its `enter()` returns the value, or null when the lock was busy
    try_write(): RwLockWriteGuard<T> {
        return RwLockWriteGuard<T>(this, false);
    }

    ## Replaces the whole value under the write lock and returns the one the
    ## RwLock held.
    ##
    ## @param value the new value
    ## @returns the value the RwLock held
    ## @panics if the calling thread already holds the lock for writing
    replace(value: T): T {
        this._lock_write();
        T old = _value[0];
        _value[0] = value;
        this._unlock_write();
        return old;
    }

    # Waits until readers may go on, and counts the caller as one.
    _lock_read() {
        if (_writer.load() == _async_holder_id()) {
            panic("RwLock.read: the caller holds this RwLock for writing");
        }
        with (var state = _state.lock()) {
            while (state.writing || state.writers_waiting != 0) {
                _readers_go.wait();
            }
            state.readers = state.readers + 1;
        }
    }

    # Counts the caller as a reader if no writer holds or waits; true if so.
    _try_lock_read(): bool {
        if (_writer.load() == _async_holder_id()) {
            return false;
        }
        with (var state = _state.lock()) {
            if (state.writing || state.writers_waiting != 0) {
                return false;
            }
            state.readers = state.readers + 1;
        }
        return true;
    }

    _unlock_read() {
        with (var state = _state.lock()) {
            state.readers = state.readers - 1;
            if (state.readers == 0 && state.writers_waiting != 0) {
                _writer_go.notify_one();
            }
        }
    }

    # Waits until no thread holds the lock, and takes it for writing.
    _lock_write() {
        var me = _async_holder_id();
        if (_writer.load() == me) {
            panic("RwLock.write: the caller already holds this RwLock for writing");
        }
        with (var state = _state.lock()) {
            state.writers_waiting = state.writers_waiting + 1;
            while (state.writing || state.readers != 0) {
                _writer_go.wait();
            }
            state.writers_waiting = state.writers_waiting - 1;
            state.writing = true;
        }
        _writer.store(me);
    }

    # Takes the lock for writing if no thread holds it; true if so.
    _try_lock_write(): bool {
        var me = _async_holder_id();
        if (_writer.load() == me) {
            return false;
        }
        with (var state = _state.lock()) {
            if (state.writing || state.readers != 0) {
                return false;
            }
            state.writing = true;
        }
        _writer.store(me);
        return true;
    }

    # Hands the lock to the next writer if one waits, else to every waiting
    # reader.
    _unlock_write() {
        _writer.store(0);
        with (var state = _state.lock()) {
            state.writing = false;
            if (state.writers_waiting != 0) {
                _writer_go.notify_one();
            } else {
                _readers_go.notify_all();
            }
        }
    }
}

## The read lock on an `RwLock<T>` that a `with` block holds: `enter()`
## returns the value, and destroying the guard unlocks. Get one from
## `RwLock.read()` or `RwLock.try_read()` in a `with` header.
##
## @typeParam T the protected value's type
## @example
##     with (var stats = counters.read()) {
##         total = stats.hits.load() + stats.misses.load();
##     }   # unlocked here
export struct RwLockReadGuard<T: Shared> {
    # The RwLock this guard locks.
    const _source: RwLock<T>;

    ## Whether the guard holds the lock: false once `exit()` has run, and for
    ## a `try_read()` that could not take it.
    bool locked;

    ## Takes `source` for reading and creates the guard that holds it; the
    ## same as `source.read()` (or `source.try_read()` when `wait` is false).
    ##
    ## @param source the RwLock to lock
    ## @param wait true to wait for the lock; false to take it only if that needs no wait
    ## @panics if `wait` is true and the calling thread holds the lock for writing
    construct(source: RwLock<T>, wait: bool = true) {
        _source = source;
        if (wait) {
            source._lock_read();
            locked = true;
        } else {
            locked = source._try_lock_read();
        }
    }

    destruct {
        this.exit();
    }

    ## Returns the RwLock's value, for the `with` header to bind.
    ##
    ## @returns the protected value, or the default of `T` (null for a struct) when the guard does not hold the lock
    enter(): T {
        if (!locked) {
            return __default<T>();
        }
        return _source._value[0];
    }

    ## Unlocks if the guard holds the lock. The destructor calls it; calling
    ## it again does nothing.
    exit() {
        if (locked) {
            locked = false;
            _source._unlock_read();
        }
    }
}

extend RwLockReadGuard<T> with Scoped<T>;

## The write lock on an `RwLock<T>` that a `with` block holds: `enter()`
## returns the value, and destroying the guard unlocks. Get one from
## `RwLock.write()` or `RwLock.try_write()` in a `with` header.
##
## @typeParam T the protected value's type
## @example
##     with (var stats = counters.write()) {
##         stats.hits.store(0);
##         stats.misses.store(0);
##     }   # unlocked here
export struct RwLockWriteGuard<T: Shared> {
    # The RwLock this guard locks.
    const _source: RwLock<T>;

    ## Whether the guard holds the lock: false once `exit()` has run, and for
    ## a `try_write()` that found the lock busy.
    bool locked;

    ## Takes `source` for writing and creates the guard that holds it; the
    ## same as `source.write()` (or `source.try_write()` when `wait` is
    ## false).
    ##
    ## @param source the RwLock to lock
    ## @param wait true to wait for the lock; false to take it only if it is free right now
    ## @panics if `wait` is true and the calling thread already holds the lock for writing
    construct(source: RwLock<T>, wait: bool = true) {
        _source = source;
        if (wait) {
            source._lock_write();
            locked = true;
        } else {
            locked = source._try_lock_write();
        }
    }

    destruct {
        this.exit();
    }

    ## Returns the RwLock's value, for the `with` header to bind.
    ##
    ## @returns the protected value, or the default of `T` (null for a struct) when the guard does not hold the lock
    enter(): T {
        if (!locked) {
            return __default<T>();
        }
        return _source._value[0];
    }

    ## Unlocks if the guard holds the lock. The destructor calls it; calling
    ## it again does nothing.
    exit() {
        if (locked) {
            locked = false;
            _source._unlock_write();
        }
    }
}

extend RwLockWriteGuard<T> with Scoped<T>;

# Who holds an RwLock and who waits for it.
struct _RwLockState {
    # How many threads hold it for reading.
    var readers: ulong;
    # Whether a thread holds it for writing.
    var writing: bool;
    # How many threads wait to write.
    var writers_waiting: ulong;
}
