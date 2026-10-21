# Shadowing: a name declared in an inner scope hides the outer one until
# that scope ends. A function's parameters share its body's outermost
# scope, so `var count = 0;` there would be a redefinition of 'count'.

enum Shape {
    Circle(radius: int),
    Square(side: int),
}

# A loop variable and a block's local live in scopes of their own.
sum_below(count: int): int {
    var total = 0;
    for (var count in 0..3) {
        total += count as int;
    }
    {
        var count = 100;
        total += count;
    }
    return total + count;
}

# A match arm binds its names in the arm's scope.
size(radius: int, shape: Shape): int {
    match (shape) {
        Circle(radius) => {
            return radius;
        }
        Square(side) => {
            return side + radius;
        }
    }
}

# So does an `is` pattern, in the block it guards.
first_or(value: int, found: int?): int {
    if (found is Value(value)) {
        return value;
    }
    return value;
}

# A closure's parameter hides a local of the function it is written in.
twice_plus(offset: int): int {
    var value = 4;
    var twice = (value: int) => value * 2;
    return twice(offset) + value;
}

main(): int {
    assert(sum_below(5) == 108, "0 + 1 + 2, the block's 100, and the parameter's 5");
    assert(size(1, Shape.Circle(7)) == 7, "the arm's radius hides the parameter");
    assert(size(1, Shape.Square(2)) == 3, "the parameter is visible in the other arm");
    assert(first_or(1, Optional<int>.Value(9)) == 9, "the pattern's value hides the parameter");
    assert(first_or(1, Optional<int>.Empty) == 1, "the parameter is back after the block");
    assert(twice_plus(3) == 10, "the closure's value is its argument; the local is still 4");
    return 0;
}
