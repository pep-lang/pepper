<!-- Generated from runtime/os/time.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Time

Clocks and spans of time: `Duration`, `Instant` for measuring, and
`SystemTime` for the wall clock.

Source: `runtime/os/time.pep`

## Duration

```pepper
[Value] struct Duration
```

A span of time, counted in nanoseconds, like Rust's
`std::time::Duration`. It is never negative and reaches about 584 years.

Make one with `from_seconds`, `from_milliseconds`, `from_microseconds` or
`from_nanoseconds`, or by subtracting two `Instant`s. A value struct: it
is copied, compared with `==`, and allocates nothing.

**Example**
```pepper
import os;

main(): int {
    var timeout = os.Duration.from_seconds(2) + os.Duration.from_milliseconds(500);
    print(timeout.milliseconds());   # 2500
    print(timeout);                  # 2.5s
    return 0;
}
```

### Constructor

#### Duration()

```pepper
construct()
```

Makes a zero-length duration.

### Static methods

#### from_nanoseconds

```pepper
static from_nanoseconds(nanoseconds: ulong): Duration
```

Returns a duration of `nanoseconds` nanoseconds.

**Parameters**
- `nanoseconds` — the length in nanoseconds

**Returns**
- the duration

#### from_microseconds

```pepper
static from_microseconds(microseconds: ulong): Duration
```

Returns a duration of `microseconds` microseconds.

**Parameters**
- `microseconds` — the length in microseconds

**Returns**
- the duration

**Panics**
- if the duration does not fit in a `ulong` of nanoseconds

#### from_milliseconds

```pepper
static from_milliseconds(milliseconds: ulong): Duration
```

Returns a duration of `milliseconds` milliseconds.

**Parameters**
- `milliseconds` — the length in milliseconds

**Returns**
- the duration

**Panics**
- if the duration does not fit in a `ulong` of nanoseconds

#### from_seconds

```pepper
static from_seconds(seconds: ulong): Duration
```

Returns a duration of `seconds` seconds.

**Parameters**
- `seconds` — the length in seconds

**Returns**
- the duration

**Panics**
- if the duration does not fit in a `ulong` of nanoseconds (about 584 years)

### Methods

#### nanoseconds

```pepper
nanoseconds(): ulong
```

Returns the whole number of nanoseconds in this duration.

**Returns**
- the length in nanoseconds

#### microseconds

```pepper
microseconds(): ulong
```

Returns the whole number of microseconds in this duration, rounded
down.

**Returns**
- the length in microseconds

#### milliseconds

```pepper
milliseconds(): ulong
```

Returns the whole number of milliseconds in this duration, rounded
down.

**Returns**
- the length in milliseconds

#### seconds

```pepper
seconds(): ulong
```

Returns the whole number of seconds in this duration, rounded down.

**Returns**
- the length in seconds

#### seconds_fraction

```pepper
seconds_fraction(): double
```

Returns this duration in seconds, with the fraction.

**Returns**
- the length in seconds, as a `double`

#### is_zero

```pepper
is_zero(): bool
```

Returns whether this duration is zero.

**Returns**
- true for a zero-length duration

#### operator +

```pepper
+(other: Duration): Duration
```

Returns the sum of two durations.

**Parameters**
- `other` — the duration to add

**Returns**
- the longer duration

**Panics**
- if the sum does not fit in a `ulong` of nanoseconds

#### operator -

```pepper
-(other: Duration): Duration
```

Returns this duration less `other`.

**Parameters**
- `other` — the duration to take away

**Returns**
- the difference

**Panics**
- if `other` is longer than this duration: a duration is never negative

#### operator *

```pepper
*(times: ulong): Duration
```

Returns this duration `times` times over.

**Parameters**
- `times` — the factor

**Returns**
- the product

**Panics**
- if the product does not fit in a `ulong` of nanoseconds

#### operator /

```pepper
/(parts: ulong): Duration
```

Returns this duration split into `parts` equal parts, rounded down to
a whole nanosecond.

**Parameters**
- `parts` — the divisor

**Returns**
- the quotient

**Panics**
- if `parts` is zero

#### operator <

```pepper
<(other: Duration): bool
```

Returns whether this duration is shorter than `other`.

**Parameters**
- `other` — the duration to compare with

**Returns**
- true when this one is shorter

#### operator <=

```pepper
<=(other: Duration): bool
```

Returns whether this duration is shorter than or as long as `other`.

**Parameters**
- `other` — the duration to compare with

**Returns**
- true when this one is not longer

#### operator >

```pepper
>(other: Duration): bool
```

Returns whether this duration is longer than `other`.

**Parameters**
- `other` — the duration to compare with

**Returns**
- true when this one is longer

#### operator >=

```pepper
>=(other: Duration): bool
```

Returns whether this duration is longer than or as long as `other`.

**Parameters**
- `other` — the duration to compare with

**Returns**
- true when this one is not shorter

#### to_string

```pepper
to_string(): String
```

Returns this duration as text in the largest unit it reaches, with
the fraction it needs and no trailing zeros: `2.5s`, `15ms`,
`1.25µs`, `40ns`, `0s`.

**Returns**
- the duration as text

## Instant

```pepper
[Value] struct Instant
```

A moment on a monotonic clock, for measuring how long something takes,
like Rust's `std::time::Instant`.

The clock only moves forward: setting the system's date and time does
not change it. Its readings mean nothing by themselves, only the
`Duration` between two of them, and they cannot be compared across
processes or reboots. Use `SystemTime` for the date and time.

The clock is `CLOCK_MONOTONIC` on Linux and macOS and
`QueryPerformanceCounter` on Windows, read to the nanosecond.

**Example**
```pepper
import os;

main(): int {
    var start = os.Instant.now();
    var total = 0;
    for (var i in 0..1000000) {
        total = total + i;
    }
    var elapsed = os.Instant.now() - start;
    print($"summed in {elapsed.milliseconds()} ms");
    return 0;
}
```

### Constructor

#### Instant()

```pepper
construct()
```

Makes the instant the clock started from; use `now()` to read the
clock.

### Static methods

#### now

```pepper
static now(): Instant
```

Reads the monotonic clock.

**Returns**
- the current moment

### Methods

#### elapsed

```pepper
elapsed(): Duration
```

Returns how long ago this instant was: `Instant.now() - this`.

**Returns**
- the time since this instant

#### operator -

```pepper
-(earlier: Instant): Duration
```

Returns the time from `earlier` to this instant.

**Parameters**
- `earlier` — an instant no later than this one

**Returns**
- the time between them

**Panics**
- if `earlier` is later than this instant

#### operator +

```pepper
+(duration: Duration): Instant
```

Returns the instant `duration` after this one.

**Parameters**
- `duration` — how far to move forward

**Returns**
- the later instant

**Panics**
- if the result does not fit the clock

#### operator -

```pepper
-(duration: Duration): Instant
```

Returns the instant `duration` before this one.

**Parameters**
- `duration` — how far to move back

**Returns**
- the earlier instant

**Panics**
- if the result is before the clock's start

#### operator <

```pepper
<(other: Instant): bool
```

Returns whether this instant is earlier than `other`.

**Parameters**
- `other` — the instant to compare with

**Returns**
- true when this one is earlier

#### operator <=

```pepper
<=(other: Instant): bool
```

Returns whether this instant is earlier than or the same as `other`.

**Parameters**
- `other` — the instant to compare with

**Returns**
- true when this one is not later

#### operator >

```pepper
>(other: Instant): bool
```

Returns whether this instant is later than `other`.

**Parameters**
- `other` — the instant to compare with

**Returns**
- true when this one is later

#### operator >=

```pepper
>=(other: Instant): bool
```

Returns whether this instant is later than or the same as `other`.

**Parameters**
- `other` — the instant to compare with

**Returns**
- true when this one is not earlier

## SystemTime

```pepper
[Value] struct SystemTime
```

A date and time on the system's wall clock, counted in nanoseconds from
the Unix epoch (1970-01-01 00:00:00 UTC), like Rust's
`std::time::SystemTime`. It reaches from the year 1677 to 2262.

The wall clock can jump, backwards too, when the system's time is set,
so measure how long something takes with `Instant` instead. Dates, time
zones and formatting are not part of `os`.

**Example**
```pepper
import os;

main(): int {
    var now = os.SystemTime.now();
    print($"{now.unix_seconds()} seconds since 1970");
    return 0;
}
```

### Constructor

#### SystemTime()

```pepper
construct()
```

Makes the Unix epoch, 1970-01-01 00:00:00 UTC.

### Static methods

#### now

```pepper
static now(): SystemTime
```

Reads the wall clock.

**Returns**
- the current date and time

#### from_unix_nanoseconds

```pepper
static from_unix_nanoseconds(nanoseconds: long): SystemTime
```

Returns the time `nanoseconds` nanoseconds after the Unix epoch.

**Parameters**
- `nanoseconds` — nanoseconds since the epoch; negative for earlier times

**Returns**
- the time

#### from_unix_seconds

```pepper
static from_unix_seconds(seconds: long): SystemTime
```

Returns the time `seconds` seconds after the Unix epoch, as file
systems and most protocols record it.

**Parameters**
- `seconds` — seconds since the epoch; negative for earlier times

**Returns**
- the time

**Panics**
- if the time is outside the years 1677 to 2262

### Methods

#### unix_nanoseconds

```pepper
unix_nanoseconds(): long
```

Returns the nanoseconds from the Unix epoch to this time.

**Returns**
- nanoseconds since the epoch; negative for earlier times

#### unix_milliseconds

```pepper
unix_milliseconds(): long
```

Returns the milliseconds from the Unix epoch to this time, rounded
down (towards the past).

**Returns**
- milliseconds since the epoch; negative for earlier times

#### unix_seconds

```pepper
unix_seconds(): long
```

Returns the seconds from the Unix epoch to this time, rounded down
(towards the past).

**Returns**
- seconds since the epoch; negative for earlier times

#### duration_since

```pepper
duration_since(earlier: SystemTime): Duration?
```

Returns the time from `earlier` to this time, or none when `earlier`
is later: the wall clock can be set back between two readings.

**Parameters**
- `earlier` — the time to measure from

**Returns**
- the time between them, or none when `earlier` is later

#### elapsed

```pepper
elapsed(): Duration?
```

Returns how long ago this time was on the wall clock, or none when it
is in the future.

**Returns**
- the time since this one, or none when it is later than now

#### operator +

```pepper
+(duration: Duration): SystemTime
```

Returns the time `duration` after this one.

**Parameters**
- `duration` — how far to move forward

**Returns**
- the later time

**Panics**
- if the result is after the year 2262

#### operator -

```pepper
-(duration: Duration): SystemTime
```

Returns the time `duration` before this one.

**Parameters**
- `duration` — how far to move back

**Returns**
- the earlier time

**Panics**
- if the result is before the year 1677

#### operator <

```pepper
<(other: SystemTime): bool
```

Returns whether this time is earlier than `other`.

**Parameters**
- `other` — the time to compare with

**Returns**
- true when this one is earlier

#### operator <=

```pepper
<=(other: SystemTime): bool
```

Returns whether this time is earlier than or the same as `other`.

**Parameters**
- `other` — the time to compare with

**Returns**
- true when this one is not later

#### operator >

```pepper
>(other: SystemTime): bool
```

Returns whether this time is later than `other`.

**Parameters**
- `other` — the time to compare with

**Returns**
- true when this one is later

#### operator >=

```pepper
>=(other: SystemTime): bool
```

Returns whether this time is later than or the same as `other`.

**Parameters**
- `other` — the time to compare with

**Returns**
- true when this one is not earlier
