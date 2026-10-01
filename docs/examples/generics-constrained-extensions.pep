trait Shape {
    area(): int;
}

trait Named {
    name(): String;
}

struct Square {
    area(): int { return 4; }
    name(): String { return "square"; }
}

extend Square with Shape;
extend Square with Named;

struct Box<T> {
    var item: T;
    construct(item: T) { this.item = item; }
}

# Only a Box of something Named has `label()`.
extend Box<T: Named> {
    label(): String { return "box of " + item.name(); }
}

# A Box of shapes is itself a shape.
extend Box<T: Shape> with Shape {
    area(): int { return item.area() * 2; }
}

main(): int {
    var box = Box<Square>(Square());
    assert(box.label() == "box of square", "constrained extension");

    Shape shape = box;
    assert(shape.area() == 8, "conditional conformance");

    # Box<String> is still a Box, without `label()` or `area()`.
    var text = Box<String>("plain");
    assert(text.item == "plain", "any Box");
    return 0;
}
