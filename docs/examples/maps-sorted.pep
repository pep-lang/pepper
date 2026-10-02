main(): int {
    var scores = Map<String, int>();
    scores["carol"] = 91;
    scores["alice"] = 84;
    scores["bob"] = 77;

    # Entries come out sorted by key.
    var names = "";
    for (var (name, score) in scores) {
        names = names + name + " ";
    }
    assert(names == "alice bob carol ", "key order");

    # Order queries return an optional (key, value) tuple.
    assert(scores.first().value().0 == "alice", "smallest key");
    assert(scores.lower_bound("b").value().0 == "bob", "first key >= b");
    assert(scores.upper_bound("carol").is_empty(), "nothing after carol");

    # A key range: from "a" up to, not including, "c".
    var in_range = 0;
    for (var (name, score) in scores.range("a", "c")) {
        in_range += 1;
    }
    assert(in_range == 2, "alice and bob");

    # A Set keeps sorted members; an array converts to one.
    Set<int> primes = [7, 2, 5, 3];
    var digits = 0;
    for (var p in primes.reversed()) {
        digits = digits * 10 + p;
    }
    assert(digits == 7532, "descending");
    return 0;
}
