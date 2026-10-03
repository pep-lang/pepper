## Checks for tests: `expect_equal`, `expect_not_equal`, `expect_true` and
## `expect_false`, which every program can call without an import. Each
## panics when its check fails, as `assert` does, but reports the values it
## compared, at the line of the call:
##
##     math_test.pep:12:5: panic: expect_equal failed
##       actual:   3
##       expected: 4
##
## A `[Test]` function fails on that panic (see the testing chapter).

## Panics unless `actual == expected`, reporting both values.
##
## @typeParam T the type of the values; it needs `==` and a text form
##   (see `to_string`)
## @param actual the value the code under test produced
## @param expected the value it should have produced
## @panics if the values differ: prints the location of the call and both
##   values, and aborts (see `panic`)
## @example
##     var numbers = Array<int>();
##     numbers.append(1);
##     expect_equal(numbers.count, 1);
export expect_equal<T>(actual: T, expected: T, location: __ptr<char> = __caller_location()) {
    if (!(actual == expected)) {
        panic($"expect_equal failed\n  actual:   {actual}\n  expected: {expected}", location);
    }
}

## Panics if `actual == unexpected`, reporting the value.
##
## @typeParam T the type of the values; it needs `==` and a text form
##   (see `to_string`)
## @param actual the value the code under test produced
## @param unexpected the value it must not be
## @panics if the values are equal: prints the location of the call and the
##   value, and aborts (see `panic`)
## @example
##     expect_not_equal("a".repeat(2), "a");
export expect_not_equal<T>(actual: T, unexpected: T, location: __ptr<char> = __caller_location()) {
    if (actual == unexpected) {
        panic($"expect_not_equal failed\n  both: {actual}", location);
    }
}

## Panics unless `condition` holds. Unlike `assert`, it needs no message:
## the location names the check.
##
## @param condition the condition that must hold
## @panics if `condition` is false: prints the location of the call, and
##   aborts (see `panic`)
## @example
##     expect_true("pepper".starts_with("pep"));
export expect_true(condition: bool, location: __ptr<char> = __caller_location()) {
    if (!condition) {
        panic("expect_true failed: the condition is false", location);
    }
}

## Panics if `condition` holds.
##
## @param condition the condition that must not hold
## @panics if `condition` is true: prints the location of the call, and
##   aborts (see `panic`)
## @example
##     expect_false("pepper".is_empty);
export expect_false(condition: bool, location: __ptr<char> = __caller_location()) {
    if (condition) {
        panic("expect_false failed: the condition is true", location);
    }
}
