struct Point {
    int x;
    int y;

    construct(this.x = 0, this.y = 0) {}

    # Two points are equal when their coordinates are...
    ==(other: Point): bool {
        return x == other.x and y == other.y;
    }
}

# ...so equal points must hash equally: hash the same fields `==` compares.
# A tuple hashes each element in turn, which combines them.
hash<Point>(value: Point): u64 {
    return hash<(int, int)>((value.x, value.y));
}

struct Person {
    String name;
    int id;
    # Not part of the identity: two records for the same person may differ.
    String nickname;

    construct(this.name = "", this.id = 0, this.nickname = "") {}

    ==(other: Person): bool {
        return id == other.id and name == other.name;
    }
}

# A String field hashes by its content, through hash<String>.
hash<Person>(value: Person): u64 {
    return hash<(String, int)>((value.name, value.id));
}

main(): int {
    var visits = HashMap<Point, int>();
    visits[Point(1, 2)] = 1;
    visits[Point(1, 2)] = visits[Point(1, 2)] + 1;   # the same key
    assert(visits.count() == 1, "one entry");
    assert(visits[Point(1, 2)] == 2, "found by content");
    assert(Point(1, 2) != Point(2, 1), "!= is the negation of ==");

    HashSet<Person> people = [Person("Ada", 1, "A"), Person("Ada", 1, "Countess")];
    assert(people.count() == 1, "equal people are one member");
    assert(people.contains(Person("Ada", 1)), "the nickname is ignored");
    assert(!people.contains(Person("Ada", 2)), "a different id");
    return 0;
}
