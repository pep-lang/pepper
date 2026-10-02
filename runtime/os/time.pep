## Clocks and spans of time: `Duration`, `Instant` for measuring, and
## `SystemTime` for the wall clock.

import "sys_posix";
import "sys_wasi";
import "sys_windows";

const NANOSECONDS_PER_MICROSECOND: ulong = 1000;
const NANOSECONDS_PER_MILLISECOND: ulong = 1000000;
const NANOSECONDS_PER_SECOND: ulong = 1000000000;

## A span of time, counted in nanoseconds, like Rust's
## `std::time::Duration`. It is never negative and reaches about 584 years.
##
## Make one with `from_seconds`, `from_milliseconds`, `from_microseconds` or
## `from_nanoseconds`, or by subtracting two `Instant`s. A value struct: it
## is copied, compared with `==`, and allocates nothing.
##
## @example
##     import os;
##
##     main(): int {
##         var timeout = os.Duration.from_seconds(2) + os.Duration.from_milliseconds(500);
##         print(timeout.milliseconds());   # 2500
##         print(timeout);                  # 2.5s
##         return 0;
##     }
[Value]
export struct Duration {
    var _nanoseconds: ulong;

    ## Makes a zero-length duration.
    construct() {}

    ## Returns a duration of `nanoseconds` nanoseconds.
    ##
    ## @param nanoseconds the length in nanoseconds
    ## @returns the duration
    static from_nanoseconds(nanoseconds: ulong): Duration {
        var duration = Duration();
        duration._nanoseconds = nanoseconds;
        return duration;
    }

    ## Returns a duration of `microseconds` microseconds.
    ##
    ## @param microseconds the length in microseconds
    ## @returns the duration
    ## @panics if the duration does not fit in a `ulong` of nanoseconds
    static from_microseconds(microseconds: ulong): Duration {
        return Duration._scaled(microseconds, NANOSECONDS_PER_MICROSECOND);
    }

    ## Returns a duration of `milliseconds` milliseconds.
    ##
    ## @param milliseconds the length in milliseconds
    ## @returns the duration
    ## @panics if the duration does not fit in a `ulong` of nanoseconds
    static from_milliseconds(milliseconds: ulong): Duration {
        return Duration._scaled(milliseconds, NANOSECONDS_PER_MILLISECOND);
    }

    ## Returns a duration of `seconds` seconds.
    ##
    ## @param seconds the length in seconds
    ## @returns the duration
    ## @panics if the duration does not fit in a `ulong` of nanoseconds
    ##   (about 584 years)
    static from_seconds(seconds: ulong): Duration {
        return Duration._scaled(seconds, NANOSECONDS_PER_SECOND);
    }

    static _scaled(count: ulong, unit: ulong): Duration {
        assert(count <= 0xFFFFFFFFFFFFFFFF / unit, "os.Duration: the duration is too long");
        return Duration.from_nanoseconds(count * unit);
    }

    ## Returns the whole number of nanoseconds in this duration.
    ##
    ## @returns the length in nanoseconds
    nanoseconds(): ulong {
        return _nanoseconds;
    }

    ## Returns the whole number of microseconds in this duration, rounded
    ## down.
    ##
    ## @returns the length in microseconds
    microseconds(): ulong {
        return _nanoseconds / NANOSECONDS_PER_MICROSECOND;
    }

    ## Returns the whole number of milliseconds in this duration, rounded
    ## down.
    ##
    ## @returns the length in milliseconds
    milliseconds(): ulong {
        return _nanoseconds / NANOSECONDS_PER_MILLISECOND;
    }

    ## Returns the whole number of seconds in this duration, rounded down.
    ##
    ## @returns the length in seconds
    seconds(): ulong {
        return _nanoseconds / NANOSECONDS_PER_SECOND;
    }

    ## Returns this duration in seconds, with the fraction.
    ##
    ## @returns the length in seconds, as a `double`
    seconds_fraction(): double {
        return (_nanoseconds as double) / (NANOSECONDS_PER_SECOND as double);
    }

    ## Returns whether this duration is zero.
    ##
    ## @returns true for a zero-length duration
    is_zero(): bool {
        return _nanoseconds == 0;
    }

    ## Returns the sum of two durations.
    ##
    ## @param other the duration to add
    ## @returns the longer duration
    ## @panics if the sum does not fit in a `ulong` of nanoseconds
    +(other: Duration): Duration {
        var sum = _nanoseconds + other._nanoseconds;
        assert(sum >= _nanoseconds, "os.Duration: the duration is too long");
        return Duration.from_nanoseconds(sum);
    }

    ## Returns this duration less `other`.
    ##
    ## @param other the duration to take away
    ## @returns the difference
    ## @panics if `other` is longer than this duration: a duration is never
    ##   negative
    -(other: Duration): Duration {
        assert(other._nanoseconds <= _nanoseconds, "os.Duration: subtracting a longer duration");
        return Duration.from_nanoseconds(_nanoseconds - other._nanoseconds);
    }

    ## Returns this duration `times` times over.
    ##
    ## @param times the factor
    ## @returns the product
    ## @panics if the product does not fit in a `ulong` of nanoseconds
    *(times: ulong): Duration {
        if (_nanoseconds == 0) {
            return this;
        }
        return Duration._scaled(times, _nanoseconds);
    }

    ## Returns this duration split into `parts` equal parts, rounded down to
    ## a whole nanosecond.
    ##
    ## @param parts the divisor
    ## @returns the quotient
    ## @panics if `parts` is zero
    /(parts: ulong): Duration {
        assert(parts != 0, "os.Duration: dividing by zero");
        return Duration.from_nanoseconds(_nanoseconds / parts);
    }

    ## Returns whether this duration is shorter than `other`.
    ##
    ## @param other the duration to compare with
    ## @returns true when this one is shorter
    <(other: Duration): bool {
        return _nanoseconds < other._nanoseconds;
    }

    ## Returns whether this duration is shorter than or as long as `other`.
    ##
    ## @param other the duration to compare with
    ## @returns true when this one is not longer
    <=(other: Duration): bool {
        return _nanoseconds <= other._nanoseconds;
    }

    ## Returns whether this duration is longer than `other`.
    ##
    ## @param other the duration to compare with
    ## @returns true when this one is longer
    >(other: Duration): bool {
        return _nanoseconds > other._nanoseconds;
    }

    ## Returns whether this duration is longer than or as long as `other`.
    ##
    ## @param other the duration to compare with
    ## @returns true when this one is not shorter
    >=(other: Duration): bool {
        return _nanoseconds >= other._nanoseconds;
    }

    ## Returns this duration as text in the largest unit it reaches, with
    ## the fraction it needs and no trailing zeros: `2.5s`, `15ms`,
    ## `1.25µs`, `40ns`, `0s`.
    ##
    ## @returns the duration as text
    to_string(): String {
        if (_nanoseconds >= NANOSECONDS_PER_SECOND) {
            return _in_unit(NANOSECONDS_PER_SECOND, 9, "s");
        }
        if (_nanoseconds >= NANOSECONDS_PER_MILLISECOND) {
            return _in_unit(NANOSECONDS_PER_MILLISECOND, 6, "ms");
        }
        if (_nanoseconds >= NANOSECONDS_PER_MICROSECOND) {
            return _in_unit(NANOSECONDS_PER_MICROSECOND, 3, "µs");
        }
        if (_nanoseconds == 0) {
            return "0s";
        }
        return $"{_nanoseconds}ns";
    }

    # The whole units, then the fraction's `digits` digits without trailing
    # zeros.
    _in_unit(unit: ulong, digits: ulong, suffix: String): String {
        var whole = _nanoseconds / unit;
        var fraction = _nanoseconds % unit;
        if (fraction == 0) {
            return $"{whole}{suffix}";
        }
        var text = $"{fraction}";
        text = "0".repeat(digits - text.size) + text;
        var size = text.size;
        while (text.byte_at(size - 1) == '0') {
            size = size - 1;
        }
        return $"{whole}.{text.substr_bytes(0, size)}{suffix}";
    }
}

## A moment on a monotonic clock, for measuring how long something takes,
## like Rust's `std::time::Instant`.
##
## The clock only moves forward: setting the system's date and time does
## not change it. Its readings mean nothing by themselves, only the
## `Duration` between two of them, and they cannot be compared across
## processes or reboots. Use `SystemTime` for the date and time.
##
## The clock is `CLOCK_MONOTONIC` on Linux and macOS and
## `QueryPerformanceCounter` on Windows, read to the nanosecond.
##
## @example
##     import os;
##
##     main(): int {
##         var start = os.Instant.now();
##         var total = 0;
##         for (var i in 0..1000000) {
##             total = total + i;
##         }
##         var elapsed = os.Instant.now() - start;
##         print($"summed in {elapsed.milliseconds()} ms");
##         return 0;
##     }
[Value]
export struct Instant {
    var _nanoseconds: ulong;

    ## Makes the instant the clock started from; use `now()` to read the
    ## clock.
    construct() {}

    ## Reads the monotonic clock.
    ##
    ## @returns the current moment
    static now(): Instant {
        var instant = Instant();
        instant._nanoseconds = _os_sys_monotonic_nanoseconds();
        return instant;
    }

    ## Returns how long ago this instant was: `Instant.now() - this`.
    ##
    ## @returns the time since this instant
    elapsed(): Duration {
        return Instant.now() - this;
    }

    ## Returns the time from `earlier` to this instant.
    ##
    ## @param earlier an instant no later than this one
    ## @returns the time between them
    ## @panics if `earlier` is later than this instant
    -(earlier: Instant): Duration {
        assert(earlier._nanoseconds <= _nanoseconds, "os.Instant: subtracting a later instant");
        return Duration.from_nanoseconds(_nanoseconds - earlier._nanoseconds);
    }

    ## Returns the instant `duration` after this one.
    ##
    ## @param duration how far to move forward
    ## @returns the later instant
    ## @panics if the result does not fit the clock
    +(duration: Duration): Instant {
        var later = Instant();
        later._nanoseconds = _nanoseconds + duration._nanoseconds;
        assert(later._nanoseconds >= _nanoseconds, "os.Instant: the instant is out of range");
        return later;
    }

    ## Returns the instant `duration` before this one.
    ##
    ## @param duration how far to move back
    ## @returns the earlier instant
    ## @panics if the result is before the clock's start
    -(duration: Duration): Instant {
        assert(duration._nanoseconds <= _nanoseconds, "os.Instant: the instant is out of range");
        var earlier = Instant();
        earlier._nanoseconds = _nanoseconds - duration._nanoseconds;
        return earlier;
    }

    ## Returns whether this instant is earlier than `other`.
    ##
    ## @param other the instant to compare with
    ## @returns true when this one is earlier
    <(other: Instant): bool {
        return _nanoseconds < other._nanoseconds;
    }

    ## Returns whether this instant is earlier than or the same as `other`.
    ##
    ## @param other the instant to compare with
    ## @returns true when this one is not later
    <=(other: Instant): bool {
        return _nanoseconds <= other._nanoseconds;
    }

    ## Returns whether this instant is later than `other`.
    ##
    ## @param other the instant to compare with
    ## @returns true when this one is later
    >(other: Instant): bool {
        return _nanoseconds > other._nanoseconds;
    }

    ## Returns whether this instant is later than or the same as `other`.
    ##
    ## @param other the instant to compare with
    ## @returns true when this one is not earlier
    >=(other: Instant): bool {
        return _nanoseconds >= other._nanoseconds;
    }
}

## A date and time on the system's wall clock, counted in nanoseconds from
## the Unix epoch (1970-01-01 00:00:00 UTC), like Rust's
## `std::time::SystemTime`. It reaches from the year 1677 to 2262.
##
## The wall clock can jump, backwards too, when the system's time is set,
## so measure how long something takes with `Instant` instead. Dates, time
## zones and formatting are not part of `os`.
##
## @example
##     import os;
##
##     main(): int {
##         var now = os.SystemTime.now();
##         print($"{now.unix_seconds()} seconds since 1970");
##         return 0;
##     }
[Value]
export struct SystemTime {
    var _nanoseconds: long;

    ## Makes the Unix epoch, 1970-01-01 00:00:00 UTC.
    construct() {}

    ## Reads the wall clock.
    ##
    ## @returns the current date and time
    static now(): SystemTime {
        return SystemTime.from_unix_nanoseconds(_os_sys_system_nanoseconds());
    }

    ## Returns the time `nanoseconds` nanoseconds after the Unix epoch.
    ##
    ## @param nanoseconds nanoseconds since the epoch; negative for earlier
    ##   times
    ## @returns the time
    static from_unix_nanoseconds(nanoseconds: long): SystemTime {
        var time = SystemTime();
        time._nanoseconds = nanoseconds;
        return time;
    }

    ## Returns the time `seconds` seconds after the Unix epoch, as file
    ## systems and most protocols record it.
    ##
    ## @param seconds seconds since the epoch; negative for earlier times
    ## @returns the time
    ## @panics if the time is outside the years 1677 to 2262
    static from_unix_seconds(seconds: long): SystemTime {
        var limit = 9223372036 as long;
        assert(seconds <= limit && seconds >= 0 - limit, "os.SystemTime: the time is out of range");
        return SystemTime.from_unix_nanoseconds(seconds * (NANOSECONDS_PER_SECOND as long));
    }

    ## Returns the nanoseconds from the Unix epoch to this time.
    ##
    ## @returns nanoseconds since the epoch; negative for earlier times
    unix_nanoseconds(): long {
        return _nanoseconds;
    }

    ## Returns the milliseconds from the Unix epoch to this time, rounded
    ## down (towards the past).
    ##
    ## @returns milliseconds since the epoch; negative for earlier times
    unix_milliseconds(): long {
        return _floor_divide(NANOSECONDS_PER_MILLISECOND as long);
    }

    ## Returns the seconds from the Unix epoch to this time, rounded down
    ## (towards the past).
    ##
    ## @returns seconds since the epoch; negative for earlier times
    unix_seconds(): long {
        return _floor_divide(NANOSECONDS_PER_SECOND as long);
    }

    _floor_divide(unit: long): long {
        var quotient = _nanoseconds / unit;
        if (_nanoseconds % unit < 0) {
            quotient = quotient - 1;
        }
        return quotient;
    }

    ## Returns the time from `earlier` to this time, or none when `earlier`
    ## is later: the wall clock can be set back between two readings.
    ##
    ## @param earlier the time to measure from
    ## @returns the time between them, or none when `earlier` is later
    duration_since(earlier: SystemTime): Duration? {
        if (earlier._nanoseconds > _nanoseconds) {
            return Optional<Duration>.Empty;
        }
        var span = (_nanoseconds - earlier._nanoseconds) as ulong;
        return Optional<Duration>.Value(Duration.from_nanoseconds(span));
    }

    ## Returns how long ago this time was on the wall clock, or none when it
    ## is in the future.
    ##
    ## @returns the time since this one, or none when it is later than now
    elapsed(): Duration? {
        return SystemTime.now().duration_since(this);
    }

    ## Returns the time `duration` after this one.
    ##
    ## @param duration how far to move forward
    ## @returns the later time
    ## @panics if the result is after the year 2262
    +(duration: Duration): SystemTime {
        var limit = 9223372036854775807 as ulong;
        assert(
            duration._nanoseconds <= limit && _nanoseconds <= (limit - duration._nanoseconds) as long,
            "os.SystemTime: the time is out of range"
        );
        return SystemTime.from_unix_nanoseconds(_nanoseconds + duration._nanoseconds as long);
    }

    ## Returns the time `duration` before this one.
    ##
    ## @param duration how far to move back
    ## @returns the earlier time
    ## @panics if the result is before the year 1677
    -(duration: Duration): SystemTime {
        var limit = 9223372036854775807 as ulong;
        assert(
            duration._nanoseconds <= limit && _nanoseconds >= (0 - 9223372036854775807) + duration._nanoseconds as long,
            "os.SystemTime: the time is out of range"
        );
        return SystemTime.from_unix_nanoseconds(_nanoseconds - duration._nanoseconds as long);
    }

    ## Returns whether this time is earlier than `other`.
    ##
    ## @param other the time to compare with
    ## @returns true when this one is earlier
    <(other: SystemTime): bool {
        return _nanoseconds < other._nanoseconds;
    }

    ## Returns whether this time is earlier than or the same as `other`.
    ##
    ## @param other the time to compare with
    ## @returns true when this one is not later
    <=(other: SystemTime): bool {
        return _nanoseconds <= other._nanoseconds;
    }

    ## Returns whether this time is later than `other`.
    ##
    ## @param other the time to compare with
    ## @returns true when this one is later
    >(other: SystemTime): bool {
        return _nanoseconds > other._nanoseconds;
    }

    ## Returns whether this time is later than or the same as `other`.
    ##
    ## @param other the time to compare with
    ## @returns true when this one is not earlier
    >=(other: SystemTime): bool {
        return _nanoseconds >= other._nanoseconds;
    }
}
