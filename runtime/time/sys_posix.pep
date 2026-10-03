# POSIX (Linux, macOS) platform layer for time: the local zone through the C
# library's localtime_r, and named zones from the TZif files of the system's
# database. sys_windows.pep and sys_wasi.pep declare the same `_time_sys_*`
# functions.

import os;
import "zone";

[Target(OS(Linux) || OS(Mac))]
extern void* localtime_r(long* time, void* result);

# The local offset at `seconds`: struct tm's tm_gmtoff, the long after its
# nine ints (byte 40) in glibc, musl, bionic and Darwin alike.
[Target(OS(Linux) || OS(Mac))]
export _time_sys_local_offset(seconds: long): int {
    __ptr<long> time = _pep_malloc(8);
    time[0] = seconds;
    __ptr<long> parts = _pep_malloc(64);
    var offset = 0;
    if (localtime_r(time, parts) != __null) {
        offset = parts[5] as int;
    }
    _pep_free(parts);
    _pep_free(time);
    return offset;
}

[Target(OS(Linux) || OS(Mac))]
export _time_sys_named(name: String): Result<TimeZone> {
    return _time_zone_from_database(name, os.environment("TZDIR").value_or("/usr/share/zoneinfo"));
}

# ICU is only used on Windows.
[Target(OS(Linux) || OS(Mac))]
export _time_sys_icu_offset(name: String, seconds: long): int {
    return 0;
}
