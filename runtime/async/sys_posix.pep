# POSIX (Linux, macOS) platform layer for async. Every declaration carries
# [Target(OS(Linux) || OS(Mac))] or a narrower target; sys_windows.pep and
# sys_wasi.pep declare the same `_async_sys_*` functions with the same
# signatures for Windows and WASI. These
# are exported to the other async files only: module.pep does not re-export
# them.
#
# `pthread_t` is an unsigned long on Linux and a pointer on macOS; it travels
# as `__ptr<void>` (the same register either way), like a Windows `HANDLE`.
# `pthread_key_t` is an unsigned int on Linux and an unsigned long on macOS;
# it travels as `ulong` (64-bit little-endian targets only: a key written into
# a zeroed 8-byte buffer reads back the same either way).

import io;

[Target(OS(Linux) || OS(Mac))]
extern int pthread_create(void* thread, void* attributes, void* start, void* argument);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_join(void* thread, void* result);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_detach(void* thread);
[Target(OS(Linux) || OS(Mac))]
extern ulong pthread_self();
[Target(OS(Linux) || OS(Mac))]
extern int pthread_key_create(void* key, void* destructor);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_key_delete(ulong key);
[Target(OS(Linux) || OS(Mac))]
extern void* pthread_getspecific(ulong key);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_setspecific(ulong key, void* value);
[Target(OS(Linux) || OS(Mac))]
extern int nanosleep(void* request, void* remaining);
[Target(OS(Linux) || OS(Mac))]
extern long sysconf(int name);
[Target(OS(Mac))]
extern int sysctlbyname(char* name, void* value, void* size, void* new_value, ulong new_size);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_mutex_init(void* mutex, void* attributes);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_mutex_destroy(void* mutex);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_mutex_lock(void* mutex);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_mutex_trylock(void* mutex);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_mutex_unlock(void* mutex);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_cond_init(void* condition, void* attributes);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_cond_destroy(void* condition);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_cond_wait(void* condition, void* mutex);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_cond_signal(void* condition);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_cond_broadcast(void* condition);
[Target(OS(Linux) || OS(Mac))]
extern int clock_gettime(int clock, void* time);
[Target(OS(Linux))]
extern int pthread_condattr_init(void* attributes);
[Target(OS(Linux))]
extern int pthread_condattr_setclock(void* attributes, int clock);
[Target(OS(Linux))]
extern int pthread_condattr_destroy(void* attributes);
[Target(OS(Linux))]
extern int pthread_cond_timedwait(void* condition, void* mutex, void* deadline);
[Target(OS(Mac))]
extern int pthread_cond_timedwait_relative_np(void* condition, void* mutex, void* timeout);

# ── Threads ──────────────────────────────────────────────────────────────────

# Starts a thread running `start(argument)`; its handle, or null on failure.
[Target(OS(Linux) || OS(Mac))]
export _async_sys_spawn(start: __ptr<void>, argument: __ptr<void>): __ptr<void> {
    __ptr<__ptr<void>> thread = _pep_malloc(8);
    var result = pthread_create(thread, __null, start, argument);
    __ptr<void> handle = thread[0];
    _pep_free(thread);
    if (result != 0) {
        return __null;
    }
    return handle;
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_join(handle: __ptr<void>) {
    pthread_join(handle, __null);
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_detach(handle: __ptr<void>) {
    pthread_detach(handle);
}

# The operating system's identity of the calling thread.
[Target(OS(Linux) || OS(Mac))]
export _async_sys_os_thread(): ulong {
    return pthread_self();
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_sleep(milliseconds: ulong) {
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
[Target(OS(Linux) || OS(Mac))]
export _async_sys_key_create(destructor: __ptr<void>): ulong {
    __ptr<ulong> key = _pep_malloc(8);
    if (pthread_key_create(key, destructor) != 0) {
        panic("ThreadLocal: the operating system has no thread-local keys left");
    }
    ulong created = key[0];
    _pep_free(key);
    return created;
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_key_delete(key: ulong) {
    pthread_key_delete(key);
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_key_get(key: ulong): __ptr<void> {
    return pthread_getspecific(key);
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_key_set(key: ulong, value: __ptr<void>) {
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
[Target(OS(Linux) || OS(Mac))]
export _async_sys_mutex_create(): __ptr<void> {
    var mutex = _pep_malloc(64);
    if (pthread_mutex_init(mutex, __null) != 0) {
        panic("Mutex: the operating system could not create a mutex");
    }
    return mutex;
}

# Destroys an unlocked mutex and frees its block.
[Target(OS(Linux) || OS(Mac))]
export _async_sys_mutex_destroy(mutex: __ptr<void>) {
    pthread_mutex_destroy(mutex);
    _pep_free(mutex);
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_mutex_lock(mutex: __ptr<void>) {
    pthread_mutex_lock(mutex);
}

# Locks `mutex` only if it is free; true if it is now held.
[Target(OS(Linux) || OS(Mac))]
export _async_sys_mutex_try_lock(mutex: __ptr<void>): bool {
    return pthread_mutex_trylock(mutex) == 0;
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_mutex_unlock(mutex: __ptr<void>) {
    pthread_mutex_unlock(mutex);
}

# A new condition variable. On Linux it times waits against the monotonic
# clock (CLOCK_MONOTONIC is 1), so a change to the wall clock cannot stretch
# or cut a timed wait.
[Target(OS(Linux))]
export _async_sys_condition_create(): __ptr<void> {
    var condition = _pep_malloc(64);
    var attributes = _pep_malloc(16);  # pthread_condattr_t: 4 bytes
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
[Target(OS(Mac))]
export _async_sys_condition_create(): __ptr<void> {
    var condition = _pep_malloc(64);
    if (pthread_cond_init(condition, __null) != 0) {
        panic("Condition: the operating system could not create a condition variable");
    }
    return condition;
}

# Destroys a condition variable no thread waits on and frees its block.
[Target(OS(Linux) || OS(Mac))]
export _async_sys_condition_destroy(condition: __ptr<void>) {
    pthread_cond_destroy(condition);
    _pep_free(condition);
}

# Unlocks `mutex` (held by the caller), sleeps until notified (or woken
# spuriously), and locks it again.
[Target(OS(Linux) || OS(Mac))]
export _async_sys_condition_wait(condition: __ptr<void>, mutex: __ptr<void>) {
    pthread_cond_wait(condition, mutex);
}

# Like `_async_sys_condition_wait`, for at most `milliseconds`; false if the
# time ran out. Waits past ~31 years are capped.
[Target(OS(Linux))]
export _async_sys_condition_wait_for(condition: __ptr<void>, mutex: __ptr<void>, milliseconds: ulong): bool {
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

[Target(OS(Mac))]
export _async_sys_condition_wait_for(condition: __ptr<void>, mutex: __ptr<void>, milliseconds: ulong): bool {
    var wait = milliseconds > 1000000000000 ? 1000000000000 : milliseconds;
    # A relative timeout: struct timespec { time_t tv_sec; long tv_nsec; }.
    __ptr<long> timeout = _pep_malloc(16);
    timeout[0] = (wait / 1000) as long;
    timeout[1] = ((wait % 1000) * 1000000) as long;
    var result = pthread_cond_timedwait_relative_np(condition, mutex, timeout);
    _pep_free(timeout);
    return result == 0;
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_condition_notify_one(condition: __ptr<void>) {
    pthread_cond_signal(condition);
}

[Target(OS(Linux) || OS(Mac))]
export _async_sys_condition_notify_all(condition: __ptr<void>) {
    pthread_cond_broadcast(condition);
}

# Milliseconds on a clock that only moves forward (CLOCK_MONOTONIC: 1 on
# Linux, 6 on macOS), for measuring timeouts.
[Target(OS(Linux))]
export _async_sys_monotonic_milliseconds(): ulong {
    return _async_monotonic_milliseconds(1);
}

[Target(OS(Mac))]
export _async_sys_monotonic_milliseconds(): ulong {
    return _async_monotonic_milliseconds(6);
}

[Target(OS(Linux) || OS(Mac))]
_async_monotonic_milliseconds(clock: int): ulong {
    __ptr<long> time = _pep_malloc(16);
    clock_gettime(clock, time);
    var milliseconds = (time[0] * 1000 + time[1] / 1000000) as ulong;
    _pep_free(time);
    return milliseconds;
}

# ── Processor counts (0 when unknown) ────────────────────────────────────────

# Online processors, capped by a cgroup CPU quota (`docker run --cpus`) the
# way Go and the JVM cap theirs: a quota of 1.5 processors counts as 2.
[Target(OS(Linux))]
export _async_sys_logical_cpus(): ulong {
    var count = sysconf(84);  # _SC_NPROCESSORS_ONLN
    if (count < 1) {
        return 0;
    }
    var online = count as ulong;
    var quota = _async_sys_cgroup_cpu_quota();
    return quota != 0 && quota < online ? quota : online;
}

# The smallest CPU quota on this process's cgroup or its ancestors, in whole
# processors rounded up, or 0 when none is set: cgroup v2's `cpu.max`
# ("max 100000" or "150000 100000"), or v1's `cpu.cfs_quota_us` (-1 when
# unlimited) over `cpu.cfs_period_us`.
[Target(OS(Linux))]
_async_sys_cgroup_cpu_quota(): ulong {
    ulong smallest = 0;
    for (var directory in _async_sys_cgroup_directories("cpu")) {
        long quota = -1;
        long period = 0;
        var v2 = io.File.read_to_string(io.Path(directory + "/cpu.max"));
        if (v2.is_ok()) {
            var fields = v2.value().trim().split(" ");
            if (fields.count == 2) {
                quota = long.parse(fields[0]).value_or(-1);
                period = long.parse(fields[1]).value_or(0);
            }
        } else {
            var v1 = io.File.read_to_string(io.Path(directory + "/cpu.cfs_quota_us"));
            var v1_period = io.File.read_to_string(io.Path(directory + "/cpu.cfs_period_us"));
            if (v1.is_ok() && v1_period.is_ok()) {
                quota = long.parse(v1.value().trim()).value_or(-1);
                period = long.parse(v1_period.value().trim()).value_or(0);
            }
        }
        if (quota > 0 && period > 0) {
            var processors = ((quota + period - 1) / period) as ulong;
            if (smallest == 0 || processors < smallest) {
                smallest = processors;
            }
        }
    }
    return smallest;
}

# The directories of this process's cgroup and each of its ancestors for
# `controller`, innermost first, read from /proc/self/cgroup: under
# /sys/fs/cgroup/<controller> when a cgroup v1 hierarchy has the controller,
# otherwise under the unified (v2) hierarchy at /sys/fs/cgroup. Empty
# outside any cgroup. Some may not exist: in a container without a cgroup
# namespace the path names the host's view, while the container sees its
# own cgroup at the root, which the walk reaches last. Callers skip the
# files they cannot read.
[Target(OS(Linux))]
export _async_sys_cgroup_directories(controller: String): String[] {
    var directories = Array<String>();
    var table = io.File.read_to_string(io.Path("/proc/self/cgroup"));
    if (!table.is_ok()) {
        return directories;
    }
    var root = String();
    var path = String();
    for (var line in table.value().lines()) {
        # hierarchy-ID:controller-list:cgroup-path
        var fields = line.split(":");
        if (fields.count < 3) {
            continue;
        }
        # The path may itself hold ':'.
        var rest = line.substr_bytes(
            fields[0].size + fields[1].size + 2, line.size - fields[0].size - fields[1].size - 2
        );
        if (fields[0] == "0" && fields[1].is_empty) {
            if (root.is_empty) {
                root = "/sys/fs/cgroup";
                path = rest;
            }
        } else {
            for (var name in fields[1].split(",")) {
                if (name == controller) {
                    root = "/sys/fs/cgroup/" + controller;
                    path = rest;
                }
            }
        }
    }
    if (root.is_empty) {
        return directories;
    }
    while (true) {
        while (path.ends_with("/")) {
            path = path.substr_bytes(0, path.size - 1);
        }
        directories.append(root + path);
        if (path.is_empty) {
            break;
        }
        var slash = path.rfind("/");
        path = slash < 0 ? String() : path.substr_bytes(0, slash as ulong);
    }
    return directories;
}

# One core per distinct list of hardware threads sharing it, read from the
# topology of every configured CPU (offline CPUs have none).
[Target(OS(Linux))]
export _async_sys_physical_cpus(): ulong {
    var configured = sysconf(83);  # _SC_NPROCESSORS_CONF
    var cores = HashSet<String>();
    var cpu: long = 0;
    while (cpu < configured) {
        var topology = $"/sys/devices/system/cpu/cpu{cpu}/topology/";
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
    return cores.count as ulong;
}

[Target(OS(Mac))]
export _async_sys_logical_cpus(): ulong {
    __ptr<int> value = _pep_malloc(4);
    __ptr<ulong> size = _pep_malloc(8);
    size[0] = 4;
    var result = sysctlbyname("hw.logicalcpu", value, size, __null, 0);
    int count = value[0];
    _pep_free(value);
    _pep_free(size);
    return result != 0 || count < 1 ? 0 : count as ulong;
}

[Target(OS(Mac))]
export _async_sys_physical_cpus(): ulong {
    __ptr<int> value = _pep_malloc(4);
    __ptr<ulong> size = _pep_malloc(8);
    size[0] = 4;
    var result = sysctlbyname("hw.physicalcpu", value, size, __null, 0);
    int count = value[0];
    _pep_free(value);
    _pep_free(size);
    return result != 0 || count < 1 ? 0 : count as ulong;
}
