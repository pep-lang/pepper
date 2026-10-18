struct Version {
    var major: int;
    var minor: int;

    construct(this.major = 0, this.minor = 0) {}

    # The one method Comparable asks for.
    compare(other: Version): int {
        var order = major.compare(other.major);
        if (order != 0) {
            return order;
        }
        return minor.compare(other.minor);
    }
}

extend Version with Comparable;

# A generic function asks for an order with `T: Comparable`.
largest<T: Comparable>(items: Array<T>): T {
    var best = items[0];
    for (var item in items) {
        best = best.max(item);
    }
    return best;
}

main(): int {
    # `<`, `<=`, `>` and `>=` come from `compare`.
    assert(Version(1, 2) < Version(1, 10), "1.2 sorts before 1.10");
    assert(Version(2, 0).min(Version(1, 9)).major == 1, "min");
    assert(Version(3, 0).clamp(Version(1, 0), Version(2, 0)).major == 2, "clamp");

    # Numbers and strings are Comparable too.
    assert(largest([3, 9, 2]) == 9, "numbers");
    assert(largest(["pear", "apple"]) == "pear", "strings");
    assert((15).clamp(0, 10) == 10, "clamp a number");

    # A Comparable struct is a Map key, in its order.
    var releases = Map<Version, String>();
    releases[Version(2, 0)] = "second";
    releases[Version(1, 5)] = "first";
    assert(releases.first().value().1 == "first", "sorted by compare");

    # Sorting takes the order as a comparer.
    var versions = [Version(2, 1), Version(1, 5)];
    versions.sort((a, b) => a.compare(b));
    assert(versions[0].major == 1, "sorted");
    return 0;
}
