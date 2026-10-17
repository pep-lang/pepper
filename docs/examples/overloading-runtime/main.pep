import "point";

# The file's own `to_string` joins the runtime's.
to_string(p: Point): String {
    return $"Point({p.x}, {p.y})";
}

main(): int {
    var p = Point(1, 2);
    print(p);       # point's member
    print("text");  # the runtime's member
    assert(to_string(p) == "Point(1, 2)", "this file's member");
    assert(to_string(42) == "42", "the runtime's member");
    return 0;
}
