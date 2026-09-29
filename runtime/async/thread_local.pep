## Per-thread values: `ThreadLocal<T>` gives every thread its own copy of a
## variable.

# Each ThreadLocal owns one operating-system thread-local key
# (`pthread_key_create`, or `FlsAlloc` on Windows). A thread's value lives in
# a malloc'd slot the key points at: `sizeof<T>()` bytes for a POD `T`, one
# reference for a struct `T`. The key's destructor (`_release_slot`, passed as
# a C callback with `__function_pointer`) runs when a thread exits and
# releases that thread's value.

import "sys_posix";
import "sys_windows";

## A variable with a separate value on every thread, like C++
## `thread_local` or Rust's `thread_local!`.
##
## Each thread that calls `set` stores its own value, and `get` returns the
## calling thread's value (the default of `T`, zero or null, until that thread
## sets one). When a thread exits, its value is released.
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
    ## The operating-system thread-local key.
    const Key: ulong;

    ## Creates a thread-local variable. No thread has a value yet.
    ##
    ## @panics if the operating system has no thread-local keys left
    construct() {
        Key = _async_sys_key_create(__function_pointer(_release_slot));
    }

    destruct {
        this.clear();
        _async_sys_key_delete(Key);
    }

    # Releases the value in `slot` and frees it: the key's destructor, which
    # the operating system calls on each exiting thread that has a value.
    static void _release_slot(__ptr<void> slot) {
        __ptr<T> value = slot;
        value[0] = __default<T>();
        _pep_free(slot);
    }

    ## Returns the calling thread's value.
    ##
    ## For a struct `T` the caller gets its own reference.
    ##
    ## @returns the value this thread last stored, or the default of `T` (zero or null) if it has not stored one
    T get() {
        __ptr<T> slot = _async_sys_key_get(Key);
        if (slot == __null) {
            return __default<T>();
        }
        return slot[0];
    }

    ## Stores `value` as the calling thread's value, replacing (and, for a
    ## struct `T`, releasing) the one it held. Other threads' values are not
    ## affected.
    ##
    ## @param value the new value for this thread
    void set(T value) {
        __ptr<T> slot = _async_sys_key_get(Key);
        if (slot == __null) {
            # sizeof<T>() is the size of a stored T: one pointer for a
            # struct, two for a trait value (object and vtable), the value
            # itself for a number.
            slot = _pep_malloc(sizeof<T>());
            _async_sys_key_set(Key, slot);
        }
        slot[0] = value;
    }

    ## Reports whether the calling thread has stored a value since it started
    ## or last called `clear()`.
    ##
    ## @returns true if this thread has a value
    bool is_set() {
        return _async_sys_key_get(Key) != __null;
    }

    ## Removes the calling thread's value, releasing it for a struct `T`.
    ## `get()` returns the default of `T` afterwards.
    void clear() {
        var slot = _async_sys_key_get(Key);
        if (slot != __null) {
            _async_sys_key_set(Key, __null);
            ThreadLocal<T>._release_slot(slot);
        }
    }
}
