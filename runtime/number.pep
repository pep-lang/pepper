## Reading numbers from text, and arithmetic that says what to do on
## overflow.
##
## Every number type has a static `parse`: `int.parse("42")` gives an
## `int?`, empty when the text is not a number of that type. The integer
## types take a base from 2 to 36; `float` and `double` read decimal
## notation. Each spelling of a type is the same type, so `i32.parse` is
## `int.parse`.
##
## Integer `+`, `-` and `*` panic on overflow. Each integer type also has
## `wrapping_add` (the result modulo 2^bits), `checked_add` (none on
## overflow), `saturating_add` (clamped to the type's range) and
## `overflowing_add` (the wrapped result and whether it overflowed), with
## `sub` and `mul` forms of each.
##
## Each integer type also has bit operations that compile to one
## instruction on most CPUs (`leading_zeros`, `trailing_zeros`,
## `count_ones`, `count_zeros`, `swap_bytes`, `reverse_bits`, `rotate_left`,
## `rotate_right`), and `min`, `max` and, when signed, `abs`. `float` and
## `double` have `square_root`, `floor`, `ceiling`, `truncate`, `round`,
## `abs`, `copy_sign`, `multiply_add`, `min` and `max`, the trigonometric,
## hyperbolic, exponential and logarithmic functions of C's `<math.h>` with
## their names spelled out (`sine`, `arc_tangent2`, `logarithm10`, ...),
## `cube_root`, `hypotenuse`, `remainder`, and `is_nan`, `is_infinite`,
## `is_finite` and `sign_bit`. The `math` module has their constants
## (`math.PI`).
##
## @example
##     var port = int.parse("8080");
##     assert(port.is_value() && port.value() == 8080, "parsed");
##     assert(byte.parse("256").is_empty(), "too big for a byte");
##     int big = 2147483647;
##     assert(big.wrapping_add(1) == -2147483648, "wraps around");
##     assert(big.checked_add(1).is_empty(), "does not fit");
##     assert((40 as uint).trailing_zeros() == 3, "40 is 0b101000");

extern double strtod(char* text, char** end);
extern float strtof(char* text, char** end);

# LLVM intrinsics: each extern below is the instruction it names,
# overloaded on the width its prototype gives (see "LLVM intrinsics" in
# docs/src/language/c-interop.md).

[Link(name = "llvm.ctlz")]
extern byte _leading_zeros_8(byte value, bool is_zero_poison);

[Link(name = "llvm.cttz")]
extern byte _trailing_zeros_8(byte value, bool is_zero_poison);

[Link(name = "llvm.ctpop")]
extern byte _count_ones_8(byte value);

[Link(name = "llvm.bitreverse")]
extern byte _reverse_bits_8(byte value);

[Link(name = "llvm.fshl")]
extern byte _rotate_left_8(byte high, byte low, byte count);

[Link(name = "llvm.fshr")]
extern byte _rotate_right_8(byte high, byte low, byte count);

[Link(name = "llvm.ctlz")]
extern ushort _leading_zeros_16(ushort value, bool is_zero_poison);

[Link(name = "llvm.cttz")]
extern ushort _trailing_zeros_16(ushort value, bool is_zero_poison);

[Link(name = "llvm.ctpop")]
extern ushort _count_ones_16(ushort value);

[Link(name = "llvm.bitreverse")]
extern ushort _reverse_bits_16(ushort value);

[Link(name = "llvm.fshl")]
extern ushort _rotate_left_16(ushort high, ushort low, ushort count);

[Link(name = "llvm.fshr")]
extern ushort _rotate_right_16(ushort high, ushort low, ushort count);

[Link(name = "llvm.bswap")]
extern ushort _swap_bytes_16(ushort value);

[Link(name = "llvm.ctlz")]
extern uint _leading_zeros_32(uint value, bool is_zero_poison);

[Link(name = "llvm.cttz")]
extern uint _trailing_zeros_32(uint value, bool is_zero_poison);

[Link(name = "llvm.ctpop")]
extern uint _count_ones_32(uint value);

[Link(name = "llvm.bitreverse")]
extern uint _reverse_bits_32(uint value);

[Link(name = "llvm.fshl")]
extern uint _rotate_left_32(uint high, uint low, uint count);

[Link(name = "llvm.fshr")]
extern uint _rotate_right_32(uint high, uint low, uint count);

[Link(name = "llvm.bswap")]
extern uint _swap_bytes_32(uint value);

[Link(name = "llvm.ctlz")]
extern ulong _leading_zeros_64(ulong value, bool is_zero_poison);

[Link(name = "llvm.cttz")]
extern ulong _trailing_zeros_64(ulong value, bool is_zero_poison);

[Link(name = "llvm.ctpop")]
extern ulong _count_ones_64(ulong value);

[Link(name = "llvm.bitreverse")]
extern ulong _reverse_bits_64(ulong value);

[Link(name = "llvm.fshl")]
extern ulong _rotate_left_64(ulong high, ulong low, ulong count);

[Link(name = "llvm.fshr")]
extern ulong _rotate_right_64(ulong high, ulong low, ulong count);

[Link(name = "llvm.bswap")]
extern ulong _swap_bytes_64(ulong value);

[Link(name = "llvm.sqrt")]
extern float _square_root_32(float value);

[Link(name = "llvm.floor")]
extern float _floor_32(float value);

[Link(name = "llvm.ceil")]
extern float _ceiling_32(float value);

[Link(name = "llvm.trunc")]
extern float _truncate_32(float value);

[Link(name = "llvm.round")]
extern float _round_32(float value);

[Link(name = "llvm.fabs")]
extern float _abs_32(float value);

[Link(name = "llvm.copysign")]
extern float _copy_sign_32(float magnitude, float sign);

[Link(name = "llvm.fma")]
extern float _multiply_add_32(float a, float b, float c);

[Link(name = "llvm.minnum")]
extern float _min_32(float a, float b);

[Link(name = "llvm.maxnum")]
extern float _max_32(float a, float b);

[Link(name = "llvm.sin")]
extern float _sine_32(float value);

[Link(name = "llvm.cos")]
extern float _cosine_32(float value);

[Link(name = "llvm.tan")]
extern float _tangent_32(float value);

[Link(name = "llvm.asin")]
extern float _arc_sine_32(float value);

[Link(name = "llvm.acos")]
extern float _arc_cosine_32(float value);

[Link(name = "llvm.atan")]
extern float _arc_tangent_32(float value);

[Link(name = "llvm.atan2")]
extern float _arc_tangent2_32(float value, float x);

[Link(name = "llvm.sinh")]
extern float _hyperbolic_sine_32(float value);

[Link(name = "llvm.cosh")]
extern float _hyperbolic_cosine_32(float value);

[Link(name = "llvm.tanh")]
extern float _hyperbolic_tangent_32(float value);

[Link(name = "asinhf")]
extern float _arc_hyperbolic_sine_32(float value);

[Link(name = "acoshf")]
extern float _arc_hyperbolic_cosine_32(float value);

[Link(name = "atanhf")]
extern float _arc_hyperbolic_tangent_32(float value);

[Link(name = "llvm.exp")]
extern float _exponential_32(float value);

[Link(name = "llvm.exp2")]
extern float _exponential2_32(float value);

[Link(name = "expm1f")]
extern float _exponential_minus_one_32(float value);

[Link(name = "llvm.log")]
extern float _logarithm_32(float value);

[Link(name = "llvm.log2")]
extern float _logarithm2_32(float value);

[Link(name = "llvm.log10")]
extern float _logarithm10_32(float value);

[Link(name = "log1pf")]
extern float _logarithm_one_plus_32(float value);

[Link(name = "cbrtf")]
extern float _cube_root_32(float value);

[Link(name = "hypotf")]
extern float _hypotenuse_32(float value, float other);

[Link(name = "remainderf")]
extern float _remainder_32(float value, float divisor);

[Link(name = "llvm.sqrt")]
extern double _square_root_64(double value);

[Link(name = "llvm.floor")]
extern double _floor_64(double value);

[Link(name = "llvm.ceil")]
extern double _ceiling_64(double value);

[Link(name = "llvm.trunc")]
extern double _truncate_64(double value);

[Link(name = "llvm.round")]
extern double _round_64(double value);

[Link(name = "llvm.fabs")]
extern double _abs_64(double value);

[Link(name = "llvm.copysign")]
extern double _copy_sign_64(double magnitude, double sign);

[Link(name = "llvm.fma")]
extern double _multiply_add_64(double a, double b, double c);

[Link(name = "llvm.minnum")]
extern double _min_64(double a, double b);

[Link(name = "llvm.maxnum")]
extern double _max_64(double a, double b);

[Link(name = "llvm.sin")]
extern double _sine_64(double value);

[Link(name = "llvm.cos")]
extern double _cosine_64(double value);

[Link(name = "llvm.tan")]
extern double _tangent_64(double value);

[Link(name = "llvm.asin")]
extern double _arc_sine_64(double value);

[Link(name = "llvm.acos")]
extern double _arc_cosine_64(double value);

[Link(name = "llvm.atan")]
extern double _arc_tangent_64(double value);

[Link(name = "llvm.atan2")]
extern double _arc_tangent2_64(double value, double x);

[Link(name = "llvm.sinh")]
extern double _hyperbolic_sine_64(double value);

[Link(name = "llvm.cosh")]
extern double _hyperbolic_cosine_64(double value);

[Link(name = "llvm.tanh")]
extern double _hyperbolic_tangent_64(double value);

[Link(name = "asinh")]
extern double _arc_hyperbolic_sine_64(double value);

[Link(name = "acosh")]
extern double _arc_hyperbolic_cosine_64(double value);

[Link(name = "atanh")]
extern double _arc_hyperbolic_tangent_64(double value);

[Link(name = "llvm.exp")]
extern double _exponential_64(double value);

[Link(name = "llvm.exp2")]
extern double _exponential2_64(double value);

[Link(name = "expm1")]
extern double _exponential_minus_one_64(double value);

[Link(name = "llvm.log")]
extern double _logarithm_64(double value);

[Link(name = "llvm.log2")]
extern double _logarithm2_64(double value);

[Link(name = "llvm.log10")]
extern double _logarithm10_64(double value);

[Link(name = "log1p")]
extern double _logarithm_one_plus_64(double value);

[Link(name = "cbrt")]
extern double _cube_root_64(double value);

[Link(name = "hypot")]
extern double _hypotenuse_64(double value, double other);

[Link(name = "remainder")]
extern double _remainder_64(double value, double divisor);

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
        var value = text.byte_at(index).digit_value(base);
        if (value.is_empty()) {
            return (false, 0);
        }
        var digit = value.value() as ulong;
        if (magnitude > (limit - digit) / radix) {
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
    var value = magnitude as long;
    return (true, negative ? (0 as long).wrapping_sub(value) : value);
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

# C's `strtod` for text `_is_decimal` accepted. The Windows C runtime's
# result can be one unit in the last place off, so `_float_correct`
# (float_parse.pep) rounds it to the nearest double there.
[Target(OS(Windows))]
_number_strtod(text: String): double {
    return _float_correct(text, strtod(text.c_str(), __null));
}

[Target(!OS(Windows))]
_number_strtod(text: String): double {
    return strtod(text.c_str(), __null);
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
    while (index < size && text.byte_at(index).is_digit()) {
        index = index + 1;
        digits = digits + 1;
    }
    if (index < size && text.byte_at(index) == '.') {
        index = index + 1;
        while (index < size && text.byte_at(index).is_digit()) {
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
        while (index < size && text.byte_at(index).is_digit()) {
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
            return Optional<char>.Empty;
        }
        return Optional<char>.Value(value as char);
    }

    ## Whether this is an ASCII decimal digit, `0` to `9`, like C's
    ## `isdigit`.
    ##
    ## Like every classification method on `char`, it looks at ASCII only,
    ## as C does in the "C" locale: a negative `char` (a byte of UTF-8 text
    ## above 127) is never a digit, letter, space or punctuation. Unlike C's
    ## functions, it is defined for every value, negative ones included.
    ##
    ## @returns true for `0` to `9`
    is_digit(): bool {
        return (this as byte).is_digit();
    }

    ## Whether this is an ASCII hexadecimal digit, `0` to `9`, `a` to `f` or
    ## `A` to `F`, like C's `isxdigit`.
    ##
    ## @returns true for a hexadecimal digit, either case
    is_hex_digit(): bool {
        return (this as byte).is_hex_digit();
    }

    ## Whether this is an ASCII letter, `a` to `z` or `A` to `Z`, like C's
    ## `isalpha`.
    ##
    ## @returns true for an ASCII letter
    is_alphabetic(): bool {
        return (this as byte).is_alphabetic();
    }

    ## Whether this is an ASCII letter or digit, like C's `isalnum`.
    ##
    ## @returns true for `a` to `z`, `A` to `Z` or `0` to `9`
    is_alphanumeric(): bool {
        return (this as byte).is_alphanumeric();
    }

    ## Whether this is an ASCII uppercase letter, `A` to `Z`, like C's
    ## `isupper`.
    ##
    ## @returns true for `A` to `Z`
    is_upper(): bool {
        return (this as byte).is_upper();
    }

    ## Whether this is an ASCII lowercase letter, `a` to `z`, like C's
    ## `islower`.
    ##
    ## @returns true for `a` to `z`
    is_lower(): bool {
        return (this as byte).is_lower();
    }

    ## Whether this is ASCII whitespace: a space, tab (`\t`), line feed
    ## (`\n`), vertical tab, form feed or carriage return (`\r`), like C's
    ## `isspace`. `String.trim` strips the same set.
    ##
    ## @returns true for one of the six whitespace characters
    is_whitespace(): bool {
        return (this as byte).is_whitespace();
    }

    ## Whether this is a space or a tab, like C's `isblank`.
    ##
    ## @returns true for `' '` and `'\t'`
    is_blank(): bool {
        return (this as byte).is_blank();
    }

    ## Whether this is ASCII punctuation: printable, but not a letter, digit
    ## or space, like C's `ispunct`. That is ``!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~``.
    ##
    ## @returns true for one of the 32 ASCII punctuation characters
    is_punctuation(): bool {
        return (this as byte).is_punctuation();
    }

    ## Whether this is printable and not a space, `!` to `~`, like C's
    ## `isgraph`.
    ##
    ## @returns true for a letter, digit or punctuation
    is_graphic(): bool {
        return (this as byte).is_graphic();
    }

    ## Whether this is printable, a space through `~` (`0x20` to `0x7E`),
    ## like C's `isprint`.
    ##
    ## @returns true for a space, letter, digit or punctuation
    is_printable(): bool {
        return (this as byte).is_printable();
    }

    ## Whether this is an ASCII control character, `0x00` to `0x1F` or
    ## `0x7F` (delete), like C's `iscntrl`.
    ##
    ## @returns true for a control character
    is_control(): bool {
        return (this as byte).is_control();
    }

    ## Whether this is ASCII, `0x00` to `0x7F`, like C's `isascii`.
    ##
    ## @returns true for a value from 0 to 127
    is_ascii(): bool {
        return (this as byte).is_ascii();
    }

    ## Returns the uppercase letter for an ASCII lowercase letter, and this
    ## value unchanged for anything else, like C's `toupper`.
    ##
    ## @returns `A` to `Z` for `a` to `z`, otherwise this value
    to_upper(): char {
        return (this as byte).to_upper() as char;
    }

    ## Returns the lowercase letter for an ASCII uppercase letter, and this
    ## value unchanged for anything else, like C's `tolower`.
    ##
    ## @returns `a` to `z` for `A` to `Z`, otherwise this value
    to_lower(): char {
        return (this as byte).to_lower() as char;
    }

    ## Returns the value of this digit in `base`: `0` to `9` are 0 to 9,
    ## and the letters, either case, are 10 and up (`a` is 10, `z` is 35).
    ##
    ## @param base the base the digit is written in, from 2 to 36; 10 by
    ##   default
    ## @returns the digit's value, or none when this is not a digit in `base`
    ## @panics if `base` is less than 2 or greater than 36
    digit_value(base: int = 10): int? {
        return (this as byte).digit_value(base);
    }

    ## Returns `this + other` modulo 2^8: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to add
    ## @returns the sum, wrapped to a `char`
    wrapping_add(other: char): char {
        return __wrapping_add(this, other) as char;
    }

    ## Returns `this + other`, or none when the sum does not fit a
    ## `char`.
    ##
    ## @param other the value to add
    ## @returns the sum, or none on overflow
    checked_add(other: char): char? {
        if (__add_overflows(this, other)) {
            return Optional<char>.Empty;
        }
        return Optional<char>.Value(__wrapping_add(this, other) as char);
    }

    ## Returns `this + other`, clamped to the highest or lowest `char` on overflow.
    ##
    ## @param other the value to add
    ## @returns the sum, or the nearest `char` to it
    saturating_add(other: char): char {
        if (!__add_overflows(this, other)) {
            return __wrapping_add(this, other) as char;
        }
        return other > 0 ? 127 : -128;
    }

    ## Returns `this + other` modulo 2^8, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to add
    ## @returns the wrapped sum, and true when it overflowed
    overflowing_add(other: char): (char, bool) {
        return (__wrapping_add(this, other) as char, __add_overflows(this, other));
    }

    ## Returns `this - other` modulo 2^8: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to subtract
    ## @returns the difference, wrapped to a `char`
    wrapping_sub(other: char): char {
        return __wrapping_sub(this, other) as char;
    }

    ## Returns `this - other`, or none when the difference does not fit a
    ## `char`.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or none on overflow
    checked_sub(other: char): char? {
        if (__sub_overflows(this, other)) {
            return Optional<char>.Empty;
        }
        return Optional<char>.Value(__wrapping_sub(this, other) as char);
    }

    ## Returns `this - other`, clamped to the highest or lowest `char` on overflow.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or the nearest `char` to it
    saturating_sub(other: char): char {
        if (!__sub_overflows(this, other)) {
            return __wrapping_sub(this, other) as char;
        }
        return other < 0 ? 127 : -128;
    }

    ## Returns `this - other` modulo 2^8, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to subtract
    ## @returns the wrapped difference, and true when it overflowed
    overflowing_sub(other: char): (char, bool) {
        return (__wrapping_sub(this, other) as char, __sub_overflows(this, other));
    }

    ## Returns `this * other` modulo 2^8: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to multiply by
    ## @returns the product, wrapped to a `char`
    wrapping_mul(other: char): char {
        return __wrapping_mul(this, other) as char;
    }

    ## Returns `this * other`, or none when the product does not fit a
    ## `char`.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or none on overflow
    checked_mul(other: char): char? {
        if (__mul_overflows(this, other)) {
            return Optional<char>.Empty;
        }
        return Optional<char>.Value(__wrapping_mul(this, other) as char);
    }

    ## Returns `this * other`, clamped to the highest or lowest `char` on overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or the nearest `char` to it
    saturating_mul(other: char): char {
        if (!__mul_overflows(this, other)) {
            return __wrapping_mul(this, other) as char;
        }
        return (this < 0) == (other < 0) ? 127 : -128;
    }

    ## Returns `this * other` modulo 2^8, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to multiply by
    ## @returns the wrapped product, and true when it overflowed
    overflowing_mul(other: char): (char, bool) {
        return (__wrapping_mul(this, other) as char, __mul_overflows(this, other));
    }

    ## Returns the number of zero bits above the highest set bit: 8 for
    ## zero, 0 when the highest bit is set. One instruction on most CPUs
    ## (`llvm.ctlz`).
    ##
    ## @returns the count of leading zero bits, from 0 to 8
    ## @example
    ##     assert(((1 as char)).leading_zeros() == 7, "one bit, at the bottom");
    leading_zeros(): int {
        return _leading_zeros_8(this, false) as int;
    }

    ## Returns the number of zero bits below the lowest set bit: 8 for
    ## zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
    ## first set bit of a mask without a loop.
    ##
    ## @returns the count of trailing zero bits, from 0 to 8
    ## @example
    ##     assert((8 as char).trailing_zeros() == 3, "8 is 0b1000");
    trailing_zeros(): int {
        return _trailing_zeros_8(this, false) as int;
    }

    ## Returns the number of bits that are set (the population count,
    ## `llvm.ctpop`).
    ##
    ## @returns the count of one bits, from 0 to 8
    ## @example
    ##     assert((11 as char).count_ones() == 3, "three bits set");
    count_ones(): int {
        return _count_ones_8(this) as int;
    }

    ## Returns the number of bits that are clear.
    ##
    ## @returns the count of zero bits, from 0 to 8
    ## @example
    ##     assert((11 as char).count_zeros() == 5, "three bits set");
    count_zeros(): int {
        return 8 - _count_ones_8(this) as int;
    }

    ## Returns this value with its bytes in reverse order: a one-byte value
    ## is itself. Each integer type has this method; see `int.swap_bytes`.
    ##
    ## @returns this value
    swap_bytes(): char {
        return this;
    }

    ## Returns this value with its bits in reverse order: the lowest bit
    ## becomes the highest (`llvm.bitreverse`).
    ##
    ## @returns the value with its 8 bits reversed
    ## @example
    ##     assert(((1 as char)).reverse_bits().leading_zeros() == 0, "bottom to top");
    reverse_bits(): char {
        return unsafe_cast<char>(_reverse_bits_8(this));
    }

    ## Returns this value's bits rotated left by `count`: the bits shifted
    ## out at the top come back in at the bottom (`llvm.fshl`). `count` is
    ## taken modulo 8, so a negative count rotates right.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert((9 as char).rotate_left(7) == (9 as char).rotate_right(1), "the same rotation");
    rotate_left(count: int): char {
        return unsafe_cast<char>(_rotate_left_8(this, this, (count & 7) as byte));
    }

    ## Returns this value's bits rotated right by `count`: the bits shifted
    ## out at the bottom come back in at the top (`llvm.fshr`). `count` is
    ## taken modulo 8, so a negative count rotates left.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert(((1 as char)).rotate_right(1) == ((1 as char)).rotate_left(7), "the bottom bit to the top");
    rotate_right(count: int): char {
        return unsafe_cast<char>(_rotate_right_8(this, this, (count & 7) as byte));
    }

    ## Returns the smaller of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not greater than `other`, else `other`
    ## @example
    ##     assert((3 as char).min(5) == 3, "smaller");
    min(other: char): char {
        return this <= other ? this : other;
    }

    ## Returns the larger of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not less than `other`, else `other`
    ## @example
    ##     assert((3 as char).max(5) == 5, "larger");
    max(other: char): char {
        return this >= other ? this : other;
    }

    ## Returns the absolute value: `this` without its sign. The lowest
    ## value, -128, has no positive counterpart in a `char`, so it panics, as
    ## its negation does.
    ##
    ## @returns `-this` when this value is negative, else `this`
    ## @panics if this value is -128 ("integer overflow in 'char' absolute value")
    ## @example
    ##     assert((-5 as char).abs() == 5, "negative");
    abs(location: __ptr<char> = __caller_location()): char {
        if (this >= 0) {
            return this;
        }
        if (this == -127 - 1) {
            panic("integer overflow in 'char' absolute value", location);
        }
        return -this;
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
            return Optional<byte>.Empty;
        }
        return Optional<byte>.Value(value as byte);
    }

    ## Whether this is an ASCII decimal digit, `0` to `9`, like C's
    ## `isdigit`.
    ##
    ## Like every classification method on `byte`, it looks at ASCII only,
    ## as C does in the "C" locale: a value above 127 is never a digit,
    ## letter, space or punctuation.
    ##
    ## @returns true for `0` to `9`
    ## @example
    ##     assert(('7' as byte).is_digit(), "a digit");
    ##     assert(!('x' as byte).is_digit(), "a letter");
    is_digit(): bool {
        return this >= '0' && this <= '9';
    }

    ## Whether this is an ASCII hexadecimal digit, `0` to `9`, `a` to `f` or
    ## `A` to `F`, like C's `isxdigit`.
    ##
    ## @returns true for a hexadecimal digit, either case
    is_hex_digit(): bool {
        return is_digit() || (this >= 'a' && this <= 'f') || (this >= 'A' && this <= 'F');
    }

    ## Whether this is an ASCII letter, `a` to `z` or `A` to `Z`, like C's
    ## `isalpha`.
    ##
    ## @returns true for an ASCII letter
    is_alphabetic(): bool {
        return is_lower() || is_upper();
    }

    ## Whether this is an ASCII letter or digit, like C's `isalnum`.
    ##
    ## @returns true for `a` to `z`, `A` to `Z` or `0` to `9`
    is_alphanumeric(): bool {
        return is_alphabetic() || is_digit();
    }

    ## Whether this is an ASCII uppercase letter, `A` to `Z`, like C's
    ## `isupper`.
    ##
    ## @returns true for `A` to `Z`
    is_upper(): bool {
        return this >= 'A' && this <= 'Z';
    }

    ## Whether this is an ASCII lowercase letter, `a` to `z`, like C's
    ## `islower`.
    ##
    ## @returns true for `a` to `z`
    is_lower(): bool {
        return this >= 'a' && this <= 'z';
    }

    ## Whether this is ASCII whitespace: a space, tab (`\t`), line feed
    ## (`\n`), vertical tab, form feed or carriage return (`\r`), like C's
    ## `isspace`. `String.trim` strips the same set.
    ##
    ## @returns true for one of the six whitespace characters
    is_whitespace(): bool {
        return this == ' ' || (this >= '\t' && this <= '\r');
    }

    ## Whether this is a space or a tab, like C's `isblank`.
    ##
    ## @returns true for `' '` and `'\t'`
    is_blank(): bool {
        return this == ' ' || this == '\t';
    }

    ## Whether this is ASCII punctuation: printable, but not a letter, digit
    ## or space, like C's `ispunct`. That is ``!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~``.
    ##
    ## @returns true for one of the 32 ASCII punctuation characters
    ## @example
    ##     assert((';' as byte).is_punctuation(), "punctuation");
    ##     assert(!(' ' as byte).is_punctuation(), "a space is not");
    is_punctuation(): bool {
        return is_graphic() && !is_alphanumeric();
    }

    ## Whether this is printable and not a space, `!` to `~`, like C's
    ## `isgraph`.
    ##
    ## @returns true for a letter, digit or punctuation
    is_graphic(): bool {
        return this > ' ' && this <= '~';
    }

    ## Whether this is printable, a space through `~` (`0x20` to `0x7E`),
    ## like C's `isprint`.
    ##
    ## @returns true for a space, letter, digit or punctuation
    is_printable(): bool {
        return this >= ' ' && this <= '~';
    }

    ## Whether this is an ASCII control character, `0x00` to `0x1F` or
    ## `0x7F` (delete), like C's `iscntrl`.
    ##
    ## @returns true for a control character
    is_control(): bool {
        return this < ' ' || this == 127;
    }

    ## Whether this is ASCII, `0x00` to `0x7F`, like C's `isascii`.
    ##
    ## @returns true for a value below 128
    is_ascii(): bool {
        return this < 128;
    }

    ## Returns the uppercase letter for an ASCII lowercase letter, and this
    ## value unchanged for anything else, like C's `toupper`.
    ##
    ## @returns `A` to `Z` for `a` to `z`, otherwise this value
    ## @example
    ##     assert(('q' as byte).to_upper() == 'Q', "raised");
    ##     assert(('?' as byte).to_upper() == '?', "kept");
    to_upper(): byte {
        if (is_lower()) {
            return (this - 'a' + 'A') as byte;
        }
        return this;
    }

    ## Returns the lowercase letter for an ASCII uppercase letter, and this
    ## value unchanged for anything else, like C's `tolower`.
    ##
    ## @returns `a` to `z` for `A` to `Z`, otherwise this value
    to_lower(): byte {
        if (is_upper()) {
            return (this - 'A' + 'a') as byte;
        }
        return this;
    }

    ## Returns the value of this digit in `base`: `0` to `9` are 0 to 9,
    ## and the letters, either case, are 10 and up (`a` is 10, `z` is 35).
    ##
    ## @param base the base the digit is written in, from 2 to 36; 10 by
    ##   default
    ## @returns the digit's value, or none when this is not a digit in `base`
    ## @panics if `base` is less than 2 or greater than 36
    ## @example
    ##     assert(('7' as byte).digit_value().value() == 7, "decimal");
    ##     assert(('F' as byte).digit_value(16).value() == 15, "hexadecimal");
    ##     assert(('9' as byte).digit_value(8).is_empty(), "not octal");
    digit_value(base: int = 10): int? {
        assert(base >= 2 && base <= 36, "digit_value: the base must be from 2 to 36");
        var value = base;
        if (is_digit()) {
            value = (this - '0') as int;
        } else if (is_lower()) {
            value = (this - 'a' + 10) as int;
        } else if (is_upper()) {
            value = (this - 'A' + 10) as int;
        }
        if (value >= base) {
            return Optional<int>.Empty;
        }
        return Optional<int>.Value(value);
    }

    ## Returns `this + other` modulo 2^8: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to add
    ## @returns the sum, wrapped to a `byte`
    wrapping_add(other: byte): byte {
        return __wrapping_add(this, other) as byte;
    }

    ## Returns `this + other`, or none when the sum does not fit a
    ## `byte`.
    ##
    ## @param other the value to add
    ## @returns the sum, or none on overflow
    checked_add(other: byte): byte? {
        if (__add_overflows(this, other)) {
            return Optional<byte>.Empty;
        }
        return Optional<byte>.Value(__wrapping_add(this, other) as byte);
    }

    ## Returns `this + other`, clamped to the highest `byte` on overflow.
    ##
    ## @param other the value to add
    ## @returns the sum, or the nearest `byte` to it
    saturating_add(other: byte): byte {
        if (!__add_overflows(this, other)) {
            return __wrapping_add(this, other) as byte;
        }
        return 255;
    }

    ## Returns `this + other` modulo 2^8, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to add
    ## @returns the wrapped sum, and true when it overflowed
    overflowing_add(other: byte): (byte, bool) {
        return (__wrapping_add(this, other) as byte, __add_overflows(this, other));
    }

    ## Returns `this - other` modulo 2^8: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to subtract
    ## @returns the difference, wrapped to a `byte`
    wrapping_sub(other: byte): byte {
        return __wrapping_sub(this, other) as byte;
    }

    ## Returns `this - other`, or none when the difference does not fit a
    ## `byte`.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or none on overflow
    checked_sub(other: byte): byte? {
        if (__sub_overflows(this, other)) {
            return Optional<byte>.Empty;
        }
        return Optional<byte>.Value(__wrapping_sub(this, other) as byte);
    }

    ## Returns `this - other`, clamped to 0 on overflow.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or the nearest `byte` to it
    saturating_sub(other: byte): byte {
        if (!__sub_overflows(this, other)) {
            return __wrapping_sub(this, other) as byte;
        }
        return 0;
    }

    ## Returns `this - other` modulo 2^8, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to subtract
    ## @returns the wrapped difference, and true when it overflowed
    overflowing_sub(other: byte): (byte, bool) {
        return (__wrapping_sub(this, other) as byte, __sub_overflows(this, other));
    }

    ## Returns `this * other` modulo 2^8: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to multiply by
    ## @returns the product, wrapped to a `byte`
    wrapping_mul(other: byte): byte {
        return __wrapping_mul(this, other) as byte;
    }

    ## Returns `this * other`, or none when the product does not fit a
    ## `byte`.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or none on overflow
    checked_mul(other: byte): byte? {
        if (__mul_overflows(this, other)) {
            return Optional<byte>.Empty;
        }
        return Optional<byte>.Value(__wrapping_mul(this, other) as byte);
    }

    ## Returns `this * other`, clamped to the highest `byte` on overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or the nearest `byte` to it
    saturating_mul(other: byte): byte {
        if (!__mul_overflows(this, other)) {
            return __wrapping_mul(this, other) as byte;
        }
        return 255;
    }

    ## Returns `this * other` modulo 2^8, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to multiply by
    ## @returns the wrapped product, and true when it overflowed
    overflowing_mul(other: byte): (byte, bool) {
        return (__wrapping_mul(this, other) as byte, __mul_overflows(this, other));
    }

    ## Returns the number of zero bits above the highest set bit: 8 for
    ## zero, 0 when the highest bit is set. One instruction on most CPUs
    ## (`llvm.ctlz`).
    ##
    ## @returns the count of leading zero bits, from 0 to 8
    ## @example
    ##     assert(((1 as byte)).leading_zeros() == 7, "one bit, at the bottom");
    leading_zeros(): int {
        return _leading_zeros_8(this, false) as int;
    }

    ## Returns the number of zero bits below the lowest set bit: 8 for
    ## zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
    ## first set bit of a mask without a loop.
    ##
    ## @returns the count of trailing zero bits, from 0 to 8
    ## @example
    ##     assert((8 as byte).trailing_zeros() == 3, "8 is 0b1000");
    trailing_zeros(): int {
        return _trailing_zeros_8(this, false) as int;
    }

    ## Returns the number of bits that are set (the population count,
    ## `llvm.ctpop`).
    ##
    ## @returns the count of one bits, from 0 to 8
    ## @example
    ##     assert((11 as byte).count_ones() == 3, "three bits set");
    count_ones(): int {
        return _count_ones_8(this) as int;
    }

    ## Returns the number of bits that are clear.
    ##
    ## @returns the count of zero bits, from 0 to 8
    ## @example
    ##     assert((11 as byte).count_zeros() == 5, "three bits set");
    count_zeros(): int {
        return 8 - _count_ones_8(this) as int;
    }

    ## Returns this value with its bytes in reverse order: a one-byte value
    ## is itself. Each integer type has this method; see `int.swap_bytes`.
    ##
    ## @returns this value
    swap_bytes(): byte {
        return this;
    }

    ## Returns this value with its bits in reverse order: the lowest bit
    ## becomes the highest (`llvm.bitreverse`).
    ##
    ## @returns the value with its 8 bits reversed
    ## @example
    ##     assert(((1 as byte)).reverse_bits().leading_zeros() == 0, "bottom to top");
    reverse_bits(): byte {
        return _reverse_bits_8(this);
    }

    ## Returns this value's bits rotated left by `count`: the bits shifted
    ## out at the top come back in at the bottom (`llvm.fshl`). `count` is
    ## taken modulo 8, so a negative count rotates right.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert((9 as byte).rotate_left(7) == (9 as byte).rotate_right(1), "the same rotation");
    rotate_left(count: int): byte {
        return _rotate_left_8(this, this, (count & 7) as byte);
    }

    ## Returns this value's bits rotated right by `count`: the bits shifted
    ## out at the bottom come back in at the top (`llvm.fshr`). `count` is
    ## taken modulo 8, so a negative count rotates left.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert(((1 as byte)).rotate_right(1) == ((1 as byte)).rotate_left(7), "the bottom bit to the top");
    rotate_right(count: int): byte {
        return _rotate_right_8(this, this, (count & 7) as byte);
    }

    ## Returns the smaller of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not greater than `other`, else `other`
    ## @example
    ##     assert((3 as byte).min(5) == 3, "smaller");
    min(other: byte): byte {
        return this <= other ? this : other;
    }

    ## Returns the larger of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not less than `other`, else `other`
    ## @example
    ##     assert((3 as byte).max(5) == 5, "larger");
    max(other: byte): byte {
        return this >= other ? this : other;
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
            return Optional<short>.Empty;
        }
        return Optional<short>.Value(value as short);
    }

    ## Returns `this + other` modulo 2^16: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to add
    ## @returns the sum, wrapped to a `short`
    wrapping_add(other: short): short {
        return __wrapping_add(this, other) as short;
    }

    ## Returns `this + other`, or none when the sum does not fit a
    ## `short`.
    ##
    ## @param other the value to add
    ## @returns the sum, or none on overflow
    checked_add(other: short): short? {
        if (__add_overflows(this, other)) {
            return Optional<short>.Empty;
        }
        return Optional<short>.Value(__wrapping_add(this, other) as short);
    }

    ## Returns `this + other`, clamped to the highest or lowest `short` on overflow.
    ##
    ## @param other the value to add
    ## @returns the sum, or the nearest `short` to it
    saturating_add(other: short): short {
        if (!__add_overflows(this, other)) {
            return __wrapping_add(this, other) as short;
        }
        return other > 0 ? 32767 : -32768;
    }

    ## Returns `this + other` modulo 2^16, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to add
    ## @returns the wrapped sum, and true when it overflowed
    overflowing_add(other: short): (short, bool) {
        return (__wrapping_add(this, other) as short, __add_overflows(this, other));
    }

    ## Returns `this - other` modulo 2^16: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to subtract
    ## @returns the difference, wrapped to a `short`
    wrapping_sub(other: short): short {
        return __wrapping_sub(this, other) as short;
    }

    ## Returns `this - other`, or none when the difference does not fit a
    ## `short`.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or none on overflow
    checked_sub(other: short): short? {
        if (__sub_overflows(this, other)) {
            return Optional<short>.Empty;
        }
        return Optional<short>.Value(__wrapping_sub(this, other) as short);
    }

    ## Returns `this - other`, clamped to the highest or lowest `short` on overflow.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or the nearest `short` to it
    saturating_sub(other: short): short {
        if (!__sub_overflows(this, other)) {
            return __wrapping_sub(this, other) as short;
        }
        return other < 0 ? 32767 : -32768;
    }

    ## Returns `this - other` modulo 2^16, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to subtract
    ## @returns the wrapped difference, and true when it overflowed
    overflowing_sub(other: short): (short, bool) {
        return (__wrapping_sub(this, other) as short, __sub_overflows(this, other));
    }

    ## Returns `this * other` modulo 2^16: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to multiply by
    ## @returns the product, wrapped to a `short`
    wrapping_mul(other: short): short {
        return __wrapping_mul(this, other) as short;
    }

    ## Returns `this * other`, or none when the product does not fit a
    ## `short`.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or none on overflow
    checked_mul(other: short): short? {
        if (__mul_overflows(this, other)) {
            return Optional<short>.Empty;
        }
        return Optional<short>.Value(__wrapping_mul(this, other) as short);
    }

    ## Returns `this * other`, clamped to the highest or lowest `short` on overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or the nearest `short` to it
    saturating_mul(other: short): short {
        if (!__mul_overflows(this, other)) {
            return __wrapping_mul(this, other) as short;
        }
        return (this < 0) == (other < 0) ? 32767 : -32768;
    }

    ## Returns `this * other` modulo 2^16, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to multiply by
    ## @returns the wrapped product, and true when it overflowed
    overflowing_mul(other: short): (short, bool) {
        return (__wrapping_mul(this, other) as short, __mul_overflows(this, other));
    }

    ## Returns the number of zero bits above the highest set bit: 16 for
    ## zero, 0 when the highest bit is set. One instruction on most CPUs
    ## (`llvm.ctlz`).
    ##
    ## @returns the count of leading zero bits, from 0 to 16
    ## @example
    ##     assert(((1 as short)).leading_zeros() == 15, "one bit, at the bottom");
    leading_zeros(): int {
        return _leading_zeros_16(this, false) as int;
    }

    ## Returns the number of zero bits below the lowest set bit: 16 for
    ## zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
    ## first set bit of a mask without a loop.
    ##
    ## @returns the count of trailing zero bits, from 0 to 16
    ## @example
    ##     assert((8 as short).trailing_zeros() == 3, "8 is 0b1000");
    trailing_zeros(): int {
        return _trailing_zeros_16(this, false) as int;
    }

    ## Returns the number of bits that are set (the population count,
    ## `llvm.ctpop`).
    ##
    ## @returns the count of one bits, from 0 to 16
    ## @example
    ##     assert((11 as short).count_ones() == 3, "three bits set");
    count_ones(): int {
        return _count_ones_16(this) as int;
    }

    ## Returns the number of bits that are clear.
    ##
    ## @returns the count of zero bits, from 0 to 16
    ## @example
    ##     assert((11 as short).count_zeros() == 13, "three bits set");
    count_zeros(): int {
        return 16 - _count_ones_16(this) as int;
    }

    ## Returns this value with its bytes in reverse order (`llvm.bswap`), to
    ## convert between little-endian and big-endian byte order.
    ##
    ## @returns the value with its 2 bytes reversed
    ## @example
    ##     assert((0x1234 as short).swap_bytes() == 0x3412, "bytes reversed");
    swap_bytes(): short {
        return unsafe_cast<short>(_swap_bytes_16(this));
    }

    ## Returns this value with its bits in reverse order: the lowest bit
    ## becomes the highest (`llvm.bitreverse`).
    ##
    ## @returns the value with its 16 bits reversed
    ## @example
    ##     assert(((1 as short)).reverse_bits().leading_zeros() == 0, "bottom to top");
    reverse_bits(): short {
        return unsafe_cast<short>(_reverse_bits_16(this));
    }

    ## Returns this value's bits rotated left by `count`: the bits shifted
    ## out at the top come back in at the bottom (`llvm.fshl`). `count` is
    ## taken modulo 16, so a negative count rotates right.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert((9 as short).rotate_left(15) == (9 as short).rotate_right(1), "the same rotation");
    rotate_left(count: int): short {
        return unsafe_cast<short>(_rotate_left_16(this, this, (count & 15) as ushort));
    }

    ## Returns this value's bits rotated right by `count`: the bits shifted
    ## out at the bottom come back in at the top (`llvm.fshr`). `count` is
    ## taken modulo 16, so a negative count rotates left.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert(((1 as short)).rotate_right(1) == ((1 as short)).rotate_left(15), "the bottom bit to the top");
    rotate_right(count: int): short {
        return unsafe_cast<short>(_rotate_right_16(this, this, (count & 15) as ushort));
    }

    ## Returns the smaller of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not greater than `other`, else `other`
    ## @example
    ##     assert((3 as short).min(5) == 3, "smaller");
    min(other: short): short {
        return this <= other ? this : other;
    }

    ## Returns the larger of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not less than `other`, else `other`
    ## @example
    ##     assert((3 as short).max(5) == 5, "larger");
    max(other: short): short {
        return this >= other ? this : other;
    }

    ## Returns the absolute value: `this` without its sign. The lowest
    ## value, -32768, has no positive counterpart in a `short`, so it panics, as
    ## its negation does.
    ##
    ## @returns `-this` when this value is negative, else `this`
    ## @panics if this value is -32768 ("integer overflow in 'short' absolute value")
    ## @example
    ##     assert((-5 as short).abs() == 5, "negative");
    abs(location: __ptr<char> = __caller_location()): short {
        if (this >= 0) {
            return this;
        }
        if (this == -32767 - 1) {
            panic("integer overflow in 'short' absolute value", location);
        }
        return -this;
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
            return Optional<ushort>.Empty;
        }
        return Optional<ushort>.Value(value as ushort);
    }

    ## Returns `this + other` modulo 2^16: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to add
    ## @returns the sum, wrapped to a `ushort`
    wrapping_add(other: ushort): ushort {
        return __wrapping_add(this, other) as ushort;
    }

    ## Returns `this + other`, or none when the sum does not fit a
    ## `ushort`.
    ##
    ## @param other the value to add
    ## @returns the sum, or none on overflow
    checked_add(other: ushort): ushort? {
        if (__add_overflows(this, other)) {
            return Optional<ushort>.Empty;
        }
        return Optional<ushort>.Value(__wrapping_add(this, other) as ushort);
    }

    ## Returns `this + other`, clamped to the highest `ushort` on overflow.
    ##
    ## @param other the value to add
    ## @returns the sum, or the nearest `ushort` to it
    saturating_add(other: ushort): ushort {
        if (!__add_overflows(this, other)) {
            return __wrapping_add(this, other) as ushort;
        }
        return 65535;
    }

    ## Returns `this + other` modulo 2^16, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to add
    ## @returns the wrapped sum, and true when it overflowed
    overflowing_add(other: ushort): (ushort, bool) {
        return (__wrapping_add(this, other) as ushort, __add_overflows(this, other));
    }

    ## Returns `this - other` modulo 2^16: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to subtract
    ## @returns the difference, wrapped to a `ushort`
    wrapping_sub(other: ushort): ushort {
        return __wrapping_sub(this, other) as ushort;
    }

    ## Returns `this - other`, or none when the difference does not fit a
    ## `ushort`.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or none on overflow
    checked_sub(other: ushort): ushort? {
        if (__sub_overflows(this, other)) {
            return Optional<ushort>.Empty;
        }
        return Optional<ushort>.Value(__wrapping_sub(this, other) as ushort);
    }

    ## Returns `this - other`, clamped to 0 on overflow.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or the nearest `ushort` to it
    saturating_sub(other: ushort): ushort {
        if (!__sub_overflows(this, other)) {
            return __wrapping_sub(this, other) as ushort;
        }
        return 0;
    }

    ## Returns `this - other` modulo 2^16, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to subtract
    ## @returns the wrapped difference, and true when it overflowed
    overflowing_sub(other: ushort): (ushort, bool) {
        return (__wrapping_sub(this, other) as ushort, __sub_overflows(this, other));
    }

    ## Returns `this * other` modulo 2^16: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to multiply by
    ## @returns the product, wrapped to a `ushort`
    wrapping_mul(other: ushort): ushort {
        return __wrapping_mul(this, other) as ushort;
    }

    ## Returns `this * other`, or none when the product does not fit a
    ## `ushort`.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or none on overflow
    checked_mul(other: ushort): ushort? {
        if (__mul_overflows(this, other)) {
            return Optional<ushort>.Empty;
        }
        return Optional<ushort>.Value(__wrapping_mul(this, other) as ushort);
    }

    ## Returns `this * other`, clamped to the highest `ushort` on overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or the nearest `ushort` to it
    saturating_mul(other: ushort): ushort {
        if (!__mul_overflows(this, other)) {
            return __wrapping_mul(this, other) as ushort;
        }
        return 65535;
    }

    ## Returns `this * other` modulo 2^16, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to multiply by
    ## @returns the wrapped product, and true when it overflowed
    overflowing_mul(other: ushort): (ushort, bool) {
        return (__wrapping_mul(this, other) as ushort, __mul_overflows(this, other));
    }

    ## Returns the number of zero bits above the highest set bit: 16 for
    ## zero, 0 when the highest bit is set. One instruction on most CPUs
    ## (`llvm.ctlz`).
    ##
    ## @returns the count of leading zero bits, from 0 to 16
    ## @example
    ##     assert(((1 as ushort)).leading_zeros() == 15, "one bit, at the bottom");
    leading_zeros(): int {
        return _leading_zeros_16(this, false) as int;
    }

    ## Returns the number of zero bits below the lowest set bit: 16 for
    ## zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
    ## first set bit of a mask without a loop.
    ##
    ## @returns the count of trailing zero bits, from 0 to 16
    ## @example
    ##     assert((8 as ushort).trailing_zeros() == 3, "8 is 0b1000");
    trailing_zeros(): int {
        return _trailing_zeros_16(this, false) as int;
    }

    ## Returns the number of bits that are set (the population count,
    ## `llvm.ctpop`).
    ##
    ## @returns the count of one bits, from 0 to 16
    ## @example
    ##     assert((11 as ushort).count_ones() == 3, "three bits set");
    count_ones(): int {
        return _count_ones_16(this) as int;
    }

    ## Returns the number of bits that are clear.
    ##
    ## @returns the count of zero bits, from 0 to 16
    ## @example
    ##     assert((11 as ushort).count_zeros() == 13, "three bits set");
    count_zeros(): int {
        return 16 - _count_ones_16(this) as int;
    }

    ## Returns this value with its bytes in reverse order (`llvm.bswap`), to
    ## convert between little-endian and big-endian byte order.
    ##
    ## @returns the value with its 2 bytes reversed
    ## @example
    ##     assert((0x1234 as ushort).swap_bytes() == 0x3412, "bytes reversed");
    swap_bytes(): ushort {
        return _swap_bytes_16(this);
    }

    ## Returns this value with its bits in reverse order: the lowest bit
    ## becomes the highest (`llvm.bitreverse`).
    ##
    ## @returns the value with its 16 bits reversed
    ## @example
    ##     assert(((1 as ushort)).reverse_bits().leading_zeros() == 0, "bottom to top");
    reverse_bits(): ushort {
        return _reverse_bits_16(this);
    }

    ## Returns this value's bits rotated left by `count`: the bits shifted
    ## out at the top come back in at the bottom (`llvm.fshl`). `count` is
    ## taken modulo 16, so a negative count rotates right.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert((9 as ushort).rotate_left(15) == (9 as ushort).rotate_right(1), "the same rotation");
    rotate_left(count: int): ushort {
        return _rotate_left_16(this, this, (count & 15) as ushort);
    }

    ## Returns this value's bits rotated right by `count`: the bits shifted
    ## out at the bottom come back in at the top (`llvm.fshr`). `count` is
    ## taken modulo 16, so a negative count rotates left.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert(((1 as ushort)).rotate_right(1) == ((1 as ushort)).rotate_left(15), "the bottom bit to the top");
    rotate_right(count: int): ushort {
        return _rotate_right_16(this, this, (count & 15) as ushort);
    }

    ## Returns the smaller of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not greater than `other`, else `other`
    ## @example
    ##     assert((3 as ushort).min(5) == 3, "smaller");
    min(other: ushort): ushort {
        return this <= other ? this : other;
    }

    ## Returns the larger of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not less than `other`, else `other`
    ## @example
    ##     assert((3 as ushort).max(5) == 5, "larger");
    max(other: ushort): ushort {
        return this >= other ? this : other;
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
    ##     assert(int.parse("12x").is_empty(), "not a number");
    static parse(text: String, base: int = 10): int? {
        var (ok, value) = _parse_signed(text, base, 2147483648, 2147483647);
        if (!ok) {
            return Optional<int>.Empty;
        }
        return Optional<int>.Value(value as int);
    }

    ## Returns `this + other` modulo 2^32: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to add
    ## @returns the sum, wrapped to a `int`
    wrapping_add(other: int): int {
        return __wrapping_add(this, other) as int;
    }

    ## Returns `this + other`, or none when the sum does not fit a
    ## `int`.
    ##
    ## @param other the value to add
    ## @returns the sum, or none on overflow
    checked_add(other: int): int? {
        if (__add_overflows(this, other)) {
            return Optional<int>.Empty;
        }
        return Optional<int>.Value(__wrapping_add(this, other) as int);
    }

    ## Returns `this + other`, clamped to the highest or lowest `int` on overflow.
    ##
    ## @param other the value to add
    ## @returns the sum, or the nearest `int` to it
    saturating_add(other: int): int {
        if (!__add_overflows(this, other)) {
            return __wrapping_add(this, other) as int;
        }
        return other > 0 ? 2147483647 : -2147483648;
    }

    ## Returns `this + other` modulo 2^32, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to add
    ## @returns the wrapped sum, and true when it overflowed
    overflowing_add(other: int): (int, bool) {
        return (__wrapping_add(this, other) as int, __add_overflows(this, other));
    }

    ## Returns `this - other` modulo 2^32: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to subtract
    ## @returns the difference, wrapped to a `int`
    wrapping_sub(other: int): int {
        return __wrapping_sub(this, other) as int;
    }

    ## Returns `this - other`, or none when the difference does not fit a
    ## `int`.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or none on overflow
    checked_sub(other: int): int? {
        if (__sub_overflows(this, other)) {
            return Optional<int>.Empty;
        }
        return Optional<int>.Value(__wrapping_sub(this, other) as int);
    }

    ## Returns `this - other`, clamped to the highest or lowest `int` on overflow.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or the nearest `int` to it
    saturating_sub(other: int): int {
        if (!__sub_overflows(this, other)) {
            return __wrapping_sub(this, other) as int;
        }
        return other < 0 ? 2147483647 : -2147483648;
    }

    ## Returns `this - other` modulo 2^32, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to subtract
    ## @returns the wrapped difference, and true when it overflowed
    overflowing_sub(other: int): (int, bool) {
        return (__wrapping_sub(this, other) as int, __sub_overflows(this, other));
    }

    ## Returns `this * other` modulo 2^32: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to multiply by
    ## @returns the product, wrapped to a `int`
    wrapping_mul(other: int): int {
        return __wrapping_mul(this, other) as int;
    }

    ## Returns `this * other`, or none when the product does not fit a
    ## `int`.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or none on overflow
    checked_mul(other: int): int? {
        if (__mul_overflows(this, other)) {
            return Optional<int>.Empty;
        }
        return Optional<int>.Value(__wrapping_mul(this, other) as int);
    }

    ## Returns `this * other`, clamped to the highest or lowest `int` on overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or the nearest `int` to it
    saturating_mul(other: int): int {
        if (!__mul_overflows(this, other)) {
            return __wrapping_mul(this, other) as int;
        }
        return (this < 0) == (other < 0) ? 2147483647 : -2147483648;
    }

    ## Returns `this * other` modulo 2^32, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to multiply by
    ## @returns the wrapped product, and true when it overflowed
    overflowing_mul(other: int): (int, bool) {
        return (__wrapping_mul(this, other) as int, __mul_overflows(this, other));
    }

    ## Returns the number of zero bits above the highest set bit: 32 for
    ## zero, 0 when the highest bit is set. One instruction on most CPUs
    ## (`llvm.ctlz`).
    ##
    ## @returns the count of leading zero bits, from 0 to 32
    ## @example
    ##     assert(((1 as int)).leading_zeros() == 31, "one bit, at the bottom");
    leading_zeros(): int {
        return _leading_zeros_32(this, false) as int;
    }

    ## Returns the number of zero bits below the lowest set bit: 32 for
    ## zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
    ## first set bit of a mask without a loop.
    ##
    ## @returns the count of trailing zero bits, from 0 to 32
    ## @example
    ##     assert((8 as int).trailing_zeros() == 3, "8 is 0b1000");
    trailing_zeros(): int {
        return _trailing_zeros_32(this, false) as int;
    }

    ## Returns the number of bits that are set (the population count,
    ## `llvm.ctpop`).
    ##
    ## @returns the count of one bits, from 0 to 32
    ## @example
    ##     assert((11 as int).count_ones() == 3, "three bits set");
    count_ones(): int {
        return _count_ones_32(this) as int;
    }

    ## Returns the number of bits that are clear.
    ##
    ## @returns the count of zero bits, from 0 to 32
    ## @example
    ##     assert((11 as int).count_zeros() == 29, "three bits set");
    count_zeros(): int {
        return 32 - _count_ones_32(this) as int;
    }

    ## Returns this value with its bytes in reverse order (`llvm.bswap`), to
    ## convert between little-endian and big-endian byte order.
    ##
    ## @returns the value with its 4 bytes reversed
    ## @example
    ##     assert((0x12345678 as int).swap_bytes() == 0x78563412, "bytes reversed");
    swap_bytes(): int {
        return unsafe_cast<int>(_swap_bytes_32(this));
    }

    ## Returns this value with its bits in reverse order: the lowest bit
    ## becomes the highest (`llvm.bitreverse`).
    ##
    ## @returns the value with its 32 bits reversed
    ## @example
    ##     assert(((1 as int)).reverse_bits().leading_zeros() == 0, "bottom to top");
    reverse_bits(): int {
        return unsafe_cast<int>(_reverse_bits_32(this));
    }

    ## Returns this value's bits rotated left by `count`: the bits shifted
    ## out at the top come back in at the bottom (`llvm.fshl`). `count` is
    ## taken modulo 32, so a negative count rotates right.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert((9 as int).rotate_left(31) == (9 as int).rotate_right(1), "the same rotation");
    rotate_left(count: int): int {
        return unsafe_cast<int>(_rotate_left_32(this, this, (count & 31) as uint));
    }

    ## Returns this value's bits rotated right by `count`: the bits shifted
    ## out at the bottom come back in at the top (`llvm.fshr`). `count` is
    ## taken modulo 32, so a negative count rotates left.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert(((1 as int)).rotate_right(1) == ((1 as int)).rotate_left(31), "the bottom bit to the top");
    rotate_right(count: int): int {
        return unsafe_cast<int>(_rotate_right_32(this, this, (count & 31) as uint));
    }

    ## Returns the smaller of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not greater than `other`, else `other`
    ## @example
    ##     assert((3 as int).min(5) == 3, "smaller");
    min(other: int): int {
        return this <= other ? this : other;
    }

    ## Returns the larger of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not less than `other`, else `other`
    ## @example
    ##     assert((3 as int).max(5) == 5, "larger");
    max(other: int): int {
        return this >= other ? this : other;
    }

    ## Returns the absolute value: `this` without its sign. The lowest
    ## value, -2147483648, has no positive counterpart in a `int`, so it panics, as
    ## its negation does.
    ##
    ## @returns `-this` when this value is negative, else `this`
    ## @panics if this value is -2147483648 ("integer overflow in 'int' absolute value")
    ## @example
    ##     assert((-5 as int).abs() == 5, "negative");
    abs(location: __ptr<char> = __caller_location()): int {
        if (this >= 0) {
            return this;
        }
        if (this == -2147483647 - 1) {
            panic("integer overflow in 'int' absolute value", location);
        }
        return -this;
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
            return Optional<uint>.Empty;
        }
        return Optional<uint>.Value(value as uint);
    }

    ## Returns `this + other` modulo 2^32: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to add
    ## @returns the sum, wrapped to a `uint`
    wrapping_add(other: uint): uint {
        return __wrapping_add(this, other) as uint;
    }

    ## Returns `this + other`, or none when the sum does not fit a
    ## `uint`.
    ##
    ## @param other the value to add
    ## @returns the sum, or none on overflow
    checked_add(other: uint): uint? {
        if (__add_overflows(this, other)) {
            return Optional<uint>.Empty;
        }
        return Optional<uint>.Value(__wrapping_add(this, other) as uint);
    }

    ## Returns `this + other`, clamped to the highest `uint` on overflow.
    ##
    ## @param other the value to add
    ## @returns the sum, or the nearest `uint` to it
    saturating_add(other: uint): uint {
        if (!__add_overflows(this, other)) {
            return __wrapping_add(this, other) as uint;
        }
        return 4294967295;
    }

    ## Returns `this + other` modulo 2^32, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to add
    ## @returns the wrapped sum, and true when it overflowed
    overflowing_add(other: uint): (uint, bool) {
        return (__wrapping_add(this, other) as uint, __add_overflows(this, other));
    }

    ## Returns `this - other` modulo 2^32: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to subtract
    ## @returns the difference, wrapped to a `uint`
    wrapping_sub(other: uint): uint {
        return __wrapping_sub(this, other) as uint;
    }

    ## Returns `this - other`, or none when the difference does not fit a
    ## `uint`.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or none on overflow
    checked_sub(other: uint): uint? {
        if (__sub_overflows(this, other)) {
            return Optional<uint>.Empty;
        }
        return Optional<uint>.Value(__wrapping_sub(this, other) as uint);
    }

    ## Returns `this - other`, clamped to 0 on overflow.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or the nearest `uint` to it
    saturating_sub(other: uint): uint {
        if (!__sub_overflows(this, other)) {
            return __wrapping_sub(this, other) as uint;
        }
        return 0;
    }

    ## Returns `this - other` modulo 2^32, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to subtract
    ## @returns the wrapped difference, and true when it overflowed
    overflowing_sub(other: uint): (uint, bool) {
        return (__wrapping_sub(this, other) as uint, __sub_overflows(this, other));
    }

    ## Returns `this * other` modulo 2^32: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to multiply by
    ## @returns the product, wrapped to a `uint`
    wrapping_mul(other: uint): uint {
        return __wrapping_mul(this, other) as uint;
    }

    ## Returns `this * other`, or none when the product does not fit a
    ## `uint`.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or none on overflow
    checked_mul(other: uint): uint? {
        if (__mul_overflows(this, other)) {
            return Optional<uint>.Empty;
        }
        return Optional<uint>.Value(__wrapping_mul(this, other) as uint);
    }

    ## Returns `this * other`, clamped to the highest `uint` on overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or the nearest `uint` to it
    saturating_mul(other: uint): uint {
        if (!__mul_overflows(this, other)) {
            return __wrapping_mul(this, other) as uint;
        }
        return 4294967295;
    }

    ## Returns `this * other` modulo 2^32, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to multiply by
    ## @returns the wrapped product, and true when it overflowed
    overflowing_mul(other: uint): (uint, bool) {
        return (__wrapping_mul(this, other) as uint, __mul_overflows(this, other));
    }

    ## Returns the number of zero bits above the highest set bit: 32 for
    ## zero, 0 when the highest bit is set. One instruction on most CPUs
    ## (`llvm.ctlz`).
    ##
    ## @returns the count of leading zero bits, from 0 to 32
    ## @example
    ##     assert(((1 as uint)).leading_zeros() == 31, "one bit, at the bottom");
    leading_zeros(): int {
        return _leading_zeros_32(this, false) as int;
    }

    ## Returns the number of zero bits below the lowest set bit: 32 for
    ## zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
    ## first set bit of a mask without a loop.
    ##
    ## @returns the count of trailing zero bits, from 0 to 32
    ## @example
    ##     assert((8 as uint).trailing_zeros() == 3, "8 is 0b1000");
    trailing_zeros(): int {
        return _trailing_zeros_32(this, false) as int;
    }

    ## Returns the number of bits that are set (the population count,
    ## `llvm.ctpop`).
    ##
    ## @returns the count of one bits, from 0 to 32
    ## @example
    ##     assert((11 as uint).count_ones() == 3, "three bits set");
    count_ones(): int {
        return _count_ones_32(this) as int;
    }

    ## Returns the number of bits that are clear.
    ##
    ## @returns the count of zero bits, from 0 to 32
    ## @example
    ##     assert((11 as uint).count_zeros() == 29, "three bits set");
    count_zeros(): int {
        return 32 - _count_ones_32(this) as int;
    }

    ## Returns this value with its bytes in reverse order (`llvm.bswap`), to
    ## convert between little-endian and big-endian byte order.
    ##
    ## @returns the value with its 4 bytes reversed
    ## @example
    ##     assert((0x12345678 as uint).swap_bytes() == 0x78563412, "bytes reversed");
    swap_bytes(): uint {
        return _swap_bytes_32(this);
    }

    ## Returns this value with its bits in reverse order: the lowest bit
    ## becomes the highest (`llvm.bitreverse`).
    ##
    ## @returns the value with its 32 bits reversed
    ## @example
    ##     assert(((1 as uint)).reverse_bits().leading_zeros() == 0, "bottom to top");
    reverse_bits(): uint {
        return _reverse_bits_32(this);
    }

    ## Returns this value's bits rotated left by `count`: the bits shifted
    ## out at the top come back in at the bottom (`llvm.fshl`). `count` is
    ## taken modulo 32, so a negative count rotates right.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert((9 as uint).rotate_left(31) == (9 as uint).rotate_right(1), "the same rotation");
    rotate_left(count: int): uint {
        return _rotate_left_32(this, this, (count & 31) as uint);
    }

    ## Returns this value's bits rotated right by `count`: the bits shifted
    ## out at the bottom come back in at the top (`llvm.fshr`). `count` is
    ## taken modulo 32, so a negative count rotates left.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert(((1 as uint)).rotate_right(1) == ((1 as uint)).rotate_left(31), "the bottom bit to the top");
    rotate_right(count: int): uint {
        return _rotate_right_32(this, this, (count & 31) as uint);
    }

    ## Returns the smaller of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not greater than `other`, else `other`
    ## @example
    ##     assert((3 as uint).min(5) == 3, "smaller");
    min(other: uint): uint {
        return this <= other ? this : other;
    }

    ## Returns the larger of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not less than `other`, else `other`
    ## @example
    ##     assert((3 as uint).max(5) == 5, "larger");
    max(other: uint): uint {
        return this >= other ? this : other;
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
    ##     assert(long.parse("9223372036854775808").is_empty(), "too big");
    static parse(text: String, base: int = 10): long? {
        var (ok, value) = _parse_signed(text, base, 0x8000000000000000, 9223372036854775807);
        if (!ok) {
            return Optional<long>.Empty;
        }
        return Optional<long>.Value(value);
    }

    ## Returns `this + other` modulo 2^64: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to add
    ## @returns the sum, wrapped to a `long`
    wrapping_add(other: long): long {
        return __wrapping_add(this, other) as long;
    }

    ## Returns `this + other`, or none when the sum does not fit a
    ## `long`.
    ##
    ## @param other the value to add
    ## @returns the sum, or none on overflow
    checked_add(other: long): long? {
        if (__add_overflows(this, other)) {
            return Optional<long>.Empty;
        }
        return Optional<long>.Value(__wrapping_add(this, other) as long);
    }

    ## Returns `this + other`, clamped to the highest or lowest `long` on overflow.
    ##
    ## @param other the value to add
    ## @returns the sum, or the nearest `long` to it
    saturating_add(other: long): long {
        if (!__add_overflows(this, other)) {
            return __wrapping_add(this, other) as long;
        }
        return other > 0 ? 9223372036854775807 : (-9223372036854775807 - 1);
    }

    ## Returns `this + other` modulo 2^64, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to add
    ## @returns the wrapped sum, and true when it overflowed
    overflowing_add(other: long): (long, bool) {
        return (__wrapping_add(this, other) as long, __add_overflows(this, other));
    }

    ## Returns `this - other` modulo 2^64: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to subtract
    ## @returns the difference, wrapped to a `long`
    wrapping_sub(other: long): long {
        return __wrapping_sub(this, other) as long;
    }

    ## Returns `this - other`, or none when the difference does not fit a
    ## `long`.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or none on overflow
    checked_sub(other: long): long? {
        if (__sub_overflows(this, other)) {
            return Optional<long>.Empty;
        }
        return Optional<long>.Value(__wrapping_sub(this, other) as long);
    }

    ## Returns `this - other`, clamped to the highest or lowest `long` on overflow.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or the nearest `long` to it
    saturating_sub(other: long): long {
        if (!__sub_overflows(this, other)) {
            return __wrapping_sub(this, other) as long;
        }
        return other < 0 ? 9223372036854775807 : (-9223372036854775807 - 1);
    }

    ## Returns `this - other` modulo 2^64, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to subtract
    ## @returns the wrapped difference, and true when it overflowed
    overflowing_sub(other: long): (long, bool) {
        return (__wrapping_sub(this, other) as long, __sub_overflows(this, other));
    }

    ## Returns `this * other` modulo 2^64: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to multiply by
    ## @returns the product, wrapped to a `long`
    wrapping_mul(other: long): long {
        return __wrapping_mul(this, other) as long;
    }

    ## Returns `this * other`, or none when the product does not fit a
    ## `long`.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or none on overflow
    checked_mul(other: long): long? {
        if (__mul_overflows(this, other)) {
            return Optional<long>.Empty;
        }
        return Optional<long>.Value(__wrapping_mul(this, other) as long);
    }

    ## Returns `this * other`, clamped to the highest or lowest `long` on overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or the nearest `long` to it
    saturating_mul(other: long): long {
        if (!__mul_overflows(this, other)) {
            return __wrapping_mul(this, other) as long;
        }
        return (this < 0) == (other < 0) ? 9223372036854775807 : (-9223372036854775807 - 1);
    }

    ## Returns `this * other` modulo 2^64, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to multiply by
    ## @returns the wrapped product, and true when it overflowed
    overflowing_mul(other: long): (long, bool) {
        return (__wrapping_mul(this, other) as long, __mul_overflows(this, other));
    }

    ## Returns the number of zero bits above the highest set bit: 64 for
    ## zero, 0 when the highest bit is set. One instruction on most CPUs
    ## (`llvm.ctlz`).
    ##
    ## @returns the count of leading zero bits, from 0 to 64
    ## @example
    ##     assert(((1 as long)).leading_zeros() == 63, "one bit, at the bottom");
    leading_zeros(): int {
        return _leading_zeros_64(this, false) as int;
    }

    ## Returns the number of zero bits below the lowest set bit: 64 for
    ## zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
    ## first set bit of a mask without a loop.
    ##
    ## @returns the count of trailing zero bits, from 0 to 64
    ## @example
    ##     assert((8 as long).trailing_zeros() == 3, "8 is 0b1000");
    trailing_zeros(): int {
        return _trailing_zeros_64(this, false) as int;
    }

    ## Returns the number of bits that are set (the population count,
    ## `llvm.ctpop`).
    ##
    ## @returns the count of one bits, from 0 to 64
    ## @example
    ##     assert((11 as long).count_ones() == 3, "three bits set");
    count_ones(): int {
        return _count_ones_64(this) as int;
    }

    ## Returns the number of bits that are clear.
    ##
    ## @returns the count of zero bits, from 0 to 64
    ## @example
    ##     assert((11 as long).count_zeros() == 61, "three bits set");
    count_zeros(): int {
        return 64 - _count_ones_64(this) as int;
    }

    ## Returns this value with its bytes in reverse order (`llvm.bswap`), to
    ## convert between little-endian and big-endian byte order.
    ##
    ## @returns the value with its 8 bytes reversed
    ## @example
    ##     assert((0x0102030405060708 as long).swap_bytes() == 0x0807060504030201, "bytes reversed");
    swap_bytes(): long {
        return unsafe_cast<long>(_swap_bytes_64(this));
    }

    ## Returns this value with its bits in reverse order: the lowest bit
    ## becomes the highest (`llvm.bitreverse`).
    ##
    ## @returns the value with its 64 bits reversed
    ## @example
    ##     assert(((1 as long)).reverse_bits().leading_zeros() == 0, "bottom to top");
    reverse_bits(): long {
        return unsafe_cast<long>(_reverse_bits_64(this));
    }

    ## Returns this value's bits rotated left by `count`: the bits shifted
    ## out at the top come back in at the bottom (`llvm.fshl`). `count` is
    ## taken modulo 64, so a negative count rotates right.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert((9 as long).rotate_left(63) == (9 as long).rotate_right(1), "the same rotation");
    rotate_left(count: int): long {
        return unsafe_cast<long>(_rotate_left_64(this, this, (count & 63) as ulong));
    }

    ## Returns this value's bits rotated right by `count`: the bits shifted
    ## out at the bottom come back in at the top (`llvm.fshr`). `count` is
    ## taken modulo 64, so a negative count rotates left.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert(((1 as long)).rotate_right(1) == ((1 as long)).rotate_left(63), "the bottom bit to the top");
    rotate_right(count: int): long {
        return unsafe_cast<long>(_rotate_right_64(this, this, (count & 63) as ulong));
    }

    ## Returns the smaller of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not greater than `other`, else `other`
    ## @example
    ##     assert((3 as long).min(5) == 3, "smaller");
    min(other: long): long {
        return this <= other ? this : other;
    }

    ## Returns the larger of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not less than `other`, else `other`
    ## @example
    ##     assert((3 as long).max(5) == 5, "larger");
    max(other: long): long {
        return this >= other ? this : other;
    }

    ## Returns the absolute value: `this` without its sign. The lowest
    ## value, -9223372036854775808, has no positive counterpart in a `long`, so it panics, as
    ## its negation does.
    ##
    ## @returns `-this` when this value is negative, else `this`
    ## @panics if this value is -9223372036854775808 ("integer overflow in 'long' absolute value")
    ## @example
    ##     assert((-5 as long).abs() == 5, "negative");
    abs(location: __ptr<char> = __caller_location()): long {
        if (this >= 0) {
            return this;
        }
        if (this == -9223372036854775807 - 1) {
            panic("integer overflow in 'long' absolute value", location);
        }
        return -this;
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
    ##     assert(ulong.parse("ffffffffffffffff", 16).is_value(), "the highest");
    static parse(text: String, base: int = 10): ulong? {
        var (ok, value) = _parse_unsigned(text, base, 0xFFFFFFFFFFFFFFFF);
        if (!ok) {
            return Optional<ulong>.Empty;
        }
        return Optional<ulong>.Value(value);
    }

    ## Returns `this + other` modulo 2^64: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to add
    ## @returns the sum, wrapped to a `ulong`
    wrapping_add(other: ulong): ulong {
        return __wrapping_add(this, other) as ulong;
    }

    ## Returns `this + other`, or none when the sum does not fit a
    ## `ulong`.
    ##
    ## @param other the value to add
    ## @returns the sum, or none on overflow
    checked_add(other: ulong): ulong? {
        if (__add_overflows(this, other)) {
            return Optional<ulong>.Empty;
        }
        return Optional<ulong>.Value(__wrapping_add(this, other) as ulong);
    }

    ## Returns `this + other`, clamped to the highest `ulong` on overflow.
    ##
    ## @param other the value to add
    ## @returns the sum, or the nearest `ulong` to it
    saturating_add(other: ulong): ulong {
        if (!__add_overflows(this, other)) {
            return __wrapping_add(this, other) as ulong;
        }
        return 0xFFFFFFFFFFFFFFFF;
    }

    ## Returns `this + other` modulo 2^64, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to add
    ## @returns the wrapped sum, and true when it overflowed
    overflowing_add(other: ulong): (ulong, bool) {
        return (__wrapping_add(this, other) as ulong, __add_overflows(this, other));
    }

    ## Returns `this - other` modulo 2^64: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to subtract
    ## @returns the difference, wrapped to a `ulong`
    wrapping_sub(other: ulong): ulong {
        return __wrapping_sub(this, other) as ulong;
    }

    ## Returns `this - other`, or none when the difference does not fit a
    ## `ulong`.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or none on overflow
    checked_sub(other: ulong): ulong? {
        if (__sub_overflows(this, other)) {
            return Optional<ulong>.Empty;
        }
        return Optional<ulong>.Value(__wrapping_sub(this, other) as ulong);
    }

    ## Returns `this - other`, clamped to 0 on overflow.
    ##
    ## @param other the value to subtract
    ## @returns the difference, or the nearest `ulong` to it
    saturating_sub(other: ulong): ulong {
        if (!__sub_overflows(this, other)) {
            return __wrapping_sub(this, other) as ulong;
        }
        return 0;
    }

    ## Returns `this - other` modulo 2^64, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to subtract
    ## @returns the wrapped difference, and true when it overflowed
    overflowing_sub(other: ulong): (ulong, bool) {
        return (__wrapping_sub(this, other) as ulong, __sub_overflows(this, other));
    }

    ## Returns `this * other` modulo 2^64: on overflow the result wraps
    ## around instead of panicking. For hashes, checksums and random number
    ## generators, which rely on wrapping.
    ##
    ## @param other the value to multiply by
    ## @returns the product, wrapped to a `ulong`
    wrapping_mul(other: ulong): ulong {
        return __wrapping_mul(this, other) as ulong;
    }

    ## Returns `this * other`, or none when the product does not fit a
    ## `ulong`.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or none on overflow
    checked_mul(other: ulong): ulong? {
        if (__mul_overflows(this, other)) {
            return Optional<ulong>.Empty;
        }
        return Optional<ulong>.Value(__wrapping_mul(this, other) as ulong);
    }

    ## Returns `this * other`, clamped to the highest `ulong` on overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the product, or the nearest `ulong` to it
    saturating_mul(other: ulong): ulong {
        if (!__mul_overflows(this, other)) {
            return __wrapping_mul(this, other) as ulong;
        }
        return 0xFFFFFFFFFFFFFFFF;
    }

    ## Returns `this * other` modulo 2^64, and whether the operation
    ## overflowed.
    ##
    ## @param other the value to multiply by
    ## @returns the wrapped product, and true when it overflowed
    overflowing_mul(other: ulong): (ulong, bool) {
        return (__wrapping_mul(this, other) as ulong, __mul_overflows(this, other));
    }

    ## Returns the number of zero bits above the highest set bit: 64 for
    ## zero, 0 when the highest bit is set. One instruction on most CPUs
    ## (`llvm.ctlz`).
    ##
    ## @returns the count of leading zero bits, from 0 to 64
    ## @example
    ##     assert(((1 as ulong)).leading_zeros() == 63, "one bit, at the bottom");
    leading_zeros(): int {
        return _leading_zeros_64(this, false) as int;
    }

    ## Returns the number of zero bits below the lowest set bit: 64 for
    ## zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
    ## first set bit of a mask without a loop.
    ##
    ## @returns the count of trailing zero bits, from 0 to 64
    ## @example
    ##     assert((8 as ulong).trailing_zeros() == 3, "8 is 0b1000");
    trailing_zeros(): int {
        return _trailing_zeros_64(this, false) as int;
    }

    ## Returns the number of bits that are set (the population count,
    ## `llvm.ctpop`).
    ##
    ## @returns the count of one bits, from 0 to 64
    ## @example
    ##     assert((11 as ulong).count_ones() == 3, "three bits set");
    count_ones(): int {
        return _count_ones_64(this) as int;
    }

    ## Returns the number of bits that are clear.
    ##
    ## @returns the count of zero bits, from 0 to 64
    ## @example
    ##     assert((11 as ulong).count_zeros() == 61, "three bits set");
    count_zeros(): int {
        return 64 - _count_ones_64(this) as int;
    }

    ## Returns this value with its bytes in reverse order (`llvm.bswap`), to
    ## convert between little-endian and big-endian byte order.
    ##
    ## @returns the value with its 8 bytes reversed
    ## @example
    ##     assert((0x0102030405060708 as ulong).swap_bytes() == 0x0807060504030201, "bytes reversed");
    swap_bytes(): ulong {
        return _swap_bytes_64(this);
    }

    ## Returns this value with its bits in reverse order: the lowest bit
    ## becomes the highest (`llvm.bitreverse`).
    ##
    ## @returns the value with its 64 bits reversed
    ## @example
    ##     assert(((1 as ulong)).reverse_bits().leading_zeros() == 0, "bottom to top");
    reverse_bits(): ulong {
        return _reverse_bits_64(this);
    }

    ## Returns this value's bits rotated left by `count`: the bits shifted
    ## out at the top come back in at the bottom (`llvm.fshl`). `count` is
    ## taken modulo 64, so a negative count rotates right.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert((9 as ulong).rotate_left(63) == (9 as ulong).rotate_right(1), "the same rotation");
    rotate_left(count: int): ulong {
        return _rotate_left_64(this, this, (count & 63) as ulong);
    }

    ## Returns this value's bits rotated right by `count`: the bits shifted
    ## out at the bottom come back in at the top (`llvm.fshr`). `count` is
    ## taken modulo 64, so a negative count rotates left.
    ##
    ## @param count how many places to rotate
    ## @returns the rotated value
    ## @example
    ##     assert(((1 as ulong)).rotate_right(1) == ((1 as ulong)).rotate_left(63), "the bottom bit to the top");
    rotate_right(count: int): ulong {
        return _rotate_right_64(this, this, (count & 63) as ulong);
    }

    ## Returns the smaller of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not greater than `other`, else `other`
    ## @example
    ##     assert((3 as ulong).min(5) == 3, "smaller");
    min(other: ulong): ulong {
        return this <= other ? this : other;
    }

    ## Returns the larger of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns `this` when it is not less than `other`, else `other`
    ## @example
    ##     assert((3 as ulong).max(5) == 5, "larger");
    max(other: ulong): ulong {
        return this >= other ? this : other;
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
    ##     assert(float.parse("1e39").is_empty(), "too big");
    static parse(text: String): float? {
        if (!_is_decimal(text)) {
            return Optional<float>.Empty;
        }
        var value = strtof(text.c_str(), __null);
        # An infinity minus itself is NaN, not zero: the value overflowed.
        if (value - value != 0) {
            return Optional<float>.Empty;
        }
        return Optional<float>.Value(value);
    }

    ## Returns the square root (`llvm.sqrt`, one instruction on most CPUs):
    ## NaN for a negative value, and `-0.0` for `-0.0`.
    ##
    ## @returns the non-negative square root
    ## @example
    ##     assert((2.25 as float).square_root() == 1.5, "exact");
    square_root(): float {
        return _square_root_32(this);
    }

    ## Returns the largest whole number not greater than this value
    ## (`llvm.floor`).
    ##
    ## @returns the value rounded toward negative infinity
    ## @example
    ##     assert((-1.5 as float).floor() == -2.0, "down");
    floor(): float {
        return _floor_32(this);
    }

    ## Returns the smallest whole number not less than this value
    ## (`llvm.ceil`).
    ##
    ## @returns the value rounded toward positive infinity
    ## @example
    ##     assert((-1.5 as float).ceiling() == -1.0, "up");
    ceiling(): float {
        return _ceiling_32(this);
    }

    ## Returns this value without its fractional part (`llvm.trunc`).
    ##
    ## @returns the value rounded toward zero
    ## @example
    ##     assert((-1.5 as float).truncate() == -1.0, "toward zero");
    truncate(): float {
        return _truncate_32(this);
    }

    ## Returns the nearest whole number, halfway cases away from zero
    ## (`llvm.round`).
    ##
    ## @returns the rounded value
    ## @example
    ##     assert((2.5 as float).round() == 3.0, "half away from zero");
    round(): float {
        return _round_32(this);
    }

    ## Returns the absolute value: this value with its sign bit cleared
    ## (`llvm.fabs`).
    ##
    ## @returns the value without its sign
    ## @example
    ##     assert((-2.0 as float).abs() == 2.0, "negative");
    abs(): float {
        return _abs_32(this);
    }

    ## Returns this value's magnitude with the sign of `sign`
    ## (`llvm.copysign`).
    ##
    ## @param sign the value whose sign the result takes
    ## @returns `abs()` of this value, negated when `sign` is negative
    ## @example
    ##     assert((3.0 as float).copy_sign(-0.0) == -3.0, "negative zero is negative");
    copy_sign(sign: float): float {
        return _copy_sign_32(this, sign);
    }

    ## Returns `this * factor + addend` with a single rounding, as one fused
    ## multiply-add (`llvm.fma`): more precise than the two operations, and
    ## one instruction where the CPU has it.
    ##
    ## @param factor the value to multiply by
    ## @param addend the value to add to the product
    ## @returns the fused product and sum
    ## @example
    ##     assert((2.0 as float).multiply_add(3.0, 1.0) == 7.0, "2 * 3 + 1");
    multiply_add(factor: float, addend: float): float {
        return _multiply_add_32(this, factor, addend);
    }

    ## Returns the smaller of this value and `other`; when one of them is
    ## NaN, the other (`llvm.minnum`).
    ##
    ## @param other the value to compare with
    ## @returns the smaller value
    ## @example
    ##     assert((1.5 as float).min(-2.0) == -2.0, "smaller");
    min(other: float): float {
        return _min_32(this, other);
    }

    ## Returns the larger of this value and `other`; when one of them is
    ## NaN, the other (`llvm.maxnum`).
    ##
    ## @param other the value to compare with
    ## @returns the larger value
    ## @example
    ##     assert((1.5 as float).max(-2.0) == 1.5, "larger");
    max(other: float): float {
        return _max_32(this, other);
    }

    ## Returns the sine of this angle, in radians (`llvm.sin`).
    ##
    ## @returns the sine, from -1 to 1; NaN for an infinity or NaN
    ## @example
    ##     assert((0.0 as float).sine() == 0.0, "sine of zero");
    sine(): float {
        return _sine_32(this);
    }

    ## Returns the cosine of this angle, in radians (`llvm.cos`).
    ##
    ## @returns the cosine, from -1 to 1; NaN for an infinity or NaN
    ## @example
    ##     assert((0.0 as float).cosine() == 1.0, "cosine of zero");
    cosine(): float {
        return _cosine_32(this);
    }

    ## Returns the tangent of this angle, in radians (`llvm.tan`).
    ##
    ## @returns the tangent; NaN for an infinity or NaN
    ## @example
    ##     assert((0.0 as float).tangent() == 0.0, "tangent of zero");
    tangent(): float {
        return _tangent_32(this);
    }

    ## Returns the angle, in radians, whose sine is this value (`llvm.asin`).
    ##
    ## @returns the angle, from -π/2 to π/2; NaN when this value is outside -1 to 1
    ## @example
    ##     assert((0.0 as float).arc_sine() == 0.0, "arc sine of zero");
    arc_sine(): float {
        return _arc_sine_32(this);
    }

    ## Returns the angle, in radians, whose cosine is this value (`llvm.acos`).
    ##
    ## @returns the angle, from 0 to π; NaN when this value is outside -1 to 1
    ## @example
    ##     assert((1.0 as float).arc_cosine() == 0.0, "arc cosine of one");
    arc_cosine(): float {
        return _arc_cosine_32(this);
    }

    ## Returns the angle, in radians, whose tangent is this value (`llvm.atan`).
    ##
    ## @returns the angle, from -π/2 to π/2
    ## @example
    ##     assert((0.0 as float).arc_tangent() == 0.0, "arc tangent of zero");
    arc_tangent(): float {
        return _arc_tangent_32(this);
    }

    ## Returns the angle, in radians, from the positive x axis to the point
    ## (`x`, this value), using both signs to pick the quadrant: C's
    ## `atan2(y, x)` with this value as `y` (`llvm.atan2`).
    ##
    ## @param x the x coordinate of the point
    ## @returns the angle, from -π to π
    ## @example
    ##     assert((0.0 as float).arc_tangent2(1.0) == 0.0, "along the positive x axis");
    ##     assert((1.0 as float).arc_tangent2(0.0) == (1.0 as float).arc_sine(), "straight up is π/2");
    arc_tangent2(x: float): float {
        return _arc_tangent2_32(this, x);
    }

    ## Returns the hyperbolic sine of this value (`llvm.sinh`).
    ##
    ## @returns the hyperbolic sine; an infinity when it is too large
    ## @example
    ##     assert((0.0 as float).hyperbolic_sine() == 0.0, "hyperbolic sine of zero");
    hyperbolic_sine(): float {
        return _hyperbolic_sine_32(this);
    }

    ## Returns the hyperbolic cosine of this value (`llvm.cosh`).
    ##
    ## @returns the hyperbolic cosine, at least 1; an infinity when it is too large
    ## @example
    ##     assert((0.0 as float).hyperbolic_cosine() == 1.0, "hyperbolic cosine of zero");
    hyperbolic_cosine(): float {
        return _hyperbolic_cosine_32(this);
    }

    ## Returns the hyperbolic tangent of this value (`llvm.tanh`).
    ##
    ## @returns the hyperbolic tangent, from -1 to 1
    ## @example
    ##     assert((0.0 as float).hyperbolic_tangent() == 0.0, "hyperbolic tangent of zero");
    hyperbolic_tangent(): float {
        return _hyperbolic_tangent_32(this);
    }

    ## Returns the value whose hyperbolic sine is this value (C's `asinh`).
    ##
    ## @returns the inverse hyperbolic sine
    ## @example
    ##     assert((0.0 as float).arc_hyperbolic_sine() == 0.0, "inverse of zero");
    arc_hyperbolic_sine(): float {
        return _arc_hyperbolic_sine_32(this);
    }

    ## Returns the non-negative value whose hyperbolic cosine is this value
    ## (C's `acosh`).
    ##
    ## @returns the inverse hyperbolic cosine; NaN when this value is less than 1
    ## @example
    ##     assert((1.0 as float).arc_hyperbolic_cosine() == 0.0, "inverse of one");
    arc_hyperbolic_cosine(): float {
        return _arc_hyperbolic_cosine_32(this);
    }

    ## Returns the value whose hyperbolic tangent is this value (C's `atanh`).
    ##
    ## @returns the inverse hyperbolic tangent; an infinity for -1 or 1, and NaN outside
    ## @example
    ##     assert((0.0 as float).arc_hyperbolic_tangent() == 0.0, "inverse of zero");
    arc_hyperbolic_tangent(): float {
        return _arc_hyperbolic_tangent_32(this);
    }

    ## Returns *e* raised to this value (`llvm.exp`).
    ##
    ## @returns *e* to the power of this value; an infinity when it is too large
    ## @example
    ##     assert((0.0 as float).exponential() == 1.0, "e to the zero");
    exponential(): float {
        return _exponential_32(this);
    }

    ## Returns 2 raised to this value (`llvm.exp2`).
    ##
    ## @returns 2 to the power of this value
    ## @example
    ##     assert((3.0 as float).exponential2() == 8.0, "2 cubed");
    exponential2(): float {
        return _exponential2_32(this);
    }

    ## Returns *e* raised to this value, minus 1 (C's `expm1`): precise even
    ## when this value is near zero, where `exponential() - 1` loses its digits.
    ##
    ## @returns `exponential() - 1`, computed without the loss
    ## @example
    ##     assert((0.0 as float).exponential_minus_one() == 0.0, "e to the zero, minus one");
    exponential_minus_one(): float {
        return _exponential_minus_one_32(this);
    }

    ## Returns the natural logarithm (base *e*) of this value (`llvm.log`).
    ##
    ## @returns the logarithm; negative infinity for zero, and NaN for a negative value
    ## @example
    ##     assert((1.0 as float).logarithm() == 0.0, "log of one");
    logarithm(): float {
        return _logarithm_32(this);
    }

    ## Returns the base-2 logarithm of this value (`llvm.log2`).
    ##
    ## @returns the logarithm; negative infinity for zero, and NaN for a negative value
    ## @example
    ##     assert((8.0 as float).logarithm2() == 3.0, "2 cubed is 8");
    logarithm2(): float {
        return _logarithm2_32(this);
    }

    ## Returns the base-10 logarithm of this value (`llvm.log10`).
    ##
    ## @returns the logarithm; negative infinity for zero, and NaN for a negative value
    ## @example
    ##     assert((1000.0 as float).logarithm10() == 3.0, "10 cubed is 1000");
    logarithm10(): float {
        return _logarithm10_32(this);
    }

    ## Returns the natural logarithm of 1 plus this value (C's `log1p`):
    ## precise even when this value is near zero, where `(1 + x).logarithm()`
    ## loses its digits.
    ##
    ## @returns the logarithm of `1 + this`; negative infinity for -1, and NaN below it
    ## @example
    ##     assert((0.0 as float).logarithm_one_plus() == 0.0, "log of one");
    logarithm_one_plus(): float {
        return _logarithm_one_plus_32(this);
    }

    ## Returns the cube root (C's `cbrt`), negative for a negative value.
    ##
    ## @returns the cube root
    ## @example
    ##     assert((-27.0 as float).cube_root() == -3.0, "a negative value has a cube root");
    cube_root(): float {
        return _cube_root_32(this);
    }

    ## Returns `(this * this + other * other).square_root()`, the length of
    ## the hypotenuse of a right triangle with sides this value and `other`
    ## (C's `hypot`), without overflowing or underflowing in between.
    ##
    ## @param other the length of the other side
    ## @returns the distance from the origin to (this, `other`)
    ## @example
    ##     assert((3.0 as float).hypotenuse(4.0) == 5.0, "a 3-4-5 triangle");
    hypotenuse(other: float): float {
        return _hypotenuse_32(this, other);
    }

    ## Returns the IEEE remainder of this value divided by `divisor` (C's
    ## `remainder`): `this - n * divisor`, where `n` is the quotient rounded to
    ## the nearest whole number, ties to even. It is never larger than half of
    ## `divisor`, and may be negative. `%` gives the remainder of the quotient
    ## rounded toward zero instead, with the sign of this value.
    ##
    ## @param divisor the value to divide by
    ## @returns the remainder; NaN when `divisor` is zero or this value is infinite
    ## @example
    ##     assert((7.0 as float).remainder(2.0) == -1.0, "7 / 2 = 3.5 rounds to 4");
    ##     assert((7.0 as float) % 2.0 == 1.0, "% rounds toward zero");
    remainder(divisor: float): float {
        return _remainder_32(this, divisor);
    }

    ## Returns whether this value is NaN (not a number), the one value not
    ## equal to itself.
    ##
    ## @returns true for NaN
    ## @example
    ##     assert(!(1.0 as float).is_nan(), "a number");
    ##     assert(((0.0 as float) / 0.0).is_nan(), "zero over zero");
    is_nan(): bool {
        return this != this;
    }

    ## Returns whether this value is positive or negative infinity.
    ##
    ## @returns true for an infinity
    ## @example
    ##     assert(((1.0 as float) / 0.0).is_infinite(), "one over zero");
    is_infinite(): bool {
        return !is_nan() && !is_finite();
    }

    ## Returns whether this value is neither an infinity nor NaN.
    ##
    ## @returns true for every other value
    ## @example
    ##     assert((1.0 as float).is_finite() && !((1.0 as float) / 0.0).is_finite(), "finite and infinite");
    is_finite(): bool {
        # An infinity or NaN minus itself is NaN, not zero.
        return this - this == 0;
    }

    ## Returns whether this value's sign bit is set: true for every negative
    ## value, `-0.0`, and a NaN with its sign bit set, which `< 0` does not
    ## tell apart.
    ##
    ## @returns true when the sign bit is set
    ## @example
    ##     assert((-0.0 as float).sign_bit() && !(0.0 as float).sign_bit(), "negative zero");
    sign_bit(): bool {
        return _copy_sign_32(1.0, this) < 0;
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
    ##     assert(double.parse("1.5.2").is_empty(), "not a number");
    static parse(text: String): double? {
        if (!_is_decimal(text)) {
            return Optional<double>.Empty;
        }
        var value = _number_strtod(text);
        # An infinity minus itself is NaN, not zero: the value overflowed.
        if (value - value != 0) {
            return Optional<double>.Empty;
        }
        return Optional<double>.Value(value);
    }

    ## Returns the square root (`llvm.sqrt`, one instruction on most CPUs):
    ## NaN for a negative value, and `-0.0` for `-0.0`.
    ##
    ## @returns the non-negative square root
    ## @example
    ##     assert((2.25 as double).square_root() == 1.5, "exact");
    square_root(): double {
        return _square_root_64(this);
    }

    ## Returns the largest whole number not greater than this value
    ## (`llvm.floor`).
    ##
    ## @returns the value rounded toward negative infinity
    ## @example
    ##     assert((-1.5 as double).floor() == -2.0, "down");
    floor(): double {
        return _floor_64(this);
    }

    ## Returns the smallest whole number not less than this value
    ## (`llvm.ceil`).
    ##
    ## @returns the value rounded toward positive infinity
    ## @example
    ##     assert((-1.5 as double).ceiling() == -1.0, "up");
    ceiling(): double {
        return _ceiling_64(this);
    }

    ## Returns this value without its fractional part (`llvm.trunc`).
    ##
    ## @returns the value rounded toward zero
    ## @example
    ##     assert((-1.5 as double).truncate() == -1.0, "toward zero");
    truncate(): double {
        return _truncate_64(this);
    }

    ## Returns the nearest whole number, halfway cases away from zero
    ## (`llvm.round`).
    ##
    ## @returns the rounded value
    ## @example
    ##     assert((2.5 as double).round() == 3.0, "half away from zero");
    round(): double {
        return _round_64(this);
    }

    ## Returns the absolute value: this value with its sign bit cleared
    ## (`llvm.fabs`).
    ##
    ## @returns the value without its sign
    ## @example
    ##     assert((-2.0 as double).abs() == 2.0, "negative");
    abs(): double {
        return _abs_64(this);
    }

    ## Returns this value's magnitude with the sign of `sign`
    ## (`llvm.copysign`).
    ##
    ## @param sign the value whose sign the result takes
    ## @returns `abs()` of this value, negated when `sign` is negative
    ## @example
    ##     assert((3.0 as double).copy_sign(-0.0) == -3.0, "negative zero is negative");
    copy_sign(sign: double): double {
        return _copy_sign_64(this, sign);
    }

    ## Returns `this * factor + addend` with a single rounding, as one fused
    ## multiply-add (`llvm.fma`): more precise than the two operations, and
    ## one instruction where the CPU has it.
    ##
    ## @param factor the value to multiply by
    ## @param addend the value to add to the product
    ## @returns the fused product and sum
    ## @example
    ##     assert((2.0 as double).multiply_add(3.0, 1.0) == 7.0, "2 * 3 + 1");
    multiply_add(factor: double, addend: double): double {
        return _multiply_add_64(this, factor, addend);
    }

    ## Returns the smaller of this value and `other`; when one of them is
    ## NaN, the other (`llvm.minnum`).
    ##
    ## @param other the value to compare with
    ## @returns the smaller value
    ## @example
    ##     assert((1.5 as double).min(-2.0) == -2.0, "smaller");
    min(other: double): double {
        return _min_64(this, other);
    }

    ## Returns the larger of this value and `other`; when one of them is
    ## NaN, the other (`llvm.maxnum`).
    ##
    ## @param other the value to compare with
    ## @returns the larger value
    ## @example
    ##     assert((1.5 as double).max(-2.0) == 1.5, "larger");
    max(other: double): double {
        return _max_64(this, other);
    }

    ## Returns the sine of this angle, in radians (`llvm.sin`).
    ##
    ## @returns the sine, from -1 to 1; NaN for an infinity or NaN
    ## @example
    ##     assert((0.0 as double).sine() == 0.0, "sine of zero");
    sine(): double {
        return _sine_64(this);
    }

    ## Returns the cosine of this angle, in radians (`llvm.cos`).
    ##
    ## @returns the cosine, from -1 to 1; NaN for an infinity or NaN
    ## @example
    ##     assert((0.0 as double).cosine() == 1.0, "cosine of zero");
    cosine(): double {
        return _cosine_64(this);
    }

    ## Returns the tangent of this angle, in radians (`llvm.tan`).
    ##
    ## @returns the tangent; NaN for an infinity or NaN
    ## @example
    ##     assert((0.0 as double).tangent() == 0.0, "tangent of zero");
    tangent(): double {
        return _tangent_64(this);
    }

    ## Returns the angle, in radians, whose sine is this value (`llvm.asin`).
    ##
    ## @returns the angle, from -π/2 to π/2; NaN when this value is outside -1 to 1
    ## @example
    ##     assert((0.0 as double).arc_sine() == 0.0, "arc sine of zero");
    arc_sine(): double {
        return _arc_sine_64(this);
    }

    ## Returns the angle, in radians, whose cosine is this value (`llvm.acos`).
    ##
    ## @returns the angle, from 0 to π; NaN when this value is outside -1 to 1
    ## @example
    ##     assert((1.0 as double).arc_cosine() == 0.0, "arc cosine of one");
    arc_cosine(): double {
        return _arc_cosine_64(this);
    }

    ## Returns the angle, in radians, whose tangent is this value (`llvm.atan`).
    ##
    ## @returns the angle, from -π/2 to π/2
    ## @example
    ##     assert((0.0 as double).arc_tangent() == 0.0, "arc tangent of zero");
    arc_tangent(): double {
        return _arc_tangent_64(this);
    }

    ## Returns the angle, in radians, from the positive x axis to the point
    ## (`x`, this value), using both signs to pick the quadrant: C's
    ## `atan2(y, x)` with this value as `y` (`llvm.atan2`).
    ##
    ## @param x the x coordinate of the point
    ## @returns the angle, from -π to π
    ## @example
    ##     assert((0.0 as double).arc_tangent2(1.0) == 0.0, "along the positive x axis");
    ##     assert((1.0 as double).arc_tangent2(0.0) == (1.0 as double).arc_sine(), "straight up is π/2");
    arc_tangent2(x: double): double {
        return _arc_tangent2_64(this, x);
    }

    ## Returns the hyperbolic sine of this value (`llvm.sinh`).
    ##
    ## @returns the hyperbolic sine; an infinity when it is too large
    ## @example
    ##     assert((0.0 as double).hyperbolic_sine() == 0.0, "hyperbolic sine of zero");
    hyperbolic_sine(): double {
        return _hyperbolic_sine_64(this);
    }

    ## Returns the hyperbolic cosine of this value (`llvm.cosh`).
    ##
    ## @returns the hyperbolic cosine, at least 1; an infinity when it is too large
    ## @example
    ##     assert((0.0 as double).hyperbolic_cosine() == 1.0, "hyperbolic cosine of zero");
    hyperbolic_cosine(): double {
        return _hyperbolic_cosine_64(this);
    }

    ## Returns the hyperbolic tangent of this value (`llvm.tanh`).
    ##
    ## @returns the hyperbolic tangent, from -1 to 1
    ## @example
    ##     assert((0.0 as double).hyperbolic_tangent() == 0.0, "hyperbolic tangent of zero");
    hyperbolic_tangent(): double {
        return _hyperbolic_tangent_64(this);
    }

    ## Returns the value whose hyperbolic sine is this value (C's `asinh`).
    ##
    ## @returns the inverse hyperbolic sine
    ## @example
    ##     assert((0.0 as double).arc_hyperbolic_sine() == 0.0, "inverse of zero");
    arc_hyperbolic_sine(): double {
        return _arc_hyperbolic_sine_64(this);
    }

    ## Returns the non-negative value whose hyperbolic cosine is this value
    ## (C's `acosh`).
    ##
    ## @returns the inverse hyperbolic cosine; NaN when this value is less than 1
    ## @example
    ##     assert((1.0 as double).arc_hyperbolic_cosine() == 0.0, "inverse of one");
    arc_hyperbolic_cosine(): double {
        return _arc_hyperbolic_cosine_64(this);
    }

    ## Returns the value whose hyperbolic tangent is this value (C's `atanh`).
    ##
    ## @returns the inverse hyperbolic tangent; an infinity for -1 or 1, and NaN outside
    ## @example
    ##     assert((0.0 as double).arc_hyperbolic_tangent() == 0.0, "inverse of zero");
    arc_hyperbolic_tangent(): double {
        return _arc_hyperbolic_tangent_64(this);
    }

    ## Returns *e* raised to this value (`llvm.exp`).
    ##
    ## @returns *e* to the power of this value; an infinity when it is too large
    ## @example
    ##     assert((0.0 as double).exponential() == 1.0, "e to the zero");
    exponential(): double {
        return _exponential_64(this);
    }

    ## Returns 2 raised to this value (`llvm.exp2`).
    ##
    ## @returns 2 to the power of this value
    ## @example
    ##     assert((3.0 as double).exponential2() == 8.0, "2 cubed");
    exponential2(): double {
        return _exponential2_64(this);
    }

    ## Returns *e* raised to this value, minus 1 (C's `expm1`): precise even
    ## when this value is near zero, where `exponential() - 1` loses its digits.
    ##
    ## @returns `exponential() - 1`, computed without the loss
    ## @example
    ##     assert((0.0 as double).exponential_minus_one() == 0.0, "e to the zero, minus one");
    exponential_minus_one(): double {
        return _exponential_minus_one_64(this);
    }

    ## Returns the natural logarithm (base *e*) of this value (`llvm.log`).
    ##
    ## @returns the logarithm; negative infinity for zero, and NaN for a negative value
    ## @example
    ##     assert((1.0 as double).logarithm() == 0.0, "log of one");
    logarithm(): double {
        return _logarithm_64(this);
    }

    ## Returns the base-2 logarithm of this value (`llvm.log2`).
    ##
    ## @returns the logarithm; negative infinity for zero, and NaN for a negative value
    ## @example
    ##     assert((8.0 as double).logarithm2() == 3.0, "2 cubed is 8");
    logarithm2(): double {
        return _logarithm2_64(this);
    }

    ## Returns the base-10 logarithm of this value (`llvm.log10`).
    ##
    ## @returns the logarithm; negative infinity for zero, and NaN for a negative value
    ## @example
    ##     assert((1000.0 as double).logarithm10() == 3.0, "10 cubed is 1000");
    logarithm10(): double {
        return _logarithm10_64(this);
    }

    ## Returns the natural logarithm of 1 plus this value (C's `log1p`):
    ## precise even when this value is near zero, where `(1 + x).logarithm()`
    ## loses its digits.
    ##
    ## @returns the logarithm of `1 + this`; negative infinity for -1, and NaN below it
    ## @example
    ##     assert((0.0 as double).logarithm_one_plus() == 0.0, "log of one");
    logarithm_one_plus(): double {
        return _logarithm_one_plus_64(this);
    }

    ## Returns the cube root (C's `cbrt`), negative for a negative value.
    ##
    ## @returns the cube root
    ## @example
    ##     assert((-27.0 as double).cube_root() == -3.0, "a negative value has a cube root");
    cube_root(): double {
        return _cube_root_64(this);
    }

    ## Returns `(this * this + other * other).square_root()`, the length of
    ## the hypotenuse of a right triangle with sides this value and `other`
    ## (C's `hypot`), without overflowing or underflowing in between.
    ##
    ## @param other the length of the other side
    ## @returns the distance from the origin to (this, `other`)
    ## @example
    ##     assert((3.0 as double).hypotenuse(4.0) == 5.0, "a 3-4-5 triangle");
    hypotenuse(other: double): double {
        return _hypotenuse_64(this, other);
    }

    ## Returns the IEEE remainder of this value divided by `divisor` (C's
    ## `remainder`): `this - n * divisor`, where `n` is the quotient rounded to
    ## the nearest whole number, ties to even. It is never larger than half of
    ## `divisor`, and may be negative. `%` gives the remainder of the quotient
    ## rounded toward zero instead, with the sign of this value.
    ##
    ## @param divisor the value to divide by
    ## @returns the remainder; NaN when `divisor` is zero or this value is infinite
    ## @example
    ##     assert((7.0 as double).remainder(2.0) == -1.0, "7 / 2 = 3.5 rounds to 4");
    ##     assert((7.0 as double) % 2.0 == 1.0, "% rounds toward zero");
    remainder(divisor: double): double {
        return _remainder_64(this, divisor);
    }

    ## Returns whether this value is NaN (not a number), the one value not
    ## equal to itself.
    ##
    ## @returns true for NaN
    ## @example
    ##     assert(!(1.0 as double).is_nan(), "a number");
    ##     assert(((0.0 as double) / 0.0).is_nan(), "zero over zero");
    is_nan(): bool {
        return this != this;
    }

    ## Returns whether this value is positive or negative infinity.
    ##
    ## @returns true for an infinity
    ## @example
    ##     assert(((1.0 as double) / 0.0).is_infinite(), "one over zero");
    is_infinite(): bool {
        return !is_nan() && !is_finite();
    }

    ## Returns whether this value is neither an infinity nor NaN.
    ##
    ## @returns true for every other value
    ## @example
    ##     assert((1.0 as double).is_finite() && !((1.0 as double) / 0.0).is_finite(), "finite and infinite");
    is_finite(): bool {
        # An infinity or NaN minus itself is NaN, not zero.
        return this - this == 0;
    }

    ## Returns whether this value's sign bit is set: true for every negative
    ## value, `-0.0`, and a NaN with its sign bit set, which `< 0` does not
    ## tell apart.
    ##
    ## @returns true when the sign bit is set
    ## @example
    ##     assert((-0.0 as double).sign_bit() && !(0.0 as double).sign_bit(), "negative zero");
    sign_bit(): bool {
        return _copy_sign_64(1.0, this) < 0;
    }
}
