# [Equatable(ordered = true)] derives compare from the fields that take part
# in == (#369): <, compare agreeing with ==, sort(), Map keys, one field,
# and a generic struct.

[Equatable(ordered = true)]
struct Version {
    var major: int;
    var minor: int;
    [Equatable(exclude = true)]
    var note: String;

    construct(this.major = 0, this.minor = 0, this.note = "") {}
}

[Equatable(ordered = true)]
struct Name {
    var text: String;

    construct(this.text = "") {}
}

[Equatable(ordered = true)]
struct Pair<T> {
    var first: T;
    var second: T;

    construct(first: T, second: T) {
        this.first = first;
        this.second = second;
    }
}

main(): int {
    assert(Version(1, 2) < Version(1, 10), "<");
    assert(Version(2, 0, "a") == Version(2, 0, "b"), "note left out");
    assert(Version(2, 0).compare(Version(2, 0, "x")) == 0, "compare agrees with ==");
    var vs = [Version(1, 10), Version(0, 9), Version(1, 2)];
    vs.sort();
    assert(vs[0].major == 0 && vs[1].minor == 2 && vs[2].minor == 10, "sort");
    var m = Map<Version, String>();
    m[Version(2)] = "b";
    m[Version(1)] = "a";
    var order = "";
    for (var (_, v) in m) {
        order = order + v;
    }
    assert(order == "ab", "map keys");
    assert(Name("a") < Name("b") && Name("b").max(Name("a")) == Name("b"), "one field");
    assert(Pair<int>(1, 2) < Pair<int>(1, 3), "generic");
    return 0;
}
