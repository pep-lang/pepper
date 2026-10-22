# POSIX (Linux, macOS) platform layer for os. Every declaration carries
# [Target(OS(Linux) || OS(Mac))] or a narrower target; sys_windows.pep declares the
# same `_os_sys_*` functions with the same signatures for Windows.

import async;
import io;
import "machine";
import "user";

[Target(OS(Linux) || OS(Mac))]
extern char* getenv(char* name);
[Target(OS(Linux) || OS(Mac))]
extern int setenv(char* name, char* value, int overwrite);
[Target(OS(Linux) || OS(Mac))]
extern int unsetenv(char* name);
[Target(OS(Linux))]
extern void* dlsym(void* handle, char* name);
[Target(OS(Mac))]
extern void* _NSGetEnviron();
[Target(OS(Linux) || OS(Mac))]
extern int clock_gettime(int clock, void* time);
[Target(OS(Linux) || OS(Mac))]
extern int gethostname(char* name, ulong size);
[Target(OS(Linux) || OS(Mac))]
extern int uname(void* name);
[Target(OS(Linux) || OS(Mac))]
extern long sysconf(int name);
[Target(OS(Mac))]
extern int sysctlbyname(char* name, void* value, void* size, void* new_value, ulong new_size);
[Target(OS(Linux) || OS(Mac))]
extern int getrusage(int who, void* usage);
[Target(OS(Linux) || OS(Mac))]
extern uint geteuid();
[Target(OS(Linux) || OS(Mac))]
extern int getpwuid_r(uint uid, void* entry, char* buffer, ulong size, void* result);

# ── Environment ──────────────────────────────────────────────────────────────

[Target(OS(Linux) || OS(Mac))]
_os_sys_environment(name: String): String? {
    # Under `_os_environment_lock`, as setenv and unsetenv are.
    __ptr<char> value = getenv(name.c_str());
    if (value == __null) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(String(value));
}

[Target(OS(Linux) || OS(Mac))]
_os_sys_set_environment(name: String, value: String) {
    if (setenv(name.c_str(), value.c_str(), 1) != 0) {
        panic($"cannot set environment variable '{name}': out of memory");
    }
}

[Target(OS(Linux) || OS(Mac))]
_os_sys_remove_environment(name: String) {
    unsetenv(name.c_str());
}

# The `environ` array: NAME=VALUE strings, null-terminated.
[Target(OS(Linux))]
export _os_environ(): __ptr<__ptr<char>> {
    # `environ` is a variable, which an extern cannot name; dlsym finds it
    # (RTLD_DEFAULT is null on glibc).
    var name = "environ";
    __ptr<__ptr<__ptr<char>>> slot = dlsym(__null, name.c_str());
    if (slot == __null) {
        return __null;
    }
    return slot[0];
}

[Target(OS(Mac))]
export _os_environ(): __ptr<__ptr<char>> {
    __ptr<__ptr<__ptr<char>>> slot = _NSGetEnviron();
    return slot[0];
}

[Target(OS(Linux) || OS(Mac))]
_os_sys_environment_entries(): Array<String> {
    var entries = Array<String>();
    var values = _os_environ();
    if (values == __null) {
        return entries;
    }
    ulong index = 0;
    while (values[index] != __null) {
        entries.append(String(values[index]));
        index = index + 1;
    }
    return entries;
}

# ── Clocks ───────────────────────────────────────────────────────────────────

# CLOCK_MONOTONIC: 1 on Linux, 6 on macOS (as async's timeouts use).
[Target(OS(Linux))]
_os_sys_monotonic_nanoseconds(): ulong {
    return _os_clock_nanoseconds(1) as ulong;
}

[Target(OS(Mac))]
_os_sys_monotonic_nanoseconds(): ulong {
    return _os_clock_nanoseconds(6) as ulong;
}

# CLOCK_REALTIME is 0 on both.
[Target(OS(Linux) || OS(Mac))]
_os_sys_system_nanoseconds(): long {
    return _os_clock_nanoseconds(0);
}

[Target(OS(Linux) || OS(Mac))]
_os_clock_nanoseconds(clock: int): long {
    # struct timespec { time_t tv_sec; long tv_nsec; }
    __ptr<long> time = _pep_malloc(16);
    clock_gettime(clock, time);
    var nanoseconds = time[0] * 1000000000 + time[1];
    _pep_free(time);
    return nanoseconds;
}

# ── Machine ──────────────────────────────────────────────────────────────────

[Target(OS(Linux) && !OS(Android))]
_os_sys_os(): OperatingSystem {
    return OperatingSystem.Linux;
}

[Target(OS(Android))]
_os_sys_os(): OperatingSystem {
    return OperatingSystem.Android;
}

[Target(OS(Mac) && !OS(IOS))]
_os_sys_os(): OperatingSystem {
    return OperatingSystem.Mac;
}

[Target(OS(IOS))]
_os_sys_os(): OperatingSystem {
    return OperatingSystem.IOS;
}

# The release field of struct utsname: six 65-byte fields on Linux, release
# the third.
[Target(OS(Linux))]
_os_sys_version(): String {
    __ptr<char> fields = _pep_malloc(390);
    var version = uname(fields) == 0 ? String(fields + 130) : String();
    _pep_free(fields);
    return version;
}

[Target(OS(Mac))]
_os_sys_version(): String {
    return _os_sysctl_string("kern.osproductversion");
}

[Target(OS(Mac))]
_os_sysctl_string(name: String): String {
    __ptr<ulong> size = _pep_malloc(8);
    size[0] = 0;
    var text = String();
    if (sysctlbyname(name.c_str(), __null, size, __null, 0) == 0 && size[0] > 0) {
        __ptr<char> buffer = _pep_malloc(size[0]);
        if (sysctlbyname(name.c_str(), buffer, size, __null, 0) == 0) {
            text = String(buffer);
        }
        _pep_free(buffer);
    }
    _pep_free(size);
    return text;
}

[Target(OS(Linux) || OS(Mac))]
_os_sys_hostname(): String {
    # HOST_NAME_MAX is 64 on Linux and 255 on macOS; the last byte stays NUL
    # in case the name was cut short.
    __ptr<char> buffer = _pep_malloc(257);
    buffer[256] = 0;
    var name = gethostname(buffer, 256) == 0 ? String(buffer) : String();
    _pep_free(buffer);
    return name;
}

# _SC_PHYS_PAGES pages of _SC_PAGESIZE bytes, or less when a cgroup memory
# limit on this process's cgroup or an ancestor is lower: v2's `memory.max`
# ("max" when unlimited) or v1's `memory.limit_in_bytes` (a huge number when
# unlimited), as the JVM reads them.
[Target(OS(Linux))]
_os_sys_total_memory(): ulong {
    var pages = sysconf(85);
    ulong bytes = pages < 1 ? 0 : (pages as ulong) * _os_sys_page_size();
    for (var directory in async._async_sys_cgroup_directories("memory")) {
        var limit = io.File.read_to_string(io.Path(directory + "/memory.max"));
        if (!limit.is_ok()) {
            limit = io.File.read_to_string(io.Path(directory + "/memory.limit_in_bytes"));
        }
        if (limit.is_ok()) {
            var value = long.parse(limit.value().trim()).value_or(0);
            if (value > 0 && (bytes == 0 || (value as ulong) < bytes)) {
                bytes = value as ulong;
            }
        }
    }
    return bytes;
}

[Target(OS(Mac))]
_os_sys_total_memory(): ulong {
    __ptr<ulong> value = _pep_malloc(8);
    __ptr<ulong> size = _pep_malloc(8);
    value[0] = 0;
    size[0] = 8;
    var result = sysctlbyname("hw.memsize", value, size, __null, 0);
    var bytes = result == 0 ? value[0] : 0;
    _pep_free(value);
    _pep_free(size);
    return bytes;
}

# RUSAGE_SELF's struct rusage: two timevals, then ru_maxrss at byte 32 (144
# bytes in all), in kilobytes on Linux.
[Target(OS(Linux))]
_os_sys_peak_memory(): ulong {
    return _os_sys_max_rss() * 1024;
}

# macOS gives ru_maxrss in bytes.
[Target(OS(Mac))]
_os_sys_peak_memory(): ulong {
    return _os_sys_max_rss();
}

[Target(OS(Linux) || OS(Mac))]
_os_sys_max_rss(): ulong {
    __ptr<long> usage = _pep_malloc(144);
    var peak = getrusage(0, usage) == 0 && usage[4] > 0 ? usage[4] as ulong : 0;
    _pep_free(usage);
    return peak;
}

# _SC_PAGESIZE: 30 on Linux, 29 on macOS.
[Target(OS(Linux))]
_os_sys_page_size(): ulong {
    return sysconf(30) as ulong;
}

[Target(OS(Mac))]
_os_sys_page_size(): ulong {
    return sysconf(29) as ulong;
}

# ── User ─────────────────────────────────────────────────────────────────────

# struct passwd starts with pw_name on both systems; pw_dir is at 32 on
# Linux and 48 on macOS (after pw_change and pw_class).
[Target(OS(Linux))]
const PASSWD_DIRECTORY_FIELD: ulong = 4;

[Target(OS(Mac))]
const PASSWD_DIRECTORY_FIELD: ulong = 6;

# The effective user's entry in the user database: field 0 is pw_name, and
# `field` picks another pointer-sized field. Empty when there is no entry.
[Target(OS(Linux) || OS(Mac))]
_os_passwd_field(field: ulong): String? {
    __ptr<__ptr<char>> entry = _pep_malloc(128);  # struct passwd: 48 or 72 bytes
    __ptr<__ptr<char>> result = _pep_malloc(8);
    ulong size = 1024;
    var found = Optional<String>.Empty;
    while (true) {
        __ptr<char> buffer = _pep_malloc(size);
        result[0] = __null;
        var error = getpwuid_r(geteuid(), entry, buffer, size, result);
        if (error == 34 && size < 1048576) {  # ERANGE: the buffer is too small
            _pep_free(buffer);
            size = size * 2;
            continue;
        }
        if (error == 0 && result[0] != __null && entry[field] != __null) {
            found = Optional<String>.Value(String(entry[field]));
        }
        _pep_free(buffer);
        break;
    }
    _pep_free(result);
    _pep_free(entry);
    return found;
}

[Target(OS(Linux) || OS(Mac))]
_os_sys_user_name(): String? {
    var name = _os_passwd_field(0);
    if (name.is_value() && !name.value().is_empty) {
        return name;
    }
    return _os_nonempty_environment("USER");
}

[Target(OS(Linux) || OS(Mac))]
_os_sys_is_elevated(): bool {
    return geteuid() == 0;
}

[Target(OS(Linux) || OS(Mac))]
_os_sys_home_directory(): String? {
    var home = _os_nonempty_environment("HOME");
    if (home.is_value()) {
        return home;
    }
    return _os_passwd_field(PASSWD_DIRECTORY_FIELD);
}
