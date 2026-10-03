# Dates, times and time zones

The `time` module turns instants into calendar dates and times of day, and
back: dates and times with no zone, fixed offsets from UTC, time zones with
daylight saving time, and the text forms of RFC 3339, ISO 8601, HTTP and
C's `strftime`. Bring it in with `import time`. The full API is in the
[reference](../reference/time-module.md).

An instant itself is an [`os.SystemTime`](os.md#time): nanoseconds since
the Unix epoch. `time` says what date and time that is somewhere, and
which instant a date and time names.

The calendar is the proleptic Gregorian calendar, which extends today's
rules to years before it was adopted, and leap seconds are ignored, as Unix
time, Go and Java ignore them: every day has 86400 seconds.

## Dates and times of day

Four [value types](value-structs.md) carry no time zone. Each is copied,
compared with `==`, `<` and the other comparisons, and never allocated.

- `Date` is a year, a month (1 to 12) and a day. It knows its `weekday()`,
  `day_of_year()` and whether its year `is_leap_year()`, and moves with
  `add_days`, `add_months` and `add_years`. A month or year later keeps the
  day when it can and otherwise takes the month's last day, so a month
  after January 31 is February 28 or 29.
- `Time` is an hour, minute, second and nanosecond within a day.
- `DateTime` is a `Date` and a `Time` together: what TOML calls a local
  date-time. Adding or subtracting an `os.Duration` moves it.
- `Weekday` is an enum, `Monday` to `Sunday`, whose values are ISO 8601's
  numbers, 1 to 7.

```pepper
{{#include ../../examples/time-dates.pep}}
```

The constructors (`Date(2024, 2, 29)`) panic on parts that name no date or
time, which suits values written in the program. For parts that come from
outside it, `checked` returns an optional instead, and `parse` a
[`Result`](results.md). Years run from -999999 to 999999, and year 0 is
1 BC.

## Offsets and timestamps

`Offset` is a fixed offset from UTC, east positive: `Offset.from_hours(5,
30)` is `+05:30`. `OffsetDateTime` is a `DateTime` at an `Offset`, which
names one instant: RFC 3339's timestamp and TOML's offset date-time.

```pepper
{{#include ../../examples/time-format.pep}}
```

- `OffsetDateTime.from_system_time(t, offset)` is the instant `t` at
  `offset` (UTC by default), and `to_system_time()` goes back.
  `to_offset` and `to_utc` show the same instant at another offset.
- `==` compares the date, time and offset, so the same instant written at
  two offsets is not `==`. `<`, `<=`, `>` and `>=` compare instants.
- `DateTime.from_system_time(t)` and `to_system_time()` read a `DateTime`
  as UTC.

## Text

Each type's `to_string()` writes ISO 8601, and its static `parse` reads it:

| Type | Text |
|---|---|
| `Date` | `2024-02-29`; outside the years 0 to 9999, signed: `-0001-12-31`, `+10000-01-01` |
| `Time` | `08:30:00`, with the fraction of a second when there is one: `08:30:00.25` |
| `DateTime` | `2024-03-01T09:00:00` |
| `Offset` | `+01:00`; `parse` also takes `Z`, `+0100` and `+01` |
| `OffsetDateTime` | `2024-03-01T09:00:00+01:00`, `Z` for UTC |

`parse` also reads what TOML allows: a space or `t` for the `T`, `z` for
the `Z`, and a time without its seconds (`09:00`). Digits of a fraction
past the nanosecond are dropped.

`format(pattern)` lays a value out with `strftime`'s `%` codes, such as
`%Y-%m-%d`, `%A`, `%B` and `%H:%M`; the [module
reference](../reference/time-module.md) lists them all. Names are English
whatever the locale. `%z`, `%:z` and `%s` need an offset, so only an
`OffsetDateTime` takes them; an unknown code panics.

HTTP dates (RFC 9110) go both ways: `to_http_date()` writes the
IMF-fixdate of `Date` and `Last-Modified` headers, `Fri, 01 Mar 2024
08:00:00 GMT`, and `OffsetDateTime.parse_http_date` reads it and the two
obsolete forms servers must still accept, RFC 850's and C's `asctime`.

## Time zones

A `TimeZone` gives the offset from UTC at each instant in one place:

- `TimeZone.utc()`, and `TimeZone.fixed(offset)` for an offset that never
  changes.
- `TimeZone.local()`, the system's zone: the `TZ` environment variable or
  `/etc/localtime` on Linux and macOS, as the C library's `localtime` reads
  them, and the zone in Windows' settings. WebAssembly has no local zone,
  so it is UTC there.
- `TimeZone.named("Europe/Paris")`, a zone of the IANA time zone database,
  with its daylight saving time and history, or an error when the system
  does not know the name.

`zone.offset_at(t)` is the offset at the instant `t`, and `zone.at(t)` its
date and time there. `zone.at_local(date_time)` goes the other way, from
a date and time on the zone's clocks to the instant. Where the clocks go
back, a time happens twice, and `at_local` picks the earlier; where they go
forward, a time never happens, and it moves on by the length of the gap.
`time.now()` is the current date and time in the local zone, and
`time.now_utc()` in UTC.

```pepper
{{#include ../../examples/time-zones.pep}}
```

Nothing is bundled: named zones come from the system.

- On Linux and macOS, the TZif files under `/usr/share/zoneinfo`, or the
  folder the `TZDIR` environment variable names. A minimal Linux container
  may have none until its `tzdata` package is installed. The rule at the
  end of each file covers instants after its last listed change.
- On Windows, ICU (`icu.dll`, part of Windows 10 version 1903 and later),
  which knows the same names, or the TZif files in the folder `TZDIR`
  names when it is set.
- On WebAssembly, TZif files under `/usr/share/zoneinfo` (or `TZDIR`) when
  the host lends the program that folder.

## Current limitations

- `format` writes text but nothing reads a `strftime` pattern back; parse
  ISO 8601, RFC 3339 and HTTP dates with the `parse` functions.
- Names in `format` are English only, and there are no locale formats
  (`%c`, `%x`, `%X`) or zone abbreviations (`%Z`).
- On Android, named zones are not found: its database is one packed file,
  not a folder of TZif files.
