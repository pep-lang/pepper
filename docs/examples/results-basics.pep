# A function that can fail returns a Result instead of a plain value.
parse_digit(String s): Result<int> {
    if (s == "0") { return Result<int>.ok(0); }
    if (s == "1") { return Result<int>.ok(1); }
    if (s == "2") { return Result<int>.ok(2); }
    return Result<int>.err(Error("not a digit: " + s));
}

main(): int {
    var good = parse_digit("2");
    assert(good.is_ok(), "2 parses");
    assert(!good.is_err(), "is_err is the opposite of is_ok");
    assert(good.value() == 2, "value() returns the value");
    assert(good.value() == 2, "the Value field holds it too");

    var bad = parse_digit("x");
    assert(bad.is_err(), "x does not parse");
    assert(bad.error().message == "not a digit: x", "the error explains why");

    # ok_or returns the value, or the fallback for an Err. It never panics.
    assert(good.ok_or(-1) == 2, "Ok gives its value");
    assert(bad.ok_or(-1) == -1, "Err gives the fallback");

    # Result<int> is short for Result<int, Error>.
    Result<int, Error> spelled_out = good;
    assert(spelled_out.value() == 2, "the same type");

    # A default-constructed Result is an Err with a default error.
    var empty = Result<int>();
    assert(empty.is_err(), "Result() is an Err");

    # An operation with no value to return uses void.
    var done = Result<void>.ok();
    var failed = Result<void>.err(Error("disk full"));
    assert(done.is_ok() && failed.is_err(), "Result<void> works like any other");
    return 0;
}
