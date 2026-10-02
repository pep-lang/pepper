# Methods, constructors and generic functions used as values.
struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}

    norm(): int {
        return x + y;
    }

    shifted(dx: int): Point {
        return Point(x + dx, y);
    }

    # Inside a method, a bare method name is `this.norm`.
    norm_of_this(): () => int {
        return norm;
    }
}

larger<T>(a: T, b: T): T {
    return a > b ? a : b;
}

combine(f: (int, int) => int, a: int, b: int): int {
    return f(a, b);
}

main(): int {
    var p = Point(3, 4);

    # A bound method: the method of one object, which it keeps alive.
    var norm = p.norm;
    assert(norm() == 7, "bound method");
    assert(p.norm_of_this()() == 7, "bare method name");

    # An unbound method takes the object as its first argument.
    var norm_of: (Point) => int = Point.norm;
    assert(norm_of(Point(1, 1)) == 2, "unbound method");

    # A struct's name is its constructor.
    var make: (int, int) => Point = Point;
    assert(make(5, 6).y == 6, "constructor");

    # A generic function with its type arguments names one specialization.
    assert(combine(larger<int>, 2, 9) == 9, "generic function");

    var steps = Array<(int) => Point>();
    steps.append(p.shifted);
    steps.append(Point(10, 0).shifted);
    assert(steps[1](5).x == 15, "methods in an array");
    return 0;
}
