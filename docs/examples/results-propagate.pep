# A custom error type: any type can be the second type argument.
struct ParseError {
    String Input;
    int Position;

    construct(this.Input = "", this.Position = 0) {}
}

digit_value(String c): int {
    var digits = "0123456789";
    var i = 0;
    while (i < 10) {
        if (c == digits[i]) {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

parse_number(String s): Result<int, ParseError> {
    if (s.length() == 0) {
        return Result<int, ParseError>.err(ParseError(s, 0));
    }
    var value = 0;
    var position = 0;
    for (var c in s) {
        var d = digit_value(c);
        if (d < 0) {
            return Result<int, ParseError>.err(ParseError(s, position));
        }
        value = value * 10 + d;
        position = position + 1;
    }
    return Result<int, ParseError>.ok(value);
}

# Propagate an error: check it, and return early with the same error.
add_numbers(String a, String b): Result<int, ParseError> {
    var x = parse_number(a);
    if (x.is_err()) {
        return Result<int, ParseError>.err(x.Error);
    }
    var y = parse_number(b);
    if (y.is_err()) {
        return Result<int, ParseError>.err(y.Error);
    }
    return Result<int, ParseError>.ok(x.Value + y.Value);
}

# Convert an error into another type on the way out.
check_total(String a, String b, int limit): Result<void> {
    var sum = add_numbers(a, b);
    if (sum.is_err()) {
        var e = sum.Error;
        return Result<void>.err(Error("bad number '" + e.Input + "'"));
    }
    if (sum.Value > limit) {
        return Result<void>.err(Error("total is over the limit"));
    }
    return Result<void>.ok();
}

main(): int {
    var sum = add_numbers("40", "2");
    assert(sum.value() == 42, "40 + 2");

    var bad = add_numbers("40", "4x2");
    assert(bad.is_err(), "the second number is bad");
    assert(bad.Error.Input == "4x2", "the error names the input");
    assert(bad.Error.Position == 1, "and where it went wrong");

    assert(check_total("1", "2", 10).is_ok(), "3 is within the limit");
    var over = check_total("10", "20", 10);
    assert(over.Error.Message == "total is over the limit", "30 is not");
    var wrong = check_total("1", "", 10);
    assert(wrong.Error.Message == "bad number ''", "an empty number is an error");
    return 0;
}
