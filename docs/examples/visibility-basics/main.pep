import "lib";

main(): int {
    var p = at(3, 4);             # exported function
    var o: Point = origin();      # exported struct, used as a type
    Points list = Points();       # exported type alias
    list.append(p);
    list.append(o);

    assert(p.x == 3, "fields are as visible as their struct");
    assert(p.describe() == "point", "method from an exported extension");
    assert(norm_of(p) == 25, "an exported function may use private helpers");
    assert(points_made.load() == 2, "exported module variable");
    assert(platform_name().length > 0, "exported, with an attribute");
    return 0;
}
