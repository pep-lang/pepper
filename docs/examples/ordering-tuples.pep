main(): int {
    # A tuple of Comparable elements compares element by element.
    assert((1, "b") < (2, "a"), "the first element decides");
    assert((1, "a") < (1, "b"), "then the second");

    # So an array of tuples sorts, and a Map keys on them in that order.
    var scores = [(3, "cy"), (1, "al"), (3, "bo")];
    scores.sort();
    assert(scores[0].1 == "al" && scores[1].1 == "bo", "by score, then name");
    var grid = Map<(int, int), char>();
    grid[(1, 0)] = 'b';
    grid[(0, 1)] = 'a';
    var first = 'z';
    for (var (_, cell) in grid) {
        first = cell;
        break;
    }
    assert(first == 'a', "(0, 1) sorts first");
    return 0;
}
