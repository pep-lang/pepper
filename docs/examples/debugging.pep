# Build with `-g` to debug this program: break on line 18 and print `first`.
struct Point {
    var x: int = 0;
    var y: int = 0;
}

total(p: Point): int {
    return p.x + p.y;
}

main(): int {
    var points = Array<Point>();
    var p = Point();
    p.x = 1;
    p.y = 2;
    points.append(p);
    var first = points[0];
    return total(first) - 3;
}
