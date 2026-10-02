## Reading numbers from text: every number type has a static `parse`.
##
## `int.parse("42")` gives an `int?`, empty when the text is not a number
## of that type. The integer types take a base from 2 to 36; `float` and
## `double` read decimal notation. Each spelling of a type is the same
## type, so `i32.parse` is `int.parse`.
##
## @example
##     var port = int.parse("8080");
##     assert(port.is_some() && port.value() == 8080, "parsed");
##     assert(byte.parse("256").is_none(), "too big for a byte");

extern double strtod(char* text, char** end);
extern float strtof(char* text, char** end);

# The value of the digit `c` in bases up to 36 (`0`-`9`, then `a`-`z` or
# `A`-`Z`), or 36 when `c` is not a digit.
_digit_value(c: byte): ulong {
    if (c >= '0' && c <= '9') {
        return (c - '0') as ulong;
    }
    if (c >= 'a' && c <= 'z') {
        return (c - 'a' + 10) as ulong;
    }
    if (c >= 'A' && c <= 'Z') {
        return (c - 'A' + 10) as ulong;
    }
    return 36;
}

# Reads the digits of `text` from `index` to the end in `base`, failing on a
# non-digit, on no digits, or on a value above `limit`.
_parse_digits(text: String, index: ulong, base: int, limit: ulong): (bool, ulong) {
    var size = text.size;
    if (index == size) {
        return (false, 0);
    }
    var radix = base as ulong;
    ulong magnitude = 0;
    while (index < size) {
        var digit = _digit_value(text.byte_at(index));
        if (digit >= radix || magnitude > (limit - digit) / radix) {
            return (false, 0);
        }
        magnitude = magnitude * radix + digit;
        index = index + 1;
    }
    return (true, magnitude);
}

# Parses an optional sign then digits in `base`, for a signed type whose
# values run from -`lowest` to `highest`.
_parse_signed(text: String, base: int, lowest: ulong, highest: ulong): (bool, long) {
    assert(base >= 2 && base <= 36, "parse: the base must be from 2 to 36");
    ulong index = 0;
    var negative = false;
    if (text.size > 0 && (text.byte_at(0) == '-' || text.byte_at(0) == '+')) {
        negative = text.byte_at(0) == '-';
        index = 1;
    }
    var (ok, magnitude) = _parse_digits(text, index, base, negative ? lowest : highest);
    if (!ok) {
        return (false, 0);
    }
    # The most negative long's magnitude, 2^63, wraps to itself here.
    return (true, negative ? 0 - (magnitude as long) : magnitude as long);
}

# Parses an optional `+` then digits in `base`, for an unsigned type whose
# values run up to `highest`.
_parse_unsigned(text: String, base: int, highest: ulong): (bool, ulong) {
    assert(base >= 2 && base <= 36, "parse: the base must be from 2 to 36");
    ulong index = 0;
    if (text.size > 0 && text.byte_at(0) == '+') {
        index = 1;
    }
    return _parse_digits(text, index, base, highest);
}

# Whether `text` is decimal notation: an optional sign, digits with at most
# one `.` among or around them (at least one digit), then optionally `e` or
# `E`, an optional sign and digits. strtod would also skip leading spaces and
# read `inf`, `nan` and hexadecimal, which `parse` does not accept.
_is_decimal(text: String): bool {
    var size = text.size;
    ulong index = 0;
    if (index < size && (text.byte_at(index) == '-' || text.byte_at(index) == '+')) {
        index = index + 1;
    }
    ulong digits = 0;
    while (index < size && _digit_value(text.byte_at(index)) < 10) {
        index = index + 1;
        digits = digits + 1;
    }
    if (index < size && text.byte_at(index) == '.') {
        index = index + 1;
        while (index < size && _digit_value(text.byte_at(index)) < 10) {
            index = index + 1;
            digits = digits + 1;
        }
    }
    if (digits == 0) {
        return false;
    }
    if (index < size && (text.byte_at(index) == 'e' || text.byte_at(index) == 'E')) {
        index = index + 1;
        if (index < size && (text.byte_at(index) == '-' || text.byte_at(index) == '+')) {
            index = index + 1;
        }
        ulong exponent = 0;
        while (index < size && _digit_value(text.byte_at(index)) < 10) {
            index = index + 1;
            exponent = exponent + 1;
        }
        if (exponent == 0) {
            return false;
        }
    }
    return index == size;
}

export extend char {
    ## Parses `text` as a `char` (`i8`) written in `base`: an optional `+`
    ## or `-`, then one or more digits, and nothing else. Digits past 9 are
    ## the letters, either case. No spaces, prefixes (`0x`) or separators
    ## are accepted.
    ##
    ## @param text the text to parse
    ## @param base the base the digits are written in, from 2 to 36; 10 by
    ##   default
    ## @returns the value, or none when `text` is not an integer in `base` or
    ##   the value is outside -128 to 127
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(i8.parse("-128").value() == -128, "the lowest");
    static parse(text: String, base: int = 10): char? {
        var (ok, value) = _parse_signed(text, base, 128, 127);
        if (!ok) {
            return Optional<char>.none();
        }
        return Optional<char>.some(value as char);
    }
}

export extend byte {
    ## Parses `text` as a `byte` (`u8`) written in `base`: an optional `+`,
    ## then one or more digits, and nothing else. Digits past 9 are the
    ## letters, either case. No spaces, prefixes (`0x`) or separators are
    ## accepted.
    ##
    ## @param text the text to parse
    ## @param base the base the digits are written in, from 2 to 36; 10 by
    ##   default
    ## @returns the value, or none when `text` is not an integer in `base` or
    ##   the value is above 255 (a `-` sign is never accepted)
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(byte.parse("ff", 16).value() == 255, "hexadecimal");
    static parse(text: String, base: int = 10): byte? {
        var (ok, value) = _parse_unsigned(text, base, 255);
        if (!ok) {
            return Optional<byte>.none();
        }
        return Optional<byte>.some(value as byte);
    }
}

export extend short {
    ## Parses `text` as a `short` (`i16`) written in `base`: an optional
    ## `+` or `-`, then one or more digits, and nothing else. Digits past 9
    ## are the letters, either case. No spaces, prefixes (`0x`) or
    ## separators are accepted.
    ##
    ## @param text the text to parse
    ## @param base the base the digits are written in, from 2 to 36; 10 by
    ##   default
    ## @returns the value, or none when `text` is not an integer in `base` or
    ##   the value is outside -32768 to 32767
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(short.parse("-300").value() == -300, "decimal");
    static parse(text: String, base: int = 10): short? {
        var (ok, value) = _parse_signed(text, base, 32768, 32767);
        if (!ok) {
            return Optional<short>.none();
        }
        return Optional<short>.some(value as short);
    }
}

export extend ushort {
    ## Parses `text` as a `ushort` (`u16`) written in `base`: an optional
    ## `+`, then one or more digits, and nothing else. Digits past 9 are the
    ## letters, either case. No spaces, prefixes (`0x`) or separators are
    ## accepted.
    ##
    ## @param text the text to parse
    ## @param base the base the digits are written in, from 2 to 36; 10 by
    ##   default
    ## @returns the value, or none when `text` is not an integer in `base` or
    ##   the value is above 65535 (a `-` sign is never accepted)
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(ushort.parse("8080").value() == 8080, "a port");
    static parse(text: String, base: int = 10): ushort? {
        var (ok, value) = _parse_unsigned(text, base, 65535);
        if (!ok) {
            return Optional<ushort>.none();
        }
        return Optional<ushort>.some(value as ushort);
    }
}

export extend int {
    ## Parses `text` as an `int` (`i32`) written in `base`: an optional `+`
    ## or `-`, then one or more digits, and nothing else. Digits past 9 are
    ## the letters, either case (`"ff"` in base 16 is 255). No spaces,
    ## prefixes (`0x`) or separators are accepted.
    ##
    ## @param text the text to parse
    ## @param base the base the digits are written in, from 2 to 36; 10 by
    ##   default
    ## @returns the value, or none when `text` is not an integer in `base` or
    ##   the value does not fit an `int`
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(int.parse("-42").value() == -42, "decimal");
    ##     assert(int.parse("ff", 16).value() == 255, "hexadecimal");
    ##     assert(int.parse("12x").is_none(), "not a number");
    static parse(text: String, base: int = 10): int? {
        var (ok, value) = _parse_signed(text, base, 2147483648, 2147483647);
        if (!ok) {
            return Optional<int>.none();
        }
        return Optional<int>.some(value as int);
    }
}

export extend uint {
    ## Parses `text` as a `uint` (`u32`) written in `base`: an optional `+`,
    ## then one or more digits, and nothing else. Digits past 9 are the
    ## letters, either case. No spaces, prefixes (`0x`) or separators are
    ## accepted.
    ##
    ## @param text the text to parse
    ## @param base the base the digits are written in, from 2 to 36; 10 by
    ##   default
    ## @returns the value, or none when `text` is not an integer in `base` or
    ##   the value does not fit a `uint` (a `-` sign is never accepted)
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(uint.parse("4294967295").value() == 4294967295, "the highest");
    static parse(text: String, base: int = 10): uint? {
        var (ok, value) = _parse_unsigned(text, base, 4294967295);
        if (!ok) {
            return Optional<uint>.none();
        }
        return Optional<uint>.some(value as uint);
    }
}

export extend long {
    ## Parses `text` as a `long` (`i64`) written in `base`: an optional `+`
    ## or `-`, then one or more digits, and nothing else. Digits past 9 are
    ## the letters, either case. No spaces, prefixes (`0x`) or separators
    ## are accepted.
    ##
    ## @param text the text to parse
    ## @param base the base the digits are written in, from 2 to 36; 10 by
    ##   default
    ## @returns the value, or none when `text` is not an integer in `base` or
    ##   the value does not fit a `long`
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(long.parse("-9000000000").value() == -9000000000, "decimal");
    ##     assert(long.parse("9223372036854775808").is_none(), "too big");
    static parse(text: String, base: int = 10): long? {
        var (ok, value) = _parse_signed(text, base, 0x8000000000000000, 9223372036854775807);
        if (!ok) {
            return Optional<long>.none();
        }
        return Optional<long>.some(value);
    }
}

export extend ulong {
    ## Parses `text` as a `ulong` (`u64`) written in `base`: an optional
    ## `+`, then one or more digits, and nothing else. Digits past 9 are the
    ## letters, either case. No spaces, prefixes (`0x`) or separators are
    ## accepted.
    ##
    ## @param text the text to parse
    ## @param base the base the digits are written in, from 2 to 36; 10 by
    ##   default
    ## @returns the value, or none when `text` is not an integer in `base` or
    ##   the value does not fit a `ulong` (a `-` sign is never accepted)
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(ulong.parse("ffffffffffffffff", 16).is_some(), "the highest");
    static parse(text: String, base: int = 10): ulong? {
        var (ok, value) = _parse_unsigned(text, base, 0xFFFFFFFFFFFFFFFF);
        if (!ok) {
            return Optional<ulong>.none();
        }
        return Optional<ulong>.some(value);
    }
}

export extend float {
    ## Parses `text` as a `float` written in decimal notation: an optional
    ## `+` or `-`, digits with an optional `.` among them (`"1.5"`, `".5"`,
    ## `"2."`), then an optional exponent (`"1e-3"`, `"2.5E8"`), and nothing
    ## else. The value is the nearest `float`. No spaces, `inf`, `nan` or
    ## hexadecimal are accepted.
    ##
    ## @param text the text to parse
    ## @returns the value, or none when `text` is not decimal notation or its
    ##   value is too large for a `float` (one too small rounds to zero)
    ## @example
    ##     assert(float.parse("0.25").value() == 0.25, "decimal");
    ##     assert(float.parse("1e39").is_none(), "too big");
    static parse(text: String): float? {
        if (!_is_decimal(text)) {
            return Optional<float>.none();
        }
        var value = strtof(text.c_str(), __null);
        # An infinity minus itself is NaN, not zero: the value overflowed.
        if (value - value != 0) {
            return Optional<float>.none();
        }
        return Optional<float>.some(value);
    }
}

export extend double {
    ## Parses `text` as a `double` written in decimal notation: an optional
    ## `+` or `-`, digits with an optional `.` among them (`"1.5"`, `".5"`,
    ## `"2."`), then an optional exponent (`"1e-3"`, `"2.5E8"`), and nothing
    ## else. The value is the nearest `double`. No spaces, `inf`, `nan` or
    ## hexadecimal are accepted.
    ##
    ## @param text the text to parse
    ## @returns the value, or none when `text` is not decimal notation or its
    ##   value is too large for a `double` (one too small rounds to zero)
    ## @example
    ##     assert(double.parse("-2.5e3").value() == -2500.0, "an exponent");
    ##     assert(double.parse("1.5.2").is_none(), "not a number");
    static parse(text: String): double? {
        if (!_is_decimal(text)) {
            return Optional<double>.none();
        }
        var value = strtod(text.c_str(), __null);
        # An infinity minus itself is NaN, not zero: the value overflowed.
        if (value - value != 0) {
            return Optional<double>.none();
        }
        return Optional<double>.some(value);
    }
}
