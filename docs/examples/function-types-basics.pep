# Function types and references to named functions.
square(x: int): int { return x * x; }
negate(x: int): int { return -x; }

# A parameter can take a function: its type is '(parameter types) => return type'.
apply(f: (int) => int, x: int): int {
    return f(x);
}

twice(f: (int) => int, x: int): int {
    return f(f(x));
}

# Generic functions can take function values too.
apply_twice<T>(f: (T) => T, x: T): T {
    return f(f(x));
}

main(): int {
    # A function's name without a call is a value of its function type.
    var f = square;                 # f: (int) => int
    assert(f(3) == 9, "call through a local");

    var g: (int) => int = negate;   # the type can be written out
    assert(g(4) == -4, "explicit function type");

    # Function variables can be reassigned to another function of the same type.
    f = negate;
    assert(f(6) == -6, "reassigned");

    assert(apply(square, 5) == 25, "pass a function as an argument");
    assert(twice(square, 3) == 81, "(3 * 3) * (3 * 3)");
    assert(twice(negate, 7) == 7, "negating twice");
    assert(apply_twice<int>(square, 2) == 16, "generic");
    return 0;
}
