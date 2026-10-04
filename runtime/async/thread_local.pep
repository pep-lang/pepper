## Per-thread values: `ThreadLocal<T>` gives every thread its own copy of a
## variable.

# Each ThreadLocal has an index, given out once from `_thread_local_indexes`
# and never reused. A thread's values live in a table of its own, held in
# native `[ThreadLocal]` variables (#625): `_thread_local_slots[index]`
# points at a malloc'd slot, `sizeof<T>()` bytes for a POD `T`, one reference
# for a struct `T`, or is null where the thread has no value. So `get()` is a
# thread-local load, a bounds check and two loads, with no call into the
# operating system (it used to be a `pthread_getspecific` or `FlsGetValue`
# call per access), and there is no limit on how many exist.
#
# `_thread_local_releases[index]` is the function that releases the slot
# (`ThreadLocal<T>._release_slot`), stored with it, since the code that
# empties a thread's table at its exit does not know `T`. That code is the
# destructor of `_ThreadLocalTable`, a `[Shared]` struct that one
# reference-typed thread-local holds while the thread has any value: the
# compiler releases it when a thread started with `Thread.spawn` exits
# (`_pep_release_thread_locals`), and `clear()` releases it when the thread's
# last value goes, which frees the table.
#
# For a `T` that is not thread-safe, a thread's value is reached only through
# `with (var value = local.enter())`: `ThreadLocalGuard` is `[Isolated]`, so
# `passes/check_confinement.rs` keeps references into the value inside the
# block, `get()` is a compile error, and `set` takes a new value (`[Move]`).
# Otherwise a function called under a lock could park part of the locked
# value in a thread-local, and a later `get()` would hand it out after the
# lock is released.

import "atomic";

# The tables come from the C allocator, not `_pep_malloc`: like the
# operating system's own key tables they are bookkeeping, not values, so a
# test's allocation count does not see the main thread's.
extern void* realloc(void* p, ulong size);
extern void free(void* p);
extern void memset(void* p, int c, ulong n);

# Releases the value in a thread's slot and frees the slot: a ThreadLocal's
# `_release_slot`.
type _SlotRelease = shared (__ptr<void>) => void;

# Gives every ThreadLocal its index.
const _thread_local_indexes = Atomic<ulong>(0);

# The calling thread's slots, by ThreadLocal index; null where it has no
# value.
[ThreadLocal]
var _thread_local_slots: __ptr<__ptr<void>>;

# The function that releases each of the calling thread's slots.
[ThreadLocal]
var _thread_local_releases: __ptr<_SlotRelease>;

# How many entries the calling thread's tables have room for.
[ThreadLocal]
var _thread_local_capacity: ulong = 0;

# How many of the calling thread's slots hold a value.
[ThreadLocal]
var _thread_local_count: ulong = 0;

# Held while the calling thread has a value: its release empties the table.
[ThreadLocal]
var _thread_local_table: _ThreadLocalTable;

# Owns the calling thread's table of ThreadLocal values: destroying it
# releases every value left in it and frees it. It runs on the thread whose
# table it is, at its exit or when its last value is cleared.
[Shared]
struct _ThreadLocalTable {
    construct() {}

    destruct {
        var slots = _thread_local_slots;
        var releases = _thread_local_releases;
        var capacity = _thread_local_capacity;
        # A release below may store a new value on this thread: it starts a
        # new table, which the thread's exit releases in turn.
        _thread_local_slots = __null;
        _thread_local_releases = __null;
        _thread_local_capacity = 0;
        _thread_local_count = 0;
        var index: ulong = 0;
        while (index < capacity) {
            var slot = slots[index];
            if (slot != __null) {
                var release = releases[index];
                release(slot);
            }
            releases[index] = __default<_SlotRelease>();
            index += 1;
        }
        free(slots);
        free(releases);
    }
}

# The calling thread's slot for the ThreadLocal at `index`, or null.
_thread_local_slot(index: ulong): __ptr<void> {
    if (index < _thread_local_capacity) {
        return _thread_local_slots[index];
    }
    return __null;
}

# A new zeroed slot of `size` bytes for the ThreadLocal at `index` on the
# calling thread, which `release` will release: grows the thread's table to
# hold `index` and starts one if the thread has none.
_thread_local_add(index: ulong, size: ulong, release: _SlotRelease): __ptr<void> {
    if (index >= _thread_local_capacity) {
        var capacity: ulong = _thread_local_capacity * 2;
        if (capacity < 8) {
            capacity = 8;
        }
        if (capacity <= index) {
            capacity = index + 1;
        }
        _thread_local_slots = _thread_local_grow(_thread_local_slots, _thread_local_capacity * 8, capacity * 8);
        _thread_local_releases = _thread_local_grow(
            _thread_local_releases, _thread_local_capacity * sizeof<_SlotRelease>(), capacity * sizeof<_SlotRelease>()
        );
        _thread_local_capacity = capacity;
    }
    if (_thread_local_count == 0 && _thread_local_table === __null) {
        _thread_local_table = _ThreadLocalTable();
    }
    var slot = _pep_malloc(size);
    _thread_local_slots[index] = slot;
    _thread_local_releases[index] = release;
    _thread_local_count += 1;
    return slot;
}

# `table`, of `size` bytes, grown to `new_size` bytes with the new part
# zeroed.
_thread_local_grow(table: __ptr<void>, size: ulong, new_size: ulong): __ptr<void> {
    var grown = realloc(table, new_size);
    if (grown == __null) {
        panic("ThreadLocal: out of memory");
    }
    memset(grown + size, 0, new_size - size);
    return grown;
}

# Takes the calling thread's slot for the ThreadLocal at `index` out of its
# table: null when it has none. The caller releases the slot, then calls
# `_thread_local_removed`.
_thread_local_take(index: ulong): __ptr<void> {
    var slot = _thread_local_slot(index);
    if (slot != __null) {
        _thread_local_slots[index] = __null;
        _thread_local_releases[index] = __default<_SlotRelease>();
        _thread_local_count -= 1;
    }
    return slot;
}

# After a slot taken from the table is released: frees the table when the
# thread has no value left.
_thread_local_removed() {
    if (_thread_local_count == 0) {
        _thread_local_table = __default<_ThreadLocalTable>();
    }
}

## A variable with a separate value on every thread, like C++
## `thread_local` or Rust's `thread_local!`.
##
## Each thread that calls `set` stores its own value. When a thread exits, its
## value is released.
##
## For a thread-safe `T` (a number, a `[Shared]` struct), `get` returns the
## calling thread's value (the default of `T`, zero or null, until that thread
## sets one). For any other `T`, such as a `String`, the value is reached
## through a `with` block, `with (var value = local.enter()) { ... }`, and
## `get` is a compile error; `set` then takes a new value (a constructor call,
## a string literal, `copy(x)`). Inside the block the value is kept apart
## from the rest of the program, as for a `Mutex`.
##
## A `ThreadLocal` is `[Shared]`, so one object can be used from every
## thread; it is usually a module-scope variable. `T` does not have to be
## thread-safe, because each value stays on the thread that stored it.
##
## Destroying a `ThreadLocal` releases the calling thread's value; values
## that other threads still hold are released when those threads exit.
##
## A thread's values are released when it exits if `Thread.spawn` started
## it (the `async` runtime's workers too). The main thread's are released
## only by `clear()`, and a thread started by C code leaks the values it did
## not clear.
##
## @typeParam T the type of the per-thread value
## @example
##     import async;
##
##     const calls = async.ThreadLocal<int>();
##
##     count_call() {
##         calls.set(calls.get() + 1);
##     }
##
##     main(): int {
##         count_call();
##         count_call();
##         assert(calls.get() == 2, "two calls on this thread");
##         return 0;
##     }
[Shared]
export struct ThreadLocal<T> {
    # The index of this variable's slot in every thread's table.
    const _index: ulong;

    ## Creates a thread-local variable. No thread has a value yet.
    construct() {
        _index = _thread_local_indexes.fetch_add(1);
    }

    destruct {
        this.clear();
    }

    # Releases the value in `slot` and frees it: the slot's release
    # function, which `_ThreadLocalTable` calls for each value a thread
    # still holds when it exits.
    static _release_slot(slot: __ptr<void>) {
        __ptr<T> value = slot;
        value[0] = __default<T>();
        _pep_free(slot);
    }

    ## Returns the calling thread's value.
    ##
    ## For a struct `T` the caller gets its own reference. Only for a
    ## thread-safe `T`: for any other `T`, use `with (var value =
    ## local.enter())`.
    ##
    ## @returns the value this thread last stored, or the default of `T` (zero or null) if it has not stored one
    get(): T {
        __ptr<T> slot = _thread_local_slot(_index);
        if (slot == __null) {
            return __default<T>();
        }
        return slot[0];
    }

    ## Stores `value` as the calling thread's value, replacing (and, for a
    ## struct `T`, releasing) the one it held. Other threads' values are not
    ## affected.
    ##
    ## For a `T` that is not thread-safe, `value` must be a new value (a
    ## constructor call, a string literal, `copy(x)`), which the compiler
    ## checks.
    ##
    ## @param value the new value for this thread
    set([Move] value: T) {
        __ptr<T> slot = _thread_local_slot(_index);
        if (slot == __null) {
            slot = this._add_slot();
        }
        slot[0] = value;
    }

    # A new, empty slot for the calling thread's value, in its table.
    _add_slot(): __ptr<void> {
        # sizeof<T>() is the size of a stored T: one pointer for a struct,
        # two for a trait value (object and vtable), the value itself for a
        # number.
        return _thread_local_add(_index, sizeof<T>(), (slot: __ptr<void>) => {
            ThreadLocal<T>._release_slot(slot);
        });
    }

    # The calling thread's slot, or null when it has no value.
    _slot(): __ptr<void> {
        return _thread_local_slot(_index);
    }

    ## Returns the guard that a `with` block enters to reach the calling
    ## thread's value: `with (var value = local.enter()) { ... }`. The body
    ## runs with the value bound; the `else` block runs when this thread has
    ## no value (for a struct `T`).
    ##
    ## @returns the guard; its `enter()` returns this thread's value
    ## @example
    ##     const names = async.ThreadLocal<Array<String>>();
    ##
    ##     remember(String name) {
    ##         if (!names.is_set()) {
    ##             names.set(Array<String>());
    ##         }
    ##         with (var list = names.enter()) {
    ##             list.append(name.copy());
    ##         }
    ##     }
    enter(): ThreadLocalGuard<T> {
        return ThreadLocalGuard<T>(this);
    }

    ## Reports whether the calling thread has stored a value since it started
    ## or last called `clear()`.
    ##
    ## @returns true if this thread has a value
    is_set(): bool {
        return _thread_local_slot(_index) != __null;
    }

    ## Removes the calling thread's value, releasing it for a struct `T`.
    ## `get()` returns the default of `T` afterwards.
    clear() {
        var slot = _thread_local_take(_index);
        if (slot != __null) {
            ThreadLocal<T>._release_slot(slot);
            _thread_local_removed();
        }
    }
}

## The access to a thread's `ThreadLocal<T>` value that a `with` block holds:
## `enter()` returns the value. Get one from `ThreadLocal.enter()`.
##
## A guard is `[Isolated]`: it can only be the scope of a `with` header, and
## the compiler checks the block with the confinement rule (see `Mutex`).
##
## @typeParam T the type of the per-thread value
[Isolated]
export struct ThreadLocalGuard<T> {
    # The thread-local variable.
    const _local: ThreadLocal<T>;

    ## Creates the guard for the calling thread's value of `local`; the same
    ## as `local.enter()`.
    ##
    ## @param local the thread-local variable
    construct(local: ThreadLocal<T>) {
        _local = local;
    }

    ## Returns the calling thread's value, for the `with` header to bind.
    ##
    ## @returns this thread's value, or the default of `T` (null for a struct) when it has none
    enter(): T {
        __ptr<T> slot = _local._slot();
        if (slot == __null) {
            return __default<T>();
        }
        return slot[0];
    }

    ## Does nothing: the value stays with the thread.
    exit() {}
}

extend ThreadLocalGuard<T> with Scoped<T>;
