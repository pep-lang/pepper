# A value enum: stored inline and copied, never null.

[Value]
enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Point,
}

struct Drawing {
    var shape: Shape;
}

main(): int {
    # The tag, then every case's values in their own fields: radius, width
    # and height, four bytes each.
    assert(sizeof<Shape>() == 16, "tag + radius + width + height");
    # A field never given a value holds the first case, with its values zero.
    var drawing = Drawing();
    assert(drawing.shape == Shape.Circle(0), "an unset Shape is Circle(0)");
    var copy = drawing.shape;
    drawing.shape = Shape.Rect(2, 3);
    assert(copy == Shape.Circle(0), "a copy keeps its own value");
    return 0;
}
