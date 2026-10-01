# Reading numbers from text with each number type's static parse.

main(): int {
    # An integer type takes an optional base from 2 to 36.
    assert(int.parse("-42").value() == -42, "decimal");
    assert(byte.parse("ff", 16).value() == 255, "hexadecimal");

    # The result is empty when the text is not a number of that type.
    assert(int.parse("4 2").is_none(), "not an integer");
    assert(byte.parse("256").is_none(), "too big for a byte");

    # float and double read decimal notation.
    var ratio = double.parse("2.5e-1");
    if (ratio.is_some()) {
        assert(ratio.value() == 0.25, "an exponent");
    }
    return 0;
}
