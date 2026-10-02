# Branch hints: `[Likely]` and `[Unlikely]` say which way a branch usually
# goes, so the optimizer keeps the common path straight.
enum Reading {
    Value(celsius: double),
    Missing,
}

parse_digit(c: char): int {
    [Unlikely]
    if (c < '0' || c > '9') {
        return -1;
    } else [Likely] if (c != '0') {
        return c - '0';
    }
    return 0;
}

describe(reading: Reading): String {
    match (reading) {
        [Likely]
        Value(celsius) => {
            return $"{celsius}";
        }
        [Unlikely]
        Missing => {
            return "missing";
        }
    }
}

main(): int {
    assert(parse_digit('7') == 7, "a digit");
    assert(parse_digit('x') == -1, "not a digit");
    assert(describe(Reading.Missing) == "missing", "the rare arm still runs");
    return 0;
}
