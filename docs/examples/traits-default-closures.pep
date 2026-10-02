# A closure in a trait's default method can use `this` and the trait's
# methods.
trait Shape {
    area(): int;

    # Every type with Shape gets this method, and its own copy of the
    # closure, which captures `this`.
    scaled_area(): (int) => int {
        return (factor: int) => area() * factor;
    }
}

struct Square {
    var side: int = 1;
    construct(this.side = 1) {}
}

extend Square with Shape {
    area(): int {
        return side * side;
    }
}

main(): int {
    var square = Square(3);
    var scale = square.scaled_area();
    assert(scale(2) == 18, "closure in a default method");

    # The closure keeps the square alive and sees its current side.
    square.side = 4;
    assert(scale(2) == 32, "sees the current value");
    return 0;
}
