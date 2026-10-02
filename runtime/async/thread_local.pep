## Per-thread values: `ThreadLocal<T>` gives every thread its own copy of a
## variable.

# Each ThreadLocal owns one operating-system thread-local key
# (`pthread_key_create`, or `FlsAlloc` on Windows). A thread's value lives in
# a malloc'd slot the key points at: `sizeof<T>()` bytes for a POD `T`, one
# reference for a struct `T`. The key's destructor (`_release_slot`, passed as
# a C callback with `__function_pointer`) runs when a thread exits and
# releases that thread's value.
#
# For a `T` that is not thread-safe, a thread's value is reached only through
# `with (var value = local.enter())`: `ThreadLocalGuard` is `[Isolated]`, so
# `passes/check_confinement.rs` keeps references into the value inside the
# block, `get()` is a compile error, and `set` takes a new value (`[Move]`).
# Otherwise a function called under a lock could park part of the locked
# value in a thread-local, and a later `get()` would hand it out after the
# lock is released.

import "sys_posix";
import "sys_wasi";
import "sys_windows";

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
## Destroying a `ThreadLocal` releases the calling thread's value only. Values
## that other threads still hold are released on Windows and leak elsewhere,
## so destroy one only after the threads that used it have exited.
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
    # The operating-system thread-local key.
    const _key: ulong;

    ## Creates a thread-local variable. No thread has a value yet.
    ##
    ## @panics if the operating system has no thread-local keys left
    construct() {
        _key = _async_sys_key_create(__function_pointer(_release_slot));
    }

    destruct {
        this.clear();
        _async_sys_key_delete(_key);
    }

    # Releases the value in `slot` and frees it: the key's destructor, which
    # the operating system calls on each exiting thread that has a value.
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
        __ptr<T> slot = _async_sys_key_get(_key);
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
        __ptr<T> slot = _async_sys_key_get(_key);
        if (slot == __null) {
            # sizeof<T>() is the size of a stored T: one pointer for a
            # struct, two for a trait value (object and vtable), the value
            # itself for a number.
            slot = _pep_malloc(sizeof<T>());
            _async_sys_key_set(_key, slot);
        }
        slot[0] = value;
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
        return _async_sys_key_get(_key) != __null;
    }

    ## Removes the calling thread's value, releasing it for a struct `T`.
    ## `get()` returns the default of `T` afterwards.
    clear() {
        var slot = _async_sys_key_get(_key);
        if (slot != __null) {
            _async_sys_key_set(_key, __null);
            ThreadLocal<T>._release_slot(slot);
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
        __ptr<T> slot = _async_sys_key_get(_local._key);
        if (slot == __null) {
            return __default<T>();
        }
        return slot[0];
    }

    ## Does nothing: the value stays with the thread.
    exit() {}
}

extend ThreadLocalGuard<T> with Scoped<T>;
