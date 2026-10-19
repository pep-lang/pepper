# Result<TValue, TError>: the default and a custom error type, matching on
# Ok and Err, Result<void>, and a struct value released with its result.

struct Code {
    int value;

    construct(v: int) {
        this.value = v;
    }
}

struct Point {
    int x;

    construct(v: int) {
        this.x = v;
    }
}

parse(text: String): Result<int> {
    if (text == "42") {
        return Result<int>.Ok(42);
    }
    return Result<int>.Err(Error("not a number"));
}

check(n: int): Result<void> {
    if (n < 0) {
        return Result<void>.Err(Error("negative"));
    }
    return Result<void>.Ok;
}

check_good(good: bool): Result<void> {
    if (good) {
        return Result<void>.ok();
    }
    return Result<void>.err(Error("bad"));
}

# `Result<int, Error>` is the same specialization shape as `Result<int>`.
[Test]
explicit_terror_matches_default() {
    Result<int, Error> a = Result<int>.ok(1);
    Result<int> b = Result<int, Error>.err(Error("x"));
    expect_true(a.is_ok());
    expect_equal(a.value(), 1);
    expect_true(b.is_err());
    expect_equal(b.error().message, "x");
}

[Test]
custom_terror() {
    var r = Result<int, Code>.err(Code(500));
    expect_false(r.is_ok());
    expect_equal(r.error().value, 500);
    var ok = Result<int, Code>.ok(3);
    expect_true(ok.is_ok());
    expect_equal(ok.value(), 3);
}

[Test]
match_on_result() {
    var n = match (parse("42")) {
        Ok(v) => v,
        Err(e) => -1,
    };
    expect_equal(n, 42);
    var message = match (parse("x")) {
        Ok(v) => "",
        Err(e) => e.message,
    };
    expect_equal(message, "not a number");
    expect_true(parse("42") is Ok);
    var length = 0;
    if (parse("x") is Err(e)) {
        length = e.message.length as int;
    }
    expect_equal(length, 12);
    var text = match (Result<String>.ok("s")) {
        Ok(s) => s,
        Err(e) => e.message,
    };
    expect_equal(text, "s");
}

[Test]
void_result_ok_carries_nothing() {
    expect_true(check(1) is Ok);
    check(1).value();
    expect_false(check(-1) is Ok);
    expect_equal(check(-1).error().message, "negative");
}

# A struct `TValue` flows through ok and value into a second reference; the
# runner's leak check confirms no leak and no double free.
[Test]
struct_value_refcount_balanced() {
    var r = Result<Point>.ok(Point(7));
    var p = r.value();
    expect_equal(p.x, 7);
}

# Ok and Err of Result<void>, and a function returning one: `ok()` takes no
# argument and `value()` only checks.
[Test]
void_value() {
    var ok = check_good(true);
    expect_true(ok.is_ok());
    ok.value();
    var err = check_good(false);
    expect_true(err.is_err());
    expect_equal(err.error().message, "bad");
}
