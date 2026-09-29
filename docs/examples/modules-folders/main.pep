import "geometry" as g;
import [rect_area, Point as Pt] from "geometry";

# Qualified names work in types, too.
corner(): g.Point {
    return g.make(1, 1);
}

main(): int {
    var p: g.Point = g.make(3, 4);
    assert(p.x == 3, "qualified function and type");

    Pt q = corner();
    assert(q.y == 1, "the struct under its import-list name");

    assert(g.rect_area(2, 3) == 6, "re-exported under a new name");
    assert(rect_area(2, 5) == 10, "imported unqualified");
    assert(g.reset() == 0, "a private function, re-exported");
    assert(g.box_volume(2, 3, 4) == 24, "re-exported from a nested module");

    var b = g.Box<int>();
    b.value = 7;
    var boxes: g.Box<int>[] = g.Box<int>[]();
    boxes.append(b);
    assert(boxes[0].value == 7, "a generic struct through a qualifier");
    return 0;
}
