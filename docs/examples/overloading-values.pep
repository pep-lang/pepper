# An overloaded function used as a value, and closures passed to overloads.

twice(n: int): int { return n * 2; }
twice(s: String): String { return s + s; }

apply(f: (int) => int, n: int): int { return f(n); }

# Overloads that differ in the type of a function parameter.
run(f: (int) => int): int { return f(10); }
run(f: (int, int) => int): int { return f(10, 20); }

main(): int {
    # The declared type picks the overload.
    var doubler: (int) => int = twice;
    assert(doubler(4) == 8, "twice(int)");

    # So does the parameter it is passed to.
    assert(apply(twice, 5) == 10, "twice(int) again");

    # A closure without parameter types picks the overload of its arity.
    assert(run((a) => a + 1) == 11, "one parameter");
    assert(run((a, b) => a + b) == 30, "two parameters");
    return 0;
}
