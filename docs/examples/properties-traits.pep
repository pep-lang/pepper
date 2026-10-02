# A trait can require a property; a struct meets it with a property of the
# same name and type.
trait Shape {
    var area: double { get; }
    var label: String { get; set; }
}

struct Square {
    var side: double { get; set; } = 1.0;
    var area: double {
        get {
            return side * side;
        }
    }
    var label: String { get; set; } = "square";
}

extend Square with Shape;

# An extension can add computed properties, which need no storage.
extend Square {
    var perimeter: double {
        get {
            return side * 4.0;
        }
    }
}

describe(shape: Shape): String {
    shape.label = "seen";
    return $"{shape.label}: {shape.area}";
}

main(): int {
    var square = Square();
    square.side = 3.0;
    assert(square.area == 9.0, "the computed area follows the side");
    assert(square.perimeter == 12.0, "an extension's property reads like any other");
    assert(describe(square) == "seen: 9.0", "a trait value reaches the struct's accessors");
    assert(square.label == "seen", "the set through the trait reached the struct");
    return 0;
}
