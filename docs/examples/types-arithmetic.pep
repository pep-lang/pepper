# Arithmetic follows C's rules for promotion and conversion.
main(): int {
    # Integer division truncates toward zero; % takes the sign of the left side.
    assert(7 / 2 == 3, "7 / 2 is 3");
    assert(-7 / 2 == -3, "-7 / 2 is -3");
    assert(-7 % 3 == -1, "-7 % 3 is -1");

    # Types narrower than int are promoted to int before arithmetic,
    # so the sum of two chars does not wrap at 8 bits...
    char a = 100;
    char b = 100;
    int sum = a + b;
    assert(sum == 200, "char + char is computed as int");

    # ...but storing the result back into a char does.
    char c = a + b;
    assert(c == -56, "200 does not fit in a char");

    # Mixing signed and unsigned of the same width is unsigned, as in C.
    int minus_one = -1;
    uint one = 1;
    assert(!(minus_one < one), "-1 converts to 4294967295 when compared with a uint");
    uint zero = 0;
    assert(zero - 1 == 4294967295, "unsigned arithmetic wraps");

    # Mixing an integer with a floating-point value gives floating point.
    int whole = 3;
    double half = 0.5;
    double product = whole * half;
    assert(product == 1.5, "3 * 0.5 is 1.5");

    # 'as' converts explicitly. Floating point to integer truncates toward zero.
    assert((7.9 as int) == 7, "7.9 as int is 7");
    assert((-7.9 as int) == -7, "-7.9 as int is -7");
    assert(((whole as double) / 2) == 1.5, "divide as double");

    # Assignment converts implicitly, including from double to int.
    int truncated = 2.7;
    assert(truncated == 2, "2.7 stored in an int is 2");

    # Shifts: >> is arithmetic for signed types and logical for unsigned types.
    assert(-8 >> 1 == -4, "signed shift keeps the sign");
    uint bits = 0x80000000;
    assert(bits >> 31 == 1, "unsigned shift fills with zeros");
    return 0;
}
