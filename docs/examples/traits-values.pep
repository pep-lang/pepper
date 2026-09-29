# A trait used as a type holds any struct that declares the trait.
trait Shape {
    area(): int;
    name(): String;
}

struct Square {
    var side: int = 1;
    construct(this.side = 1) {}
}

extend Square with Shape {
    area(): int { return side * side; }
    name(): String { return "square"; }
}

struct Rect {
    var width: int = 1;
    var height: int = 1;
    construct(this.width = 1, this.height = 1) {}
}

extend Rect with Shape {
    area(): int { return width * height; }
    name(): String { return "rect"; }
}

# One function accepts every Shape; each call runs the value's own method.
measure(shape: Shape): int {
    return shape.area();
}

main(): int {
    # A Square converts to a Shape wherever a Shape is expected.
    var s: Shape = Square(3);
    assert(measure(s) == 9, "square through a trait parameter");
    assert(s.name() == "square", "method of the concrete type");

    # Collections can hold different types that share a trait.
    var shapes = Array<Shape>();
    shapes.append(Square(2));
    shapes.append(Rect(2, 5));
    var total = 0;
    for (var shape in shapes) {
        total = total + shape.area();
    }
    assert(total == 14, "sum of areas");

    # Two trait values are equal when they refer to the same object.
    var same: Shape = s;
    assert(same == s, "same object");
    return 0;
}
