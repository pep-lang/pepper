struct Point {
    var x: int = 0;
    var y: int = 0;

    # `this.x = 0` as a parameter stores the argument straight into the field.
    construct(this.x = 0, this.y = 0) {}

    length_squared(): int {
        return this.x * this.x + this.y * this.y;
    }

    move_by(dx: int, dy: int) {
        this.x = this.x + dx;
        this.y = this.y + dy;
    }
}

# An extension adds methods to a struct that is declared elsewhere.
extend Point {
    swapped(): Point {
        return Point(this.y, this.x);
    }
}

main(): int {
    var p = Point(3, 4);
    assert(p.length_squared() == 25, "3*3 + 4*4");

    var origin = Point();
    assert(origin.x == 0 && origin.y == 0, "defaults from the constructor");

    # Struct values are references: q and p name the same Point.
    var q = p;
    q.move_by(1, 1);
    assert(p.x == 4 && p.y == 5, "p sees the move made through q");

    var s = p.swapped();
    assert(s.x == 5 && s.y == 4, "swapped is a new Point");
    assert(p.x == 4, "p itself is unchanged");
    return 0;
}
