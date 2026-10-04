## Fixed offsets from UTC, `Offset`, and the date and time at one,
## `OffsetDateTime`: an instant written the way RFC 3339 and TOML write it.

import os;
import "civil";
import "format";

## A fixed offset from UTC, east positive: `+02:00` for Central European
## Summer Time, `-05:00` for US Eastern Standard Time, `+00:00` for UTC.
##
## A value struct: copied, compared with `==`, and never allocated. It is
## less than a day either way, to the second. Its text is `+02:00`, with the
## seconds when there are any (`+00:19:32`).
##
## @example
##     import time;
##
##     main(): int {
##         var india = time.Offset.from_hours(5, 30);
##         print(india);            # +05:30
##         print(india.seconds);    # 19800
##         return 0;
##     }
[Value]
export struct Offset {
    ## The offset in seconds, east of UTC positive.
    var seconds: int { get; }

    ## Makes the offset `seconds` seconds east of UTC (west when negative);
    ## with no argument, UTC itself.
    ##
    ## @param seconds the offset in seconds, east positive
    ## @panics if the offset is a day or more either way
    construct(seconds: int = 0) {
        assert(seconds > -86400 && seconds < 86400, $"time.Offset: {seconds} seconds is not an offset");
        this.seconds = seconds;
    }

    ## Returns UTC, the zero offset.
    ##
    ## @returns the zero offset
    static utc(): Offset {
        return Offset();
    }

    ## Returns the offset `hours` hours and `minutes` minutes from UTC. Both
    ## take the offset's sign: `from_hours(-3, -30)` is `-03:30`, and
    ## `from_hours(0, -30)` is `-00:30`.
    ##
    ## @param hours whole hours, east positive
    ## @param minutes minutes on top of the hours, with the same sign
    ## @returns the offset
    ## @panics if the offset is a day or more either way
    static from_hours(hours: int, minutes: int = 0): Offset {
        return Offset(hours * 3600 + minutes * 60);
    }

    ## Returns the offset written as `+02:00`, `-0530`, `+02` or `Z` (UTC),
    ## or an error when `text` is not one.
    ##
    ## @param text the text to read
    ## @returns the offset, or an error saying what is wrong with `text`
    static parse(text: String): Result<Offset> {
        var scanner = _TimeScanner(text);
        var offset = scanner.offset(true);
        if (offset.is_err() || !scanner.at_end()) {
            return Result<Offset>.err(Error($"invalid UTC offset '{text}'"));
        }
        return offset;
    }

    ## Returns whether this is UTC, the zero offset.
    ##
    ## @returns true for `+00:00`
    is_utc(): bool {
        return seconds == 0;
    }

    ## Returns the offset as text: `+02:00`, `-05:30`, `+00:00`, with the
    ## seconds when there are any (`+00:19:32`).
    ##
    ## @returns the offset as text
    to_string(): String {
        var out = StringBuilder();
        _time_write_offset(out, seconds, true, false);
        return out.to_string();
    }
}

extend Offset with ToString;

## A date and time at a fixed offset from UTC, such as
## `2024-03-01T09:00:00+01:00`: an instant, together with the local date and
## time it was written in. This is RFC 3339's timestamp and TOML's offset
## date-time.
##
## A value struct: copied and never allocated. `==` compares the date, time
## and offset, so the same instant at two offsets is not `==`; compare
## instants with `to_system_time()`, or with `<` and the other comparisons,
## which compare instants. Its text is RFC 3339's, with `Z` for UTC.
##
## @example
##     import time;
##
##     main(): int {
##         var meeting = time.OffsetDateTime.parse("2024-03-01T09:00:00+01:00").value();
##         print(meeting.to_utc());   # 2024-03-01T08:00:00Z
##         print(meeting.to_http_date());   # Fri, 01 Mar 2024 08:00:00 GMT
##         return 0;
##     }
[Value]
export struct OffsetDateTime {
    ## The local date and time at `offset`.
    var date_time: DateTime { get; }
    ## The offset from UTC that `date_time` is at.
    var offset: Offset { get; }

    ## Makes the date and time `date_time` at `offset`; with no arguments,
    ## the Unix epoch, 1970-01-01T00:00:00Z.
    ##
    ## @param date_time the local date and time
    ## @param offset its offset from UTC
    construct(date_time: DateTime = DateTime(), offset: Offset = Offset()) {
        this.date_time = date_time;
        this.offset = offset;
    }

    ## Returns the date and time of a wall-clock reading at `offset`.
    ##
    ## @param time the instant
    ## @param offset the offset to show it at; UTC by default
    ## @returns the instant's date and time at `offset`
    static from_system_time(time: os.SystemTime, offset: Offset = Offset()): OffsetDateTime {
        var nanoseconds = time.unix_nanoseconds();
        var local = DateTime.from_unix_seconds(
            _time_floor_divide(nanoseconds, NANOSECONDS_PER_SECOND) + offset.seconds,
            _time_floor_modulo(nanoseconds, NANOSECONDS_PER_SECOND) as int
        );
        return OffsetDateTime(local, offset);
    }

    ## Returns the RFC 3339 timestamp in `text`, such as
    ## `2024-03-01T09:00:00+01:00` or `2024-03-01T08:00:00.5Z`, or an error
    ## when it is not one. A space or a lowercase `t` may stand for the `T`
    ## and a lowercase `z` for the `Z`, and the seconds may be left out, as
    ## TOML allows.
    ##
    ## @param text the text to read
    ## @returns the date and time, or an error saying what is wrong with
    ##   `text`
    static parse(text: String): Result<OffsetDateTime> {
        var scanner = _TimeScanner(text);
        var date_time = scanner.date_time();
        if (date_time.is_ok()) {
            var offset = scanner.offset(false);
            if (offset.is_ok() && scanner.at_end()) {
                return Result<OffsetDateTime>.ok(OffsetDateTime(date_time.value(), offset.value()));
            }
        }
        return Result<OffsetDateTime>.err(Error($"invalid RFC 3339 date and time '{text}'"));
    }

    ## Returns the HTTP date in `text`, as RFC 9110 defines it, or an error
    ## when it is not one. It reads the preferred IMF-fixdate
    ## (`Sun, 06 Nov 1994 08:49:37 GMT`) and the two obsolete forms that
    ## servers must still accept: RFC 850's (`Sunday, 06-Nov-94 08:49:37
    ## GMT`, where a two-digit year from 70 is in the 1900s and below 70 in
    ## the 2000s) and C's `asctime` (`Sun Nov  6 08:49:37 1994`). The
    ## weekday must match the date.
    ##
    ## @param text the text to read
    ## @returns the date and time in UTC, or an error saying what is wrong
    ##   with `text`
    static parse_http_date(text: String): Result<OffsetDateTime> {
        var parsed = _time_parse_http_date(text);
        if (parsed.is_empty()) {
            return Result<OffsetDateTime>.err(Error($"invalid HTTP date '{text}'"));
        }
        return Result<OffsetDateTime>.ok(OffsetDateTime(parsed.value(), Offset()));
    }

    ## The local date, as `date_time.date`.
    var date: Date {
        get {
            return date_time.date;
        }
    }
    ## The local time of day, as `date_time.time`.
    var time: Time {
        get {
            return date_time.time;
        }
    }

    ## Returns the seconds from the Unix epoch to this instant, rounded
    ## down.
    ##
    ## @returns seconds since 1970-01-01T00:00:00Z; negative for earlier
    unix_seconds(): long {
        return date_time.unix_seconds() - offset.seconds;
    }

    ## Returns this instant as a `SystemTime`.
    ##
    ## @returns the instant
    ## @panics if the instant is outside what a `SystemTime` reaches, the
    ##   years 1677 to 2262
    to_system_time(): os.SystemTime {
        return _time_system_time(unix_seconds(), date_time.nanosecond);
    }

    ## Returns the same instant at another offset.
    ##
    ## @param offset the offset to show the instant at
    ## @returns the date and time at `offset`
    to_offset(offset: Offset): OffsetDateTime {
        var local = DateTime.from_unix_seconds(unix_seconds() + offset.seconds, date_time.nanosecond);
        return OffsetDateTime(local, offset);
    }

    ## Returns the same instant in UTC.
    ##
    ## @returns the date and time at offset zero
    to_utc(): OffsetDateTime {
        return to_offset(Offset());
    }

    ## Returns the day of the week of the local date.
    ##
    ## @returns the weekday
    weekday(): Weekday {
        return date_time.weekday();
    }

    ## Returns the instant `duration` later, at the same offset.
    ##
    ## @param duration how far to move forward
    ## @returns the later date and time
    +(duration: os.Duration): OffsetDateTime {
        return OffsetDateTime(date_time + duration, offset);
    }

    ## Returns the instant `duration` earlier, at the same offset.
    ##
    ## @param duration how far to move back
    ## @returns the earlier date and time
    -(duration: os.Duration): OffsetDateTime {
        return OffsetDateTime(date_time - duration, offset);
    }

    ## Returns whether this instant is earlier than `other`, whatever their
    ## offsets.
    ##
    ## @param other the instant to compare with
    ## @returns true when this one is earlier
    <(other: OffsetDateTime): bool {
        return _compare(other) < 0;
    }

    ## Returns whether this instant is earlier than or the same as `other`.
    ##
    ## @param other the instant to compare with
    ## @returns true when this one is not later
    <=(other: OffsetDateTime): bool {
        return _compare(other) <= 0;
    }

    ## Returns whether this instant is later than `other`, whatever their
    ## offsets.
    ##
    ## @param other the instant to compare with
    ## @returns true when this one is later
    >(other: OffsetDateTime): bool {
        return _compare(other) > 0;
    }

    ## Returns whether this instant is later than or the same as `other`.
    ##
    ## @param other the instant to compare with
    ## @returns true when this one is not earlier
    >=(other: OffsetDateTime): bool {
        return _compare(other) >= 0;
    }

    _compare(other: OffsetDateTime): int {
        var a = unix_seconds();
        var b = other.unix_seconds();
        if (a != b) {
            return a < b ? -1 : 1;
        }
        var c = date_time.nanosecond;
        var d = other.date_time.nanosecond;
        if (c != d) {
            return c < d ? -1 : 1;
        }
        return 0;
    }

    ## Returns the date and time as text laid out by `pattern`, whose `%`
    ## codes are those of C's `strftime` (see the
    ## [time module](time-module.md)). `%z` is the offset as `+0200`, `%:z`
    ## as `+02:00`, and `%s` the Unix seconds.
    ##
    ## @param pattern the layout, such as `"%Y-%m-%d %H:%M %z"`
    ## @returns the formatted date and time
    ## @panics if `pattern` has an unknown code
    format(pattern: String): String {
        return _time_format(pattern, date_time.date, date_time.time, Optional<int>.Value(offset.seconds));
    }

    ## Returns the instant as an HTTP date in UTC, the IMF-fixdate of RFC
    ## 9110 that `Date` and `Last-Modified` headers carry:
    ## `Fri, 01 Mar 2024 08:00:00 GMT`. The fraction of a second is dropped.
    ##
    ## @returns the date as an HTTP date
    to_http_date(): String {
        return to_utc().format("%a, %d %b %Y %H:%M:%S GMT");
    }

    ## Returns the date and time as an RFC 3339 timestamp:
    ## `2024-03-01T09:00:00+01:00`, `Z` for UTC, with the fraction of a
    ## second when it is not zero.
    ##
    ## @returns the date and time as text
    to_string(): String {
        var out = StringBuilder();
        _time_write_date(out, date_time.date);
        out.append("T");
        _time_write_time(out, date_time.time);
        _time_write_offset(out, offset.seconds, true, true);
        return out.to_string();
    }
}

extend OffsetDateTime with ToString;

_time_floor_divide(value: long, unit: long): long {
    var quotient = value / unit;
    if (value % unit < 0) {
        quotient = quotient - 1;
    }
    return quotient;
}

_time_floor_modulo(value: long, unit: long): long {
    var rest = value % unit;
    return rest < 0 ? rest + unit : rest;
}
