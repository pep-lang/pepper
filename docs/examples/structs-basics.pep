# A struct groups related values into one type.
struct Point {
    var x: int = 0;
    var y: int = 0;
}

# Fields can also be declared C-style, with the type first.
struct Counter {
    int count;          # no initializer: starts at zero
    String label = "clicks";
}

main(): int {
    # Without a constructor, `Point()` makes a Point with every field
    # at its initial value.
    var p = Point();
    assert(p.x == 0 && p.y == 0, "fields start at their initializers");

    p.x = 3;
    p.y = 4;
    assert(p.x * p.x + p.y * p.y == 25, "fields can be read and written");

    var c = Counter();
    assert(c.count == 0, "a numeric field without an initializer is zero");
    assert(c.label == "clicks", "a String field can have an initializer");

    # A struct value is a reference: `q` names the same Point as `p`.
    var q = p;
    q.x = 10;
    assert(p.x == 10, "p and q are the same object");
    assert(p === q, "=== tests whether two references name the same object");
    assert(!(p === Point()), "a new Point is a different object");
    return 0;
}
