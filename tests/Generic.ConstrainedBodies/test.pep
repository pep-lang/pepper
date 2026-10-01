# What the body of a constrained generic may do with a value of its
# constrained type: call the constraints' instance methods and operators,
# call their static members through the parameter, convert to a constraint's
# trait type, and store, pass, return and compare it.

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

extend Square with Shape {}
extend Square with Ordered {}

struct Pair<T: Shape & Ordered> {
    var first: T;
    var second: T;

    construct(a: T, b: T) {
        first = a;
        second = b;
    }

    larger(): T { return first < second ? second : first; }
    total(): int { return first.area() + second.area(); }
}

biggest<T: Shape & Ordered>(items: Array<T>): T {
    var best = items[0];
    for (var item in items) {
        if (best < item) {
            best = item;
        }
    }
    return best;
}

grow<T: Shape>(item: T): T { return item.scaled(2); }

unit_area<T: Shape>(item: T): int { return T.unit().area(); }

as_shape<T: Shape>(item: T): Shape {
    var shape: Shape = item;
    return shape;
}

same<T: Shape>(a: T, b: T): bool { return a === b; }

sum<I: Iterator<int>>(values: I): int {
    var total = 0;
    while (values.next()) {
        total += values.current();
    }
    return total;
}

struct Counter {
    var n = 0;
    next(): bool {
        n++;
        return n < 4;
    }
    current(): int { return n; }
}

extend Counter with Iterator<int> {}

trait Maker {
    static make(): this;
    size(): int;
}

struct Crate<T> {
    var count: int = 7;
    static make(): Crate<T> { return Crate<T>(); }
    size(): int { return count; }
}

extend Crate<T> with Maker {}

build<T: Maker>(): int { return T.make().size(); }

main(): int {
    var squares = Array<Square>();
    squares.append(Square(2));
    squares.append(Square(3));
    squares.append(Square(1));
    if (biggest(squares).side != 3) {
        return 1;
    }
    if (grow(Square(2)).side != 4) {
        return 2;
    }
    if (unit_area(Square(5)) != 1) {
        return 3;
    }
    if (as_shape(Square(3)).area() != 9) {
        return 4;
    }
    var s = Square(2);
    if (!same(s, s) or same(s, Square(2))) {
        return 5;
    }
    var pair = Pair<Square>(Square(2), Square(3));
    if (pair.larger().side != 3 or pair.total() != 13) {
        return 6;
    }
    if (sum(Counter()) != 6) {
        return 7;
    }
    if (build<Crate<int>>() != 7) {
        return 8;
    }
    return 0;
}
