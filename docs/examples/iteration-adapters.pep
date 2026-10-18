struct Person {
    String name;
    int age;
    construct(this.name = "", this.age = 0) {}
}

main(): int {
    var people = Array<Person>();
    people.append(Person("Ada", 36));
    people.append(Person("Bo", 12));
    people.append(Person("Cyd", 40));

    # filter keeps the adults, map turns each one into a name.
    var names = Array<String>();
    for (var name in people.iterate().filter((p) => p.age >= 18).map((p) => p.name)) {
        names.append(name);
    }
    assert(names.count == 2, "two adults");
    assert(names[0] == "Ada", "Ada first");
    assert(names[1] == "Cyd", "then Cyd");

    # Adapters work on any Iterator, including a String's.
    var kept = 0;
    for (var c in "hello".iterate().filter((c) => c != "l")) {
        kept += 1;
    }
    assert(kept == 3, "h, e, o");

    # enumerate pairs each element with its position, and zip pairs two
    # iterators in step; destructure the tuple to name both parts.
    var ranked = "";
    for (var (i, person) in people.iterate().enumerate()) {
        ranked += $"{i}:{person.name} ";
    }
    assert(ranked == "0:Ada 1:Bo 2:Cyd ", "numbered from 0");
    var seats = ["window", "aisle"];
    var seated = 0;
    for (var (person, seat) in people.iterate().zip(seats.iterate())) {
        seated += 1;   # Cyd gets no seat: zip stops at the shorter
    }
    assert(seated == 2, "two pairs");

    # flat_map yields the elements of the iterator it returns for each one.
    var letters = people.iterate().flat_map((p) => p.name.iterate()).count();
    assert(letters == 8, "Ada, Bo and Cyd");

    # to_array collects what an iterator yields.
    var ages = people.iterate().map((p) => p.age).to_array();
    assert(ages.count == 3 && ages[2] == 40, "every age");

    # Consumers run the iterator and return one value.
    assert(people.iterate().any((p) => p.age < 18), "Bo is a child");
    assert(people.iterate().map((p) => p.age).sum() == 88, "total age");
    assert(people.iterate().map((p) => p.age).max().value() == 40, "oldest");
    assert(people.iterate().find((p) => p.age > 36).value().name == "Cyd", "first over 36");
    assert(people.iterate().skip(1).take(1).count() == 1, "just Bo");
    return 0;
}
