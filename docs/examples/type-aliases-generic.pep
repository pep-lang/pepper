# Generic aliases take their own type parameters.
type Predicate<T> = (T) => bool;
type Lookup<V> = HashMap<String, V>;
type Outcome<T, E=Error> = Result<T, E>;

is_even(x: int): bool {
    return x % 2 == 0;
}

count_matching(values: Array<int>, test: Predicate<int>): int {
    var n = 0;
    for (var v in values) {
        if (test(v)) {
            n += 1;
        }
    }
    return n;
}

parse_digit(text: String): Outcome<int> {
    if (text == "7") {
        return Outcome<int>.ok(7);
    }
    return Outcome<int>.err(Error("not a digit I know"));
}

main(): int {
    var values = Array<int>();
    values.append(1);
    values.append(2);
    values.append(4);
    assert(count_matching(values, is_even) == 2, "Predicate<int> is (int) => bool");

    var ages = Lookup<int>();   # HashMap<String, int>
    ages.insert("Ada", 36);
    assert(ages.contains("Ada"), "Lookup<int> is HashMap<String, int>");

    # Outcome<int> fills E with its default: Result<int, Error>.
    assert(parse_digit("7").unwrap() == 7, "ok");
    assert(parse_digit("x").is_err(), "err");
    return 0;
}
