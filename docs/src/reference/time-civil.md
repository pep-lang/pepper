<!-- Generated from runtime/time/civil.pep by `pep-doc reference`. Do not edit. -->

# Dates and times

Calendar dates and times of day with no time zone: `Date`, `Time`,
`DateTime` and `Weekday`, on the proleptic Gregorian calendar, plus
`is_leap_year` and `days_in_month`.

Source: `runtime/time/civil.pep`

## is_leap_year

```pepper
is_leap_year(year: int): bool
```

Returns whether `year` is a leap year on the Gregorian calendar: divisible
by 4, except centuries not divisible by 400. Year 0 (1 BC) is one.

**Parameters**
- `year` — the year

**Returns**
- true when February of `year` has 29 days

**Example**
```pepper
assert(time.is_leap_year(2024) && !time.is_leap_year(1900), "leap years");
```

## days_in_month

```pepper
days_in_month(year: int, month: int): int
```

Returns the number of days in `month` of `year`: 28 to 31.

**Parameters**
- `year` — the year, for February
- `month` — the month, 1 (January) to 12 (December)

**Returns**
- the number of days in that month

**Panics**
- if `month` is not from 1 to 12

## Weekday

```pepper
enum Weekday
```

A day of the week. Each case's value is its ISO 8601 number, Monday 1 to
Sunday 7, so `day as int` gives that number, and `day.name()` its English
name.

### Cases

#### Monday

```pepper
Monday = 1
```

The first day of the ISO week.

#### Tuesday

```pepper
Tuesday
```

The second day.

#### Wednesday

```pepper
Wednesday
```

The third day.

#### Thursday

```pepper
Thursday
```

The fourth day.

#### Friday

```pepper
Friday
```

The fifth day.

#### Saturday

```pepper
Saturday
```

The sixth day.

#### Sunday

```pepper
Sunday
```

The seventh and last day of the ISO week.

### Methods

#### to_string

```pepper
to_string(): String
```

Returns the weekday's English name, as `name()` does: `Monday`.

**Returns**
- the name

## Date

```pepper
[Value] struct Date
```

A date on the proleptic Gregorian calendar, which extends the calendar's
rules to years before it was adopted: a year, a month (1 to 12) and a
day of the month (1 to 31), with no time of day or time zone.

A value struct: copied, compared with `==`, `<` and the other
comparisons, and never allocated. Years run from -999999 to 999999; year
0 is 1 BC. Its text is ISO 8601's `2024-02-29`.

**Example**
```pepper
import time;

main(): int {
    var day = time.Date(2024, 2, 28).add_days(1);
    print(day);               # 2024-02-29
    print(day.weekday());     # Thursday
    return 0;
}
```

### Properties

#### year

```pepper
var year: int { get; }
```

The year: 2024, or 0 for 1 BC and -1 for 2 BC.

#### month

```pepper
var month: int { get; }
```

The month, 1 (January) to 12 (December).

#### day

```pepper
var day: int { get; }
```

The day of the month, 1 to 31.

### Constructor

#### Date()

```pepper
construct(year: int = 1970, month: int = 1, day: int = 1)
```

Makes the date `year`-`month`-`day`; with no arguments, the Unix
epoch's 1970-01-01.

**Parameters**
- `year` — the year, from -999999 to 999999
- `month` — the month, 1 to 12
- `day` — the day of the month, 1 to the month's last day

**Panics**
- if the parts do not name a date: use `checked` for parts that come from outside the program

### Static methods

#### checked

```pepper
static checked(year: int, month: int, day: int): Date?
```

Returns the date `year`-`month`-`day`, or none when the parts do not
name one, such as February 30.

**Parameters**
- `year` — the year, from -999999 to 999999
- `month` — the month, 1 to 12
- `day` — the day of the month

**Returns**
- the date, or none

#### from_days

```pepper
static from_days(days: long): Date
```

Returns the date `days` days after 1970-01-01.

**Parameters**
- `days` — days since the Unix epoch; negative for earlier dates

**Returns**
- the date

**Panics**
- if the date is outside the years -999999 to 999999

#### parse

```pepper
static parse(text: String): Result<Date>
```

Returns the date in the ISO 8601 form `2024-02-29`, or none when
`text` is not a date. Years outside 0 to 9999 take a sign and more
digits (`+10000-01-01`, `-0001-12-31`).

**Parameters**
- `text` — the text to read

**Returns**
- the date, or an error saying what is wrong with `text`

### Methods

#### days

```pepper
days(): long
```

Returns the number of days from 1970-01-01 to this date.

**Returns**
- days since the Unix epoch; negative for earlier dates

#### weekday

```pepper
weekday(): Weekday
```

Returns the day of the week.

**Returns**
- the weekday

#### day_of_year

```pepper
day_of_year(): int
```

Returns the day of the year, 1 for January 1 to 366 for December 31
of a leap year.

**Returns**
- the ordinal day

#### is_leap_year

```pepper
is_leap_year(): bool
```

Returns whether this date's year is a leap year.

**Returns**
- true when the year has a February 29

#### days_in_month

```pepper
days_in_month(): int
```

Returns the number of days in this date's month.

**Returns**
- 28 to 31

#### add_days

```pepper
add_days(days: long): Date
```

Returns the date `days` days later, or earlier when `days` is
negative.

**Parameters**
- `days` — the number of days to move

**Returns**
- the date

**Panics**
- if the date is outside the years -999999 to 999999

#### add_months

```pepper
add_months(months: long): Date
```

Returns the date `months` months later, or earlier when `months` is
negative. A day past the end of the new month becomes its last day:
a month after January 31 is February 28 or 29.

**Parameters**
- `months` — the number of months to move

**Returns**
- the date

**Panics**
- if the date is outside the years -999999 to 999999

#### add_years

```pepper
add_years(years: long): Date
```

Returns the date `years` years later, or earlier when `years` is
negative. February 29 becomes February 28 in a year that is not a
leap year.

**Parameters**
- `years` — the number of years to move

**Returns**
- the date

**Panics**
- if the date is outside the years -999999 to 999999

#### days_since

```pepper
days_since(earlier: Date): long
```

Returns the number of days from `earlier` to this date: negative when
`earlier` is later.

**Parameters**
- `earlier` — the date to count from

**Returns**
- the number of days between them

#### at

```pepper
at(time: Time = Time()): DateTime
```

Returns the start of this date, midnight, as a `DateTime`.

**Parameters**
- `time` — the time of day; midnight by default

**Returns**
- the date and time

#### operator <

```pepper
<(other: Date): bool
```

Returns whether this date is earlier than `other`.

**Parameters**
- `other` — the date to compare with

**Returns**
- true when this one is earlier

#### operator <=

```pepper
<=(other: Date): bool
```

Returns whether this date is earlier than or the same as `other`.

**Parameters**
- `other` — the date to compare with

**Returns**
- true when this one is not later

#### operator >

```pepper
>(other: Date): bool
```

Returns whether this date is later than `other`.

**Parameters**
- `other` — the date to compare with

**Returns**
- true when this one is later

#### operator >=

```pepper
>=(other: Date): bool
```

Returns whether this date is later than or the same as `other`.

**Parameters**
- `other` — the date to compare with

**Returns**
- true when this one is not earlier

#### format

```pepper
format(pattern: String): String
```

Returns the date as text laid out by `pattern`, whose `%` codes are
those of C's `strftime` (see the [time module](time-module.md)). The
time of day is midnight, and an offset code (`%z`) panics.

**Parameters**
- `pattern` — the layout, such as `"%d %B %Y"`

**Returns**
- the formatted date

**Panics**
- if `pattern` has an unknown code, or an offset code

#### to_string

```pepper
to_string(): String
```

Returns the date in ISO 8601 form: `2024-02-29`.

**Returns**
- the date as text

## Time

```pepper
[Value] struct Time
```

A time of day with no date or time zone: an hour (0 to 23), a minute,
a second and a nanosecond. Leap seconds are not represented, as in Unix
time.

A value struct: copied, compared with `==`, `<` and the other
comparisons, and never allocated. Its text is ISO 8601's `08:30:00`,
with a fraction of a second when there is one (`08:30:00.25`).

**Example**
```pepper
import time;

main(): int {
    var lunch = time.Time(12, 30);
    print(lunch);   # 12:30:00
    return 0;
}
```

### Properties

#### hour

```pepper
var hour: int { get; }
```

The hour, 0 to 23.

#### minute

```pepper
var minute: int { get; }
```

The minute, 0 to 59.

#### second

```pepper
var second: int { get; }
```

The second, 0 to 59.

#### nanosecond

```pepper
var nanosecond: int { get; }
```

The nanosecond within the second, 0 to 999999999.

### Constructor

#### Time()

```pepper
construct(hour: int = 0, minute: int = 0, second: int = 0, nanosecond: int = 0)
```

Makes the time `hour`:`minute`:`second`; with no arguments,
midnight.

**Parameters**
- `hour` — the hour, 0 to 23
- `minute` — the minute, 0 to 59
- `second` — the second, 0 to 59
- `nanosecond` — the nanosecond within the second, 0 to 999999999

**Panics**
- if a part is out of range: use `checked` for parts that come from outside the program

### Static methods

#### checked

```pepper
static checked(hour: int, minute: int, second: int = 0, nanosecond: int = 0): Time?
```

Returns the time `hour`:`minute`:`second`, or none when a part is out
of range.

**Parameters**
- `hour` — the hour, 0 to 23
- `minute` — the minute, 0 to 59
- `second` — the second, 0 to 59
- `nanosecond` — the nanosecond within the second

**Returns**
- the time, or none

#### from_nanoseconds

```pepper
static from_nanoseconds(nanoseconds: long): Time
```

Returns the time `nanoseconds` nanoseconds after midnight.

**Parameters**
- `nanoseconds` — nanoseconds since midnight, less than a day's

**Returns**
- the time

**Panics**
- if `nanoseconds` is negative or a day or more

#### parse

```pepper
static parse(text: String): Result<Time>
```

Returns the time in the ISO 8601 form `08:30:00`, with an optional
fraction of a second (`08:30:00.25`), or an error when `text` is not
a time. The seconds may be left out (`08:30`), as TOML 1.1 allows.

**Parameters**
- `text` — the text to read

**Returns**
- the time, or an error saying what is wrong with `text`

### Methods

#### nanoseconds

```pepper
nanoseconds(): long
```

Returns the number of nanoseconds since midnight.

**Returns**
- nanoseconds since midnight

#### seconds

```pepper
seconds(): long
```

Returns the number of whole seconds since midnight.

**Returns**
- seconds since midnight

#### operator <

```pepper
<(other: Time): bool
```

Returns whether this time is earlier in the day than `other`.

**Parameters**
- `other` — the time to compare with

**Returns**
- true when this one is earlier

#### operator <=

```pepper
<=(other: Time): bool
```

Returns whether this time is earlier than or the same as `other`.

**Parameters**
- `other` — the time to compare with

**Returns**
- true when this one is not later

#### operator >

```pepper
>(other: Time): bool
```

Returns whether this time is later in the day than `other`.

**Parameters**
- `other` — the time to compare with

**Returns**
- true when this one is later

#### operator >=

```pepper
>=(other: Time): bool
```

Returns whether this time is later than or the same as `other`.

**Parameters**
- `other` — the time to compare with

**Returns**
- true when this one is not earlier

#### format

```pepper
format(pattern: String): String
```

Returns the time as text laid out by `pattern`, whose `%` codes are
those of C's `strftime` (see the [time module](time-module.md)). The
date is 1970-01-01, and an offset code (`%z`) panics.

**Parameters**
- `pattern` — the layout, such as `"%H:%M"`

**Returns**
- the formatted time

**Panics**
- if `pattern` has an unknown code, or an offset code

#### to_string

```pepper
to_string(): String
```

Returns the time in ISO 8601 form: `08:30:00`, with the fraction of a
second when it is not zero, without trailing zeros (`08:30:00.25`).

**Returns**
- the time as text

## DateTime

```pepper
[Value] struct DateTime
```

A date and a time of day with no time zone, such as a meeting's
`2024-03-01 09:00` written down without saying where. TOML calls it a
local date-time. Attach an offset with `OffsetDateTime`, or a zone's
rules with `TimeZone.at_local`, to name an instant.

A value struct: copied, compared with `==`, `<` and the other
comparisons, and never allocated. Its text is ISO 8601's
`2024-03-01T09:00:00`.

**Example**
```pepper
import time;

main(): int {
    var start = time.DateTime(2024, 3, 1, 9, 0);
    var end = start + os.Duration.from_seconds(90 * 60);
    print(end);   # 2024-03-01T10:30:00
    return 0;
}
```

### Properties

#### date

```pepper
var date: Date { get; }
```

The date.

#### time

```pepper
var time: Time { get; }
```

The time of day.

#### year

```pepper
var year: int { get; }
```

The year, as `date.year`.

#### month

```pepper
var month: int { get; }
```

The month, 1 to 12, as `date.month`.

#### day

```pepper
var day: int { get; }
```

The day of the month, as `date.day`.

#### hour

```pepper
var hour: int { get; }
```

The hour, 0 to 23, as `time.hour`.

#### minute

```pepper
var minute: int { get; }
```

The minute, as `time.minute`.

#### second

```pepper
var second: int { get; }
```

The second, as `time.second`.

#### nanosecond

```pepper
var nanosecond: int { get; }
```

The nanosecond within the second, as `time.nanosecond`.

### Constructor

#### DateTime()

```pepper
construct( year: int = 1970, month: int = 1, day: int = 1, hour: int = 0, minute: int = 0, second: int = 0, nanosecond: int = 0 )
```

Makes the date and time from its parts; with no arguments, the Unix
epoch's 1970-01-01T00:00:00.

**Parameters**
- `year` — the year, from -999999 to 999999
- `month` — the month, 1 to 12
- `day` — the day of the month
- `hour` — the hour, 0 to 23
- `minute` — the minute, 0 to 59
- `second` — the second, 0 to 59
- `nanosecond` — the nanosecond within the second

**Panics**
- if the parts do not name a date and time

### Static methods

#### combine

```pepper
static combine(date: Date, time: Time): DateTime
```

Returns `date` at `time`.

**Parameters**
- `date` — the date
- `time` — the time of day

**Returns**
- the date and time

#### from_unix_nanoseconds

```pepper
static from_unix_nanoseconds(nanoseconds: long): DateTime
```

Returns the date and time `nanoseconds` nanoseconds after
1970-01-01T00:00:00, counting every day as 86400 seconds.

**Parameters**
- `nanoseconds` — nanoseconds since the epoch; negative for earlier

**Returns**
- the date and time

#### from_unix_seconds

```pepper
static from_unix_seconds(seconds: long, nanosecond: int = 0): DateTime
```

Returns the date and time `seconds` seconds after
1970-01-01T00:00:00, counting every day as 86400 seconds, as Unix
time does. Reaches further than a `SystemTime`.

**Parameters**
- `seconds` — seconds since the epoch; negative for earlier
- `nanosecond` — the nanosecond within the second

**Returns**
- the date and time

**Panics**
- if `nanosecond` is not from 0 to 999999999, or the date is outside the years -999999 to 999999

#### from_system_time

```pepper
static from_system_time(time: os.SystemTime): DateTime
```

Returns the date and time in UTC of a wall-clock reading.

**Parameters**
- `time` — the instant

**Returns**
- its date and time in UTC

#### parse

```pepper
static parse(text: String): Result<DateTime>
```

Returns the date and time in the ISO 8601 form
`2024-03-01T09:00:00`, or an error when `text` is not one. A space or
a lowercase `t` may stand for the `T`, as TOML allows, and the
seconds may be left out.

**Parameters**
- `text` — the text to read

**Returns**
- the date and time, or an error saying what is wrong with `text`

### Methods

#### unix_seconds

```pepper
unix_seconds(): long
```

Returns the number of seconds from 1970-01-01T00:00:00 to this date
and time, rounded down, counting every day as 86400 seconds.

**Returns**
- seconds since the epoch; negative for earlier

#### to_system_time

```pepper
to_system_time(): os.SystemTime
```

Returns this date and time as a `SystemTime`, reading it as UTC.

**Returns**
- the instant

**Panics**
- if the date is outside what a `SystemTime` reaches, the years 1677 to 2262

#### weekday

```pepper
weekday(): Weekday
```

Returns the day of the week.

**Returns**
- the weekday

#### operator +

```pepper
+(duration: os.Duration): DateTime
```

Returns the date and time `duration` later.

**Parameters**
- `duration` — how far to move forward

**Returns**
- the later date and time

**Panics**
- if the result is past the year 999999

#### operator -

```pepper
-(duration: os.Duration): DateTime
```

Returns the date and time `duration` earlier.

**Parameters**
- `duration` — how far to move back

**Returns**
- the earlier date and time

**Panics**
- if the result is before the year -999999

#### operator <

```pepper
<(other: DateTime): bool
```

Returns whether this date and time is earlier than `other`.

**Parameters**
- `other` — the date and time to compare with

**Returns**
- true when this one is earlier

#### operator <=

```pepper
<=(other: DateTime): bool
```

Returns whether this date and time is earlier than or the same as
`other`.

**Parameters**
- `other` — the date and time to compare with

**Returns**
- true when this one is not later

#### operator >

```pepper
>(other: DateTime): bool
```

Returns whether this date and time is later than `other`.

**Parameters**
- `other` — the date and time to compare with

**Returns**
- true when this one is later

#### operator >=

```pepper
>=(other: DateTime): bool
```

Returns whether this date and time is later than or the same as
`other`.

**Parameters**
- `other` — the date and time to compare with

**Returns**
- true when this one is not earlier

#### format

```pepper
format(pattern: String): String
```

Returns the date and time as text laid out by `pattern`, whose `%`
codes are those of C's `strftime` (see the
[time module](time-module.md)). An offset code (`%z`) panics.

**Parameters**
- `pattern` — the layout, such as `"%Y-%m-%d %H:%M"`

**Returns**
- the formatted date and time

**Panics**
- if `pattern` has an unknown code, or an offset code

#### to_string

```pepper
to_string(): String
```

Returns the date and time in ISO 8601 form: `2024-03-01T09:00:00`,
with the fraction of a second when it is not zero.

**Returns**
- the date and time as text
