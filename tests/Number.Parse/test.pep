# Every number type's static `parse`: signs, bases, the limits of each
# integer type, decimal notation for `float` and `double`, the texts each
# one rejects, and a call through a generic `T`.

parsed<T>(text: String): bool {
    return T.parse(text).is_value();
}

main(): int {
    # Signed integers: both signs, both limits, one past each limit.
    assert(char.parse("-128").value() == -128, "char lowest");
    assert(i8.parse("127").value() == 127, "i8 highest");
    assert(char.parse("128").is_empty(), "char too big");
    assert(char.parse("-129").is_empty(), "char too small");
    assert(short.parse("-32768").value() == -32768, "short lowest");
    assert(i16.parse("32767").value() == 32767, "i16 highest");
    assert(short.parse("32768").is_empty(), "short too big");
    assert(int.parse("-2147483648").value() == -2147483647 - 1, "int lowest");
    assert(i32.parse("2147483647").value() == 2147483647, "i32 highest");
    assert(int.parse("2147483648").is_empty(), "int too big");
    assert(int.parse("-2147483649").is_empty(), "int too small");
    assert(long.parse("-9223372036854775808").value() == -9223372036854775807 - 1, "long lowest");
    assert(i64.parse("9223372036854775807").value() == 9223372036854775807, "i64 highest");
    assert(long.parse("9223372036854775808").is_empty(), "long too big");
    assert(long.parse("99999999999999999999999").is_empty(), "long far too big");

    # Unsigned integers: the highest value, one past it, and no `-`.
    assert(byte.parse("255").value() == 255, "byte highest");
    assert(u8.parse("256").is_empty(), "u8 too big");
    assert(byte.parse("-0").is_empty(), "byte minus");
    assert(ushort.parse("65535").value() == 65535, "ushort highest");
    assert(u16.parse("65536").is_empty(), "u16 too big");
    assert(uint.parse("+4294967295").value() == 4294967295, "uint highest");
    assert(u32.parse("4294967296").is_empty(), "u32 too big");
    assert(ulong.parse("18446744073709551615").value() == 0xFFFFFFFFFFFFFFFF, "ulong highest");
    assert(u64.parse("18446744073709551616").is_empty(), "u64 too big");

    # Bases from 2 to 36, letters in either case.
    assert(int.parse("ff", 16).value() == 255, "hex lower");
    assert(int.parse("FF", 16).value() == 255, "hex upper");
    assert(int.parse("-101", 2).value() == -5, "binary");
    assert(int.parse("z", 36).value() == 35, "base 36");
    assert(int.parse("2", 2).is_empty(), "digit past the base");
    assert(ulong.parse("ffffffffffffffff", 16).value() == 0xFFFFFFFFFFFFFFFF, "hex ulong");

    # Integer texts that are not numbers.
    assert(int.parse("").is_empty(), "empty");
    assert(int.parse("-").is_empty(), "only a sign");
    assert(int.parse(" 1").is_empty(), "a space");
    assert(int.parse("12x").is_empty(), "a trailing letter");
    assert(int.parse("0x1f").is_empty(), "a prefix");
    assert(int.parse("1.5").is_empty(), "a fraction");

    # Decimal notation.
    assert(double.parse("2.5").value() == 2.5, "double");
    assert(double.parse("-2.5e3").value() == -2500.0, "exponent");
    assert(double.parse("+.5").value() == 0.5, "no integer part");
    assert(double.parse("2.").value() == 2.0, "no fraction digits");
    assert(double.parse("1E-2").value() == 0.01, "negative exponent");
    assert(double.parse("42").value() == 42.0, "an integer");
    assert(double.parse("1e400").is_empty(), "double too big");
    assert(double.parse("1e-400").value() == 0.0, "double too small rounds to zero");
    assert(float.parse("0.25").value() == 0.25, "float");
    assert(f32.parse("-1.5").value() == -1.5, "f32");
    assert(float.parse("1e39").is_empty(), "float too big");

    # Decimal texts that are not numbers.
    assert(double.parse("").is_empty(), "empty");
    assert(double.parse(".").is_empty(), "only a point");
    assert(double.parse("1.5.2").is_empty(), "two points");
    assert(double.parse("1e").is_empty(), "no exponent digits");
    assert(double.parse(" 1").is_empty(), "a space");
    assert(double.parse("inf").is_empty(), "inf");
    assert(double.parse("nan").is_empty(), "nan");
    assert(double.parse("0x1p3").is_empty(), "hexadecimal");

    # A generic function reaches each type's parse through `T`.
    assert(parsed<int>("7") && !parsed<byte>("300") && parsed<double>("1.5"), "generic");
    return 0;
}
