# A trait value converts back to the struct it holds, or to another trait
# that struct declares, with `is`, `match` and `as?`.
trait Shape {
    area(): int;
}

trait Named {
    name(): String;
}

struct Square {
    var side: int = 1;
    construct(this.side = 1) {}
}

extend Square with Shape {
    area(): int { return side * side; }
}

extend Square with Named {
    name(): String { return "square"; }
}

struct Rect {
    var width: int = 1;
    var height: int = 1;
    construct(this.width = 1, this.height = 1) {}
}

extend Rect with Shape {
    area(): int { return width * height; }
}

# A type pattern tests for a struct and binds the value as that struct.
describe(shape: Shape): String {
    return match (shape) {
        Square(square) => $"a square of side {square.side}",
        Rect(rect) => $"a {rect.width} by {rect.height} rectangle",
        else => "another shape",
    };
}

main(): int {
    var shape: Shape = Square(3);
    assert(describe(shape) == "a square of side 3", "match on the struct");
    assert(describe(Rect(2, 5)) == "a 2 by 5 rectangle", "another struct");

    # `is` tests without converting; as an `if` condition it can bind.
    assert(shape is Square, "a square");
    assert(!(shape is Rect), "not a rectangle");
    if (shape is Square(square)) {
        assert(square.side == 3, "bound as a Square");
    }

    # `as?` gives an optional: Empty when the value is something else.
    var square = shape as? Square;
    assert(square.value().side == 3, "converted to Square");
    var rect = shape as? Rect;
    assert(rect.is_empty(), "not a Rect");

    # Converting to another trait works when the struct declares both.
    var named = shape as? Named;
    assert(named.value().name() == "square", "a Square is Named");
    var other: Shape = Rect(1, 1);
    assert((other as? Named).is_empty(), "a Rect is not Named");
    return 0;
}
