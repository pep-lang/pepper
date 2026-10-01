# A lookup that may find nothing returns an Optional instead of a sentinel.
struct Person {
    String name;
    int age;

    construct(this.name = "", this.age = 0) {}
}

find_adult(people: Array<Person>): Optional<Person> {
    for (var p in people) {
        if (p.age >= 18) { return Optional<Person>.some(p); }
    }
    return Optional<Person>.none();
}

# `ulong?` is shorthand for `Optional<ulong>`.
index_of(text: String, wanted: String): ulong? {
    var i: ulong = 0;
    while (i < text.length()) {
        if (text[i] == wanted) { return Optional<ulong>.some(i); }
        i = i + 1;
    }
    return Optional<ulong>.none();
}

main(): int {
    var people = Array<Person>();
    people.append(Person("ada", 12));
    assert(find_adult(people).is_none(), "no adult yet");

    people.append(Person("grace", 45));
    var adult = find_adult(people);
    assert(adult.is_some(), "grace is an adult");
    # An optional is a condition by itself: `if (adult)` tests is_some().
    if (!adult) { return 1; }
    assert(adult.value().name == "grace", "value() returns the Person");

    # Works for types that have no null, too.
    assert(index_of("pepper", "e").value() == 1, "first 'e' is at 1");
    assert(index_of("pepper", "z").is_none(), "no 'z'");

    # value_or supplies a fallback instead of panicking.
    assert(index_of("pepper", "z").value_or(99) == 99, "fallback for None");

    # Optional is an enum with the cases None and Some(value).
    var nothing = Optional<int>.None;
    assert(nothing.is_none(), "the None case is None");
    var first_p = match (index_of("pepper", "p")) {
        None => -1,
        Some(at) => at as int,
    };
    assert(first_p == 0, "match on an optional");

    # An optional slot that is not given a value starts as None.
    var later: String?;
    assert(later.is_none(), "unassigned optionals are None");
    return 0;
}
