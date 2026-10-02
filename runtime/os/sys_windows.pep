# Windows platform layer for os: the same `_os_sys_*` functions as
# sys_posix.pep. Text crosses the Windows API as UTF-16 (the `W` functions)
# and is converted to UTF-8 with io's helpers.

import io;
import "machine";
import "user";

[Target(OS(Windows))]
extern uint GetEnvironmentVariableW(ushort* name, ushort* buffer, uint size);
[Target(OS(Windows))]
extern ushort* GetEnvironmentStringsW();
[Target(OS(Windows))]
extern int FreeEnvironmentStringsW(ushort* block);
[Target(OS(Windows))]
extern uint GetLastError();
[Target(OS(Windows))]
extern void SetLastError(uint code);
[Target(OS(Windows))]
extern int QueryPerformanceCounter(long* count);
[Target(OS(Windows))]
extern int QueryPerformanceFrequency(long* frequency);
[Target(OS(Windows))]
extern void GetSystemTimePreciseAsFileTime(void* time);
[Target(OS(Windows))]
extern int GetComputerNameExW(int format, ushort* buffer, uint* size);
[Target(OS(Windows))]
extern int GlobalMemoryStatusEx(void* status);
[Target(OS(Windows))]
extern void GetSystemInfo(void* info);
[Target(OS(Windows))]
[Link("ntdll")]
extern int RtlGetVersion(void* info);
[Target(OS(Windows))]
[Link("advapi32")]
extern int GetUserNameW(ushort* buffer, uint* size);

# ── Environment ──────────────────────────────────────────────────────────────

[Target(OS(Windows))]
export _os_sys_environment(name: String): String? {
    var wide_name = io._io_win_wide(name);
    uint capacity = 256;
    var found = Optional<String>.none();
    while (true) {
        __ptr<u16> buffer = _pep_malloc((capacity as ulong) * 2);
        # An empty value also returns 0, without setting an error.
        SetLastError(0);
        var length = GetEnvironmentVariableW(wide_name, buffer, capacity);
        if (length == 0) {
            if (GetLastError() != 203) {  # ERROR_ENVVAR_NOT_FOUND
                found = Optional<String>.some(String());
            }
            _pep_free(buffer);
            break;
        }
        if (length < capacity) {
            found = Optional<String>.some(io._io_win_narrow(buffer, length as int));
            _pep_free(buffer);
            break;
        }
        # Too small: `length` is the size needed, its NUL included.
        _pep_free(buffer);
        capacity = length;
    }
    _pep_free(wide_name);
    return found;
}

[Target(OS(Windows))]
export _os_sys_environment_entries(): Array<String> {
    var entries = Array<String>();
    var block = GetEnvironmentStringsW();
    if (block == __null) {
        return entries;
    }
    # NAME=VALUE strings, each NUL-terminated, then an empty one.
    var start = 0;
    while (block[start] != 0) {
        var length = io._io_win_wide_len(block + start);
        entries.append(io._io_win_narrow(block + start, length));
        start = start + length + 1;
    }
    FreeEnvironmentStringsW(block);
    return entries;
}

# ── Clocks ───────────────────────────────────────────────────────────────────

[Target(OS(Windows))]
export _os_sys_monotonic_nanoseconds(): ulong {
    __ptr<long> value = _pep_malloc(8);
    QueryPerformanceFrequency(value);
    var frequency = value[0] as ulong;
    QueryPerformanceCounter(value);
    var count = value[0] as ulong;
    _pep_free(value);
    # Split, so count * 10^9 cannot overflow.
    return (count / frequency) * 1000000000 + (count % frequency) * 1000000000 / frequency;
}

# A FILETIME counts 100-nanosecond ticks since 1601-01-01 UTC.
[Target(OS(Windows))]
export _os_sys_system_nanoseconds(): long {
    __ptr<long> value = _pep_malloc(8);
    GetSystemTimePreciseAsFileTime(value);
    var ticks = value[0];
    _pep_free(value);
    return (ticks - 116444736000000000) * 100;
}

# ── Machine ──────────────────────────────────────────────────────────────────

[Target(OS(Windows))]
export _os_sys_os(): OperatingSystem {
    return OperatingSystem.Windows;
}

# RTL_OSVERSIONINFOW: its size, then the major, minor and build numbers
# (276 bytes in all). GetVersionEx would report the version the program's
# manifest claims, not the system's.
[Target(OS(Windows))]
export _os_sys_version(): String {
    __ptr<uint> info = _pep_malloc(276);
    info[0] = 276;
    var version = String();
    if (RtlGetVersion(info) == 0) {
        version = $"{info[1]}.{info[2]}.{info[3]}";
    }
    _pep_free(info);
    return version;
}

[Target(OS(Windows))]
export _os_sys_hostname(): String {
    __ptr<uint> size = _pep_malloc(4);
    size[0] = 0;
    # ComputerNameDnsHostname. Asking with no buffer reports the size
    # needed, its NUL included.
    GetComputerNameExW(1, __null, size);
    var name = String();
    if (size[0] > 0) {
        __ptr<u16> buffer = _pep_malloc((size[0] as ulong) * 2);
        if (GetComputerNameExW(1, buffer, size) != 0) {
            name = io._io_win_narrow(buffer, size[0] as int);
        }
        _pep_free(buffer);
    }
    _pep_free(size);
    return name;
}

# MEMORYSTATUSEX: dwLength, dwMemoryLoad, then ullTotalPhys at byte 8
# (64 bytes in all).
[Target(OS(Windows))]
export _os_sys_total_memory(): ulong {
    __ptr<uint> status = _pep_malloc(64);
    status[0] = 64;
    var bytes: ulong = 0;
    if (GlobalMemoryStatusEx(status) != 0) {
        __ptr<ulong> fields = unsafe_cast<__ptr<ulong>>(status);
        bytes = fields[1];
    }
    _pep_free(status);
    return bytes;
}

# SYSTEM_INFO: two 16-bit fields, then dwPageSize at byte 4 (48 bytes in
# all on 64-bit Windows).
[Target(OS(Windows))]
export _os_sys_page_size(): ulong {
    __ptr<uint> info = _pep_malloc(48);
    GetSystemInfo(info);
    var size = info[1] as ulong;
    _pep_free(info);
    return size;
}

# ── User ─────────────────────────────────────────────────────────────────────

[Target(OS(Windows))]
export _os_sys_user_name(): String? {
    __ptr<uint> size = _pep_malloc(4);
    size[0] = 257;  # UNLEN + 1
    __ptr<u16> buffer = _pep_malloc(514);
    var found = Optional<String>.none();
    # On success `size` counts the NUL too.
    if (GetUserNameW(buffer, size) != 0 && size[0] > 1) {
        found = Optional<String>.some(io._io_win_narrow(buffer, (size[0] - 1) as int));
    }
    _pep_free(buffer);
    _pep_free(size);
    if (found.is_some()) {
        return found;
    }
    return _os_nonempty_environment("USERNAME");
}

[Target(OS(Windows))]
export _os_sys_home_directory(): String? {
    return _os_nonempty_environment("USERPROFILE");
}
