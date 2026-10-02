# Reporting the caller's location with `__caller_location()`.

# A check that names its caller's line when it fails, the way `assert`,
# `panic`, `Array` indexing and `Optional.value()` do: the default is the
# location of the call that leaves `location` out.
check_positive(value: int, location: __ptr<char> = __caller_location()): int {
    assert(value > 0, "expected a positive value", location);
    return value;
}

# The location is a C string, `file:line:col`.
here(location: __ptr<char> = __caller_location()): String {
    return String(location);
}

main(): int {
    assert(check_positive(3) == 3, "positive");
    var at = here();
    assert(at.ends_with("functions-caller-location.pep:18:14"), "this call");
    return 0;
}
