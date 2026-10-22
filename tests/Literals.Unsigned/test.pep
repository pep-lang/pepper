# Decimal literals past `long`'s range are `ulong`s, the same values as
# their hexadecimal spellings, wherever a `ulong` takes them; `long`'s
# minimum is written with its sign.
const ULONG_MAX: ulong = 18446744073709551615;

struct Holder {
    var value: ulong = 9223372036854775808;
}

enum Big: ulong {
    Top = 18446744073709551615,
}

same(x: ulong): ulong {
    return x;
}

main(): int {
    ulong near = 9223372036854775808;
    if (near != 0x8000000000000000) { return 1; }
    if (ULONG_MAX != 0xFFFFFFFFFFFFFFFF) { return 2; }
    if (same(18446744073709551615) != 0xFFFFFFFFFFFFFFFF) { return 3; }
    if (Holder().value != 0x8000000000000000) { return 4; }
    var inferred = 9223372036854775809;
    if (inferred != 0x8000000000000001) { return 5; }
    long x = -1;
    if (x as ulong != 18446744073709551615) { return 6; }
    long low = -9223372036854775808;
    if (low != 0x8000000000000000 as long) { return 7; }
    if ($"{low}" != "-9223372036854775808") { return 8; }
    if (Big.Top as ulong != 0xFFFFFFFFFFFFFFFF) { return 9; }
    near = 10000000000000000000;
    if ($"{near}" != "10000000000000000000") { return 10; }
    double d = 18446744073709551615;
    if (d != 18446744073709551616.0) { return 11; }
    return 0;
}
