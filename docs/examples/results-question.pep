# `?` propagates a failure: on an Err it returns that error from the
# enclosing function, and on an Ok it is the value.
struct ParseError {
    String input;

    construct(this.input = "") {}
}

parse_number(text: String): Result<int, ParseError> {
    if (text.is_empty) {
        return Result<int, ParseError>.err(ParseError(text));
    }
    var value = 0;
    for (var c in text) {
        var digit = "0123456789".find(c);
        if (digit < 0) {
            return Result<int, ParseError>.err(ParseError(text));
        }
        value = value * 10 + (digit as int);
    }
    return Result<int, ParseError>.ok(value);
}

# Each `?` returns early with the error, so the sum is computed only when
# both numbers parse.
add_numbers(a: String, b: String): Result<int, ParseError> {
    return Result<int, ParseError>.ok(parse_number(a)? + parse_number(b)?);
}

# A function with a different error type: the `[Implicit]` constructor
# converts a ParseError on its way out.
struct ConfigError {
    String message;

    [Implicit]
    construct(e: ParseError) {
        this.message = "bad number '" + e.input + "'";
    }
}

read_limit(text: String): Result<int, ConfigError> {
    var limit = parse_number(text)?;
    if (limit == 0) {
        return Result<int, ConfigError>.err(ConfigError(ParseError(text)));
    }
    return Result<int, ConfigError>.ok(limit);
}

first_name(names: Array<String>): String? {
    if (names.is_empty) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(names[0]);
}

# On an Optional, `?` returns an Empty optional from a function that returns
# one.
first_length(names: Array<String>): ulong? {
    return Optional<ulong>.Value(first_name(names)?.length);
}

main(): int {
    assert(add_numbers("40", "2").value() == 42, "40 + 2");
    assert(add_numbers("40", "4x2").error().input == "4x2", "the error is the second number's");

    assert(read_limit("10").value() == 10, "a limit");
    assert(read_limit("ten").error().message == "bad number 'ten'", "converted to a ConfigError");

    assert(first_length(["Ada", "Grace"]).value() == 3, "Ada");
    assert(first_length(Array<String>()).is_empty(), "no names");
    return 0;
}
