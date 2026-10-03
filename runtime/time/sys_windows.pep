# Windows platform layer for time: the local zone through
# SystemTimeToTzSpecificLocalTime, and named (IANA) zones through the ICU
# that Windows 10 version 1903 and later ship as icu.dll.

import os;
import "civil";
import "zone";

[Target(OS(Windows))]
extern int SystemTimeToTzSpecificLocalTime(void* zone, ushort* universal, ushort* local);
[Target(OS(Windows))]
[Link("icu")]
extern void* ucal_open(ushort* zone, int length, char* locale, int calendar_type, int* status);
[Target(OS(Windows))]
[Link("icu")]
extern void ucal_setMillis(void* calendar, double milliseconds, int* status);
[Target(OS(Windows))]
[Link("icu")]
extern int ucal_get(void* calendar, int field, int* status);
[Target(OS(Windows))]
[Link("icu")]
extern void ucal_close(void* calendar);
[Target(OS(Windows))]
[Link("icu")]
extern int ucal_getCanonicalTimeZoneID(
    ushort* id, int length, ushort* result, int capacity, char* is_system, int* status
);

# SYSTEMTIME reaches the years 1601 to 30827.
const FIRST_SECOND: long = -11644473600;
const LAST_SECOND: long = 910692730000;

# The local offset at `seconds`: SYSTEMTIME in UTC through the zone in
# Windows' settings, and the difference read back.
[Target(OS(Windows))]
export _time_sys_local_offset(seconds: long): int {
    var clamped = seconds < FIRST_SECOND ? FIRST_SECOND : (seconds > LAST_SECOND ? LAST_SECOND : seconds);
    var universal = DateTime.from_unix_seconds(clamped);
    # wYear, wMonth, wDayOfWeek, wDay, wHour, wMinute, wSecond, wMilliseconds
    __ptr<u16> parts = _pep_malloc(32);
    parts[0] = universal.year as u16;
    parts[1] = universal.month as u16;
    parts[2] = ((universal.weekday() as int) % 7) as u16;
    parts[3] = universal.day as u16;
    parts[4] = universal.hour as u16;
    parts[5] = universal.minute as u16;
    parts[6] = universal.second as u16;
    parts[7] = 0;
    var offset = 0;
    if (SystemTimeToTzSpecificLocalTime(__null, parts, parts + 8) != 0) {
        var local = DateTime(
            parts[8] as int, parts[9] as int, parts[11] as int, parts[12] as int, parts[13] as int, parts[14] as int
        );
        offset = (local.unix_seconds() - clamped) as int;
    }
    _pep_free(parts);
    return offset;
}

# The zone's name as NUL-terminated UTF-16; zone names are ASCII.
[Target(OS(Windows))]
_time_wide_name(name: String): __ptr<u16> {
    __ptr<u16> wide = _pep_malloc((name.size + 1) * 2);
    for (var i in 0..name.size) {
        wide[i] = name.byte_at(i) as u16;
    }
    wide[name.size] = 0;
    return wide;
}

# A database folder named by TZDIR wins over ICU, as on Linux and macOS.
[Target(OS(Windows))]
export _time_sys_named(name: String): Result<TimeZone> {
    var folder = os.environment("TZDIR");
    if (!folder.is_empty()) {
        return _time_zone_from_database(name, folder.value());
    }
    var wide = _time_wide_name(name);
    __ptr<u16> canonical = _pep_malloc(512);
    __ptr<char> is_system = _pep_malloc(1);
    __ptr<int> status = _pep_malloc(4);
    status[0] = 0;
    ucal_getCanonicalTimeZoneID(wide, -1, canonical, 256, is_system, status);
    var known = status[0] <= 0 && is_system[0] != 0;
    _pep_free(status);
    _pep_free(is_system);
    _pep_free(canonical);
    _pep_free(wide);
    if (!known) {
        return Result<TimeZone>.err(Error($"unknown time zone '{name}'"));
    }
    return Result<TimeZone>.ok(TimeZone._from_icu(name));
}

# UCAL_GREGORIAN is 1; UCAL_ZONE_OFFSET 15 and UCAL_DST_OFFSET 16, in
# milliseconds.
[Target(OS(Windows))]
export _time_sys_icu_offset(name: String, seconds: long): int {
    var wide = _time_wide_name(name);
    __ptr<int> status = _pep_malloc(4);
    status[0] = 0;
    var offset = 0;
    var calendar = ucal_open(wide, -1, __null, 1, status);
    if (status[0] <= 0 && calendar != __null) {
        ucal_setMillis(calendar, (seconds as double) * 1000.0, status);
        var zone = ucal_get(calendar, 15, status);
        var daylight = ucal_get(calendar, 16, status);
        if (status[0] <= 0) {
            offset = (zone + daylight) / 1000;
        }
    }
    if (calendar != __null) {
        ucal_close(calendar);
    }
    _pep_free(status);
    _pep_free(wide);
    return offset;
}
