## Calendar dates and times of day with no time zone: `Date`, `Time`,
## `DateTime` and `Weekday`, on the proleptic Gregorian calendar, plus
## `is_leap_year` and `days_in_month`.

import os;
import "format";

const SECONDS_PER_DAY: long = 86400;
const NANOSECONDS_PER_SECOND: long = 1000000000;
const MINIMUM_YEAR: int = -999999;
const MAXIMUM_YEAR: int = 999999;

## Returns whether `year` is a leap year on the Gregorian calendar: divisible
## by 4, except centuries not divisible by 400. Year 0 (1 BC) is one.
##
## @param year the year
## @returns true when February of `year` has 29 days
## @example
##     assert(time.is_leap_year(2024) && !time.is_leap_year(1900), "leap years");
export is_leap_year(year: int): bool {
    return _time_is_leap_year(year);
}

## Returns the number of days in `month` of `year`: 28 to 31.
##
## @param year the year, for February
## @param month the month, 1 (January) to 12 (December)
## @returns the number of days in that month
## @panics if `month` is not from 1 to 12
export days_in_month(year: int, month: int): int {
    assert(month >= 1 && month <= 12, $"time.days_in_month: {month} is not a month");
    return _time_days_in_month(year, month);
}

## A day of the week. Each case's value is its ISO 8601 number, Monday 1 to
## Sunday 7, so `day as int` gives that number, and `day.name()` its English
## name.
export enum Weekday {
    ## The first day of the ISO week.
    Monday = 1,
    ## The second day.
    Tuesday,
    ## The third day.
    Wednesday,
    ## The fourth day.
    Thursday,
    ## The fifth day.
    Friday,
    ## The sixth day.
    Saturday,
    ## The seventh and last day of the ISO week.
    Sunday,

    ## Returns the weekday's English name, as `name()` does: `Monday`.
    ##
    ## @returns the name
    to_string(): String {
        return name();
    }
}

## A date on the proleptic Gregorian calendar, which extends the calendar's
## rules to years before it was adopted: a year, a month (1 to 12) and a
## day of the month (1 to 31), with no time of day or time zone.
##
## A value struct: copied, compared with `==`, `<` and the other
## comparisons, and never allocated. Years run from -999999 to 999999; year
## 0 is 1 BC. Its text is ISO 8601's `2024-02-29`.
##
## @example
##     import time;
##
##     main(): int {
##         var day = time.Date(2024, 2, 28).add_days(1);
##         print(day);               # 2024-02-29
##         print(day.weekday());     # Thursday
##         return 0;
##     }
[Value]
export struct Date {
    ## The year: 2024, or 0 for 1 BC and -1 for 2 BC.
    var year: int { get; }
    ## The month, 1 (January) to 12 (December).
    var month: int { get; }
    ## The day of the month, 1 to 31.
    var day: int { get; }

    ## Makes the date `year`-`month`-`day`; with no arguments, the Unix
    ## epoch's 1970-01-01.
    ##
    ## @param year the year, from -999999 to 999999
    ## @param month the month, 1 to 12
    ## @param day the day of the month, 1 to the month's last day
    ## @panics if the parts do not name a date: use `checked` for parts that
    ##   come from outside the program
    construct(year: int = 1970, month: int = 1, day: int = 1) {
        assert(_time_is_date(year, month, day), $"time.Date: {year}-{month}-{day} is not a date");
        this.year = year;
        this.month = month;
        this.day = day;
    }

    ## Returns the date `year`-`month`-`day`, or none when the parts do not
    ## name one, such as February 30.
    ##
    ## @param year the year, from -999999 to 999999
    ## @param month the month, 1 to 12
    ## @param day the day of the month
    ## @returns the date, or none
    static checked(year: int, month: int, day: int): Date? {
        if (!_time_is_date(year, month, day)) {
            return Optional<Date>.Empty;
        }
        return Optional<Date>.Value(Date(year, month, day));
    }

    ## Returns the date `days` days after 1970-01-01.
    ##
    ## @param days days since the Unix epoch; negative for earlier dates
    ## @returns the date
    ## @panics if the date is outside the years -999999 to 999999
    static from_days(days: long): Date {
        var (year, month, day) = _time_civil_from_days(days);
        assert(year >= MINIMUM_YEAR && year <= MAXIMUM_YEAR, "time.Date: the date is out of range");
        return Date(year as int, month, day);
    }

    ## Returns the date in the ISO 8601 form `2024-02-29`, or none when
    ## `text` is not a date. Years outside 0 to 9999 take a sign and more
    ## digits (`+10000-01-01`, `-0001-12-31`).
    ##
    ## @param text the text to read
    ## @returns the date, or an error saying what is wrong with `text`
    static parse(text: String): Result<Date> {
        var scanner = _TimeScanner(text);
        var date = scanner.date();
        if (date.is_err() || !scanner.at_end()) {
            return Result<Date>.err(Error($"invalid date '{text}'"));
        }
        return date;
    }

    ## Returns the number of days from 1970-01-01 to this date.
    ##
    ## @returns days since the Unix epoch; negative for earlier dates
    days(): long {
        return _time_days_from_civil(year, month, day);
    }

    ## Returns the day of the week.
    ##
    ## @returns the weekday
    weekday(): Weekday {
        var days = days() % 7;
        if (days < 0) {
            days = days + 7;
        }
        # 1970-01-01 was a Thursday, ISO day 4.
        return Weekday.from_value(((days + 3) % 7 + 1) as int).value();
    }

    ## Returns the day of the year, 1 for January 1 to 366 for December 31
    ## of a leap year.
    ##
    ## @returns the ordinal day
    day_of_year(): int {
        return (days() - _time_days_from_civil(year, 1, 1) + 1) as int;
    }

    ## Returns whether this date's year is a leap year.
    ##
    ## @returns true when the year has a February 29
    is_leap_year(): bool {
        return _time_is_leap_year(year);
    }

    ## Returns the number of days in this date's month.
    ##
    ## @returns 28 to 31
    days_in_month(): int {
        return _time_days_in_month(year, month);
    }

    ## Returns the date `days` days later, or earlier when `days` is
    ## negative.
    ##
    ## @param days the number of days to move
    ## @returns the date
    ## @panics if the date is outside the years -999999 to 999999
    add_days(days: long): Date {
        return Date.from_days(days() + days);
    }

    ## Returns the date `months` months later, or earlier when `months` is
    ## negative. A day past the end of the new month becomes its last day:
    ## a month after January 31 is February 28 or 29.
    ##
    ## @param months the number of months to move
    ## @returns the date
    ## @panics if the date is outside the years -999999 to 999999
    add_months(months: long): Date {
        var index = (year as long) * 12 + (month - 1) + months;
        var new_year = index / 12;
        var new_month = index % 12;
        if (new_month < 0) {
            new_month = new_month + 12;
            new_year = new_year - 1;
        }
        assert(new_year >= MINIMUM_YEAR && new_year <= MAXIMUM_YEAR, "time.Date: the date is out of range");
        var last = _time_days_in_month(new_year as int, (new_month + 1) as int);
        return Date(new_year as int, (new_month + 1) as int, day < last ? day : last);
    }

    ## Returns the date `years` years later, or earlier when `years` is
    ## negative. February 29 becomes February 28 in a year that is not a
    ## leap year.
    ##
    ## @param years the number of years to move
    ## @returns the date
    ## @panics if the date is outside the years -999999 to 999999
    add_years(years: long): Date {
        return add_months(years * 12);
    }

    ## Returns the number of days from `earlier` to this date: negative when
    ## `earlier` is later.
    ##
    ## @param earlier the date to count from
    ## @returns the number of days between them
    days_since(earlier: Date): long {
        return days() - earlier.days();
    }

    ## Returns the start of this date, midnight, as a `DateTime`.
    ##
    ## @param time the time of day; midnight by default
    ## @returns the date and time
    at(time: Time = Time()): DateTime {
        return DateTime.combine(this, time);
    }

    ## Returns whether this date is earlier than `other`.
    ##
    ## @param other the date to compare with
    ## @returns true when this one is earlier
    <(other: Date): bool {
        return _compare(other) < 0;
    }

    ## Returns whether this date is earlier than or the same as `other`.
    ##
    ## @param other the date to compare with
    ## @returns true when this one is not later
    <=(other: Date): bool {
        return _compare(other) <= 0;
    }

    ## Returns whether this date is later than `other`.
    ##
    ## @param other the date to compare with
    ## @returns true when this one is later
    >(other: Date): bool {
        return _compare(other) > 0;
    }

    ## Returns whether this date is later than or the same as `other`.
    ##
    ## @param other the date to compare with
    ## @returns true when this one is not earlier
    >=(other: Date): bool {
        return _compare(other) >= 0;
    }

    _compare(other: Date): int {
        if (year != other.year) {
            return year < other.year ? -1 : 1;
        }
        if (month != other.month) {
            return month < other.month ? -1 : 1;
        }
        if (day != other.day) {
            return day < other.day ? -1 : 1;
        }
        return 0;
    }

    ## Returns the date as text laid out by `pattern`, whose `%` codes are
    ## those of C's `strftime` (see the [time module](time-module.md)). The
    ## time of day is midnight, and an offset code (`%z`) panics.
    ##
    ## @param pattern the layout, such as `"%d %B %Y"`
    ## @returns the formatted date
    ## @panics if `pattern` has an unknown code, or an offset code
    format(pattern: String): String {
        return _time_format(pattern, this, Time(), Optional<int>.Empty);
    }

    ## Returns the date in ISO 8601 form: `2024-02-29`.
    ##
    ## @returns the date as text
    to_string(): String {
        var out = StringBuilder();
        _time_write_date(out, this);
        return out.to_string();
    }
}

extend Date with ToString;

## A time of day with no date or time zone: an hour (0 to 23), a minute,
## a second and a nanosecond. Leap seconds are not represented, as in Unix
## time.
##
## A value struct: copied, compared with `==`, `<` and the other
## comparisons, and never allocated. Its text is ISO 8601's `08:30:00`,
## with a fraction of a second when there is one (`08:30:00.25`).
##
## @example
##     import time;
##
##     main(): int {
##         var lunch = time.Time(12, 30);
##         print(lunch);   # 12:30:00
##         return 0;
##     }
[Value]
export struct Time {
    ## The hour, 0 to 23.
    var hour: int { get; }
    ## The minute, 0 to 59.
    var minute: int { get; }
    ## The second, 0 to 59.
    var second: int { get; }
    ## The nanosecond within the second, 0 to 999999999.
    var nanosecond: int { get; }

    ## Makes the time `hour`:`minute`:`second`; with no arguments,
    ## midnight.
    ##
    ## @param hour the hour, 0 to 23
    ## @param minute the minute, 0 to 59
    ## @param second the second, 0 to 59
    ## @param nanosecond the nanosecond within the second, 0 to 999999999
    ## @panics if a part is out of range: use `checked` for parts that come
    ##   from outside the program
    construct(hour: int = 0, minute: int = 0, second: int = 0, nanosecond: int = 0) {
        assert(
            _time_is_time(hour, minute, second, nanosecond),
            $"time.Time: {hour}:{minute}:{second}.{nanosecond} is not a time of day"
        );
        this.hour = hour;
        this.minute = minute;
        this.second = second;
        this.nanosecond = nanosecond;
    }

    ## Returns the time `hour`:`minute`:`second`, or none when a part is out
    ## of range.
    ##
    ## @param hour the hour, 0 to 23
    ## @param minute the minute, 0 to 59
    ## @param second the second, 0 to 59
    ## @param nanosecond the nanosecond within the second
    ## @returns the time, or none
    static checked(hour: int, minute: int, second: int = 0, nanosecond: int = 0): Time? {
        if (!_time_is_time(hour, minute, second, nanosecond)) {
            return Optional<Time>.Empty;
        }
        return Optional<Time>.Value(Time(hour, minute, second, nanosecond));
    }

    ## Returns the time `nanoseconds` nanoseconds after midnight.
    ##
    ## @param nanoseconds nanoseconds since midnight, less than a day's
    ## @returns the time
    ## @panics if `nanoseconds` is negative or a day or more
    static from_nanoseconds(nanoseconds: long): Time {
        assert(
            nanoseconds >= 0 && nanoseconds < SECONDS_PER_DAY * NANOSECONDS_PER_SECOND,
            "time.Time: the time is not within a day"
        );
        var seconds = nanoseconds / NANOSECONDS_PER_SECOND;
        return Time(
            (seconds / 3600) as int,
            (seconds / 60 % 60) as int,
            (seconds % 60) as int,
            (nanoseconds % NANOSECONDS_PER_SECOND) as int
        );
    }

    ## Returns the time in the ISO 8601 form `08:30:00`, with an optional
    ## fraction of a second (`08:30:00.25`), or an error when `text` is not
    ## a time. The seconds may be left out (`08:30`), as TOML 1.1 allows.
    ##
    ## @param text the text to read
    ## @returns the time, or an error saying what is wrong with `text`
    static parse(text: String): Result<Time> {
        var scanner = _TimeScanner(text);
        var time = scanner.time();
        if (time.is_err() || !scanner.at_end()) {
            return Result<Time>.err(Error($"invalid time '{text}'"));
        }
        return time;
    }

    ## Returns the number of nanoseconds since midnight.
    ##
    ## @returns nanoseconds since midnight
    nanoseconds(): long {
        return seconds() * NANOSECONDS_PER_SECOND + nanosecond;
    }

    ## Returns the number of whole seconds since midnight.
    ##
    ## @returns seconds since midnight
    seconds(): long {
        return (hour as long) * 3600 + minute * 60 + second;
    }

    ## Returns whether this time is earlier in the day than `other`.
    ##
    ## @param other the time to compare with
    ## @returns true when this one is earlier
    <(other: Time): bool {
        return nanoseconds() < other.nanoseconds();
    }

    ## Returns whether this time is earlier than or the same as `other`.
    ##
    ## @param other the time to compare with
    ## @returns true when this one is not later
    <=(other: Time): bool {
        return nanoseconds() <= other.nanoseconds();
    }

    ## Returns whether this time is later in the day than `other`.
    ##
    ## @param other the time to compare with
    ## @returns true when this one is later
    >(other: Time): bool {
        return nanoseconds() > other.nanoseconds();
    }

    ## Returns whether this time is later than or the same as `other`.
    ##
    ## @param other the time to compare with
    ## @returns true when this one is not earlier
    >=(other: Time): bool {
        return nanoseconds() >= other.nanoseconds();
    }

    ## Returns the time as text laid out by `pattern`, whose `%` codes are
    ## those of C's `strftime` (see the [time module](time-module.md)). The
    ## date is 1970-01-01, and an offset code (`%z`) panics.
    ##
    ## @param pattern the layout, such as `"%H:%M"`
    ## @returns the formatted time
    ## @panics if `pattern` has an unknown code, or an offset code
    format(pattern: String): String {
        return _time_format(pattern, Date(), this, Optional<int>.Empty);
    }

    ## Returns the time in ISO 8601 form: `08:30:00`, with the fraction of a
    ## second when it is not zero, without trailing zeros (`08:30:00.25`).
    ##
    ## @returns the time as text
    to_string(): String {
        var out = StringBuilder();
        _time_write_time(out, this);
        return out.to_string();
    }
}

extend Time with ToString;

## A date and a time of day with no time zone, such as a meeting's
## `2024-03-01 09:00` written down without saying where. TOML calls it a
## local date-time. Attach an offset with `OffsetDateTime`, or a zone's
## rules with `TimeZone.at_local`, to name an instant.
##
## A value struct: copied, compared with `==`, `<` and the other
## comparisons, and never allocated. Its text is ISO 8601's
## `2024-03-01T09:00:00`.
##
## @example
##     import time;
##
##     main(): int {
##         var start = time.DateTime(2024, 3, 1, 9, 0);
##         var end = start + os.Duration.from_seconds(90 * 60);
##         print(end);   # 2024-03-01T10:30:00
##         return 0;
##     }
[Value]
export struct DateTime {
    ## The date.
    var date: Date { get; }
    ## The time of day.
    var time: Time { get; }

    ## Makes the date and time from its parts; with no arguments, the Unix
    ## epoch's 1970-01-01T00:00:00.
    ##
    ## @param year the year, from -999999 to 999999
    ## @param month the month, 1 to 12
    ## @param day the day of the month
    ## @param hour the hour, 0 to 23
    ## @param minute the minute, 0 to 59
    ## @param second the second, 0 to 59
    ## @param nanosecond the nanosecond within the second
    ## @panics if the parts do not name a date and time
    construct(
        year: int = 1970,
        month: int = 1,
        day: int = 1,
        hour: int = 0,
        minute: int = 0,
        second: int = 0,
        nanosecond: int = 0
    ) {
        this.date = Date(year, month, day);
        this.time = Time(hour, minute, second, nanosecond);
    }

    ## Returns `date` at `time`.
    ##
    ## @param date the date
    ## @param time the time of day
    ## @returns the date and time
    static combine(date: Date, time: Time): DateTime {
        var result = DateTime();
        result.date = date;
        result.time = time;
        return result;
    }

    ## Returns the date and time `nanoseconds` nanoseconds after
    ## 1970-01-01T00:00:00, counting every day as 86400 seconds.
    ##
    ## @param nanoseconds nanoseconds since the epoch; negative for earlier
    ## @returns the date and time
    static from_unix_nanoseconds(nanoseconds: long): DateTime {
        var per_day = SECONDS_PER_DAY * NANOSECONDS_PER_SECOND;
        var days = nanoseconds / per_day;
        var rest = nanoseconds % per_day;
        if (rest < 0) {
            rest = rest + per_day;
            days = days - 1;
        }
        return DateTime.combine(Date.from_days(days), Time.from_nanoseconds(rest));
    }

    ## Returns the date and time `seconds` seconds after
    ## 1970-01-01T00:00:00, counting every day as 86400 seconds, as Unix
    ## time does. Reaches further than a `SystemTime`.
    ##
    ## @param seconds seconds since the epoch; negative for earlier
    ## @param nanosecond the nanosecond within the second
    ## @returns the date and time
    ## @panics if `nanosecond` is not from 0 to 999999999, or the date is
    ##   outside the years -999999 to 999999
    static from_unix_seconds(seconds: long, nanosecond: int = 0): DateTime {
        var days = seconds / SECONDS_PER_DAY;
        var rest = seconds % SECONDS_PER_DAY;
        if (rest < 0) {
            rest = rest + SECONDS_PER_DAY;
            days = days - 1;
        }
        return DateTime.combine(
            Date.from_days(days), Time((rest / 3600) as int, (rest / 60 % 60) as int, (rest % 60) as int, nanosecond)
        );
    }

    ## Returns the date and time in UTC of a wall-clock reading.
    ##
    ## @param time the instant
    ## @returns its date and time in UTC
    static from_system_time(time: os.SystemTime): DateTime {
        return DateTime.from_unix_nanoseconds(time.unix_nanoseconds());
    }

    ## Returns the date and time in the ISO 8601 form
    ## `2024-03-01T09:00:00`, or an error when `text` is not one. A space or
    ## a lowercase `t` may stand for the `T`, as TOML allows, and the
    ## seconds may be left out.
    ##
    ## @param text the text to read
    ## @returns the date and time, or an error saying what is wrong with
    ##   `text`
    static parse(text: String): Result<DateTime> {
        var scanner = _TimeScanner(text);
        var date_time = scanner.date_time();
        if (date_time.is_err() || !scanner.at_end()) {
            return Result<DateTime>.err(Error($"invalid date and time '{text}'"));
        }
        return date_time;
    }

    ## Returns the number of seconds from 1970-01-01T00:00:00 to this date
    ## and time, rounded down, counting every day as 86400 seconds.
    ##
    ## @returns seconds since the epoch; negative for earlier
    unix_seconds(): long {
        return date.days() * SECONDS_PER_DAY + time.seconds();
    }

    ## Returns this date and time as a `SystemTime`, reading it as UTC.
    ##
    ## @returns the instant
    ## @panics if the date is outside what a `SystemTime` reaches, the
    ##   years 1677 to 2262
    to_system_time(): os.SystemTime {
        return _time_system_time(unix_seconds(), time.nanosecond);
    }

    ## The year, as `date.year`.
    var year: int {
        get {
            return date.year;
        }
    }
    ## The month, 1 to 12, as `date.month`.
    var month: int {
        get {
            return date.month;
        }
    }
    ## The day of the month, as `date.day`.
    var day: int {
        get {
            return date.day;
        }
    }
    ## The hour, 0 to 23, as `time.hour`.
    var hour: int {
        get {
            return time.hour;
        }
    }
    ## The minute, as `time.minute`.
    var minute: int {
        get {
            return time.minute;
        }
    }
    ## The second, as `time.second`.
    var second: int {
        get {
            return time.second;
        }
    }
    ## The nanosecond within the second, as `time.nanosecond`.
    var nanosecond: int {
        get {
            return time.nanosecond;
        }
    }

    ## Returns the day of the week.
    ##
    ## @returns the weekday
    weekday(): Weekday {
        return date.weekday();
    }

    ## Returns the date and time `duration` later.
    ##
    ## @param duration how far to move forward
    ## @returns the later date and time
    ## @panics if the result is past the year 999999
    +(duration: os.Duration): DateTime {
        return _moved(duration, 1);
    }

    ## Returns the date and time `duration` earlier.
    ##
    ## @param duration how far to move back
    ## @returns the earlier date and time
    ## @panics if the result is before the year -999999
    -(duration: os.Duration): DateTime {
        return _moved(duration, -1);
    }

    _moved(duration: os.Duration, sign: long): DateTime {
        var total = duration.nanoseconds();
        var per_second = NANOSECONDS_PER_SECOND as ulong;
        var seconds = (total / per_second) as long;
        var nanoseconds = (total % per_second) as long;
        var new_nanosecond = time.nanosecond + sign * nanoseconds;
        var new_seconds = unix_seconds() + sign * seconds;
        if (new_nanosecond < 0) {
            new_nanosecond = new_nanosecond + NANOSECONDS_PER_SECOND;
            new_seconds = new_seconds - 1;
        } else if (new_nanosecond >= NANOSECONDS_PER_SECOND) {
            new_nanosecond = new_nanosecond - NANOSECONDS_PER_SECOND;
            new_seconds = new_seconds + 1;
        }
        return DateTime.from_unix_seconds(new_seconds, new_nanosecond as int);
    }

    ## Returns whether this date and time is earlier than `other`.
    ##
    ## @param other the date and time to compare with
    ## @returns true when this one is earlier
    <(other: DateTime): bool {
        return _compare(other) < 0;
    }

    ## Returns whether this date and time is earlier than or the same as
    ## `other`.
    ##
    ## @param other the date and time to compare with
    ## @returns true when this one is not later
    <=(other: DateTime): bool {
        return _compare(other) <= 0;
    }

    ## Returns whether this date and time is later than `other`.
    ##
    ## @param other the date and time to compare with
    ## @returns true when this one is later
    >(other: DateTime): bool {
        return _compare(other) > 0;
    }

    ## Returns whether this date and time is later than or the same as
    ## `other`.
    ##
    ## @param other the date and time to compare with
    ## @returns true when this one is not earlier
    >=(other: DateTime): bool {
        return _compare(other) >= 0;
    }

    _compare(other: DateTime): int {
        if (date != other.date) {
            return date < other.date ? -1 : 1;
        }
        if (time != other.time) {
            return time < other.time ? -1 : 1;
        }
        return 0;
    }

    ## Returns the date and time as text laid out by `pattern`, whose `%`
    ## codes are those of C's `strftime` (see the
    ## [time module](time-module.md)). An offset code (`%z`) panics.
    ##
    ## @param pattern the layout, such as `"%Y-%m-%d %H:%M"`
    ## @returns the formatted date and time
    ## @panics if `pattern` has an unknown code, or an offset code
    format(pattern: String): String {
        return _time_format(pattern, date, time, Optional<int>.Empty);
    }

    ## Returns the date and time in ISO 8601 form: `2024-03-01T09:00:00`,
    ## with the fraction of a second when it is not zero.
    ##
    ## @returns the date and time as text
    to_string(): String {
        var out = StringBuilder();
        _time_write_date(out, date);
        out.append("T");
        _time_write_time(out, time);
        return out.to_string();
    }
}

extend DateTime with ToString;

# ── Calendar arithmetic ──────────────────────────────────────────────────────

export _time_is_date(year: int, month: int, day: int): bool {
    if (year < MINIMUM_YEAR || year > MAXIMUM_YEAR || month < 1 || month > 12) {
        return false;
    }
    return day >= 1 && day <= _time_days_in_month(year, month);
}

export _time_is_leap_year(year: int): bool {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

# The length of a month from 1 to 12.
export _time_days_in_month(year: int, month: int): int {
    if (month == 2) {
        return _time_is_leap_year(year) ? 29 : 28;
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
        return 30;
    }
    return 31;
}

export _time_is_time(hour: int, minute: int, second: int, nanosecond: int): bool {
    return hour >= 0
        && hour < 24
        && minute >= 0
        && minute < 60
        && second >= 0
        && second < 60
        && nanosecond >= 0
        && nanosecond < 1000000000;
}

# Days from 1970-01-01 to a date: Howard Hinnant's days_from_civil, which
# counts in 400-year eras of 146097 days, with years starting in March so
# the leap day comes last.
export _time_days_from_civil(year: int, month: int, day: int): long {
    var y = year as long;
    if (month <= 2) {
        y = y - 1;
    }
    var era = (y >= 0 ? y : y - 399) / 400;
    var year_of_era = y - era * 400;
    var shifted_month = month > 2 ? month - 3 : month + 9;
    var day_of_year = (153 * (shifted_month as long) + 2) / 5 + day - 1;
    var day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    return era * 146097 + day_of_era - 719468;
}

# The inverse of _time_days_from_civil: (year, month, day).
export _time_civil_from_days(days: long): (long, int, int) {
    var z = days + 719468;
    var era = (z >= 0 ? z : z - 146096) / 146097;
    var day_of_era = z - era * 146097;
    var year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    var day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    var shifted_month = (5 * day_of_year + 2) / 153;
    var day = (day_of_year - (153 * shifted_month + 2) / 5 + 1) as int;
    var month = (shifted_month < 10 ? shifted_month + 3 : shifted_month - 9) as int;
    var year = year_of_era + era * 400;
    if (month <= 2) {
        year = year + 1;
    }
    return (year, month, day);
}

# A SystemTime from Unix seconds and a nanosecond, checking its range.
export _time_system_time(seconds: long, nanosecond: int): os.SystemTime {
    # SystemTime holds a long of nanoseconds: about ±9223372036 seconds.
    var limit = 9223372035 as long;
    assert(seconds <= limit && seconds >= 0 - limit, "time: the date is outside what os.SystemTime reaches");
    return os.SystemTime.from_unix_nanoseconds(seconds * NANOSECONDS_PER_SECOND + nanosecond);
}
