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
    assert(names.count() == 2, "two adults");
    assert(names[0] == "Ada", "Ada first");
    assert(names[1] == "Cyd", "then Cyd");

    # Adapters work on any Iterator, including a String's.
    var kept = 0;
    for (var c in "hello".iterate().filter((c) => c != "l")) {
        kept += 1;
    }
    assert(kept == 3, "h, e, o");
    return 0;
}
