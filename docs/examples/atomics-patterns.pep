struct Config {
    String Name;
    construct(this.Name = "") {}
}

# A module-scope Atomic that every function can share.
var next_id = Atomic<long>(0);

new_id(): long {
    return next_id.fetch_add(1) + 1;
}

# The compare-and-swap retry loop: build any read-modify-write update.
double_it(Atomic<int> value) {
    var current = value.load();
    while (!value.compare_exchange(current, current * 2)) {
        current = value.load();
    }
}

main(): int {
    assert(new_id() == 1, "first id");
    assert(new_id() == 2, "second id");

    var n = Atomic<int>(21);
    double_it(n);
    assert(n.load() == 42, "doubled");

    # Copies of an Atomic share one slot, because Atomic is a struct.
    var same = n;
    same.store(7);
    assert(n.load() == 7, "both names see the store");

    # An Atomic can hold a struct reference.
    var first = Config("first");
    var current = Atomic<Config>(first);
    assert(current.load().Name == "first", "load returns the reference");

    # compare_exchange compares references: the same object, not equal contents.
    var lookalike = Config("first");
    var second = Config("second");
    assert(!current.compare_exchange(lookalike, second), "a different object");
    assert(current.compare_exchange(first, second), "the same object");
    assert(current.load().Name == "second", "swapped");

    var old = current.exchange(first);
    assert(old.Name == "second", "exchange hands back the old reference");
    return 0;
}
