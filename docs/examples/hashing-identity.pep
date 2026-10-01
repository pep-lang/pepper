struct Point {
    int x;
    int y;

    construct(this.x = 0, this.y = 0) {}
}

main(): int {
    var origin = Point(0, 0);
    var visits = HashMap<Point, int>();
    visits[origin] = 1;

    # A struct key is found by identity: the same object finds its entry...
    assert(visits.contains(origin), "the stored object");

    # ...but another object with equal fields is a different key.
    assert(!visits.contains(Point(0, 0)), "an equal but distinct object");
    return 0;
}
