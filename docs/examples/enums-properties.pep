# An enum can declare computed properties after its cases, read like
# fields: `size.ounces`, not `size.ounces()`.
enum Size {
    Small,
    Medium,
    Large,

    var ounces: int {
        get {
            return match (this) {
                Small => 8,
                Medium => 12,
                Large => 16,
            };
        }
    }

    # Inside the enum, a bare property name reads it on `this`.
    var cups: int {
        get { return ounces / 8; }
    }
}

# The same works for an enum whose cases carry values.
enum Shape {
    Circle(radius: int),
    Square(side: int),

    var area: int {
        get {
            return match (this) {
                Circle(r) => 3 * r * r,
                Square(s) => s * s,
            };
        }
    }
}

main(): int {
    var size = Size.Medium;
    assert(size.ounces == 12 && Size.Large.cups == 2, "value enum properties");
    assert(Shape.Square(4).area == 16 && Shape.Circle(2).area == 12, "properties that read the payload");
    return 0;
}
