# A function lists its parameters as `name: type` and gives its return
# type after the closing parenthesis.
square(x: int): int {
    return x * x;
}

# A parameter may have a default value, used when the caller leaves it out.
greet(name: String = "world"): String {
    return "Hello, " + name + "!";
}

# Adds up 1 + 2 + ... + n with a while loop.
sum_to(n: int): int {
    var total = 0;
    var i = 1;
    while i <= n {
        total += i;
        i = i + 1;
    }
    return total;
}

describe(n: int): String {
    if n > 100 {
        return "big";
    } else {
        if n > 10 {
            return "medium";
        }
    }
    return "small";
}

main(): int {
    var answer = 42;          # the type, int, comes from the value
    double ratio = 0.5;       # or write the type yourself
    var whole = (ratio * 10.0) as int;
    assert(whole == 5, "'as' converts between number types");

    assert(square(answer) == 1764, "square(42)");
    assert(greet() == "Hello, world!", "the default name");
    assert(greet("Pepper") == "Hello, Pepper!", "an explicit name");
    assert(sum_to(4) == 10, "1 + 2 + 3 + 4");

    assert(describe(answer) == "medium", "42 is medium");
    assert(describe(7) == "small", "7 is small");

    print(greet("Pepper"));
    print($"{sum_to(100)}");
    return 0;
}
