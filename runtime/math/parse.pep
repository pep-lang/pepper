## Reading integers from text.

# The value of the digit `c` in bases up to 36 (`0`-`9`, then `a`-`z` or
# `A`-`Z`), or 36 when `c` is not a digit.
_math_digit_value(c: byte): ulong {
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

## Parses `text` as an integer written in `base`: an optional `+` or `-`,
## then one or more digits, and nothing else. Digits past 9 are the
## letters, either case (`"ff"` in base 16 is 255). No spaces, prefixes
## (`0x`) or separators are accepted.
##
## @param text the text to parse
## @param base the base the digits are written in, from 2 to 36; 10 by
##   default
## @returns the value, or none when `text` is not an integer in `base` or
##   the value does not fit a `long`
## @panics if `base` is less than 2 or greater than 36
## @example
##     import math;
##
##     assert(math.parse_int("-42").value() == -42, "decimal");
##     assert(math.parse_int("ff", 16).value() == 255, "hexadecimal");
##     assert(!math.parse_int("12x").is_some(), "not a number");
##     assert(!math.parse_int("9223372036854775808").is_some(), "too big");
export parse_int(text: String, base: int = 10): long? {
    assert(base >= 2 && base <= 36, "math.parse_int: the base must be from 2 to 36");
    var size = text.size();
    ulong index = 0;
    var negative = false;
    if (size > 0 && (text.byte_at(0) == '-' || text.byte_at(0) == '+')) {
        negative = text.byte_at(0) == '-';
        index = 1;
    }
    if (index == size) {
        return Optional<long>.none();
    }
    # Accumulate the magnitude, which may reach 2^63 for the most negative
    # long.
    ulong limit = 9223372036854775807;
    if (negative) {
        limit = limit + 1;
    }
    var radix = base as ulong;
    ulong magnitude = 0;
    while (index < size) {
        var digit = _math_digit_value(text.byte_at(index));
        if (digit >= radix) {
            return Optional<long>.none();
        }
        if (magnitude > (limit - digit) / radix) {
            return Optional<long>.none();
        }
        magnitude = magnitude * radix + digit;
        index = index + 1;
    }
    if (negative) {
        return Optional<long>.some(0 - (magnitude as long));
    }
    return Optional<long>.some(magnitude as long);
}
