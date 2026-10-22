# WASI (WebAssembly) platform layer for os: the same `_os_sys_*` functions
# as sys_posix.pep and sys_windows.pep, each with [Target(OS(Wasi))]. WASI
# preview 1 has environment variables and clocks; it has no host name,
# user database, or memory and version queries, so those report nothing.

import "machine";
import "user";

[Target(OS(Wasi))]
extern char* getenv(char* name);
[Target(OS(Wasi))]
extern int setenv(char* name, char* value, int overwrite);
[Target(OS(Wasi))]
extern int unsetenv(char* name);
[Target(OS(Wasi))]
extern void* __wasilibc_get_environ();
[Target(OS(Wasi))]
extern ushort __wasi_clock_time_get(uint id, u64 precision, void* time);

# ── Environment ──────────────────────────────────────────────────────────────

[Target(OS(Wasi))]
_os_sys_environment(name: String): String? {
    __ptr<char> value = getenv(name.c_str());
    if (value == __null) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(String(value));
}

# wasi-libc keeps the environment in the program's memory: a change stays
# inside the program.
[Target(OS(Wasi))]
_os_sys_set_environment(name: String, value: String) {
    if (setenv(name.c_str(), value.c_str(), 1) != 0) {
        panic($"cannot set environment variable '{name}': out of memory");
    }
}

[Target(OS(Wasi))]
_os_sys_remove_environment(name: String) {
    unsetenv(name.c_str());
}

# The `environ` array: NAME=VALUE strings, null-terminated. wasi-libc
# fills it from `environ_get` on first use.
[Target(OS(Wasi))]
export _os_environ(): __ptr<__ptr<char>> {
    return __wasilibc_get_environ();
}

[Target(OS(Wasi))]
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

# WASI's clock ids: 0 is the wall clock, 1 the monotonic clock. The time
# is a 64-bit count of nanoseconds.
[Target(OS(Wasi))]
_os_clock_nanoseconds(clock: uint): u64 {
    __ptr<u64> time = _pep_malloc(8);
    time[0] = 0;
    __wasi_clock_time_get(clock, 1, time);
    var nanoseconds = time[0];
    _pep_free(time);
    return nanoseconds;
}

[Target(OS(Wasi))]
_os_sys_monotonic_nanoseconds(): ulong {
    return _os_clock_nanoseconds(1);
}

[Target(OS(Wasi))]
_os_sys_system_nanoseconds(): long {
    return _os_clock_nanoseconds(0) as long;
}

# ── Machine ──────────────────────────────────────────────────────────────────

[Target(OS(Wasi))]
_os_sys_os(): OperatingSystem {
    return OperatingSystem.Wasi;
}

[Target(OS(Wasi))]
_os_sys_version(): String {
    return String();
}

[Target(OS(Wasi))]
_os_sys_hostname(): String {
    return String();
}

[Target(OS(Wasi))]
_os_sys_total_memory(): ulong {
    return 0;
}

[Target(OS(Wasi))]
_os_sys_peak_memory(): ulong {
    return 0;
}

# WebAssembly's page: linear memory grows 64 KiB at a time.
[Target(OS(Wasi))]
_os_sys_page_size(): ulong {
    return 65536;
}

# ── User ─────────────────────────────────────────────────────────────────────

[Target(OS(Wasi))]
_os_sys_user_name(): String? {
    return _os_nonempty_environment("USER");
}

[Target(OS(Wasi))]
_os_sys_is_elevated(): bool {
    return false;
}

[Target(OS(Wasi))]
_os_sys_home_directory(): String? {
    return _os_nonempty_environment("HOME");
}
