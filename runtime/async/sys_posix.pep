# POSIX (Linux, macOS) platform layer for async. Every declaration carries
# [Target(!OS(Windows))] or a narrower target; sys_windows.pep declares the
# same `_async_sys_*` functions with the same signatures for Windows. These
# are exported to the other async files only: module.pep does not re-export
# them.
#
# `pthread_t` is an unsigned long on Linux and a pointer on macOS; it travels
# as `__ptr<void>` (the same register either way), like a Windows `HANDLE`.
# `pthread_key_t` is an unsigned int on Linux and an unsigned long on macOS;
# it travels as `ulong` (64-bit little-endian targets only: a key written into
# a zeroed 8-byte buffer reads back the same either way).

import io;

[Target(!OS(Windows))] extern int pthread_create(void* thread, void* attributes, void* start, void* argument);
[Target(!OS(Windows))] extern int pthread_join(void* thread, void* result);
[Target(!OS(Windows))] extern int pthread_detach(void* thread);
[Target(!OS(Windows))] extern ulong pthread_self();
[Target(!OS(Windows))] extern int pthread_key_create(void* key, void* destructor);
[Target(!OS(Windows))] extern int pthread_key_delete(ulong key);
[Target(!OS(Windows))] extern void* pthread_getspecific(ulong key);
[Target(!OS(Windows))] extern int pthread_setspecific(ulong key, void* value);
[Target(!OS(Windows))] extern int nanosleep(void* request, void* remaining);
[Target(!OS(Windows))] extern long sysconf(int name);
[Target(OS(Mac))] extern int sysctlbyname(char* name, void* value, void* size, void* new_value, ulong new_size);
[Target(!OS(Windows))] extern int pthread_mutex_init(void* mutex, void* attributes);
[Target(!OS(Windows))] extern int pthread_mutex_destroy(void* mutex);
[Target(!OS(Windows))] extern int pthread_mutex_lock(void* mutex);
[Target(!OS(Windows))] extern int pthread_mutex_trylock(void* mutex);
[Target(!OS(Windows))] extern int pthread_mutex_unlock(void* mutex);
[Target(!OS(Windows))] extern int pthread_cond_init(void* condition, void* attributes);
[Target(!OS(Windows))] extern int pthread_cond_destroy(void* condition);
[Target(!OS(Windows))] extern int pthread_cond_wait(void* condition, void* mutex);
[Target(!OS(Windows))] extern int pthread_cond_signal(void* condition);
[Target(!OS(Windows))] extern int pthread_cond_broadcast(void* condition);
[Target(!OS(Windows))] extern int clock_gettime(int clock, void* time);
[Target(OS(Linux))] extern int pthread_condattr_init(void* attributes);
[Target(OS(Linux))] extern int pthread_condattr_setclock(void* attributes, int clock);
[Target(OS(Linux))] extern int pthread_condattr_destroy(void* attributes);
[Target(OS(Linux))] extern int pthread_cond_timedwait(void* condition, void* mutex, void* deadline);
[Target(OS(Mac))] extern int pthread_cond_timedwait_relative_np(void* condition, void* mutex, void* timeout);

# ── Threads ──────────────────────────────────────────────────────────────────

# Starts a thread running `start(argument)`; its handle, or null on failure.
[Target(!OS(Windows))] export _async_sys_spawn(start: __ptr<void>, argument: __ptr<void>): __ptr<void> {
    __ptr<__ptr<void>> thread = _pep_malloc(8);
    var result = pthread_create(thread, __null, start, argument);
    __ptr<void> handle = thread[0];
    _pep_free(thread);
    if (result != 0) {
        return __null;
    }
    return handle;
}

[Target(!OS(Windows))] export _async_sys_join(handle: __ptr<void>) {
    pthread_join(handle, __null);
}

[Target(!OS(Windows))] export _async_sys_detach(handle: __ptr<void>) {
    pthread_detach(handle);
}

# The operating system's identity of the calling thread.
[Target(!OS(Windows))] export _async_sys_os_thread(): ulong {
    return pthread_self();
}

[Target(!OS(Windows))] export _async_sys_sleep(milliseconds: ulong) {
    # struct timespec { time_t tv_sec; long tv_nsec; }
    __ptr<long> time = _pep_malloc(16);
    time[0] = (milliseconds / 1000) as long;
    time[1] = ((milliseconds % 1000) * 1000000) as long;
    # Interrupted by a signal: sleep again for the time that was left, which
    # nanosleep wrote back. The request is always valid, so no other error
    # can repeat.
    while (nanosleep(time, time) != 0) {}
    _pep_free(time);
}

# ── Thread-local keys ────────────────────────────────────────────────────────

# A new key whose `destructor(value)` runs on each exiting thread with a
# non-null value.
[Target(!OS(Windows))] export _async_sys_key_create(destructor: __ptr<void>): ulong {
    __ptr<ulong> key = _pep_malloc(8);
    if (pthread_key_create(key, destructor) != 0) {
        panic("ThreadLocal: the operating system has no thread-local keys left");
    }
    ulong created = key[0];
    _pep_free(key);
    return created;
}

[Target(!OS(Windows))] export _async_sys_key_delete(key: ulong) {
    pthread_key_delete(key);
}

[Target(!OS(Windows))] export _async_sys_key_get(key: ulong): __ptr<void> {
    return pthread_getspecific(key);
}

[Target(!OS(Windows))] export _async_sys_key_set(key: ulong, value: __ptr<void>) {
    pthread_setspecific(key, value);
}

# ── Mutexes and condition variables ──────────────────────────────────────────
#
# Each lives in its own 64-byte heap block, which covers `pthread_mutex_t`
# (40 bytes on Linux x86_64, 48 on Linux aarch64, 64 on macOS) and
# `pthread_cond_t` (48): a pthread mutex or condition must not move once
# initialized. Mutexes are the default (non-recursive) kind; `Mutex<T>`
# panics on a re-lock before it would deadlock.

# A new, unlocked mutex.
[Target(!OS(Windows))] export _async_sys_mutex_create(): __ptr<void> {
    var mutex = _pep_malloc(64);
    if (pthread_mutex_init(mutex, __null) != 0) {
        panic("Mutex: the operating system could not create a mutex");
    }
    return mutex;
}

# Destroys an unlocked mutex and frees its block.
[Target(!OS(Windows))] export _async_sys_mutex_destroy(mutex: __ptr<void>) {
    pthread_mutex_destroy(mutex);
    _pep_free(mutex);
}

[Target(!OS(Windows))] export _async_sys_mutex_lock(mutex: __ptr<void>) {
    pthread_mutex_lock(mutex);
}

# Locks `mutex` only if it is free; true if it is now held.
[Target(!OS(Windows))] export _async_sys_mutex_try_lock(mutex: __ptr<void>): bool {
    return pthread_mutex_trylock(mutex) == 0;
}

[Target(!OS(Windows))] export _async_sys_mutex_unlock(mutex: __ptr<void>) {
    pthread_mutex_unlock(mutex);
}

# A new condition variable. On Linux it times waits against the monotonic
# clock (CLOCK_MONOTONIC is 1), so a change to the wall clock cannot stretch
# or cut a timed wait.
[Target(OS(Linux))] export _async_sys_condition_create(): __ptr<void> {
    var condition = _pep_malloc(64);
    var attributes = _pep_malloc(16);   # pthread_condattr_t: 4 bytes
    pthread_condattr_init(attributes);
    pthread_condattr_setclock(attributes, 1);
    var result = pthread_cond_init(condition, attributes);
    pthread_condattr_destroy(attributes);
    _pep_free(attributes);
    if (result != 0) {
        panic("Condition: the operating system could not create a condition variable");
    }
    return condition;
}

# A new condition variable. macOS times waits with
# `pthread_cond_timedwait_relative_np`, which needs no clock setting.
[Target(OS(Mac))] export _async_sys_condition_create(): __ptr<void> {
    var condition = _pep_malloc(64);
    if (pthread_cond_init(condition, __null) != 0) {
        panic("Condition: the operating system could not create a condition variable");
    }
    return condition;
}

# Destroys a condition variable no thread waits on and frees its block.
[Target(!OS(Windows))] export _async_sys_condition_destroy(condition: __ptr<void>) {
    pthread_cond_destroy(condition);
    _pep_free(condition);
}

# Unlocks `mutex` (held by the caller), sleeps until notified (or woken
# spuriously), and locks it again.
[Target(!OS(Windows))] export _async_sys_condition_wait(condition: __ptr<void>, mutex: __ptr<void>) {
    pthread_cond_wait(condition, mutex);
}

# Like `_async_sys_condition_wait`, for at most `milliseconds`; false if the
# time ran out. Waits past ~31 years are capped.
[Target(OS(Linux))] export _async_sys_condition_wait_for(condition: __ptr<void>, mutex: __ptr<void>, milliseconds: ulong): bool {
    var wait = milliseconds > 1000000000000 ? 1000000000000 : milliseconds;
    # An absolute deadline on the monotonic clock: struct timespec
    # { time_t tv_sec; long tv_nsec; }.
    __ptr<long> deadline = _pep_malloc(16);
    clock_gettime(1, deadline);
    deadline[0] = deadline[0] + (wait / 1000) as long;
    deadline[1] = deadline[1] + ((wait % 1000) * 1000000) as long;
    if (deadline[1] >= 1000000000) {
        deadline[0] = deadline[0] + 1;
        deadline[1] = deadline[1] - 1000000000;
    }
    var result = pthread_cond_timedwait(condition, mutex, deadline);
    _pep_free(deadline);
    return result == 0;
}

[Target(OS(Mac))] export _async_sys_condition_wait_for(condition: __ptr<void>, mutex: __ptr<void>, milliseconds: ulong): bool {
    var wait = milliseconds > 1000000000000 ? 1000000000000 : milliseconds;
    # A relative timeout: struct timespec { time_t tv_sec; long tv_nsec; }.
    __ptr<long> timeout = _pep_malloc(16);
    timeout[0] = (wait / 1000) as long;
    timeout[1] = ((wait % 1000) * 1000000) as long;
    var result = pthread_cond_timedwait_relative_np(condition, mutex, timeout);
    _pep_free(timeout);
    return result == 0;
}

[Target(!OS(Windows))] export _async_sys_condition_notify_one(condition: __ptr<void>) {
    pthread_cond_signal(condition);
}

[Target(!OS(Windows))] export _async_sys_condition_notify_all(condition: __ptr<void>) {
    pthread_cond_broadcast(condition);
}

# Milliseconds on a clock that only moves forward (CLOCK_MONOTONIC: 1 on
# Linux, 6 on macOS), for measuring timeouts.
[Target(OS(Linux))] export _async_sys_monotonic_milliseconds(): ulong {
    return _async_monotonic_milliseconds(1);
}

[Target(OS(Mac))] export _async_sys_monotonic_milliseconds(): ulong {
    return _async_monotonic_milliseconds(6);
}

[Target(!OS(Windows))] _async_monotonic_milliseconds(clock: int): ulong {
    __ptr<long> time = _pep_malloc(16);
    clock_gettime(clock, time);
    var milliseconds = (time[0] * 1000 + time[1] / 1000000) as ulong;
    _pep_free(time);
    return milliseconds;
}

# ── Processor counts (0 when unknown) ────────────────────────────────────────

[Target(OS(Linux))] export _async_sys_logical_cpus(): ulong {
    var count = sysconf(84);   # _SC_NPROCESSORS_ONLN
    return count < 1 ? 0 : count as ulong;
}

# One core per distinct list of hardware threads sharing it, read from the
# topology of every configured CPU (offline CPUs have none).
[Target(OS(Linux))] export _async_sys_physical_cpus(): ulong {
    var configured = sysconf(83);   # _SC_NPROCESSORS_CONF
    var cores = HashSet<String>();
    var cpu: long = 0;
    while (cpu < configured) {
        var topology = "/sys/devices/system/cpu/cpu" + _async_decimal(cpu) + "/topology/";
        # core_cpus_list since Linux 5.3; thread_siblings_list before.
        var siblings = io.File.read_to_string(io.Path(topology + "core_cpus_list"));
        if (!siblings.is_ok()) {
            siblings = io.File.read_to_string(io.Path(topology + "thread_siblings_list"));
        }
        if (siblings.is_ok()) {
            cores.insert(siblings.value());
        }
        cpu = cpu + 1;
    }
    return cores.count() as ulong;
}

# The decimal digits of `value` (>= 0).
[Target(OS(Linux))] export _async_decimal(value: long): String {
    var digits = String();
    if (value == 0) {
        return "0";
    }
    while (value > 0) {
        var digit: __ptr<char> = _pep_malloc(2);
        digit[0] = ('0' + value % 10);
        digits = String(digit, 1, 1) + digits;
        _pep_free(digit);
        value = value / 10;
    }
    return digits;
}

[Target(OS(Mac))] export _async_sys_logical_cpus(): ulong {
    __ptr<int> value = _pep_malloc(4);
    __ptr<ulong> size = _pep_malloc(8);
    size[0] = 4;
    var result = sysctlbyname("hw.logicalcpu", value, size, __null, 0);
    int count = value[0];
    _pep_free(value);
    _pep_free(size);
    return result != 0 || count < 1 ? 0 : count as ulong;
}

[Target(OS(Mac))] export _async_sys_physical_cpus(): ulong {
    __ptr<int> value = _pep_malloc(4);
    __ptr<ulong> size = _pep_malloc(8);
    size[0] = 4;
    var result = sysctlbyname("hw.physicalcpu", value, size, __null, 0);
    int count = value[0];
    _pep_free(value);
    _pep_free(size);
    return result != 0 || count < 1 ? 0 : count as ulong;
}
