# WebAssembly (WASI) platform layer for time: there is no local zone, so it
# is UTC, and named zones come from TZif files when the host lends the
# program the database's folder.

import os;
import "zone";

[Target(OS(Wasi))]
_time_sys_local_offset(seconds: long): int {
    return 0;
}

[Target(OS(Wasi))]
_time_sys_named(name: String): Result<TimeZone> {
    return _time_zone_from_database(name, os.environment("TZDIR").value_or("/usr/share/zoneinfo"));
}

[Target(OS(Wasi))]
_time_sys_icu_offset(name: String, seconds: long): int {
    return 0;
}
