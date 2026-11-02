main(): int {
    # Empty sorts before every value; values by their own order.
    var scores = [Optional<int>.Value(7), Optional<int>.Empty, Optional<int>.Value(2)];
    scores.sort();
    assert(scores[0].is_empty() && scores[1].value() == 2, "Empty first, then 2 and 7");
    assert(Optional<String>.Value("a") < Optional<String>.Value("b"), "by the values");
    return 0;
}
