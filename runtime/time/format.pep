# Reading and writing dates and times as text: ISO 8601 and RFC 3339
# (_TimeScanner, _time_write_*), strftime patterns (_time_format) and HTTP
# dates (_time_parse_http_date).

import "civil";
import "offset";

const MONTH_ABBREVIATIONS: StringConstant = "JanFebMarAprMayJunJulAugSepOctNovDec";
const MONTH_NAMES: StringConstant = "January,February,March,April,May,June,July,August,September,October,November,December";

# Reads ISO 8601 / RFC 3339 pieces from the front of a text, one call after
# another; each returns an Err (and leaves `index` wherever it stopped) when
# the text does not continue with that piece.
struct _TimeScanner {
    var _text: String;
    var _data: u8[];
    var index: ulong;

    construct(text: String) {
        _text = text;
        _data = text.bytes();
        index = 0;
    }

    at_end(): bool {
        return index >= _data.count;
    }

    # The next byte, or -1 at the end.
    peek(): int {
        return at_end() ? -1 : _data[index] as int;
    }

    # Consumes `c` when it comes next.
    take(c: int): bool {
        if (peek() != c) {
            return false;
        }
        index = index + 1;
        return true;
    }

    # Exactly `count` decimal digits as a number, or -1.
    digits(count: int): long {
        long value = 0;
        for (var i in 0..count) {
            var c = peek();
            if (c < '0' || c > '9') {
                return -1;
            }
            value = value * 10 + (c - '0');
            index = index + 1;
        }
        return value;
    }

    # A run of ASCII letters, possibly empty.
    word(): String {
        var start = index;
        while (true) {
            var c = peek();
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) {
                break;
            }
            index = index + 1;
        }
        return _text.substr_bytes(start, index - start);
    }

    # `YYYY-MM-DD`, or a signed year of four or more digits: `+10000-01-01`.
    date(): Result<Date> {
        var invalid = Result<Date>.err(Error("invalid date"));
        long year = 0;
        var c = peek();
        if (c == '+' || c == '-') {
            index = index + 1;
            var count = 0;
            while (peek() >= '0' && peek() <= '9' && count < 7) {
                year = year * 10 + (peek() - '0');
                index = index + 1;
                count = count + 1;
            }
            if (count < 4) {
                return invalid;
            }
            if (c == '-') {
                year = 0 - year;
            }
        } else {
            year = digits(4);
            if (year < 0) {
                return invalid;
            }
        }
        if (!take('-')) {
            return invalid;
        }
        var month = digits(2);
        if (month < 0 || !take('-')) {
            return invalid;
        }
        var day = digits(2);
        if (day < 0 || year > 999999 || year < -999999) {
            return invalid;
        }
        var date = Date.checked(year as int, month as int, day as int);
        if (date.is_empty()) {
            return invalid;
        }
        return Result<Date>.ok(date.value());
    }

    # `HH:MM`, `HH:MM:SS` or `HH:MM:SS.fraction`; digits past nanoseconds
    # are dropped.
    time(): Result<Time> {
        var invalid = Result<Time>.err(Error("invalid time"));
        var hour = digits(2);
        if (hour < 0 || !take(':')) {
            return invalid;
        }
        var minute = digits(2);
        if (minute < 0) {
            return invalid;
        }
        long second = 0;
        long nanosecond = 0;
        if (take(':')) {
            second = digits(2);
            if (second < 0) {
                return invalid;
            }
            if (take('.')) {
                long scale = 100000000;
                var count = 0;
                while (peek() >= '0' && peek() <= '9') {
                    nanosecond = nanosecond + (peek() - '0') * scale;
                    scale = scale / 10;
                    index = index + 1;
                    count = count + 1;
                }
                if (count == 0) {
                    return invalid;
                }
            }
        }
        var time = Time.checked(hour as int, minute as int, second as int, nanosecond as int);
        if (time.is_empty()) {
            return invalid;
        }
        return Result<Time>.ok(time.value());
    }

    # A date, `T` (or `t`, or a space), and a time.
    date_time(): Result<DateTime> {
        var invalid = Result<DateTime>.err(Error("invalid date and time"));
        var date = date();
        if (date.is_err()) {
            return invalid;
        }
        if (!take('T') && !take('t') && !take(' ')) {
            return invalid;
        }
        var time = time();
        if (time.is_err()) {
            return invalid;
        }
        return Result<DateTime>.ok(DateTime.combine(date.value(), time.value()));
    }

    # `Z` (or `z`), or `+HH:MM`, optionally with `:SS`. When `loose`, also
    # `+HH` and `+HHMM`.
    offset(loose: bool): Result<Offset> {
        var invalid = Result<Offset>.err(Error("invalid UTC offset"));
        if (take('Z') || take('z')) {
            return Result<Offset>.ok(Offset());
        }
        var sign = peek();
        if (sign != '+' && sign != '-') {
            return invalid;
        }
        index = index + 1;
        var hours = digits(2);
        if (hours < 0) {
            return invalid;
        }
        long minutes = 0;
        long seconds = 0;
        var colon = take(':');
        if (colon || (loose && !at_end())) {
            minutes = digits(2);
            if (minutes < 0) {
                return invalid;
            }
            if (colon && take(':')) {
                seconds = digits(2);
                if (seconds < 0) {
                    return invalid;
                }
            }
        } else if (!loose) {
            return invalid;
        }
        if (hours > 23 || minutes > 59 || seconds > 59) {
            return invalid;
        }
        var total = (hours * 3600 + minutes * 60 + seconds) as int;
        return Result<Offset>.ok(Offset(sign == '-' ? 0 - total : total));
    }
}

# ── Writing ──────────────────────────────────────────────────────────────────

# The year with at least four digits, signed outside 0 to 9999.
_time_write_year(out: StringBuilder, year: int) {
    if (year < 0) {
        out.append($"-{0 - year:04}");
    } else if (year > 9999) {
        out.append($"+{year}");
    } else {
        out.append($"{year:04}");
    }
}

_time_write_date(out: StringBuilder, date: Date) {
    _time_write_year(out, date.year);
    out.append($"-{date.month:02}-{date.day:02}");
}

# HH:MM:SS, then the fraction of a second without trailing zeros.
_time_write_time(out: StringBuilder, time: Time) {
    out.append($"{time.hour:02}:{time.minute:02}:{time.second:02}");
    if (time.nanosecond != 0) {
        var fraction = $"{time.nanosecond:09}";
        var size = fraction.size;
        while (fraction.byte_at(size - 1) == '0') {
            size = size - 1;
        }
        out.append(".");
        out.append(fraction.substr_bytes(0, size));
    }
}

# +HH:MM (or +HHMM without `colon`), with :SS when there are seconds, or Z
# for zero when `z_for_utc`.
_time_write_offset(out: StringBuilder, seconds: int, colon: bool, z_for_utc: bool) {
    if (seconds == 0 && z_for_utc) {
        out.append("Z");
        return;
    }
    var magnitude = seconds < 0 ? 0 - seconds : seconds;
    out.append(seconds < 0 ? "-" : "+");
    var separator = colon ? ":" : "";
    out.append($"{magnitude / 3600:02}{separator}{magnitude / 60 % 60:02}");
    if (magnitude % 60 != 0) {
        out.append($"{separator}{magnitude % 60:02}");
    }
}

_time_month_abbreviation(month: int): String {
    return MONTH_ABBREVIATIONS.substr_bytes(((month - 1) * 3) as ulong, 3);
}

_time_month_name(month: int): String {
    return MONTH_NAMES.split(",")[(month - 1) as ulong];
}

# The ISO 8601 week-numbering year and week (1 to 53) of a date. Weeks start
# on Monday, and week 1 is the one holding the year's first Thursday.
_time_iso_week(date: Date): (int, int) {
    var weekday = date.weekday() as int;
    var week = (date.day_of_year() - weekday + 10) / 7;
    if (week < 1) {
        return (date.year - 1, _time_iso_weeks_in(date.year - 1));
    }
    if (week > _time_iso_weeks_in(date.year)) {
        return (date.year + 1, 1);
    }
    return (date.year, week);
}

# 53 when the year starts on a Thursday, or is a leap year that starts on a
# Wednesday; 52 otherwise.
_time_iso_weeks_in(year: int): int {
    var first = Date(year, 1, 1).weekday();
    if (first == Weekday.Thursday || (is_leap_year(year) && first == Weekday.Wednesday)) {
        return 53;
    }
    return 52;
}

# strftime: `%` codes in `pattern` replaced by parts of the date, time and,
# when there is one, offset (seconds east of UTC).
_time_format(pattern: String, date: Date, time: Time, offset: int?): String {
    var out = StringBuilder();
    var data = pattern.bytes();
    var size = data.count;
    ulong index = 0;
    ulong start = 0;
    while (index < size) {
        if (data[index] != '%') {
            index = index + 1;
            continue;
        }
        if (index > start) {
            out.append(pattern.substr_bytes(start, index - start));
        }
        index = index + 1;
        assert(index < size, "time.format: the pattern ends with '%'");
        var code = data[index] as int;
        # %:z, and a digit count before N (%3N).
        var colon = false;
        var width = 9;
        if (code == ':' && index + 1 < size) {
            colon = true;
            index = index + 1;
            code = data[index] as int;
            assert(code == 'z', "time.format: '%:' is only used in '%:z'");
        } else if (code >= '1' && code <= '9' && index + 1 < size && data[index + 1] == 'N') {
            width = code - '0';
            index = index + 1;
            code = 'N';
        }
        index = index + 1;
        start = index;
        if (code == 'Y') {
            _time_write_year(out, date.year);
        } else if (code == 'C') {
            out.append($"{_time_floor_div(date.year, 100):02}");
        } else if (code == 'y') {
            out.append($"{_time_floor_mod(date.year, 100):02}");
        } else if (code == 'm') {
            out.append($"{date.month:02}");
        } else if (code == 'd') {
            out.append($"{date.day:02}");
        } else if (code == 'e') {
            out.append($"{date.day:2}");
        } else if (code == 'j') {
            out.append($"{date.day_of_year():03}");
        } else if (code == 'F') {
            _time_write_date(out, date);
        } else if (code == 'a') {
            out.append(date.weekday().name().substr_bytes(0, 3));
        } else if (code == 'A') {
            out.append(date.weekday().name());
        } else if (code == 'b' || code == 'h') {
            out.append(_time_month_abbreviation(date.month));
        } else if (code == 'B') {
            out.append(_time_month_name(date.month));
        } else if (code == 'u') {
            out.append($"{date.weekday() as int}");
        } else if (code == 'w') {
            out.append($"{(date.weekday() as int) % 7}");
        } else if (code == 'G') {
            var (year, week) = _time_iso_week(date);
            _time_write_year(out, year);
        } else if (code == 'V') {
            var (year, week) = _time_iso_week(date);
            out.append($"{week:02}");
        } else if (code == 'H') {
            out.append($"{time.hour:02}");
        } else if (code == 'I') {
            var hour = time.hour % 12;
            out.append($"{hour == 0 ? 12 : hour:02}");
        } else if (code == 'p') {
            out.append(time.hour < 12 ? "AM" : "PM");
        } else if (code == 'M') {
            out.append($"{time.minute:02}");
        } else if (code == 'S') {
            out.append($"{time.second:02}");
        } else if (code == 'N') {
            out.append($"{time.nanosecond:09}".substr_bytes(0, width as ulong));
        } else if (code == 'T') {
            out.append($"{time.hour:02}:{time.minute:02}:{time.second:02}");
        } else if (code == 'R') {
            out.append($"{time.hour:02}:{time.minute:02}");
        } else if (code == 'z') {
            assert(offset.is_value(), "time.format: '%z' needs an offset; format an OffsetDateTime");
            _time_write_offset(out, offset.value(), colon, false);
        } else if (code == 's') {
            assert(offset.is_value(), "time.format: '%s' needs an offset; format an OffsetDateTime");
            var seconds = date.days() * 86400 + time.seconds() - offset.value();
            out.append($"{seconds}");
        } else if (code == 'n') {
            out.append("\n");
        } else if (code == 't') {
            out.append("\t");
        } else if (code == '%') {
            out.append("%");
        } else {
            panic($"time.format: unknown code '%{pattern.substr_bytes(index - 1, 1)}'");
        }
    }
    if (size > start) {
        out.append(pattern.substr_bytes(start, size - start));
    }
    return out.to_string();
}

_time_floor_div(value: int, unit: int): int {
    var quotient = value / unit;
    if (value % unit < 0) {
        quotient = quotient - 1;
    }
    return quotient;
}

_time_floor_mod(value: int, unit: int): int {
    var rest = value % unit;
    return rest < 0 ? rest + unit : rest;
}

# ── HTTP dates ───────────────────────────────────────────────────────────────

# The month (1 to 12) a three-letter abbreviation names, or 0.
_time_month_from_abbreviation(name: String): int {
    if (name.size != 3) {
        return 0;
    }
    var at = MONTH_ABBREVIATIONS.find(name);
    return at < 0 || at % 3 != 0 ? 0 : (at / 3 + 1) as int;
}

# HH:MM:SS, exactly.
_time_scan_clock(scanner: _TimeScanner): Time? {
    var hour = scanner.digits(2);
    if (hour < 0 || !scanner.take(':')) {
        return Optional<Time>.Empty;
    }
    var minute = scanner.digits(2);
    if (minute < 0 || !scanner.take(':')) {
        return Optional<Time>.Empty;
    }
    var second = scanner.digits(2);
    if (second < 0) {
        return Optional<Time>.Empty;
    }
    return Time.checked(hour as int, minute as int, second as int);
}

# An IMF-fixdate, RFC 850 date or asctime date (RFC 9110 section 5.6.7), in
# UTC.
_time_parse_http_date(text: String): DateTime? {
    var none = Optional<DateTime>.Empty;
    var scanner = _TimeScanner(text);
    var weekday = scanner.word();
    long year = 0;
    long day = 0;
    var month = 0;
    Time? clock = Optional<Time>.Empty;
    if (scanner.take(',')) {
        if (!scanner.take(' ')) {
            return none;
        }
        day = scanner.digits(2);
        if (day < 0) {
            return none;
        }
        if (scanner.take(' ')) {
            # IMF-fixdate: Sun, 06 Nov 1994 08:49:37 GMT
            if (weekday.size != 3) {
                return none;
            }
            month = _time_month_from_abbreviation(scanner.word());
            if (!scanner.take(' ')) {
                return none;
            }
            year = scanner.digits(4);
        } else if (scanner.take('-')) {
            # RFC 850: Sunday, 06-Nov-94 08:49:37 GMT
            if (weekday.size <= 3) {
                return none;
            }
            month = _time_month_from_abbreviation(scanner.word());
            if (!scanner.take('-')) {
                return none;
            }
            year = scanner.digits(2);
            if (year >= 0) {
                year = year + (year >= 70 ? 1900 : 2000);
            }
        } else {
            return none;
        }
        if (year < 0 || !scanner.take(' ')) {
            return none;
        }
        clock = _time_scan_clock(scanner);
        if (!scanner.take(' ') || scanner.word() != "GMT") {
            return none;
        }
    } else {
        # asctime: Sun Nov  6 08:49:37 1994
        if (weekday.size != 3 || !scanner.take(' ')) {
            return none;
        }
        month = _time_month_from_abbreviation(scanner.word());
        if (!scanner.take(' ')) {
            return none;
        }
        if (scanner.take(' ')) {
            day = scanner.digits(1);
        } else {
            day = scanner.digits(2);
        }
        if (day < 0 || !scanner.take(' ')) {
            return none;
        }
        clock = _time_scan_clock(scanner);
        if (!scanner.take(' ')) {
            return none;
        }
        year = scanner.digits(4);
        if (year < 0) {
            return none;
        }
    }
    if (!scanner.at_end() || clock.is_empty()) {
        return none;
    }
    var date = Date.checked(year as int, month, day as int);
    if (date.is_empty()) {
        return none;
    }
    var name = date.value().weekday().name();
    if (weekday != name && weekday != name.substr_bytes(0, 3)) {
        return none;
    }
    return Optional<DateTime>.Value(DateTime.combine(date.value(), clock.value()));
}
