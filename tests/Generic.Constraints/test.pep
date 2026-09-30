# Generic parameters constrained by traits: struct, function, method, alias
# and generic trait constraints, several constraints joined with `&`, a
# constrained default, a trait type as the argument, and a generic struct
# that conforms through `extend Wrap<T> with Shape`.

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

extend Circle with Shape {}

struct Square {
    var side: int = 2;
    area(): int { return side * side; }
    name(): String { return "square"; }
}

extend Square with Shape {}
extend Square with Named {}

struct Wrap<T> {
    var inner: T;
    area(): int { return 5; }
}

extend Wrap<T> with Shape {}

struct Gallery<T: Shape> {
    var items = Array<T>();
    add(item: T) { items.append(item); }
    total(): int { return total_area(items); }
    largest<U: Shape>(other: U): int {
        var own = total();
        return own > other.area() ? own : other.area();
    }
}

struct Frame<TTag, TShape: Shape = Square> {
    var shape: TShape;
}

type Shapes<T: Shape> = Array<T>;

total_area<T: Shape>(shapes: Array<T>): int {
    var sum = 0;
    for (var shape in shapes) {
        sum += shape.area();
    }
    return sum;
}

describe<T: Shape & Named>(item: T): String { return item.name(); }

wrap<T: Shape>(item: T): Gallery<T> {
    var g = Gallery<T>();
    g.add(item);
    return g;
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

sum<I: Iterator<int>>(values: I): int {
    var s = 0;
    while (values.next()) {
        s += values.current();
    }
    return s;
}

struct Version {
    var number: int;
    construct(this.number = 0) {}
    <(other: Version): bool { return number < other.number; }
}

main(): int {
    var circles = Array<Circle>();
    circles.append(Circle());
    circles.append(Circle());
    if (total_area(circles) != 6) {
        return 1;
    }
    var g = Gallery<Circle>();
    g.add(Circle());
    if (g.total() != 3 or g.largest(Square()) != 4) {
        return 2;
    }
    var f = Frame<int>();
    f.shape = Square();
    if (f.shape.area() != 4) {
        return 3;
    }
    if (describe(Square()) != "square") {
        return 4;
    }
    if (wrap(Circle()).total() != 3) {
        return 5;
    }
    var shapes = Array<Shape>();
    shapes.append(Circle());
    shapes.append(Square());
    if (total_area(shapes) != 7) {
        return 6;
    }
    var wrapped = Shapes<Wrap<int>>();
    wrapped.append(Wrap<int>());
    if (total_area(wrapped) != 5) {
        return 7;
    }
    if (sum(Counter()) != 6) {
        return 8;
    }
    # A struct's own operator is not a generic method call.
    if (!(Version(1) < Version(2))) {
        return 9;
    }
    return 0;
}
