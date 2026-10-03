<!-- Generated from runtime/time/zone.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Time zones

Time zones: `TimeZone`, the rules that give an instant's offset from UTC,
for UTC, a fixed offset, the system's local zone, or a named zone such as
`Europe/Paris` from the system's time zone database; and `now()`.

Source: `runtime/time/zone.pep`

## TimeZone

```pepper
struct TimeZone
```

The rules that give the offset from UTC at each instant in one place:
UTC, a fixed offset, the system's local time zone, or a named zone from
the IANA time zone database, such as `Europe/Paris` or
`America/New_York`, with its daylight saving time and its history.

Named zones come from the system's database, nothing is bundled: the
files under `/usr/share/zoneinfo` on Linux and macOS, and ICU's
(`icu.dll`, Windows 10 version 1903 and later) on Windows. On every
system, a folder of database files that the `TZDIR` environment variable
names takes their place. Leap seconds are ignored, as in Unix time.

A zone is a reference, and it does not change once made, so copies share
it.

**Example**
```pepper
import os;
import time;

main(): int {
    var paris = time.TimeZone.named("Europe/Paris").value();
    var instant = time.OffsetDateTime.parse("2024-07-14T10:00:00Z").value();
    print(paris.at(instant.to_system_time()));   # 2024-07-14T12:00:00+02:00
    var local = paris.at_local(time.DateTime(2024, 12, 25, 18, 0));
    print(local.offset);                         # +01:00
    return 0;
}
```

### Properties

#### name

```pepper
var name: String { get; }
```

The zone's name: `UTC`, `Local`, the offset of a fixed zone
(`+05:30`), or the database name of a named one (`Europe/Paris`).

### Constructor

#### TimeZone()

```pepper
construct()
```

Makes UTC; the same as `TimeZone.utc()`.

### Static methods

#### utc

```pepper
static utc(): TimeZone
```

Returns UTC.

**Returns**
- the zone whose offset is always zero

#### fixed

```pepper
static fixed(offset: Offset): TimeZone
```

Returns a zone whose offset is always `offset`.

**Parameters**
- `offset` — the offset from UTC

**Returns**
- the zone, named after the offset (`+05:30`)

#### local

```pepper
static local(): TimeZone
```

Returns the system's local time zone, as the C library's `localtime`
sees it: the `TZ` environment variable or `/etc/localtime` on Linux
and macOS, and the zone in Windows' settings. WebAssembly (WASI) has
no local zone, so it is UTC there.

**Returns**
- the local zone, named `Local`

#### named

```pepper
static named(name: String): Result<TimeZone>
```

Returns the zone `name` from the system's time zone database, such
as `Europe/Paris`, `America/New_York` or `Asia/Kolkata`, or an error
when the system does not know it. `UTC` is always known.

**Parameters**
- `name` — the IANA name of the zone, which is case-sensitive

**Returns**
- the zone, or an error saying it was not found

### Methods

#### offset_at

```pepper
offset_at(time: os.SystemTime): Offset
```

Returns the offset from UTC in this zone at `time`.

**Parameters**
- `time` — the instant

**Returns**
- the offset in effect then

#### at

```pepper
at(time: os.SystemTime): OffsetDateTime
```

Returns the date and time in this zone at `time`.

**Parameters**
- `time` — the instant

**Returns**
- its local date and time, with the offset in effect

**Example**
```pepper
var here = time.TimeZone.local().at(os.SystemTime.now());
```

#### at_local

```pepper
at_local(local: DateTime): OffsetDateTime
```

Returns the instant that a local date and time names in this zone,
with its offset.

Where the clocks go back, a local time happens twice; this returns
the earlier, at the offset from before the change. Where they go
forward, a local time never happens; this moves it forward by the
length of the gap, so 02:30 on a night that skips from 02:00 to
03:00 is 03:30. This is what Java's `ZonedDateTime.of` does.

**Parameters**
- `local` — the date and time on the zone's clocks

**Returns**
- the date and time with the zone's offset at that instant

## now

```pepper
now(): OffsetDateTime
```

Returns the current date and time in the system's local time zone.

**Returns**
- now, at the local offset

**Example**
```pepper
print(time.now());   # such as 2024-03-01T09:00:00.123456789+01:00
```

## now_utc

```pepper
now_utc(): OffsetDateTime
```

Returns the current date and time in UTC.

**Returns**
- now, at offset zero
