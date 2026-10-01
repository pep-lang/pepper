trait Shape {
    area(): int;
}

trait Named {
    name(): String;
}

struct Circle {
    var radius: int = 1;
    area(): int { return 3 * radius * radius; }
}

extend Circle with Shape;

struct Square {
    var side: int = 2;
    area(): int { return side * side; }
    name(): String { return "square"; }
}

extend Square with Shape;
extend Square with Named;

# Every T must conform to Shape.
total_area<T: Shape>(shapes: Array<T>): int {
    var sum = 0;
    for (var shape in shapes) {
        sum += shape.area();
    }
    return sum;
}

# Several constraints are joined with `&`.
label<T: Shape & Named>(item: T): String { return item.name(); }

# A constrained parameter can have a default, which must conform too.
struct Gallery<TTag, TShape: Shape = Square> {
    var items = Array<TShape>();
    add(item: TShape) { items.append(item); }
    total(): int { return total_area(items); }
}

main(): int {
    var circles = Array<Circle>();
    circles.append(Circle());
    circles.append(Circle());
    assert(total_area(circles) == 6, "circles");
    assert(label(Square()) == "square", "label");

    # Gallery<String> is Gallery<String, Square>.
    var gallery = Gallery<String>();
    gallery.add(Square());
    assert(gallery.total() == 4, "default");

    # A trait type conforms to its own trait.
    var shapes = Array<Shape>();
    shapes.append(Circle());
    shapes.append(Square());
    assert(total_area(shapes) == 7, "trait values");
    return 0;
}
