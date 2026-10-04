## Time zones: `TimeZone`, the rules that give an instant's offset from UTC,
## for UTC, a fixed offset, the system's local zone, or a named zone such as
## `Europe/Paris` from the system's time zone database; and `now()`.

import io;
import os;
import "civil";
import "offset";
import "sys_posix";
import "sys_wasi";
import "sys_windows";

const KIND_FIXED: int = 0;
const KIND_LOCAL: int = 1;
const KIND_RULES: int = 2;
const KIND_ICU: int = 3;

## The rules that give the offset from UTC at each instant in one place:
## UTC, a fixed offset, the system's local time zone, or a named zone from
## the IANA time zone database, such as `Europe/Paris` or
## `America/New_York`, with its daylight saving time and its history.
##
## Named zones come from the system's database, nothing is bundled: the
## files under `/usr/share/zoneinfo` on Linux and macOS, and ICU's
## (`icu.dll`, Windows 10 version 1903 and later) on Windows. On every
## system, a folder of database files that the `TZDIR` environment variable
## names takes their place. Leap seconds are ignored, as in Unix time.
##
## A zone is a reference, and it does not change once made, so copies share
## it.
##
## @example
##     import os;
##     import time;
##
##     main(): int {
##         var paris = time.TimeZone.named("Europe/Paris").value();
##         var instant = time.OffsetDateTime.parse("2024-07-14T10:00:00Z").value();
##         print(paris.at(instant.to_system_time()));   # 2024-07-14T12:00:00+02:00
##         var local = paris.at_local(time.DateTime(2024, 12, 25, 18, 0));
##         print(local.offset);                         # +01:00
##         return 0;
##     }
export struct TimeZone {
    ## The zone's name: `UTC`, `Local`, the offset of a fixed zone
    ## (`+05:30`), or the database name of a named one (`Europe/Paris`).
    var name: String { get; }
    var _kind: int;
    var _fixed: int;
    # A named zone's history (KIND_RULES): the UTC seconds at which each
    # offset starts, the offset (seconds east) from each, the offset before
    # the first, and the POSIX TZ rule for the times after the last.
    var _starts: long[];
    var _offsets: int[];
    var _initial: int;
    var _rule: _TimeRule;

    ## Makes UTC; the same as `TimeZone.utc()`.
    construct() {
        name = "UTC";
        _kind = KIND_FIXED;
        _fixed = 0;
        _starts = Array<long>();
        _offsets = Array<int>();
        _initial = 0;
        _rule = _TimeRule();
    }

    ## Returns UTC.
    ##
    ## @returns the zone whose offset is always zero
    static utc(): TimeZone {
        return TimeZone();
    }

    ## Returns a zone whose offset is always `offset`.
    ##
    ## @param offset the offset from UTC
    ## @returns the zone, named after the offset (`+05:30`)
    static fixed(offset: Offset): TimeZone {
        var zone = TimeZone();
        zone.name = offset.to_string();
        zone._fixed = offset.seconds;
        return zone;
    }

    ## Returns the system's local time zone, as the C library's `localtime`
    ## sees it: the `TZ` environment variable or `/etc/localtime` on Linux
    ## and macOS, and the zone in Windows' settings. WebAssembly (WASI) has
    ## no local zone, so it is UTC there.
    ##
    ## @returns the local zone, named `Local`
    static local(): TimeZone {
        var zone = TimeZone();
        zone.name = "Local";
        zone._kind = KIND_LOCAL;
        return zone;
    }

    ## Returns the zone `name` from the system's time zone database, such
    ## as `Europe/Paris`, `America/New_York` or `Asia/Kolkata`, or an error
    ## when the system does not know it. `UTC` is always known.
    ##
    ## @param name the IANA name of the zone, which is case-sensitive
    ## @returns the zone, or an error saying it was not found
    static named(name: String): Result<TimeZone> {
        if (name == "UTC") {
            return Result<TimeZone>.ok(TimeZone());
        }
        if (!_time_is_zone_name(name)) {
            return Result<TimeZone>.err(Error($"invalid time zone name '{name}'"));
        }
        return _time_sys_named(name);
    }

    static _from_rules(name: String, starts: long[], offsets: int[], initial: int, rule: _TimeRule): TimeZone {
        var zone = TimeZone();
        zone.name = name;
        zone._kind = KIND_RULES;
        zone._starts = starts;
        zone._offsets = offsets;
        zone._initial = initial;
        zone._rule = rule;
        return zone;
    }

    static _from_icu(name: String): TimeZone {
        var zone = TimeZone();
        zone.name = name;
        zone._kind = KIND_ICU;
        return zone;
    }

    ## Returns the offset from UTC in this zone at `time`.
    ##
    ## @param time the instant
    ## @returns the offset in effect then
    offset_at(time: os.SystemTime): Offset {
        return Offset(_offset_at(time.unix_seconds()));
    }

    # The offset, in seconds east, at `seconds` since the Unix epoch.
    _offset_at(seconds: long): int {
        if (_kind == KIND_FIXED) {
            return _fixed;
        }
        if (_kind == KIND_LOCAL) {
            return _time_sys_local_offset(seconds);
        }
        if (_kind == KIND_ICU) {
            return _time_sys_icu_offset(name, seconds);
        }
        # The last start at or before `seconds`.
        var count = _starts.count;
        if (count == 0 || seconds < _starts[0]) {
            return count == 0 && _rule.is_set ? _rule.offset_at(seconds) : _initial;
        }
        ulong low = 0;
        ulong high = count;
        while (high - low > 1) {
            var middle = low + (high - low) / 2;
            if (_starts[middle] <= seconds) {
                low = middle;
            } else {
                high = middle;
            }
        }
        if (low == count - 1 && _rule.is_set) {
            return _rule.offset_at(seconds);
        }
        return _offsets[low];
    }

    ## Returns the date and time in this zone at `time`.
    ##
    ## @param time the instant
    ## @returns its local date and time, with the offset in effect
    ## @example
    ##     var here = time.TimeZone.local().at(os.SystemTime.now());
    at(time: os.SystemTime): OffsetDateTime {
        return OffsetDateTime.from_system_time(time, offset_at(time));
    }

    ## Returns the instant that a local date and time names in this zone,
    ## with its offset.
    ##
    ## Where the clocks go back, a local time happens twice; this returns
    ## the earlier, at the offset from before the change. Where they go
    ## forward, a local time never happens; this moves it forward by the
    ## length of the gap, so 02:30 on a night that skips from 02:00 to
    ## 03:00 is 03:30. This is what Java's `ZonedDateTime.of` does.
    ##
    ## @param local the date and time on the zone's clocks
    ## @returns the date and time with the zone's offset at that instant
    at_local(local: DateTime): OffsetDateTime {
        var wall = local.unix_seconds();
        # The offsets a day either side cover any one change of the clocks.
        var before = _offset_at(wall - 86400);
        var after = _offset_at(wall + 86400);
        var first = wall - before;
        var second = wall - after;
        var first_fits = _offset_at(first) == before;
        var second_fits = _offset_at(second) == after;
        int offset = before;
        if (first_fits && second_fits) {
            offset = first < second ? before : after;
        } else if (second_fits) {
            offset = after;
        } else if (!first_fits) {
            # A gap: read the time at the offset from before it, which lands
            # after it.
            offset = _offset_at(first);
            var moved = DateTime.from_unix_seconds(first + offset, local.nanosecond);
            return OffsetDateTime(moved, Offset(offset));
        }
        return OffsetDateTime(local, Offset(offset));
    }
}

## Returns the current date and time in the system's local time zone.
##
## @returns now, at the local offset
## @example
##     print(time.now());   # such as 2024-03-01T09:00:00.123456789+01:00
export now(): OffsetDateTime {
    return TimeZone.local().at(os.SystemTime.now());
}

## Returns the current date and time in UTC.
##
## @returns now, at offset zero
export now_utc(): OffsetDateTime {
    return OffsetDateTime.from_system_time(os.SystemTime.now());
}

# Letters, digits, '_', '-', '+' and '/', with no empty, '.' or '..' part:
# a name that cannot leave the database's folder.
_time_is_zone_name(name: String): bool {
    if (name.is_empty || name.size > 255 || name.starts_with("/") || name.ends_with("/")) {
        return false;
    }
    for (var part in name.split("/")) {
        if (part.is_empty || part == "." || part == "..") {
            return false;
        }
    }
    var data = name.bytes();
    for (var c in data) {
        var ok = (c >= 'a' && c <= 'z')
            || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9')
            || c == '_'
            || c == '-'
            || c == '+'
            || c == '/';
        if (!ok) {
            return false;
        }
    }
    return true;
}

# ── TZif files (RFC 8536) ────────────────────────────────────────────────────

# A named zone from the files of the time zone database under `folder`.
_time_zone_from_database(name: String, folder: String): Result<TimeZone> {
    var read = io.File.read_bytes(io.Path($"{folder}/{name}"));
    if (read.is_err()) {
        return Result<TimeZone>.err(Error($"unknown time zone '{name}'"));
    }
    var zone = _time_parse_tzif(name, read.value());
    if (zone.is_empty()) {
        return Result<TimeZone>.err(Error($"unknown time zone '{name}': not a TZif file"));
    }
    return Result<TimeZone>.ok(zone.value());
}

# A big-endian signed integer of `size` bytes at `at`.
_time_big_endian(data: u8[], at: ulong, size: ulong): long {
    ulong value = 0;
    for (var i in 0..size) {
        value = (value << 8) | data[at + i];
    }
    if (size < 8 && value >= (1 as ulong) << (size * 8 - 1)) {
        return (value as long) - ((1 as long) << (size * 8));
    }
    return value as long;
}

# The zone in a TZif file: the version 2+ block of 64-bit times and the TZ
# rule after it, or the version 1 block of a version 1 file.
_time_parse_tzif(name: String, data: u8[]): TimeZone? {
    var none = Optional<TimeZone>.Empty;
    if (data.count < 44 || data[0] != 'T' || data[1] != 'Z' || data[2] != 'i' || data[3] != 'f') {
        return none;
    }
    var version = data[4];
    ulong at = 0;
    ulong time_size = 4;
    if (version >= '2') {
        # Skip the version 1 header and block.
        var skip = _time_tzif_block_size(data, 0, 4);
        if (skip < 0) {
            return none;
        }
        at = skip as ulong;
        time_size = 8;
        if (data.count < at + 44) {
            return none;
        }
    }
    var block = _time_tzif_block_size(data, at, time_size);
    if (block < 0) {
        return none;
    }
    var time_count = _time_big_endian(data, at + 32, 4) as ulong;
    var type_count = _time_big_endian(data, at + 36, 4) as ulong;
    var times_at = at + 44;
    var indices_at = times_at + time_count * time_size;
    var types_at = indices_at + time_count;
    if (type_count == 0) {
        return none;
    }
    var type_offsets = Array<int>();
    for (var i in 0..type_count) {
        type_offsets.append(_time_big_endian(data, types_at + i * 6, 4) as int);
    }
    var starts = Array<long>();
    var offsets = Array<int>();
    for (var i in 0..time_count) {
        var index = data[indices_at + i] as ulong;
        if (index >= type_count) {
            return none;
        }
        starts.append(_time_big_endian(data, times_at + i * time_size, time_size));
        offsets.append(type_offsets[index]);
    }
    var rule = _TimeRule();
    var end = block as ulong;
    if (time_size == 8 && end < data.count && data[end] == '\n') {
        var rule_end = end + 1;
        while (rule_end < data.count && data[rule_end] != '\n') {
            rule_end = rule_end + 1;
        }
        var text = Array<u8>();
        for (var i in end + 1..rule_end) {
            text.append(data[i]);
        }
        rule = _time_parse_rule(String._from_bytes(text));
    }
    return Optional<TimeZone>.Value(TimeZone._from_rules(name, starts, offsets, type_offsets[0], rule));
}

# The offset just past a TZif header and data block at `at`, or -1 when the
# data is too short.
_time_tzif_block_size(data: u8[], at: ulong, time_size: ulong): long {
    if (data.count < at + 44) {
        return -1;
    }
    var is_ut_count = _time_big_endian(data, at + 20, 4);
    var is_standard_count = _time_big_endian(data, at + 24, 4);
    var leap_count = _time_big_endian(data, at + 28, 4);
    var time_count = _time_big_endian(data, at + 32, 4);
    var type_count = _time_big_endian(data, at + 36, 4);
    var character_count = _time_big_endian(data, at + 40, 4);
    var size = (at as long)
        + 44
        + time_count * (time_size as long)
        + time_count
        + type_count * 6
        + character_count
        + leap_count * ((time_size as long) + 4)
        + is_standard_count
        + is_ut_count;
    if (size > data.count as long) {
        return -1;
    }
    return size;
}

# ── POSIX TZ rules ───────────────────────────────────────────────────────────

# A POSIX TZ string's rule, such as `CET-1CEST,M3.5.0,M10.5.0/3`: standard
# and daylight saving offsets (seconds east), and the dates the change
# happens on.
struct _TimeRule {
    var is_set: bool;
    var standard: int;
    var daylight: int;
    var has_daylight: bool;
    var start: _TimeRuleDate;
    var end: _TimeRuleDate;

    construct() {
        is_set = false;
        standard = 0;
        daylight = 0;
        has_daylight = false;
        start = _TimeRuleDate();
        end = _TimeRuleDate();
    }

    offset_at(seconds: long): int {
        if (!has_daylight) {
            return standard;
        }
        var (year, month, day) = _time_civil_from_days(_time_floor_divide(seconds + standard, 86400));
        var begins = start.seconds_in(year as int) - standard;
        var ends = end.seconds_in(year as int) - daylight;
        if (begins < ends) {
            return seconds >= begins && seconds < ends ? daylight : standard;
        }
        return seconds >= ends && seconds < begins ? standard : daylight;
    }
}

# One of a rule's dates: `Jn` (kind 'J', n from 1 to 365, never February
# 29), `n` (kind 'n', from 0 to 365), or `Mm.w.d` (kind 'M': weekday d,
# Sunday 0, of week w, 5 meaning the last, of month m); then the local time
# of the change, in seconds.
[Value]
struct _TimeRuleDate {
    var kind: int;
    var month: int;
    var week: int;
    var day: int;
    var time: long;

    construct() {
        kind = 'M';
        month = 1;
        week = 1;
        day = 0;
        time = 7200;
    }

    # Seconds from the epoch to this date's change in `year`, on the local
    # clock (as if it were UTC).
    seconds_in(year: int): long {
        long days = 0;
        if (kind == 'J') {
            days = _time_days_from_civil(year, 1, 1) + day - 1;
            if (is_leap_year(year) && day >= 60) {
                days = days + 1;
            }
        } else if (kind == 'n') {
            days = _time_days_from_civil(year, 1, 1) + day;
        } else {
            var first = _time_days_from_civil(year, month, 1);
            # 1970-01-01 was a Thursday: day 4 counting from Sunday.
            var first_weekday = _time_floor_modulo(first + 4, 7);
            var offset = _time_floor_modulo(day - first_weekday, 7) + 7 * (week - 1);
            var length = days_in_month(year, month);
            while (offset >= length) {
                offset = offset - 7;
            }
            days = first + offset;
        }
        return days * 86400 + time;
    }
}

# Reads a POSIX TZ string; an empty or unreadable one gives a rule that is
# not set.
_time_parse_rule(text: String): _TimeRule {
    var rule = _TimeRule();
    var parser = _TimeRuleParser(text);
    if (!parser.name()) {
        return rule;
    }
    var standard = parser.clock();
    if (standard.is_empty()) {
        return rule;
    }
    # POSIX offsets count west of UTC.
    rule.standard = (0 - standard.value()) as int;
    if (parser.at_end()) {
        rule.is_set = true;
        return rule;
    }
    if (!parser.name()) {
        return rule;
    }
    rule.has_daylight = true;
    rule.daylight = rule.standard + 3600;
    if (!parser.at_end() && parser.peek() != ',') {
        var daylight = parser.clock();
        if (daylight.is_empty()) {
            return rule;
        }
        rule.daylight = (0 - daylight.value()) as int;
    }
    if (parser.at_end()) {
        # The US rule, which POSIX leaves to the implementation.
        rule.start = _time_rule_date('M', 3, 2, 0, 7200);
        rule.end = _time_rule_date('M', 11, 1, 0, 7200);
        rule.is_set = true;
        return rule;
    }
    if (!parser.take(',')) {
        return rule;
    }
    var start = parser.date();
    if (start.is_empty() || !parser.take(',')) {
        return rule;
    }
    var end = parser.date();
    if (end.is_empty() || !parser.at_end()) {
        return rule;
    }
    rule.start = start.value();
    rule.end = end.value();
    rule.is_set = true;
    return rule;
}

_time_rule_date(kind: int, month: int, week: int, day: int, time: long): _TimeRuleDate {
    var date = _TimeRuleDate();
    date.kind = kind;
    date.month = month;
    date.week = week;
    date.day = day;
    date.time = time;
    return date;
}

struct _TimeRuleParser {
    var _data: u8[];
    var _index: ulong;

    construct(text: String) {
        _data = text.bytes();
        _index = 0;
    }

    at_end(): bool {
        return _index >= _data.count;
    }

    peek(): int {
        return at_end() ? -1 : _data[_index] as int;
    }

    take(c: int): bool {
        if (peek() != c) {
            return false;
        }
        _index = _index + 1;
        return true;
    }

    # A zone abbreviation: three or more letters, or `<...>` (`<+0530>`).
    name(): bool {
        if (take('<')) {
            while (!at_end() && peek() != '>') {
                _index = _index + 1;
            }
            return take('>');
        }
        var count = 0;
        while (true) {
            var c = peek();
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) {
                break;
            }
            _index = _index + 1;
            count = count + 1;
        }
        return count >= 3;
    }

    # A number of one or more digits, or -1.
    number(): long {
        long value = -1;
        while (peek() >= '0' && peek() <= '9') {
            value = (value < 0 ? 0 : value * 10) + (peek() - '0');
            _index = _index + 1;
        }
        return value;
    }

    # [+-]hh[:mm[:ss]] in seconds; hours reach 167, as TZif's rules allow.
    clock(): long? {
        long sign = 1;
        if (take('-')) {
            sign = -1;
        } else {
            take('+');
        }
        var hours = number();
        if (hours < 0 || hours > 167) {
            return Optional<long>.Empty;
        }
        long minutes = 0;
        long seconds = 0;
        if (take(':')) {
            minutes = number();
            if (minutes < 0 || minutes > 59) {
                return Optional<long>.Empty;
            }
            if (take(':')) {
                seconds = number();
                if (seconds < 0 || seconds > 59) {
                    return Optional<long>.Empty;
                }
            }
        }
        return Optional<long>.Value(sign * (hours * 3600 + minutes * 60 + seconds));
    }

    # Jn, n or Mm.w.d, then an optional /time.
    date(): _TimeRuleDate? {
        var none = Optional<_TimeRuleDate>.Empty;
        var date = _TimeRuleDate();
        if (take('J')) {
            date.kind = 'J';
            var day = number();
            if (day < 1 || day > 365) {
                return none;
            }
            date.day = day as int;
        } else if (take('M')) {
            var month = number();
            if (month < 1 || month > 12 || !take('.')) {
                return none;
            }
            var week = number();
            if (week < 1 || week > 5 || !take('.')) {
                return none;
            }
            var day = number();
            if (day < 0 || day > 6) {
                return none;
            }
            date.month = month as int;
            date.week = week as int;
            date.day = day as int;
        } else {
            date.kind = 'n';
            var day = number();
            if (day < 0 || day > 365) {
                return none;
            }
            date.day = day as int;
        }
        if (take('/')) {
            var time = clock();
            if (time.is_empty()) {
                return none;
            }
            date.time = time.value();
        }
        return Optional<_TimeRuleDate>.Value(date);
    }
}
