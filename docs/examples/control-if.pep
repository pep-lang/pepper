# Branching with if and else.
classify(n: int): String {
    if n < 0 {
        return "negative";
    } else {
        if n == 0 {
            return "zero";
        }
    }
    return "positive";
}

main(): int {
    var temperature = 25;

    # Parentheses around the condition are optional; braces are required.
    if temperature > 30 {
        print("hot");
    } else {
        print("not hot");
    }

    if (temperature > 20) {
        temperature = 20;
    }
    assert(temperature == 20, "clamped to 20");

    assert(classify(-5) == "negative", "negative");
    assert(classify(0) == "zero", "zero");
    assert(classify(7) == "positive", "positive");

    # For a choice between two values, the ternary operator is shorter.
    var parity = temperature % 2 == 0 ? "even" : "odd";
    assert(parity == "even", "20 is even");

    # && and || evaluate both operands, so guard a check that could fail
    # with a nested if rather than with &&.
    var readings = Array<int>();
    var starts_high = false;
    if (readings.count() > 0) {
        if (readings[0] > 100) {
            starts_high = true;
        }
    }
    assert(!starts_high, "an empty array does not start high");
    return 0;
}
