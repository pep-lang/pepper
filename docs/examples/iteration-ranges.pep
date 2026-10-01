main(): int {
    # `a..b` counts from a up to, but not including, b.
    var total = 0;
    for (var i in 0..5) {
        total += i;
    }
    assert(total == 10, "0 + 1 + 2 + 3 + 4");

    # `a..>b` includes b.
    var product = 1;
    for (var i in 1..>5) {
        product *= i;
    }
    assert(product == 120, "5 factorial");

    # The bounds give the type: count() is a ulong, so i is too.
    var names = ["Ada", "Grace", "Edsger"];
    ulong letters = 0;
    for (var i in 0..names.count()) {
        letters += names[i].size();
    }
    assert(letters == 14, "letters in every name");

    # A range that starts past its end is empty.
    for (var i in 3..1) {
        assert(false, "never runs");
    }

    # A range is a value: test membership, or use the iterator adapters.
    var digits = 0..10;
    assert(digits.contains(9) && !digits.contains(10), "half-open");
    var evens = 0;
    for (var even in (1..>10).filter((n) => n % 2 == 0)) {
        evens += even;
    }
    assert(evens == 30, "2 + 4 + 6 + 8 + 10");
    return 0;
}
