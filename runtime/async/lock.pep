# Futex-based mutexes and condition variables for Linux, macOS and Windows,
# as Rust's std has had since 1.62: the `_async_sys_mutex_*` and
# `_async_sys_condition_*` functions (sys_wasi.pep declares the same ones for
# WASI), written once over the platform's wait-on-address calls
# (`_async_sys_futex_*` in sys_posix.pep and sys_windows.pep).
#
# A mutex or a condition variable is a 4-byte word at the start of an 8-byte
# block, and a zeroed block is a free mutex or a fresh condition variable,
# so `_pep_malloc` creates one and nothing needs destroying. The word may sit
# in a block that holds something else too (`Mutex<T>` keeps its value slot
# right after it), and unlike a pthread mutex it could move while unused.
#
# A mutex word is one of three states: free, held, or held with threads
# (possibly) sleeping on it. Locking a free word is one compare-exchange;
# a thread that finds it held spins briefly, then marks it contended and
# sleeps until the word changes. Unlocking stores free and, only when the
# word was contended, wakes one sleeper, which marks the word contended
# again as it takes it, so a later unlock wakes the next one.
#
# A condition variable's word is a sequence number that every notify
# increments: a waiter reads it before unlocking the mutex and sleeps only
# while it is unchanged, so a notify between the unlock and the sleep is
# never lost.

import "sys_posix";
import "sys_windows";

# The mutex word's states.
const _LOCK_FREE: uint = 0;
const _LOCK_HELD: uint = 1;
const _LOCK_CONTENDED: uint = 2;

# How many times a thread looks at a held mutex before it sleeps: a short
# critical section often ends within that, and sleeping costs two system
# calls.
const _LOCK_SPINS = 100;

# A new, free mutex.
[Target(!OS(Wasi))]
export _async_sys_mutex_create(): __ptr<void> {
    return _pep_malloc(8);
}

# Frees a free mutex's block.
[Target(!OS(Wasi))]
export _async_sys_mutex_destroy(mutex: __ptr<void>) {
    _pep_free(mutex);
}

[Target(!OS(Wasi))]
export _async_sys_mutex_lock(mutex: __ptr<void>) {
    __ptr<uint> word = mutex;
    if (!__atomic_cmpxchg<uint>(word, _LOCK_FREE, _LOCK_HELD)) {
        _async_lock_contended(word);
    }
}

# Locks `mutex` only if it is free; true if it is now held.
[Target(!OS(Wasi))]
export _async_sys_mutex_try_lock(mutex: __ptr<void>): bool {
    __ptr<uint> word = mutex;
    return __atomic_cmpxchg<uint>(word, _LOCK_FREE, _LOCK_HELD);
}

[Target(!OS(Wasi))]
export _async_sys_mutex_unlock(mutex: __ptr<void>) {
    __ptr<uint> word = mutex;
    if (_async_lock_exchange(word, _LOCK_FREE) == _LOCK_CONTENDED) {
        _async_sys_futex_wake_one(word);
    }
}

# A new condition variable.
[Target(!OS(Wasi))]
export _async_sys_condition_create(): __ptr<void> {
    return _pep_malloc(8);
}

# Frees a condition variable's block.
[Target(!OS(Wasi))]
export _async_sys_condition_destroy(condition: __ptr<void>) {
    _pep_free(condition);
}

# Unlocks `mutex` (held by the caller), sleeps until notified (or woken
# spuriously), and locks it again.
[Target(!OS(Wasi))]
export _async_sys_condition_wait(condition: __ptr<void>, mutex: __ptr<void>) {
    __ptr<uint> sequence = condition;
    var seen = __atomic_load<uint>(sequence);
    _async_sys_mutex_unlock(mutex);
    _async_sys_futex_wait(sequence, seen);
    _async_sys_mutex_lock(mutex);
}

# Like `_async_sys_condition_wait`, for at most `milliseconds`; false if the
# time ran out.
[Target(!OS(Wasi))]
export _async_sys_condition_wait_for(condition: __ptr<void>, mutex: __ptr<void>, milliseconds: ulong): bool {
    __ptr<uint> sequence = condition;
    var seen = __atomic_load<uint>(sequence);
    _async_sys_mutex_unlock(mutex);
    var woken = _async_sys_futex_wait_for(sequence, seen, milliseconds);
    _async_sys_mutex_lock(mutex);
    return woken;
}

[Target(!OS(Wasi))]
export _async_sys_condition_notify_one(condition: __ptr<void>) {
    __ptr<uint> sequence = condition;
    __atomic_fetch_add<uint>(sequence, 1);
    _async_sys_futex_wake_one(sequence);
}

[Target(!OS(Wasi))]
export _async_sys_condition_notify_all(condition: __ptr<void>) {
    __ptr<uint> sequence = condition;
    __atomic_fetch_add<uint>(sequence, 1);
    _async_sys_futex_wake_all(sequence);
}

# The slow path of a lock: spins while the word is held, then sleeps on it
# until this thread is the one to take it.
[Target(!OS(Wasi))]
_async_lock_contended(word: __ptr<uint>) {
    var state = _async_lock_spin(word);
    if (state == _LOCK_FREE && __atomic_cmpxchg<uint>(word, _LOCK_FREE, _LOCK_HELD)) {
        return;
    }
    while (true) {
        # Marking the word contended takes it if it was free: this thread
        # then holds it, and its unlock wakes a sleeper that may not exist,
        # which costs only that wake.
        if (state != _LOCK_CONTENDED && _async_lock_exchange(word, _LOCK_CONTENDED) == _LOCK_FREE) {
            return;
        }
        _async_sys_futex_wait(word, _LOCK_CONTENDED);
        state = _async_lock_spin(word);
    }
}

# Reads the word until it is not plainly held, or the spins run out, and
# returns what it read last. A contended word means others already sleep,
# so spinning more would only jump the queue.
[Target(!OS(Wasi))]
_async_lock_spin(word: __ptr<uint>): uint {
    var spins = _LOCK_SPINS;
    while (true) {
        var state = __atomic_load<uint>(word);
        if (state != _LOCK_HELD || spins == 0) {
            return state;
        }
        spins = spins - 1;
    }
}

# Stores `value` in the word and returns what it held.
[Target(!OS(Wasi))]
_async_lock_exchange(word: __ptr<uint>, value: uint): uint {
    while (true) {
        var old = __atomic_load<uint>(word);
        if (__atomic_cmpxchg<uint>(word, old, value)) {
            return old;
        }
    }
}
