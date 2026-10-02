# A struct with a `<` operator sorts by it.
struct Version {
    int major;
    int minor;

    construct(this.major = 0, this.minor = 0) {}

    <(other: Version): bool {
        return major < other.major or (major == other.major and minor < other.minor);
    }
}

# A struct without one overrides `compare<T>` for itself.
struct Point {
    int x;
    int y;

    construct(this.x = 0, this.y = 0) {}
}

compare<Point>(a: Point, b: Point): int {
    return a.x != b.x ? a.x - b.x : a.y - b.y;
}

main(): int {
    var releases = Map<Version, String>();
    releases[Version(1, 10)] = "third";
    releases[Version(0, 9)] = "first";
    releases[Version(1, 2)] = "second";
    assert(releases.first().value().1 == "first", "0.9 sorts first");
    assert(releases.last().value().1 == "third", "1.10 sorts last");

    var points = Set<Point>();
    points.insert(Point(2, 1));
    points.insert(Point(1, 5));
    # An equal point (compare returns 0) is the same member.
    assert(!points.insert(Point(1, 5)), "already a member");
    assert(points.first().value().x == 1, "sorted by x");
    return 0;
}
