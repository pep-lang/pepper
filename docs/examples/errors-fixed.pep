# The program from "Reading an error", after the fix.

struct Point {
    var x: int;
    var y: int;
}

main(): int {
    var p = Point();
    p.x = 3;
    p.y = 4;
    var total = p.x + p.y;
    assert(total == 7, "x + y");
    return 0;
}
