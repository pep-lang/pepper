# The random module: the generator against the reference xoshiro256** and
# SplitMix64 (computed from the authors' C code), ranges that stay in
# bounds and reach both ends, shuffles that keep every element, and bytes
# from the operating system.

import random;

[Test]
seeded_generator_matches_reference() {
    var g = random.Generator(42);
    expect_equal(g.next_ulong(), 0x15780b2e0c2ec716);
    expect_equal(g.next_ulong(), 0x6104d9866d113a7e);
    expect_equal(g.next_ulong(), 0xae17533239e499a1);
    # A copy carries on from the same state.
    var copy = g;
    expect_equal(copy.next_ulong(), g.next_ulong());
}

[Test]
next_int_covers_the_range_and_no_more() {
    var g = random.Generator(1);
    var seen = Array<bool>();
    for (var i in 0..6) {
        seen.append(false);
    }
    for (var i in 0..1000) {
        var roll = g.next_int(1..>6);
        expect_true(roll >= 1 && roll <= 6);
        seen[(roll - 1) as ulong] = true;
        var low = g.next_int(-3..0);
        expect_true(low >= -3 && low < 0);
    }
    for (var s in seen) {
        expect_true(s);
    }
    expect_equal(g.next_int(5..>5), 5);
    var wide = g.next_int(-2147483648..>2147483647);
    expect_true(wide >= -2147483648);
}

[Test]
doubles_and_bools() {
    var g = random.Generator(3);
    var trues = 0;
    for (var i in 0..1000) {
        var d = g.next_double();
        expect_true(d >= 0.0 && d < 1.0);
        if (g.next_bool()) {
            trues += 1;
        }
    }
    expect_true(trues > 400 && trues < 600);
}

[Test]
shuffle_keeps_every_element() {
    var g = random.Generator(9);
    var items = Array<int>();
    for (var i in 0..50) {
        items.append(i);
    }
    g.shuffle(items);
    var sorted = items.copy();
    sorted.sort((a: int, b: int) => a - b);
    for (var i in 0..50) {
        expect_equal(sorted[i as ulong], i);
    }
    expect_true(items != sorted);
    var choice = g.choose(items);
    expect_true(choice >= 0 && choice < 50);
    var empty = Array<int>();
    g.shuffle(empty);
}

[Test]
thread_generator_and_entropy() {
    var roll = random.next_int(0..10);
    expect_true(roll >= 0 && roll < 10);
    var d = random.next_double();
    expect_true(d >= 0.0 && d < 1.0);
    String[] names = ["ada", "grace"];
    var name = random.choose(names);
    expect_true(name == "ada" || name == "grace");
    random.shuffle(names);
    expect_equal(names.count, 2 as ulong);
    expect_true(random.next_ulong() != random.next_ulong());
    random.next_bool();

    var key = random.bytes(300);
    expect_equal(key.count, 300 as ulong);
    expect_true(key != random.bytes(300));
    var before = key.copy();
    random.fill(key);
    expect_true(key != before);
    expect_equal(random.bytes(0).count, 0 as ulong);
    expect_true(random.secure_ulong() != random.secure_ulong());
    # Two seeded-from-entropy generators differ.
    var first = random.Generator();
    var second = random.Generator();
    expect_true(first.next_ulong() != second.next_ulong());
}
