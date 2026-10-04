# Range: half-open and closed ranges in a loop, bounds of any integer type
# (stopping at the type's top without overflowing), contains, is_empty,
# resuming a partly used range, map, and current() before next().

[Test]
half_open_and_closed_ranges() {
    var total = 0;
    for (var i in 0..5) {
        # 0 + 1 + 2 + 3 + 4
        total += i;
    }
    for (var i in 1..>3) {
        # 100 + 200 + 300
        total += i * 100;
    }
    expect_equal(total, 610);
    for (var i in 5..5) {
        panic("5..5 is empty");
    }
    for (var i in 5..>4) {
        panic("5..>4 is empty");
    }
}

[Test]
range_type_follows_its_bounds() {
    var nums = [10, 20, 30];
    var total = 0;
    # Range<ulong>
    for (var i in 0..nums.count) {
        total += nums[i];
    }
    expect_equal(total, 60);
    ulong last = 0;
    for (var i in 0..nums.count) {
        last = i;
    }
    expect_equal(last, 2);
    byte count = 0;
    byte top = 255;
    # Stops at 255 without overflowing.
    for (var b in 250..>top) {
        count += 1;
    }
    expect_equal(count, 6);
}

[Test]
range_is_a_value_with_contains_and_adapters() {
    var r = 2..5;
    expect_true(r.contains(2));
    expect_true(r.contains(4));
    expect_false(r.contains(5));
    expect_false(r.contains(1));
    expect_true((2..>5).contains(5));
    expect_false(r.is_empty);
    expect_true((3..3).is_empty);
    # The loop below resumes where this left off.
    r.next();
    var rest = 0;
    for (var i in r) {
        rest += i;
    }
    expect_equal(rest, 3 + 4);
    var squares = 0;
    for (var s in (1..>3).map((x) => x * x)) {
        squares += s;
    }
    expect_equal(squares, 1 + 4 + 9);
}

[Test]
[ShouldPanic("Range.current() before next()")]
range_current_out_of_turn_panics() {
    var r = 0..1;
    r.current();
}
