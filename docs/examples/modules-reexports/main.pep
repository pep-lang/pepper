import "shapes";

main(): int {
    var r = make_rect(3, 4);
    assert(area(r) == 12, "from export * of rect.pep");
    assert(outline(r) == 14, "from the export list, renamed");

    var s = Side();
    s.length = 5;
    assert(s.length == 5, "a struct from the export list");
    return 0;
}
