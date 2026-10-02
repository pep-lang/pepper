# Converts a string of decimal digits to an int, or explains why it cannot.
parse_number(text: String): Result<int> {
    if text.is_empty {
        return Result<int>.err(Error("expected a number, found nothing"));
    }
    var value = 0;
    for (var c in text) {
        var digit = "0123456789".find(c);
        if digit < 0 {
            return Result<int>.err(Error("'" + c + "' is not a digit"));
        }
        value = value * 10 + (digit as int);
    }
    return Result<int>.ok(value);
}

main(): int {
    var good = parse_number("2026");
    assert(good.is_ok(), "digits parse");
    assert(good.value() == 2026, "value() returns the value");

    var bad = parse_number("12x");
    assert(bad.is_err(), "x is not a digit");
    assert(bad.error().message == "'x' is not a digit", "the error explains why");
    print(bad.error().message);

    assert(parse_number("").ok_or(-1) == -1, "ok_or supplies a fallback");
    return 0;
}
