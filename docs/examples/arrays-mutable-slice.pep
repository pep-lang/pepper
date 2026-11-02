main(): int {
    var scores = [90, 40, 75, 10, 60, 100];
    # Sort the middle four in place; the first and last stay put.
    scores.mutable_slice(1, 5).sort();
    assert(scores == [90, 10, 40, 60, 75, 100], "middle sorted");

    var tail = scores.mutable_slice(3, 6);
    tail.reverse();
    assert(scores == [90, 10, 40, 100, 75, 60], "tail reversed");
    tail[0] = 0;
    tail.fill(1);
    assert(scores == [90, 10, 40, 1, 1, 1], "tail filled");
    return 0;
}
