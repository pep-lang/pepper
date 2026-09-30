# Cases that carry values: each case is a constructor, and a `match`
# pattern binds the values of the case it matches.
enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Square(side: int),
    Point,

    area(): int {
        match (this) {
            Circle(r) => { return 3 * r * r; }
            Rect(w, h) => { return w * h; }
            Square(s) => { return s * s; }
            Point => { return 0; }
        }
        return 0;
    }
}

# A generic enum can name itself: a list is empty, or a value and the rest.
enum List<T> {
    Empty,
    Cons(head: T, tail: List<T>),
}

length(list: List<String>): int {
    match (list) {
        Empty => { return 0; }
        # `_` skips a value.
        Cons(_, tail) => { return 1 + length(tail); }
    }
    return 0;
}

main(): int {
    var shapes = Array<Shape>();
    shapes.append(Shape.Circle(2));
    shapes.append(Shape.Rect(3, 4));
    shapes.append(Shape.Point);
    var total = 0;
    for (var s in shapes) {
        total += s.area();
    }
    assert(total == 24, "12 + 12 + 0");

    # Several patterns in one arm bind the same names.
    var side = 0;
    match (Shape.Square(5)) {
        Rect(w, _), Square(w) => { side = w; }
        else => {}
    }
    assert(side == 5, "a square's side");

    var names = List<String>.Cons("a", List<String>.Cons("b", List<String>.Empty));
    assert(length(names) == 2, "two names");
    assert(names.name() == "Cons", "name() spells the case");
    return 0;
}
