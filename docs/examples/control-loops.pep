# Looping with while and for, and leaving early with break and continue.
main(): int {
    # while repeats as long as its condition is true.
    var countdown = 3;
    var launched = false;
    while countdown > 0 {
        countdown -= 1;
    }
    launched = countdown == 0;
    assert(launched, "counted down to zero");

    # for visits each element of an Array (or any other iterable).
    var scores = Array<int>();
    scores.append(70);
    scores.append(85);
    scores.append(92);
    var total = 0;
    for (var score in scores) {
        total += score;
    }
    assert(total == 247, "sum of the scores");

    # continue skips to the next iteration; break leaves the loop.
    var odd_sum = 0;
    var i = 0;
    while (i < 100) {
        i += 1;
        if (i % 2 == 0) { continue; }
        if (i > 9) { break; }
        odd_sum += i;
    }
    assert(odd_sum == 25, "1 + 3 + 5 + 7 + 9");

    # break and continue apply to the innermost loop.
    var pairs = 0;
    for (var a in scores) {
        for (var b in scores) {
            if (b == a) { break; }
            pairs += 1;
        }
    }
    assert(pairs == 3, "(85, 70), (92, 70), (92, 85)");
    return 0;
}
