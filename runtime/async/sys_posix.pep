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
extern int pthread_attr_init(void* attributes);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_attr_setstacksize(void* attributes, ulong size);
[Target(OS(Linux) || OS(Mac))]
extern int pthread_attr_destroy(void* attributes);
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
extern void* malloc(ulong size);
[Target(OS(Linux) || OS(Mac))]
extern void free(void* pointer);
[Target(OS(Linux) || OS(Mac))]
extern int nanosleep(void* request, void* remaining);
[Target(OS(Linux) || OS(Mac))]
extern long sysconf(int name);
# sysconf's names: glibc's, and bionic's, which numbers them its own way.
[Target(OS(Linux) && !OS(Android))]
const _SC_NPROCESSORS_CONF = 83;
[Target(OS(Linux) && !OS(Android))]
const _SC_NPROCESSORS_ONLN = 84;
[Target(OS(Android))]
const _SC_NPROCESSORS_CONF = 96;
[Target(OS(Android))]
const _SC_NPROCESSORS_ONLN = 97;
[Target(OS(Mac))]
extern int sysctlbyname(char* name, void* value, void* size, void* new_value, ulong new_size);
[Target(OS(Linux) || OS(Mac))]
extern int clock_gettime(int clock, void* time);
[Target(OS(Linux))]
extern long syscall(long number, ...);
[Target(OS(Linux) && !OS(Android))]
extern int* __errno_location();
[Target(OS(Android))]
extern int* __errno();
[Target(OS(Mac))]
extern int __ulock_wait(uint operation, void* address, ulong value, uint timeout);
[Target(OS(Mac))]
extern int __ulock_wake(uint operation, void* address, ulong wake_value);

# ── Threads ──────────────────────────────────────────────────────────────────

# Starts a thread running `start(argument)` with a stack of `stack_size`
# bytes, rounded up to 64 KiB (0: the system's default, usually 8 MiB on
# Linux and 512 KiB on macOS); its handle, or null on failure.
[Target(OS(Linux) || OS(Mac))]
_async_sys_spawn(start: __ptr<void>, argument: __ptr<void>, stack_size: ulong): __ptr<void> {
    # A pthread_attr_t: 56 or 64 bytes on the targets supported.
    __ptr<void> attributes = __null;
    if (stack_size > 0) {
        attributes = _pep_malloc(128);
        pthread_attr_init(attributes);
        # macOS takes only whole pages (16 KiB on arm64). A size refused
        # fails the spawn rather than leaving the thread the default stack.
        if (pthread_attr_setstacksize(attributes, (stack_size + 65535) / 65536 * 65536) != 0) {
            pthread_attr_destroy(attributes);
            _pep_free(attributes);
            return __null;
        }
    }
    __ptr<__ptr<void>> thread = _pep_malloc(8);
    var result = pthread_create(thread, attributes, start, argument);
    if (attributes != __null) {
        pthread_attr_destroy(attributes);
        _pep_free(attributes);
    }
    __ptr<void> handle = thread[0];
    _pep_free(thread);
    if (result != 0) {
        return __null;
    }
    return handle;
}

[Target(OS(Linux) || OS(Mac))]
_async_sys_join(handle: __ptr<void>) {
    pthread_join(handle, __null);
}

[Target(OS(Linux) || OS(Mac))]
_async_sys_detach(handle: __ptr<void>) {
    pthread_detach(handle);
}

# The operating system's identity of the calling thread.
[Target(OS(Linux) || OS(Mac))]
_async_sys_os_thread(): ulong {
    return pthread_self();
}

[Target(OS(Linux) || OS(Mac))]
_async_sys_sleep(milliseconds: ulong) {
    # struct timespec { time_t tv_sec; long tv_nsec; }. From C's malloc, so
    # a thread asleep does not hold a live allocation that a leak check
    # would count (a test's timeout watchdog sleeps through the test).
    __ptr<long> time = malloc(16);
    time[0] = (milliseconds / 1000) as long;
    time[1] = ((milliseconds % 1000) * 1000000) as long;
    # Interrupted by a signal: sleep again for the time that was left, which
    # nanosleep wrote back. The request is always valid, so no other error
    # can repeat.
    while (nanosleep(time, time) != 0) {}
    free(time);
}

# ── Thread-local keys ────────────────────────────────────────────────────────

# A new key whose `destructor(value)` runs on each exiting thread with a
# non-null value.
[Target(OS(Linux) || OS(Mac))]
_async_sys_key_create(destructor: __ptr<void>): ulong {
    __ptr<ulong> key = _pep_malloc(8);
    if (pthread_key_create(key, destructor) != 0) {
        panic("ThreadLocal: the operating system has no thread-local keys left");
    }
    ulong created = key[0];
    _pep_free(key);
    return created;
}

[Target(OS(Linux) || OS(Mac))]
_async_sys_key_delete(key: ulong) {
    pthread_key_delete(key);
}

[Target(OS(Linux) || OS(Mac))]
_async_sys_key_get(key: ulong): __ptr<void> {
    return pthread_getspecific(key);
}

[Target(OS(Linux) || OS(Mac))]
_async_sys_key_set(key: ulong, value: __ptr<void>) {
    pthread_setspecific(key, value);
}

# ── Waiting on an address ────────────────────────────────────────────────────
#
# The futex calls that lock.pep builds mutexes and condition variables on:
# a thread sleeps while a 4-byte word holds the value it expects, until
# another thread wakes it through the word's address. Linux has `futex`;
# macOS has `__ulock_wait` / `__ulock_wake`, which every macOS since 10.12
# has (libc++'s `std::atomic::wait` uses them; `os_sync_wait_on_address`,
# from 14.4, would need a weak import the compiler cannot declare).

# The `futex` system call's number: x86-64 and AArch64 differ.
[Target(OS(Linux) && Arch(x64))]
const _SYS_FUTEX = 202;
[Target(OS(Linux) && Arch(aarch64))]
const _SYS_FUTEX = 98;

# FUTEX_WAIT | FUTEX_PRIVATE_FLAG and FUTEX_WAKE | FUTEX_PRIVATE_FLAG: the
# word is never shared with another process.
const _FUTEX_WAIT_PRIVATE = 128;
const _FUTEX_WAKE_PRIVATE = 129;

# UL_COMPARE_AND_WAIT | ULF_NO_ERRNO (errors come back negated), and the
# same with ULF_WAKE_ALL.
const _ULOCK_COMPARE_AND_WAIT: uint = 16777217;
const _ULOCK_WAKE_ALL: uint = 16777473;

# Sleeps while `word` holds `expected`, until woken (or spuriously).
[Target(OS(Linux))]
_async_sys_futex_wait(word: __ptr<uint>, expected: uint) {
    syscall(_SYS_FUTEX, word, _FUTEX_WAIT_PRIVATE as long, expected as long, 0 as long, 0 as long, 0 as long);
}

# Like `_async_sys_futex_wait`, for at most `milliseconds`; false if the time
# ran out. Waits past ~31 years are capped.
[Target(OS(Linux))]
_async_sys_futex_wait_for(word: __ptr<uint>, expected: uint, milliseconds: ulong): bool {
    var wait = milliseconds > 1000000000000 ? 1000000000000 : milliseconds;
    # A relative timeout on the monotonic clock: struct timespec
    # { time_t tv_sec; long tv_nsec; }.
    __ptr<long> timeout = _pep_malloc(16);
    timeout[0] = (wait / 1000) as long;
    timeout[1] = ((wait % 1000) * 1000000) as long;
    var result = syscall(
        _SYS_FUTEX, word, _FUTEX_WAIT_PRIVATE as long, expected as long, timeout, 0 as long, 0 as long
    );
    _pep_free(timeout);
    return result == 0 || _async_errno() != 110;  # ETIMEDOUT
}

# Wakes one thread sleeping on `word`, if any.
[Target(OS(Linux))]
_async_sys_futex_wake_one(word: __ptr<uint>) {
    syscall(_SYS_FUTEX, word, _FUTEX_WAKE_PRIVATE as long, 1 as long);
}

# Wakes every thread sleeping on `word`.
[Target(OS(Linux))]
_async_sys_futex_wake_all(word: __ptr<uint>) {
    syscall(_SYS_FUTEX, word, _FUTEX_WAKE_PRIVATE as long, 2147483647 as long);
}

[Target(OS(Linux) && !OS(Android))]
_async_errno(): int {
    return __errno_location()[0];
}

[Target(OS(Android))]
_async_errno(): int {
    return __errno()[0];
}

[Target(OS(Mac))]
_async_sys_futex_wait(word: __ptr<uint>, expected: uint) {
    __ulock_wait(_ULOCK_COMPARE_AND_WAIT, word, expected as ulong, 0);  # 0: no timeout
}

# The timeout is in microseconds, a 32-bit count in which 0 means forever:
# a longer wait is cut to ~71 minutes and reports a wake when it ends.
[Target(OS(Mac))]
_async_sys_futex_wait_for(word: __ptr<uint>, expected: uint, milliseconds: ulong): bool {
    var capped = milliseconds > 4294967;
    var microseconds = capped ? 4294967000 : milliseconds * 1000;
    if (microseconds == 0) {
        microseconds = 1;
    }
    var result = __ulock_wait(_ULOCK_COMPARE_AND_WAIT, word, expected as ulong, microseconds as uint);
    return result != -60 || capped;  # -ETIMEDOUT
}

[Target(OS(Mac))]
_async_sys_futex_wake_one(word: __ptr<uint>) {
    __ulock_wake(_ULOCK_COMPARE_AND_WAIT, word, 0);
}

[Target(OS(Mac))]
_async_sys_futex_wake_all(word: __ptr<uint>) {
    __ulock_wake(_ULOCK_WAKE_ALL, word, 0);
}

# Milliseconds on a clock that only moves forward (CLOCK_MONOTONIC: 1 on
# Linux, 6 on macOS), for measuring timeouts.
[Target(OS(Linux))]
_async_sys_monotonic_milliseconds(): ulong {
    return _async_monotonic_milliseconds(1);
}

[Target(OS(Mac))]
_async_sys_monotonic_milliseconds(): ulong {
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
_async_sys_logical_cpus(): ulong {
    var count = sysconf(_SC_NPROCESSORS_ONLN);
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
_async_sys_physical_cpus(): ulong {
    var configured = sysconf(_SC_NPROCESSORS_CONF);
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
_async_sys_logical_cpus(): ulong {
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
_async_sys_physical_cpus(): ulong {
    __ptr<int> value = _pep_malloc(4);
    __ptr<ulong> size = _pep_malloc(8);
    size[0] = 4;
    var result = sysctlbyname("hw.physicalcpu", value, size, __null, 0);
    int count = value[0];
    _pep_free(value);
    _pep_free(size);
    return result != 0 || count < 1 ? 0 : count as ulong;
}
