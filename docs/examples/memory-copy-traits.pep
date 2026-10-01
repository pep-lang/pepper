# `copy` of a trait value copies the struct behind it, whichever it is.
trait Shape {
    area(): int;
    grow();
}

struct Square {
    var side: int = 1;
    construct(this.side = 1) {}
}

extend Square with Shape {
    area(): int { return side * side; }
    grow() { side = side + 1; }
}

struct Rect {
    var width: int = 1;
    var height: int = 1;
    construct(this.width = 1, this.height = 1) {}
}

extend Rect with Shape {
    area(): int { return width * height; }
    grow() { width = width + 1; }
}

main(): int {
    var shapes = Array<Shape>();
    var square = Square(2);
    shapes.append(square);
    shapes.append(Rect(2, 3));
    shapes.append(square);

    var copied = copy(shapes);
    for (var shape in copied) {
        shape.grow();
    }
    assert(shapes[0].area() == 4, "the original Square is unchanged");
    assert(shapes[1].area() == 6, "the original Rect is unchanged");

    # The Square appears twice, so its copy is one object, grown twice.
    assert(copied[0] == copied[2], "one copy of the shared Square");
    assert(copied[0].area() == 16, "the copied Square grew twice");
    assert(copied[1].area() == 9, "the copied Rect grew once");
    return 0;
}
