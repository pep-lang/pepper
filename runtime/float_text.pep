# Formats a double or a float as the shortest decimal text that reads back
# as exactly that value, with Ulf Adams' Ryu algorithm ("Ryu: fast
# float-to-string conversion", PLDI 2018). This is a port of the reference
# implementation's d2s.c with its small tables (d2s_small_table.h), from
# github.com/ulfjack/ryu (Apache 2.0 or Boost 1.0). A float runs through
# the same steps with its own mantissa width and bias: the 125-bit powers of
# 5 are more than precise enough for its 24-bit significand.
#
# The algorithm finds the shortest digits inside the interval of reals that
# round to the value, and of those the closest to it, with 128-bit
# fixed-point powers of 5; `_float_text` lays the digits out as Swift does.

import "internals";

extern void* malloc(ulong size);

# Ryu's tables, one block: 5^0 to 5^25 (`_FLOAT_POW5`), every 26th power of
# 5 as 128 bits (`_FLOAT_POW5_SPLIT`, low word first), the error corrections
# for the powers between them (`_FLOAT_POW5_OFFSETS`, 2 bits each), and the
# same for the inverse powers (`_FLOAT_POW5_INV_SPLIT`,
# `_FLOAT_POW5_INV_OFFSETS`). Plain `malloc`, not `_pep_malloc`: module
# constants may initialize before the allocation counter, and the block
# lives as long as the program.
const _float_tables: __ptr<ulong> = _float_make_tables();

const _FLOAT_POW5: ulong = 0;
const _FLOAT_POW5_SPLIT: ulong = 26;
const _FLOAT_POW5_OFFSETS: ulong = 52;
const _FLOAT_POW5_INV_SPLIT: ulong = 73;
const _FLOAT_POW5_INV_OFFSETS: ulong = 103;
const _FLOAT_TABLE_SIZE: ulong = 125;
const _FLOAT_POW5_BITS: long = 125;

# Stores four words at `index`. The table is written word by word, not
# from an array literal: it is built while module constants initialize,
# before the runtime's allocation counter is ready.
_float_store(tables: __ptr<ulong>, index: ulong, a: ulong, b: ulong, c: ulong, d: ulong) {
    tables[index] = a;
    tables[index + 1] = b;
    tables[index + 2] = c;
    tables[index + 3] = d;
}

_float_make_tables(): __ptr<ulong> {
    # One spare word: the last store writes four.
    __ptr<ulong> tables = malloc((_FLOAT_TABLE_SIZE + 3) * 8);
    # format: off
    _float_store(tables, 0, 0x0000000000000001, 0x0000000000000005, 0x0000000000000019, 0x000000000000007d);
    _float_store(tables, 4, 0x0000000000000271, 0x0000000000000c35, 0x0000000000003d09, 0x000000000001312d);
    _float_store(tables, 8, 0x000000000005f5e1, 0x00000000001dcd65, 0x00000000009502f9, 0x0000000002e90edd);
    _float_store(tables, 12, 0x000000000e8d4a51, 0x0000000048c27395, 0x000000016bcc41e9, 0x000000071afd498d);
    _float_store(tables, 16, 0x0000002386f26fc1, 0x000000b1a2bc2ec5, 0x000003782dace9d9, 0x00001158e460913d);
    _float_store(tables, 20, 0x000056bc75e2d631, 0x0001b1ae4d6e2ef5, 0x000878678326eac9, 0x002a5a058fc295ed);
    _float_store(tables, 24, 0x00d3c21bcecceda1, 0x0422ca8b0a00a425, 0x0000000000000000, 0x1000000000000000);
    _float_store(tables, 28, 0x0000000000000000, 0x14adf4b7320334b9, 0x0e549208b31adb10, 0x1aba4714957d300d);
    _float_store(tables, 32, 0x6dc6ad264d8f0866, 0x1145b7e285bf98f5, 0xeb1dbd923d8596ca, 0x1652efdc6018a1fc);
    _float_store(tables, 36, 0xb4c1b80b22ae923c, 0x1cda62055b2d9d83, 0x5bb28b4e8f7e4c30, 0x12a5568b9f52f416);
    _float_store(tables, 40, 0xf08aed437682d4fb, 0x1819651531f9e78f, 0xb4ee134ad99bf150, 0x1f25c186a6f04c28);
    _float_store(tables, 44, 0x16499ecb70c25f03, 0x1420eb449c8842e6, 0x85a56ead360865b0, 0x1a03fde214caf085);
    _float_store(tables, 48, 0x093db1d57999890b, 0x10cfeb353a97dad8, 0xcf38bb735e3f36ac, 0x15baaf44fa52673e);
    _float_store(tables, 52, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000);
    _float_store(tables, 56, 0x0000000040000000, 0x0000000059695995, 0x0000000055545555, 0x0000000056555515);
    _float_store(tables, 60, 0x0000000041150504, 0x0000000040555410, 0x0000000044555145, 0x0000000044504540);
    _float_store(tables, 64, 0x0000000045555550, 0x0000000040004000, 0x0000000096440440, 0x0000000055565565);
    _float_store(tables, 68, 0x0000000054454045, 0x0000000040154151, 0x0000000055559155, 0x0000000051405555);
    _float_store(tables, 72, 0x0000000000000105, 0x0000000000000001, 0x2000000000000000, 0x52a6c95fc0655034);
    _float_store(tables, 76, 0x18c240c4aecb13bb, 0x7ca8d50071dfc806, 0x1327fc58da0f6ff5, 0x6520247d3556476e);
    _float_store(tables, 80, 0x1da48ce468e7c702, 0x6139cdd76802e6e9, 0x16ef5b40c2fc7779, 0xf951a7ff43de8c79);
    _float_store(tables, 84, 0x11bebdf578b2f391, 0x7be8bee8d6e957e8, 0x1b758d848fac54b0, 0x8bd3f9e999a423ea);
    _float_store(tables, 88, 0x153eda614071a3b7, 0x0848f973cb3ee3ce, 0x10701bd527b4978c, 0x153285ebb9efbfa2);
    _float_store(tables, 92, 0x196fbb9bb44db44d, 0xadeee7f86c07b696, 0x13ae3591f5b4d936, 0x4d686a4eaf182222);
    _float_store(tables, 96, 0x1e74404f3daada91, 0x98c0a106e09ebd9f, 0x17900ea4fda7c257, 0x8f20e37371497d0e);
    _float_store(tables, 100, 0x123b140576d820b2, 0xb043138134743d85, 0x1c35f4275f7a29ad, 0x0000000054544554);
    _float_store(tables, 104, 0x0000000004055545, 0x0000000010041000, 0x0000000000400414, 0x0000000040010000);
    _float_store(tables, 108, 0x0000000041155555, 0x0000000000000454, 0x0000000000010044, 0x0000000040000000);
    _float_store(tables, 112, 0x0000000044000041, 0x0000000050454450, 0x0000000055550054, 0x0000000051655554);
    _float_store(tables, 116, 0x0000000040004000, 0x0000000001000001, 0x0000000000010500, 0x0000000051515411);
    _float_store(tables, 120, 0x0000000005555554, 0x0000000050411500, 0x0000000040040000, 0x0000000005040110);
    _float_store(tables, 124, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000);
    # format: on
    return tables;
}

# The 128-bit product of `a` and `b`, as (low, high) words.
_float_multiply(a: ulong, b: ulong): (ulong, ulong) {
    var a_low = a & 0xffffffff;
    var a_high = a >> 32;
    var b_low = b & 0xffffffff;
    var b_high = b >> 32;
    var b00 = a_low * b_low;
    var b01 = a_low * b_high;
    var b10 = a_high * b_low;
    var b11 = a_high * b_high;
    var middle1 = b10 + (b00 >> 32);
    var middle2 = b01 + (middle1 & 0xffffffff);
    var high = b11 + (middle1 >> 32) + (middle2 >> 32);
    var low = (middle2 << 32) | (b00 & 0xffffffff);
    return (low, high);
}

# The low 64 bits of the 128-bit `high:low` shifted right by `distance`,
# which is from 1 to 63.
_float_shift_right(low: ulong, high: ulong, distance: long): ulong {
    return (high << (64 - distance) as ulong) | (low >> distance as ulong);
}

# The number of bits in 5^e, plus one: ceil(log2(5^e)) for e > 0.
_float_pow5_bits(e: long): long {
    return (((e as ulong) * 1217359) >> 19) as long + 1;
}

# floor(log10(2^e)).
_float_log10_pow2(e: long): long {
    return (((e as ulong) * 78913) >> 18) as long;
}

# floor(log10(5^e)).
_float_log10_pow5(e: long): long {
    return (((e as ulong) * 732923) >> 20) as long;
}

# The correction stored for power `i` in the 2-bit offsets table at `at`.
_float_offset(at: ulong, i: ulong): ulong {
    return (_float_tables[at + i / 16] >> ((i % 16) * 2)) & 3;
}

# `high:low` shifted right by `delta` (1 to 63), plus `add`, as 128 bits.
_float_shift_add(low: ulong, middle: ulong, high: ulong, delta: long, add: ulong): (ulong, ulong) {
    var result_low = _float_shift_right(low, middle, delta);
    var result_high = _float_shift_right(middle, high, delta);
    var sum = result_low.wrapping_add(add);
    if (sum < result_low) {
        result_high = result_high + 1;
    }
    return (sum, result_high);
}

# 5^i as a 128-bit fixed-point number with `_FLOAT_POW5_BITS` significant
# bits, as (low, high): the nearest table power times 5^offset, corrected.
_float_pow5(i: long): (ulong, ulong) {
    var base = (i / 26) as ulong;
    var base2 = base * 26;
    var offset = i as ulong - base2;
    var low_word = _float_tables[_FLOAT_POW5_SPLIT + base * 2];
    var high_word = _float_tables[_FLOAT_POW5_SPLIT + base * 2 + 1];
    if (offset == 0) {
        return (low_word, high_word);
    }
    var m = _float_tables[_FLOAT_POW5 + offset];
    var (low1, high1) = _float_multiply(m, high_word);
    var (low0, high0) = _float_multiply(m, low_word);
    var sum = high0.wrapping_add(low1);
    if (sum < high0) {
        high1 = high1 + 1;
    }
    var delta = _float_pow5_bits(i) - _float_pow5_bits(base2 as long);
    return _float_shift_add(low0, sum, high1, delta, _float_offset(_FLOAT_POW5_OFFSETS, i as ulong));
}

# 2^k / 5^i as a 128-bit fixed-point number (k chosen so it has
# `_FLOAT_POW5_BITS` significant bits), rounded up, as (low, high).
_float_pow5_inverse(i: long): (ulong, ulong) {
    var base = ((i + 25) / 26) as ulong;
    var base2 = base * 26;
    var offset = base2 - i as ulong;
    var low_word = _float_tables[_FLOAT_POW5_INV_SPLIT + base * 2];
    var high_word = _float_tables[_FLOAT_POW5_INV_SPLIT + base * 2 + 1];
    if (offset == 0) {
        return (low_word, high_word);
    }
    var m = _float_tables[_FLOAT_POW5 + offset];
    var (low1, high1) = _float_multiply(m, high_word);
    var (low0, high0) = _float_multiply(m, low_word - 1);
    var sum = high0.wrapping_add(low1);
    if (sum < high0) {
        high1 = high1 + 1;
    }
    var delta = _float_pow5_bits(base2 as long) - _float_pow5_bits(i);
    return _float_shift_add(low0, sum, high1, delta, 1 + _float_offset(_FLOAT_POW5_INV_OFFSETS, i as ulong));
}

# floor(m * multiplier / 2^j) for the 128-bit `multiplier`, with j from 65
# to 127.
_float_multiply_shift(m: ulong, multiplier: (ulong, ulong), j: long): ulong {
    var (low1, high1) = _float_multiply(m, multiplier.1);
    var (_, high0) = _float_multiply(m, multiplier.0);
    var sum = high0.wrapping_add(low1);
    if (sum < high0) {
        high1 = high1 + 1;
    }
    return _float_shift_right(sum, high1, j - 64);
}

# The number of times 5 divides `value`, which is not 0.
_float_pow5_factor(value: ulong): long {
    long count = 0;
    while (true) {
        # 5 * 0xcccccccccccccccd == 1 (mod 2^64), and a multiple of 5
        # times it is at most (2^64 - 1) / 5.
        value = value.wrapping_mul(0xcccccccccccccccd);
        if (value > 0x3333333333333333) {
            break;
        }
        count = count + 1;
    }
    return count;
}

# The shortest decimal digits `d` and exponent `e` with d * 10^e inside
# the interval that rounds to the finite, positive floating-point value
# whose fields are `ieee_mantissa` and `ieee_exponent`, in a format with
# `mantissa_bits` stored mantissa bits and exponent `bias`; of those, the
# closest to the value, ties to even.
_float_shortest(ieee_mantissa: ulong, ieee_exponent: long, mantissa_bits: long, bias: long): (ulong, long) {
    long e2 = 0;
    ulong m2 = 0;
    if (ieee_exponent == 0) {
        e2 = 1 - bias - mantissa_bits - 2;
        m2 = ieee_mantissa;
    } else {
        e2 = ieee_exponent - bias - mantissa_bits - 2;
        m2 = ((1 as ulong) << mantissa_bits as ulong) | ieee_mantissa;
    }
    var accept_bounds = (m2 & 1) == 0;
    # The value and the interval's bounds, scaled by 4: mv - 1 - mm_shift
    # to mv + 2. The lower half is narrower at a power of 2.
    var mv = 4 * m2;
    ulong mm_shift = 0;
    if (ieee_mantissa != 0 || ieee_exponent <= 1) {
        mm_shift = 1;
    }
    ulong vr = 0;
    ulong vp = 0;
    ulong vm = 0;
    long e10 = 0;
    var vm_trailing_zeros = false;
    var vr_trailing_zeros = false;
    if (e2 >= 0) {
        var q = _float_log10_pow2(e2);
        if (e2 > 3) {
            q = q - 1;
        }
        e10 = q;
        var k = _FLOAT_POW5_BITS + _float_pow5_bits(q) - 1;
        var i = 0 - e2 + q + k;
        var multiplier = _float_pow5_inverse(q);
        vr = _float_multiply_shift(4 * m2, multiplier, i);
        vp = _float_multiply_shift(4 * m2 + 2, multiplier, i);
        vm = _float_multiply_shift(4 * m2 - 1 - mm_shift, multiplier, i);
        if (q <= 21) {
            # Only one of mp, mv and mm can be a multiple of 5, if any.
            if (mv % 5 == 0) {
                vr_trailing_zeros = _float_pow5_factor(mv) >= q;
            } else if (accept_bounds) {
                vm_trailing_zeros = _float_pow5_factor(mv - 1 - mm_shift) >= q;
            } else if (_float_pow5_factor(mv + 2) >= q) {
                vp = vp - 1;
            }
        }
    } else {
        var q = _float_log10_pow5(0 - e2);
        if (0 - e2 > 1) {
            q = q - 1;
        }
        e10 = q + e2;
        var i = 0 - e2 - q;
        var k = _float_pow5_bits(i) - _FLOAT_POW5_BITS;
        var j = q - k;
        var multiplier = _float_pow5(i);
        vr = _float_multiply_shift(4 * m2, multiplier, j);
        vp = _float_multiply_shift(4 * m2 + 2, multiplier, j);
        vm = _float_multiply_shift(4 * m2 - 1 - mm_shift, multiplier, j);
        if (q <= 1) {
            # mv has at least q trailing 0 bits, so vr has q trailing 0
            # digits.
            vr_trailing_zeros = true;
            if (accept_bounds) {
                vm_trailing_zeros = mm_shift == 1;
            } else {
                vp = vp - 1;
            }
        } else if (q < 63) {
            vr_trailing_zeros = (mv & (((1 as ulong) << q as ulong) - 1)) == 0;
        }
    }
    # Drop digits while the interval still holds a shorter number.
    long removed = 0;
    ulong last_removed = 0;
    ulong output = 0;
    if (vm_trailing_zeros || vr_trailing_zeros) {
        # The general case, which happens rarely (~0.7%).
        while (vp / 10 > vm / 10) {
            vm_trailing_zeros = vm_trailing_zeros && vm % 10 == 0;
            vr_trailing_zeros = vr_trailing_zeros && last_removed == 0;
            last_removed = vr % 10;
            vr = vr / 10;
            vp = vp / 10;
            vm = vm / 10;
            removed = removed + 1;
        }
        if (vm_trailing_zeros) {
            while (vm % 10 == 0) {
                vr_trailing_zeros = vr_trailing_zeros && last_removed == 0;
                last_removed = vr % 10;
                vr = vr / 10;
                vp = vp / 10;
                vm = vm / 10;
                removed = removed + 1;
            }
        }
        if (vr_trailing_zeros && last_removed == 5 && vr % 2 == 0) {
            # Exactly halfway between two outputs: round to even.
            last_removed = 4;
        }
        output = vr;
        if ((vr == vm && (!accept_bounds || !vm_trailing_zeros)) || last_removed >= 5) {
            output = output + 1;
        }
    } else {
        # The common case (~99.3%).
        var round_up = false;
        if (vp / 100 > vm / 100) {
            # Two digits at a time (~86.2%).
            round_up = vr % 100 >= 50;
            vr = vr / 100;
            vp = vp / 100;
            vm = vm / 100;
            removed = removed + 2;
        }
        while (vp / 10 > vm / 10) {
            round_up = vr % 10 >= 5;
            vr = vr / 10;
            vp = vp / 10;
            vm = vm / 10;
            removed = removed + 1;
        }
        output = vr;
        if (vr == vm || round_up) {
            output = output + 1;
        }
    }
    return (output, e10 + removed);
}

# Writes the `count` decimal digits of `value` to `buffer` from `at`.
_float_write_digits(buffer: __ptr<char>, at: ulong, value: ulong, count: ulong) {
    var index = at + count;
    while (index > at) {
        index = index - 1;
        buffer[index] = ('0' + value % 10) as char;
        value = value / 10;
    }
}

# Writes `count` copies of '0' to `buffer` from `at`.
_float_write_zeros(buffer: __ptr<char>, at: ulong, count: ulong) {
    var index = at;
    while (index < at + count) {
        buffer[index] = '0' as char;
        index = index + 1;
    }
}

# The shortest decimal text that reads back as `value` (as a `float` when
# `single`), laid out as Swift prints a number: `3.0`, `0.1`, `-2.5`, and
# an exponent outside 1e-4 to 1e16 (`1e+16`, `1.5e-05`); `nan`, `inf` and
# `-inf` for the special values.
export _float_text(value: double, single: bool): String {
    ulong mantissa = 0;
    long exponent = 0;
    var negative = false;
    var special = false;
    if (single) {
        float narrow = value as float;
        var bits = unsafe_cast<uint>(narrow) as ulong;
        negative = (bits >> 31) != 0;
        mantissa = bits & 0x7fffff;
        exponent = ((bits >> 23) & 0xff) as long;
        special = exponent == 0xff;
    } else {
        var bits = unsafe_cast<ulong>(value);
        negative = (bits >> 63) != 0;
        mantissa = bits & 0xfffffffffffff;
        exponent = ((bits >> 52) & 0x7ff) as long;
        special = exponent == 0x7ff;
    }
    if (special) {
        if (mantissa != 0) {
            return "nan";
        }
        if (negative) {
            return "-inf";
        }
        return "inf";
    }
    if (mantissa == 0 && exponent == 0) {
        if (negative) {
            return "-0.0";
        }
        return "0.0";
    }
    ulong digits = 0;
    long power = 0;
    if (single) {
        (digits, power) = _float_shortest(mantissa, exponent, 23, 127);
    } else {
        (digits, power) = _float_shortest(mantissa, exponent, 52, 1023);
    }
    while (digits % 10 == 0) {
        digits = digits / 10;
        power = power + 1;
    }
    ulong count = 1;
    ulong limit = 10;
    while (count < 17 && digits >= limit) {
        count = count + 1;
        limit = limit * 10;
    }
    if (count == 17 && digits >= limit) {
        count = 18;
    }
    # The exponent of the first digit: digits = d.ddd * 10^scientific.
    var scientific = power + count as long - 1;
    # The longest text, "-0.0000" and 17 digits or "-d.dddddddddddddddde-308",
    # is 24 bytes; one more for the terminator.
    var buffer = _pep_malloc(32) as __ptr<char>;
    ulong at = 0;
    if (negative) {
        buffer[0] = '-' as char;
        at = 1;
    }
    if (scientific < -4 || scientific >= 16) {
        _float_write_digits(buffer, at + 1, digits, count);
        buffer[at] = buffer[at + 1];
        at = at + 1;
        if (count > 1) {
            buffer[at] = '.' as char;
            at = at + count;
        }
        buffer[at] = 'e' as char;
        at = at + 1;
        var magnitude = scientific;
        if (scientific < 0) {
            buffer[at] = '-' as char;
            magnitude = 0 - scientific;
        } else {
            buffer[at] = '+' as char;
        }
        at = at + 1;
        ulong width = 2;
        if (magnitude >= 100) {
            width = 3;
        }
        _float_write_digits(buffer, at, magnitude as ulong, width);
        at = at + width;
    } else if (scientific < 0) {
        buffer[at] = '0' as char;
        buffer[at + 1] = '.' as char;
        var zeros = (0 - scientific - 1) as ulong;
        _float_write_zeros(buffer, at + 2, zeros);
        _float_write_digits(buffer, at + 2 + zeros, digits, count);
        at = at + 2 + zeros + count;
    } else {
        var whole = (scientific + 1) as ulong;
        if (count <= whole) {
            _float_write_digits(buffer, at, digits, count);
            _float_write_zeros(buffer, at + count, whole - count);
            at = at + whole;
            buffer[at] = '.' as char;
            buffer[at + 1] = '0' as char;
            at = at + 2;
        } else {
            # Write the digits one place right, then move the whole part
            # back over the gap and put the point there.
            _float_write_digits(buffer, at + 1, digits, count);
            var index = at;
            while (index < at + whole) {
                buffer[index] = buffer[index + 1];
                index = index + 1;
            }
            buffer[at + whole] = '.' as char;
            at = at + count + 1;
        }
    }
    buffer[at] = 0;
    var text = String();
    text._data = buffer;
    text._size = at;
    text._length = at;
    return text;
}
