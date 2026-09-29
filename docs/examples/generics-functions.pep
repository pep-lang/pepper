larger<T>(a: T, b: T): T {
    if (a > b) {
        return a;
    }
    return b;
}

struct Circle {
    var radius: int = 1;
    area(): int { return 3 * radius * radius; }
}

struct Square {
    var side: int = 2;
    area(): int { return side * side; }
}

# The body can use anything the type argument provides: this works for
# any T that has an `area()` method returning a number.
total_area<T>(shapes: Array<T>): int {
    var sum = 0;
    for (var shape in shapes) {
        sum += shape.area();
    }
    return sum;
}

main(): int {
    # Type arguments are written explicitly at the call.
    assert(larger<int>(3, 9) == 9, "ints");
    assert(larger<float>(2.5, 1.5) == 2.5, "floats");

    var circles = Array<Circle>();
    circles.append(Circle());
    circles.append(Circle());
    assert(total_area<Circle>(circles) == 6, "circles");

    var squares = Array<Square>();
    squares.append(Square());
    assert(total_area<Square>(squares) == 4, "squares");
    return 0;
}
