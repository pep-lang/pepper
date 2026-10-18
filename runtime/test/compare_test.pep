# Comparable: the operators, min, max and clamp it gives, the numbers',
# char's and String's conformance, the total order of floats, a generic
# `T: Comparable`, and Comparable and NaN `Map` keys.

struct Version {
    int major;
    int minor;

    construct(this.major = 0, this.minor = 0) {}

    compare(other: Version): int {
        var order = major.compare(other.major);
        if (order != 0) {
            return order;
        }
        return minor.compare(other.minor);
    }
}

extend Version with Comparable;

# A Comparable type keeps an operator it declares itself.
struct Reversed {
    int n;

    construct(this.n = 0) {}

    compare(other: Reversed): int {
        return other.n.compare(n);
    }

    <(other: Reversed): bool {
        return false;
    }
}

extend Reversed with Comparable;

largest<T: Comparable>(items: Array<T>): T {
    var best = items[0];
    for (var item in items) {
        best = best.max(item);
    }
    return best;
}

_nan(): double {
    var zero = 0.0;
    return zero / zero;
}

[Test]
comparable_struct_gets_operators() {
    expect_true(Version(1, 2) < Version(1, 10));
    expect_true(Version(1, 2) <= Version(1, 2));
    expect_true(Version(2, 0) > Version(1, 9));
    expect_true(Version(2, 0) >= Version(2, 0));
    expect_false(Version(2, 0) < Version(2, 0));
    expect_false(Version(3, 0) <= Version(2, 9));
}

[Test]
comparable_struct_gets_min_max_clamp() {
    expect_equal(Version(2, 0).max(Version(1, 9)).major, 2);
    expect_equal(Version(2, 0).min(Version(1, 9)).major, 1);
    var low = Version(1, 0);
    var high = Version(2, 0);
    expect_equal(Version(0, 5).clamp(low, high).major, 1);
    expect_equal(Version(3, 1).clamp(low, high).major, 2);
    expect_equal(Version(1, 4).clamp(low, high).minor, 4);
}

[Test]
own_operator_wins_over_the_default() {
    expect_false(Reversed(1) < Reversed(2));
    expect_true(Reversed(1) > Reversed(2));
}

[Test]
numbers_chars_and_strings_compare() {
    expect_equal((3).compare(5), -1);
    expect_equal((5).compare(5), 0);
    expect_equal((7 as ulong).compare(5 as ulong), 1);
    expect_equal((-1 as long).compare(1 as long), -1);
    expect_equal(('a' as char).compare('b' as char), -1);
    expect_equal((200 as byte).compare(100 as byte), 1);
    expect_true("apple".compare("pear") < 0);
    expect_equal("pear".min("apple"), "apple");
    expect_equal("pear".max("apple"), "pear");
    expect_equal((15).clamp(0, 10), 10);
    expect_equal((-3).clamp(0, 10), 0);
    expect_equal((4).clamp(0, 10), 4);
}

[Test]
floats_compare_in_a_total_order() {
    var nan = _nan();
    expect_equal((1.0).compare(2.0), -1);
    expect_equal((1.0).compare(nan), -1);
    expect_equal(nan.compare(1.0), 1);
    expect_equal(nan.compare(nan), 0);
    expect_equal((-0.0).compare(0.0), 0);
    expect_equal((nan as float).compare(1.0 as float), 1);
    # `<` keeps IEEE behavior.
    expect_false(1.0 < nan);
    expect_false(nan < 1.0);
}

[Test]
generic_comparable_parameter() {
    expect_equal(largest([3, 9, 2]), 9);
    expect_equal(largest(["b", "c", "a"]), "c");
    expect_equal(largest([Version(1, 1), Version(2, 0), Version(1, 9)]).major, 2);
}

[Test]
comparable_struct_is_a_map_key() {
    var names = Map<Version, String>();
    names[Version(2, 0)] = "two";
    names[Version(1, 5)] = "one";
    var keys = Array<int>();
    for (var (key, name) in names) {
        keys.append(key.major);
    }
    expect_equal(keys[0], 1);
    expect_equal(keys[1], 2);
}

[Test]
nan_is_one_map_key() {
    var counts = Map<double, int>();
    counts[_nan()] = 1;
    counts[_nan()] = 2;
    counts[1.0] = 3;
    counts[-1.0] = 4;
    expect_equal(counts.count, 3);
    expect_equal(counts.first().value().0, -1.0);
    expect_equal(counts.last().value().1, 2);
}
