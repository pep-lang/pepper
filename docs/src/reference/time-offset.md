<!-- Generated from runtime/time/offset.pep by `pep-doc reference`. Do not edit. -->

# Offsets

Fixed offsets from UTC, `Offset`, and the date and time at one,
`OffsetDateTime`: an instant written the way RFC 3339 and TOML write it.

Source: `runtime/time/offset.pep`

## Offset

```pepper
[Value] struct Offset
```

A fixed offset from UTC, east positive: `+02:00` for Central European
Summer Time, `-05:00` for US Eastern Standard Time, `+00:00` for UTC.

A value struct: copied, compared with `==`, and never allocated. It is
less than a day either way, to the second. Its text is `+02:00`, with the
seconds when there are any (`+00:19:32`).

**Example**
```pepper
import time;

main(): int {
    var india = time.Offset.from_hours(5, 30);
    print(india);            # +05:30
    print(india.seconds);    # 19800
    return 0;
}
```

### Properties

#### seconds

```pepper
var seconds: int { get; }
```

The offset in seconds, east of UTC positive.

### Constructor

#### Offset()

```pepper
construct(seconds: int = 0)
```

Makes the offset `seconds` seconds east of UTC (west when negative);
with no argument, UTC itself.

**Parameters**
- `seconds` — the offset in seconds, east positive

**Panics**
- if the offset is a day or more either way

### Static methods

#### utc

```pepper
static utc(): Offset
```

Returns UTC, the zero offset.

**Returns**
- the zero offset

#### from_hours

```pepper
static from_hours(hours: int, minutes: int = 0): Offset
```

Returns the offset `hours` hours and `minutes` minutes from UTC. Both
take the offset's sign: `from_hours(-3, -30)` is `-03:30`, and
`from_hours(0, -30)` is `-00:30`.

**Parameters**
- `hours` — whole hours, east positive
- `minutes` — minutes on top of the hours, with the same sign

**Returns**
- the offset

**Panics**
- if the offset is a day or more either way

#### parse

```pepper
static parse(text: String): Result<Offset>
```

Returns the offset written as `+02:00`, `-0530`, `+02` or `Z` (UTC),
or an error when `text` is not one.

**Parameters**
- `text` — the text to read

**Returns**
- the offset, or an error saying what is wrong with `text`

### Methods

#### is_utc

```pepper
is_utc(): bool
```

Returns whether this is UTC, the zero offset.

**Returns**
- true for `+00:00`

#### to_string

```pepper
to_string(): String
```

Returns the offset as text: `+02:00`, `-05:30`, `+00:00`, with the
seconds when there are any (`+00:19:32`).

**Returns**
- the offset as text

## OffsetDateTime

```pepper
[Value] struct OffsetDateTime
```

A date and time at a fixed offset from UTC, such as
`2024-03-01T09:00:00+01:00`: an instant, together with the local date and
time it was written in. This is RFC 3339's timestamp and TOML's offset
date-time.

A value struct: copied and never allocated. `==` compares the date, time
and offset, so the same instant at two offsets is not `==`; compare
instants with `to_system_time()`, or with `<` and the other comparisons,
which compare instants. Its text is RFC 3339's, with `Z` for UTC.

**Example**
```pepper
import time;

main(): int {
    var meeting = time.OffsetDateTime.parse("2024-03-01T09:00:00+01:00").value();
    print(meeting.to_utc());   # 2024-03-01T08:00:00Z
    print(meeting.to_http_date());   # Fri, 01 Mar 2024 08:00:00 GMT
    return 0;
}
```

### Properties

#### date_time

```pepper
var date_time: DateTime { get; }
```

The local date and time at `offset`.

#### offset

```pepper
var offset: Offset { get; }
```

The offset from UTC that `date_time` is at.

#### date

```pepper
var date: Date { get; }
```

The local date, as `date_time.date`.

#### time

```pepper
var time: Time { get; }
```

The local time of day, as `date_time.time`.

### Constructor

#### OffsetDateTime()

```pepper
construct(date_time: DateTime = DateTime(), offset: Offset = Offset())
```

Makes the date and time `date_time` at `offset`; with no arguments,
the Unix epoch, 1970-01-01T00:00:00Z.

**Parameters**
- `date_time` — the local date and time
- `offset` — its offset from UTC

### Static methods

#### from_system_time

```pepper
static from_system_time(time: os.SystemTime, offset: Offset = Offset()): OffsetDateTime
```

Returns the date and time of a wall-clock reading at `offset`.

**Parameters**
- `time` — the instant
- `offset` — the offset to show it at; UTC by default

**Returns**
- the instant's date and time at `offset`

#### parse

```pepper
static parse(text: String): Result<OffsetDateTime>
```

Returns the RFC 3339 timestamp in `text`, such as
`2024-03-01T09:00:00+01:00` or `2024-03-01T08:00:00.5Z`, or an error
when it is not one. A space or a lowercase `t` may stand for the `T`
and a lowercase `z` for the `Z`, and the seconds may be left out, as
TOML allows.

**Parameters**
- `text` — the text to read

**Returns**
- the date and time, or an error saying what is wrong with `text`

#### parse_http_date

```pepper
static parse_http_date(text: String): Result<OffsetDateTime>
```

Returns the HTTP date in `text`, as RFC 9110 defines it, or an error
when it is not one. It reads the preferred IMF-fixdate
(`Sun, 06 Nov 1994 08:49:37 GMT`) and the two obsolete forms that
servers must still accept: RFC 850's (`Sunday, 06-Nov-94 08:49:37
GMT`, where a two-digit year from 70 is in the 1900s and below 70 in
the 2000s) and C's `asctime` (`Sun Nov  6 08:49:37 1994`). The
weekday must match the date.

**Parameters**
- `text` — the text to read

**Returns**
- the date and time in UTC, or an error saying what is wrong with `text`

### Methods

#### unix_seconds

```pepper
unix_seconds(): long
```

Returns the seconds from the Unix epoch to this instant, rounded
down.

**Returns**
- seconds since 1970-01-01T00:00:00Z; negative for earlier

#### to_system_time

```pepper
to_system_time(): os.SystemTime
```

Returns this instant as a `SystemTime`.

**Returns**
- the instant

**Panics**
- if the instant is outside what a `SystemTime` reaches, the years 1677 to 2262

#### to_offset

```pepper
to_offset(offset: Offset): OffsetDateTime
```

Returns the same instant at another offset.

**Parameters**
- `offset` — the offset to show the instant at

**Returns**
- the date and time at `offset`

#### to_utc

```pepper
to_utc(): OffsetDateTime
```

Returns the same instant in UTC.

**Returns**
- the date and time at offset zero

#### weekday

```pepper
weekday(): Weekday
```

Returns the day of the week of the local date.

**Returns**
- the weekday

#### operator +

```pepper
+(duration: os.Duration): OffsetDateTime
```

Returns the instant `duration` later, at the same offset.

**Parameters**
- `duration` — how far to move forward

**Returns**
- the later date and time

#### operator -

```pepper
-(duration: os.Duration): OffsetDateTime
```

Returns the instant `duration` earlier, at the same offset.

**Parameters**
- `duration` — how far to move back

**Returns**
- the earlier date and time

#### operator <

```pepper
<(other: OffsetDateTime): bool
```

Returns whether this instant is earlier than `other`, whatever their
offsets.

**Parameters**
- `other` — the instant to compare with

**Returns**
- true when this one is earlier

#### operator <=

```pepper
<=(other: OffsetDateTime): bool
```

Returns whether this instant is earlier than or the same as `other`.

**Parameters**
- `other` — the instant to compare with

**Returns**
- true when this one is not later

#### operator >

```pepper
>(other: OffsetDateTime): bool
```

Returns whether this instant is later than `other`, whatever their
offsets.

**Parameters**
- `other` — the instant to compare with

**Returns**
- true when this one is later

#### operator >=

```pepper
>=(other: OffsetDateTime): bool
```

Returns whether this instant is later than or the same as `other`.

**Parameters**
- `other` — the instant to compare with

**Returns**
- true when this one is not earlier

#### format

```pepper
format(pattern: String): String
```

Returns the date and time as text laid out by `pattern`, whose `%`
codes are those of C's `strftime` (see the
[time module](time-module.md)). `%z` is the offset as `+0200`, `%:z`
as `+02:00`, and `%s` the Unix seconds.

**Parameters**
- `pattern` — the layout, such as `"%Y-%m-%d %H:%M %z"`

**Returns**
- the formatted date and time

**Panics**
- if `pattern` has an unknown code

#### to_http_date

```pepper
to_http_date(): String
```

Returns the instant as an HTTP date in UTC, the IMF-fixdate of RFC
9110 that `Date` and `Last-Modified` headers carry:
`Fri, 01 Mar 2024 08:00:00 GMT`. The fraction of a second is dropped.

**Returns**
- the date as an HTTP date

#### to_string

```pepper
to_string(): String
```

Returns the date and time as an RFC 3339 timestamp:
`2024-03-01T09:00:00+01:00`, `Z` for UTC, with the fraction of a
second when it is not zero.

**Returns**
- the date and time as text
