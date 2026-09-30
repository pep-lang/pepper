# A function returns several values as a tuple.
divide(a: int, b: int): (int, int) {
    return (a / b, a % b);
}

# Elements can be of any type, and a tuple can hold another tuple.
describe(n: int): (String, (bool, int)) {
    return ("number", (n % 2 == 0, n * n));
}

main(): int {
    # Read elements by position: t.0, t.1, ...
    var t = divide(17, 5);
    assert(t.0 == 3, "the quotient");
    assert(t.1 == 2, "the remainder");

    # Nested tuples chain: d.1.0 is element 0 of element 1.
    var d = describe(4);
    assert(d.0 == "number", "the name");
    assert(d.1.0 && d.1.1 == 16, "even, and its square");

    # A tuple type can be written out; the literal converts to it.
    var wide: (long, double) = (1, 2);
    assert(wide.0 == 1 && wide.1 == 2.0, "converted elements");
    return 0;
}
