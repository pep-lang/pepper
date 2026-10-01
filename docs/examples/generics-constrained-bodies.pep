trait Shape {
    area(): int;
    scaled(by: int): this;
    static unit(): this;
}

trait Ordered {
    <(other: this): bool;
}

struct Square {
    var side: int = 1;
    construct(this.side = 1) {}
    area(): int { return side * side; }
    scaled(by: int): Square { return Square(side * by); }
    static unit(): Square { return Square(1); }
    <(other: Square): bool { return side < other.side; }
}

extend Square with Shape;
extend Square with Ordered;

# Inside the body, a T offers what Shape and Ordered declare.
largest<T: Shape & Ordered>(items: Array<T>): T {
    var best = items[0];
    for (var item in items) {
        if (best < item) {
            best = item;
        }
    }
    return best;
}

# Static members are called through the parameter.
unit_area<T: Shape>(): int { return T.unit().area(); }

# A T converts to the trait types of its constraints.
as_shape<T: Shape>(item: T): Shape {
    var shape: Shape = item.scaled(2);
    return shape;
}

main(): int {
    var squares = Array<Square>();
    squares.append(Square(2));
    squares.append(Square(3));
    assert(largest(squares).side == 3, "largest");
    assert(unit_area<Square>() == 1, "static member");
    assert(as_shape(Square(3)).area() == 36, "conversion");
    return 0;
}
