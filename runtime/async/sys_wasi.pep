# WASI (WebAssembly) platform layer for async: the same `_async_sys_*`
# functions as sys_posix.pep and sys_windows.pep, each with
# [Target(OS(Wasi))]. A WASI preview 1 program has one thread: starting
# another fails, and a mutex or condition variable has no other thread to
# wait for. wasi-libc's single-threaded pthread functions keep the
# thread-local keys and the mutexes' bookkeeping.

import io;

[Target(OS(Wasi))]
extern int pthread_key_create(void* key, void* destructor);
[Target(OS(Wasi))]
extern int pthread_key_delete(ulong key);
[Target(OS(Wasi))]
extern void* pthread_getspecific(ulong key);
[Target(OS(Wasi))]
extern int pthread_setspecific(ulong key, void* value);
[Target(OS(Wasi))]
extern ushort __wasi_clock_time_get(uint id, u64 precision, void* time);
[Target(OS(Wasi))]
extern ushort __wasi_poll_oneoff(void* subscriptions, void* events, ulong count, void* returned);

# ── Threads ──────────────────────────────────────────────────────────────────

# WASI preview 1 has no threads.
[Target(OS(Wasi))]
_async_sys_spawn(start: __ptr<void>, argument: __ptr<void>): __ptr<void> {
    panic("Thread.spawn: threads are not supported on WASI");
    return __null;
}

[Target(OS(Wasi))]
_async_sys_join(handle: __ptr<void>) {}

[Target(OS(Wasi))]
_async_sys_detach(handle: __ptr<void>) {}

# The one thread.
[Target(OS(Wasi))]
_async_sys_os_thread(): ulong {
    return 1;
}

# Sleeps with poll_oneoff on one relative clock subscription (struct
# subscription: userdata u64 @0, tag u8 @8, then the clock's id u32 @16,
# timeout u64 @24, precision u64 @32, flags u16 @40; 48 bytes), for which it
# writes one 32-byte event.
[Target(OS(Wasi))]
_async_sys_sleep(milliseconds: ulong) {
    __ptr<u8> subscription = _pep_malloc(48);
    __ptr<u8> event = _pep_malloc(32);
    __ptr<u32> returned = _pep_malloc(4);
    var index: ulong = 0;
    while (index < 48) {
        subscription[index] = 0;
        index = index + 1;
    }
    unsafe_cast<__ptr<u32>>(subscription + 16)[0] = 1;  # CLOCKID_MONOTONIC
    unsafe_cast<__ptr<u64>>(subscription + 24)[0] = milliseconds * 1000000;
    __wasi_poll_oneoff(subscription, event, 1, returned);
    _pep_free(returned);
    _pep_free(event);
    _pep_free(subscription);
}

# ── Thread-local keys ────────────────────────────────────────────────────────

[Target(OS(Wasi))]
_async_sys_key_create(destructor: __ptr<void>): ulong {
    __ptr<ulong> key = _pep_malloc(8);
    key[0] = 0;
    if (pthread_key_create(key, destructor) != 0) {
        panic("ThreadLocal: the operating system has no thread-local keys left");
    }
    ulong created = key[0];
    _pep_free(key);
    return created;
}

[Target(OS(Wasi))]
_async_sys_key_delete(key: ulong) {
    pthread_key_delete(key);
}

[Target(OS(Wasi))]
_async_sys_key_get(key: ulong): __ptr<void> {
    return pthread_getspecific(key);
}

[Target(OS(Wasi))]
_async_sys_key_set(key: ulong, value: __ptr<void>) {
    pthread_setspecific(key, value);
}

# ── Mutexes and condition variables ──────────────────────────────────────────
#
# A mutex is a flag in its own heap block: with one thread, a lock that is
# taken is the caller's own re-lock, which `Mutex<T>` reports before it
# gets here. A condition variable has no other thread to notify it, so a
# wait returns at once (a spurious wake-up, which every caller allows for)
# and a timed wait sleeps out its time.

[Target(OS(Wasi))]
_async_sys_mutex_create(): __ptr<void> {
    __ptr<u8> mutex = _pep_malloc(8);
    mutex[0] = 0;
    return mutex;
}

[Target(OS(Wasi))]
_async_sys_mutex_destroy(mutex: __ptr<void>) {
    _pep_free(mutex);
}

[Target(OS(Wasi))]
_async_sys_mutex_lock(mutex: __ptr<void>) {
    __ptr<u8> flag = mutex;
    assert(flag[0] == 0, "Mutex: locked again on the only thread, which would wait forever");
    flag[0] = 1;
}

[Target(OS(Wasi))]
_async_sys_mutex_try_lock(mutex: __ptr<void>): bool {
    __ptr<u8> flag = mutex;
    if (flag[0] != 0) {
        return false;
    }
    flag[0] = 1;
    return true;
}

[Target(OS(Wasi))]
_async_sys_mutex_unlock(mutex: __ptr<void>) {
    __ptr<u8> flag = mutex;
    flag[0] = 0;
}

[Target(OS(Wasi))]
_async_sys_condition_create(): __ptr<void> {
    return _pep_malloc(8);
}

[Target(OS(Wasi))]
_async_sys_condition_destroy(condition: __ptr<void>) {
    _pep_free(condition);
}

[Target(OS(Wasi))]
_async_sys_condition_wait(condition: __ptr<void>, mutex: __ptr<void>) {}

[Target(OS(Wasi))]
_async_sys_condition_wait_for(condition: __ptr<void>, mutex: __ptr<void>, milliseconds: ulong): bool {
    _async_sys_mutex_unlock(mutex);
    _async_sys_sleep(milliseconds > 1000000000000 ? 1000000000000 : milliseconds);
    _async_sys_mutex_lock(mutex);
    return false;
}

[Target(OS(Wasi))]
_async_sys_condition_notify_one(condition: __ptr<void>) {}

[Target(OS(Wasi))]
_async_sys_condition_notify_all(condition: __ptr<void>) {}

[Target(OS(Wasi))]
_async_sys_monotonic_milliseconds(): ulong {
    __ptr<u64> time = _pep_malloc(8);
    time[0] = 0;
    __wasi_clock_time_get(1, 1000000, time);  # CLOCKID_MONOTONIC, to the millisecond
    var milliseconds = time[0] / 1000000;
    _pep_free(time);
    return milliseconds;
}

# ── Processor counts (0 when unknown) ────────────────────────────────────────

# The one thread is the only processor a program can use.
[Target(OS(Wasi))]
_async_sys_logical_cpus(): ulong {
    return 1;
}

[Target(OS(Wasi))]
_async_sys_physical_cpus(): ulong {
    return 1;
}
