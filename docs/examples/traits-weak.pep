# A weak reference can point at a trait value: it keeps the struct behind
# it without keeping it alive.
trait Shape {
    area(): int;
}

struct Square {
    var side: int = 1;
    construct(this.side = 1) {}
}

extend Square with Shape {
    area(): int { return side * side; }
}

main(): int {
    var shape: Shape = Square(3);
    var weak = Weak<Shape>(shape);

    # While a strong reference is left, `with` reaches the value as a Shape.
    with (var live = weak) {
        assert(live.area() == 9, "upgraded to a Shape");
    } else {
        assert(false, "still alive");
    }

    # Once the last strong reference goes, the Square is destroyed.
    shape = __null;
    assert(weak.expired(), "destroyed");
    with (var live = weak) {
        assert(false, "expired: the body is skipped");
    }
    return 0;
}
