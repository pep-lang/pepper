# Floating-point numbers and tuples have text too.
main(): int {
    var price = 4.5;
    var ratio = 1.0 / 3.0;
    assert($"{price}" == "4.5", "the shortest text that reads back");
    assert($"{2.0}" == "2.0", "a whole number keeps its point");
    assert($"{1.0e20}" == "1e+20", "large numbers use an exponent");
    assert($"{ratio:.3}" == "0.333", "a precision rounds to that many digits");
    assert($"[{price:8.2}]" == "[    4.50]", "numbers align right");
    assert($"{price:+08.2}" == "+0004.50", "with a sign and zeros");

    var point = (3, "north");
    assert($"{point}" == "(3, north)", "a tuple's elements in parentheses");
    print("{0} at {1:.1}", point, price);   # (3, north) at 4.5
    return 0;
}

# Output:
# (3, north) at 4.5
