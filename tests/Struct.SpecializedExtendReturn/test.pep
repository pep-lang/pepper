# A specialized extension's methods return struct references, beside a
# generic extension of the same struct.
struct Point { var x: int; }
struct Box<T> { var v: int; }

extend Box<T> {
    twice(): int { return this.v * 2; }
}

extend Box<Point> {
    make(): Point {
        var p = Point();
        p.x = this.v;
        return p;
    }
    again(): Point { return this.make(); }
}

main(): int {
    var b = Box<Point>();
    b.v = 4;
    if (b.make().x != 4) { return 1; }
    var p = b.again();
    if (p.x + b.twice() != 12) { return 2; }
    return 0;
}
