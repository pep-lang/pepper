# Corrects a decimal-to-double conversion to the nearest double, ties to
# even. The Windows C runtime's `strtod` is off by one unit in the last
# place for some inputs (`3.089261223363795e+16`, subnormals such as
# `2.205052981414646e-308`), so `double.parse` there checks its result:
# it compares the exact decimal value with the midpoints between the
# approximation and its neighbors, in big integers, and steps to the
# neighbor the decimal is closer to.

import "array";

# A non-negative big integer: 32-bit limbs, least significant first.
_float_big_from(value: ulong): ulong[] {
    var limbs = Array<ulong>();
    limbs.append(value & 0xffffffff);
    limbs.append(value >> 32);
    return limbs;
}

# Multiplies `limbs` by `factor`, which is below 2^32.
_float_big_multiply(limbs: ulong[], factor: ulong) {
    ulong carry = 0;
    ulong index = 0;
    var count = limbs.count;
    while (index < count) {
        var product = limbs[index] * factor + carry;
        limbs[index] = product & 0xffffffff;
        carry = product >> 32;
        index = index + 1;
    }
    if (carry != 0) {
        limbs.append(carry);
    }
}

# Adds `value`, which is below 2^32, to `limbs`.
_float_big_add(limbs: ulong[], value: ulong) {
    ulong carry = value;
    ulong index = 0;
    while (carry != 0 && index < limbs.count) {
        var sum = limbs[index] + carry;
        limbs[index] = sum & 0xffffffff;
        carry = sum >> 32;
        index = index + 1;
    }
    if (carry != 0) {
        limbs.append(carry);
    }
}

# Multiplies `limbs` by 10^`power`.
_float_big_multiply_pow10(limbs: ulong[], power: long) {
    while (power >= 9) {
        _float_big_multiply(limbs, 1000000000);
        power = power - 9;
    }
    while (power > 0) {
        _float_big_multiply(limbs, 10);
        power = power - 1;
    }
}

# Multiplies `limbs` by 2^`power`.
_float_big_shift(limbs: ulong[], power: long) {
    while (power >= 31) {
        _float_big_multiply(limbs, 0x80000000);
        power = power - 31;
    }
    if (power > 0) {
        _float_big_multiply(limbs, (1 as ulong) << power as ulong);
    }
}

# -1, 0 or 1 as `a` is less than, equal to or greater than `b`.
_float_big_compare(a: ulong[], b: ulong[]): int {
    var a_count = a.count;
    while (a_count > 0 && a[a_count - 1] == 0) {
        a_count = a_count - 1;
    }
    var b_count = b.count;
    while (b_count > 0 && b[b_count - 1] == 0) {
        b_count = b_count - 1;
    }
    if (a_count != b_count) {
        if (a_count < b_count) {
            return -1;
        }
        return 1;
    }
    var index = a_count;
    while (index > 0) {
        index = index - 1;
        if (a[index] != b[index]) {
            if (a[index] < b[index]) {
                return -1;
            }
            return 1;
        }
    }
    return 0;
}

# Compares `digits` * 10^`power10` with the midpoint between the finite,
# non-negative double whose bits are `bits` and the next double up.
_float_compare_midpoint(digits: ulong[], power10: long, bits: ulong): int {
    var field = (bits >> 52) as long;
    var mantissa = bits & 0xfffffffffffff;
    long exponent = -1074;
    if (field != 0) {
        mantissa = mantissa | ((1 as ulong) << 52);
        exponent = field - 1075;
    }
    # The midpoint is (2 * mantissa + 1) * 2^(exponent - 1).
    var power2 = exponent - 1;
    var left = _float_big_from(0);
    ulong index = 0;
    while (index < digits.count) {
        _float_big_multiply(left, 10);
        _float_big_add(left, digits[index]);
        index = index + 1;
    }
    var right = _float_big_from(2 * mantissa + 1);
    if (power10 >= 0) {
        _float_big_multiply_pow10(left, power10);
    } else {
        _float_big_multiply_pow10(right, 0 - power10);
    }
    if (power2 >= 0) {
        _float_big_shift(right, power2);
    } else {
        _float_big_shift(left, 0 - power2);
    }
    return _float_big_compare(left, right);
}

# The nearest double to `text`, which `_is_decimal` accepted, given
# `approximation`, a conversion that is at most a few units in the last
# place off.
export _float_correct(text: String, approximation: double): double {
    # The significant digits, without leading or trailing zeros, and the
    # power of 10 that scales them.
    var digits = Array<ulong>();
    long power10 = 0;
    var negative = false;
    var seen_point = false;
    var seen_digit = false;
    ulong index = 0;
    var size = text.size;
    ulong zeros = 0;
    while (index < size) {
        var c = text.byte_at(index);
        if (c == '-') {
            negative = true;
        } else if (c == '.') {
            seen_point = true;
        } else if (c == 'e' || c == 'E') {
            break;
        } else if (c >= '0' && c <= '9') {
            if (seen_point) {
                power10 = power10 - 1;
            }
            if (c == '0') {
                if (seen_digit) {
                    zeros = zeros + 1;
                }
            } else {
                while (zeros > 0) {
                    digits.append(0);
                    zeros = zeros - 1;
                }
                digits.append((c - '0') as ulong);
                seen_digit = true;
            }
        }
        index = index + 1;
    }
    power10 = power10 + zeros as long;
    if (index < size) {
        index = index + 1;
        var exponent_negative = false;
        if (text.byte_at(index) == '-' || text.byte_at(index) == '+') {
            exponent_negative = text.byte_at(index) == '-';
            index = index + 1;
        }
        long exponent = 0;
        while (index < size) {
            if (exponent < 100000) {
                exponent = exponent * 10 + (text.byte_at(index) - '0') as long;
            }
            index = index + 1;
        }
        if (exponent_negative) {
            exponent = 0 - exponent;
        }
        power10 = power10 + exponent;
    }
    var count = digits.count as long;
    # Zero, and values far outside the double range, convert exactly.
    if (count == 0 || count + power10 > 310 || count + power10 < -330) {
        return approximation;
    }
    # Up to 15 digits and a power of 10 up to 10^22 are both exact doubles,
    # so one correctly rounded multiply or divide gives the answer (Clinger's
    # fast path). The Windows C runtime misses even some of these
    # (`1.25865078068979e+17`), so compute it here.
    if (count <= 15 && power10 >= -22 && power10 <= 22) {
        ulong whole = 0;
        for (var digit in digits) {
            whole = whole * 10 + digit;
        }
        var scale = 1.0;
        var steps = power10;
        if (steps < 0) {
            steps = 0 - steps;
        }
        while (steps > 0) {
            scale = scale * 10.0;
            steps = steps - 1;
        }
        var value = whole as double;
        if (power10 < 0) {
            value = value / scale;
        } else {
            value = value * scale;
        }
        if (negative) {
            return -value;
        }
        return value;
    }
    var bits = unsafe_cast<ulong>(approximation) & 0x7fffffffffffffff;
    if (bits > 0x7ff0000000000000) {
        return approximation;
    }
    if (bits == 0x7ff0000000000000) {
        bits = bits - 1;
    }
    # Step up while the value is past the midpoint above, then down while
    # it is below the midpoint below; a tie goes to the even mantissa.
    while (bits < 0x7ff0000000000000) {
        var order = _float_compare_midpoint(digits, power10, bits);
        if (order < 0 || (order == 0 && (bits & 1) == 0)) {
            break;
        }
        bits = bits + 1;
    }
    while (bits > 0 && bits < 0x7ff0000000000000) {
        var order = _float_compare_midpoint(digits, power10, bits - 1);
        if (order > 0 || (order == 0 && (bits & 1) == 0)) {
            break;
        }
        bits = bits - 1;
    }
    if (negative) {
        bits = bits | 0x8000000000000000;
    }
    return unsafe_cast<double>(bits);
}
