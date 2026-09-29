# Integer types: widths, signedness, wraparound and conversions.
main(): int {
    # Each width has a short name and a descriptive alias.
    i8 tiny = -100;       # same type as char
    u8 octet = 200;       # same type as byte
    i16 small = -30000;   # same type as short
    u16 port = 65000;     # same type as ushort
    i32 count = 2000000;  # same type as int
    u32 mask = 4000000000; # same type as uint
    i64 big = 9000000000; # same type as long
    u64 huge = 9000000000000000000;  # same type as ulong

    assert(sizeof<char>() == 1 && sizeof<short>() == 2, "8 and 16 bits");
    assert(sizeof<int>() == 4 && sizeof<long>() == 8, "32 and 64 bits");

    # An alias names the same type, so assigning between them is lossless.
    short s = small;
    assert(s == -30000, "short and i16 are one type");

    # Storing a value that does not fit wraps around, as in C.
    u16 wrap = 65535;
    wrap = wrap + 1;
    assert(wrap == 0, "u16 wraps from 65535 to 0");
    i16 overflow = 32767;
    overflow += 1;
    assert(overflow == -32768, "i16 wraps from 32767 to -32768");

    # Widening keeps the value: signed types sign-extend, unsigned zero-extend.
    long widened = small;
    assert(widened == -30000, "i16 widens to long");
    assert((tiny as u8) == 156, "-100 as u8 is 156");
    assert((octet as i8) == -56, "200 as i8 is -56");

    # Narrowing with 'as' keeps the low bits.
    assert((70000 as u16) == 4464, "70000 as u16 keeps the low 16 bits");

    # Hexadecimal literals.
    assert(0xFF == 255, "0xFF is 255");
    assert(count + big > 0 && mask > 0 && huge > 0 && port > 0, "all in range");
    return 0;
}
