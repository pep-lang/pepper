import "shapes";

main(): int {
    # Only the exported member is a candidate here: `area(2, 3)` would be
    # an error, since `area(int, int)` is private to shapes.pep.
    assert(area(3) == 9, "the exported member");
    return 0;
}
