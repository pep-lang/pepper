# A tuple whose elements are all Comparable is Comparable (#367): `compare`,
# the operators and `min` from the trait, `sort()`, Map keys, labeled and
# nested tuples, and strings among the elements.

main(): int {
    assert((1, 2) < (1, 3), "<");
    assert((2, "a") > (1, "z"), ">");
    assert((1, 2) <= (1, 2) && (1, 2) >= (1, 2), "<= and >=");
    assert((1, 2).compare((1, 2)) == 0, "compare");
    assert((1, 2).min((0, 5)) == (0, 5), "min on a literal");
    var pair = (4, "x");
    assert(pair.max((4, "y")) == (4, "y"), "max");
    var words = [(2, "b"), (1, "z"), (2, "a")];
    words.sort();
    assert(words[0].0 == 1 && words[1].1 == "a" && words[2].1 == "b", "sort");
    var names = Map<(int, int), String>();
    names[(2, 1)] = "c";
    names[(1, 2)] = "b";
    names[(1, 1)] = "a";
    var order = "";
    for (var (_, name) in names) {
        order = order + name;
    }
    assert(order == "abc", "map keys in order");
    var p: (line: int, column: int) = (line: 3, column: 7);
    var q: (line: int, column: int) = (line: 3, column: 9);
    assert(p < q, "labeled");
    assert((1, (2, 3)) < (1, (2, 4)), "nested");
    assert((1, 2, 3) < (1, 2, 4), "three elements");
    return 0;
}
