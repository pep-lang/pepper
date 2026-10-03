<!-- Generated from runtime/time/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The time module

Calendar time: dates, times of day, offsets from UTC, time zones, and
formatting and parsing them, on the proleptic Gregorian calendar. Leap
seconds are ignored, as in Unix time. `os.SystemTime` is the instant
this module turns into dates and back.

`time` is a module: bring it in with `import time` (and write
`time.Date(2024, 2, 29)`) or import names directly with
`import [Date, TimeZone] from time`.

- [Dates and times](time-civil.md): `Date`, `Time`, `DateTime`,
  `Weekday`, `is_leap_year` and `days_in_month`, with no time zone
- [Offsets](time-offset.md): `Offset`, a fixed offset from UTC, and
  `OffsetDateTime`, an RFC 3339 timestamp, with HTTP dates
- [Time zones](time-zone.md): `TimeZone` (UTC, fixed, local, or named
  from the system's database), `now()` and `now_utc()`

Every type's `format(pattern)` lays it out with C `strftime` codes:

| Code | Gives | Code | Gives |
|---|---|---|---|
| `%Y` | year, at least four digits (`2024`) | `%H` | hour, `00` to `23` |
| `%C` | century (`20`) | `%I` | hour, `01` to `12` |
| `%y` | year in the century, `00` to `99` | `%p` | `AM` or `PM` |
| `%m` | month, `01` to `12` | `%M` | minute, `00` to `59` |
| `%d` | day, `01` to `31` | `%S` | second, `00` to `59` |
| `%e` | day, space-padded (` 1`) | `%N` | nanoseconds, nine digits; `%3N` milliseconds |
| `%j` | day of the year, `001` to `366` | `%T` | `%H:%M:%S` |
| `%F` | `%Y-%m-%d` | `%R` | `%H:%M` |
| `%a` | weekday, `Mon` | `%z` | offset, `+0100` |
| `%A` | weekday, `Monday` | `%:z` | offset, `+01:00` |
| `%b`, `%h` | month, `Jan` | `%s` | Unix seconds |
| `%B` | month, `January` | `%u` | ISO weekday, `1` (Monday) to `7` |
| `%G` | ISO 8601 week-numbering year | `%w` | weekday, `0` (Sunday) to `6` |
| `%V` | ISO 8601 week, `01` to `53` | `%n`, `%t`, `%%` | newline, tab, `%` |

Names are English, whatever the locale. `%z`, `%:z` and `%s` need an
offset, so only `OffsetDateTime.format` takes them.

**Example**
```pepper
import os;
import time;

main(): int {
    var now = time.now();
    print(now);                                  # 2024-03-01T09:00:00.25+01:00
    print(now.format("%A %e %B %Y, %H:%M"));     # Friday  1 March 2024, 09:00
    print(now.to_http_date());                   # Fri, 01 Mar 2024 08:00:00 GMT
    var date = time.Date.parse("2024-02-29").value();
    print(date.add_years(1));                    # 2025-02-28
    return 0;
}
```

Source: `runtime/time/module.pep`
