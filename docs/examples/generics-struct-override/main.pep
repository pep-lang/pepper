import "shapes";

struct Point {
    var x: int;
    var y: int;
}

# Overrides shapes.pep's describe<T> for Point, from another file.
describe<Point>(p: Point): int {
    return p.x + p.y;
}

main(): int {
    var p = Point();
    p.x = 3;
    p.y = 4;
    assert(describe<Point>(p) == 7, "the override");
    assert(describe_twice<Point>(p) == 14, "generic code in shapes.pep uses it too");
    assert(describe<int>(5) == 0, "other types keep the generic version");

    # The standard library's generics, such as hash<T>, can be overridden
    # for a struct the same way.
    return 0;
}
