# A struct is interpolated through its to_string() method.
struct Point {
    var x: int = 0;
    var y: int = 0;
    construct(this.x = 0, this.y = 0) {}
}

extend Point with ToString {
    to_string(): String {
        # Inside a method, fields are names too.
        return $"({x}, {y})";
    }
}

# A type without the method gets a to_string<T> override instead.
struct Celsius {
    var degrees: int = 0;
    construct(this.degrees = 0) {}
}

to_string<Celsius>(value: Celsius): String {
    return $"{value.degrees} C";
}

main(): int {
    var start = Point(1, 2);
    var reading = Celsius(21);
    assert($"from {start}" == "from (1, 2)", "ToString");
    assert($"it is {reading}" == "it is 21 C", "override");

    # A trait value converts through the value's own method.
    var shown: ToString = start;
    assert($"{shown}" == "(1, 2)", "trait value");
    return 0;
}
