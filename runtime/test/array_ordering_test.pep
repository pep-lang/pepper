# Array ordering and reshaping: sort_unstable, select_nth, partial_sort,
# compare, rotate, drain, extend_from and remove_if, checked against the
# stable sort on many sizes and input patterns, and for the counts of
# struct elements.

import random;

struct Tally {
    int alive;
    construct(this.alive = 1) {}
    destruct {
        alive = 0;
    }
}

# The sizes around the insertion-sort and ninther thresholds, and larger.
sizes(): Array<ulong> {
    return [0, 1, 2, 3, 23, 24, 25, 100, 128, 129, 1000];
}

# Input `pattern` of `count` elements: 0 random, 1 sorted, 2 reversed, 3 all
# equal, 4 few distinct values, 5 organ pipe, 6 sorted with a few swaps.
make(pattern: int, count: ulong, numbers: random.Generator): Array<int> {
    var a = Array<int>(count);
    ulong index = 0;
    while (index < count) {
        var i = index as int;
        var n = count as int;
        if (pattern == 0) {
            a.append(numbers.next_int(0..1000000));
        } else if (pattern == 1) {
            a.append(i);
        } else if (pattern == 2) {
            a.append(n - i);
        } else if (pattern == 3) {
            a.append(7);
        } else if (pattern == 4) {
            a.append(numbers.next_int(0..4));
        } else if (pattern == 5) {
            a.append(i < n / 2 ? i : n - i);
        } else {
            a.append(i);
        }
        index = index + 1;
    }
    if (pattern == 6 && count > 1) {
        a.swap(0, count - 1);
        a.swap(count / 2, count / 3);
    }
    return a;
}

const PATTERNS: int = 7;

sorted_copy(a: Array<int>): Array<int> {
    var b = a.clone();
    b.sort();
    return b;
}

[Test]
sort_unstable_matches_sort() {
    var numbers = random.Generator(12345);
    for (var count in sizes()) {
        for (var pattern in 0..PATTERNS) {
            var a = make(pattern, count, numbers);
            var expected = sorted_copy(a);
            var b = a.clone();
            b.sort_unstable();
            expect_true(b == expected);
            a.sort_unstable((x, y) => y.compare(x));
            a.reverse();
            expect_true(a == expected);
        }
    }
}

[Test]
sort_unstable_on_strings() {
    var a = ["pear", "fig", "apple", "fig"];
    a.sort_unstable();
    expect_true(a == ["apple", "fig", "fig", "pear"]);
}

[Test]
sort_unstable_keeps_counts() {
    var t = Tally();
    var u = Tally();
    var items = Array<Tally>();
    ulong index = 0;
    while (index < 50) {
        items.append(index % 3 == 0 ? t : u);
        index = index + 1;
    }
    items.sort_unstable((a, b) => (a == t ? 0 : 1) - (b == t ? 0 : 1));
    expect_equal(__refcount<Tally>(t), 18);
    expect_equal(__refcount<Tally>(u), 34);
    expect_true(items[0] == t && items[16] == t && items[17] == u);
}

[Test]
sort_unstable_survives_an_inconsistent_compare() {
    var numbers = random.Generator(12345);
    var a = make(0, 500, numbers);
    var expected = sorted_copy(a);
    a.sort_unstable((x, y) => numbers.next_int(-1..>1));
    # Not sorted, but still the same elements.
    expect_true(sorted_copy(a) == expected);
}

[Test]
sort_unstable_falls_back_to_heapsort() {
    # "Always less" makes every partition empty on one side, so the sort
    # reaches its heapsort fallback; it must stay in bounds and keep every
    # element.
    var numbers = random.Generator(12345);
    var a = make(0, 1000, numbers);
    var expected = sorted_copy(a);
    a.sort_unstable((x, y) => -1);
    expect_true(sorted_copy(a) == expected);
    a.select_nth(500, (x, y) => -1);
    expect_true(sorted_copy(a) == expected);
}

[Test]
[ShouldPanic("Array modified during sort")]
sort_unstable_that_modifies_the_array_panics() {
    var a = [3, 1, 2];
    a.sort_unstable((x, y) => {
        a.pop();
        return x - y;
    });
}

[Test]
select_nth_settles_every_position() {
    var numbers = random.Generator(12345);
    for (var count in sizes()) {
        if (count == 0) {
            continue;
        }
        for (var pattern in 0..PATTERNS) {
            var a = make(pattern, count, numbers);
            var expected = sorted_copy(a);
            for (var nth in [0, count / 2, count - 1]) {
                var b = a.clone();
                b.select_nth(nth);
                expect_equal(b[nth], expected[nth]);
                ulong index = 0;
                while (index < count) {
                    expect_true(index < nth ? b[index] <= b[nth] : b[index] >= b[nth]);
                    index = index + 1;
                }
                expect_true(sorted_copy(b) == expected);
            }
        }
    }
}

[Test]
select_nth_with_a_compare() {
    var a = [9, 1, 8, 2, 7, 3];
    a.select_nth(1, (x, y) => y - x);
    expect_equal(a[1], 8);
}

[Test]
[ShouldPanic("Array select_nth index out of bounds")]
select_nth_past_the_end_panics() {
    var a = [1, 2];
    a.select_nth(2);
}

[Test]
partial_sort_sorts_the_prefix() {
    var numbers = random.Generator(12345);
    for (var count in sizes()) {
        for (var pattern in 0..PATTERNS) {
            var a = make(pattern, count, numbers);
            var expected = sorted_copy(a);
            for (var k in [0, count / 3, count]) {
                var b = a.clone();
                b.partial_sort(k);
                expect_true(b.slice(0, k).to_array() == expected.slice(0, k).to_array());
                expect_true(sorted_copy(b) == expected);
            }
        }
    }
}

[Test]
partial_sort_with_a_compare() {
    var scores = [40, 95, 12, 77, 63];
    scores.partial_sort(3, (x, y) => y - x);
    expect_true(scores.slice(0, 3).to_array() == [95, 77, 63]);
}

[Test]
[ShouldPanic("Array partial_sort count out of bounds")]
partial_sort_past_the_end_panics() {
    var a = [1, 2];
    a.partial_sort(3);
}

[Test]
compare_is_lexicographic() {
    expect_equal([1, 2, 3].compare([1, 2, 3]), 0);
    expect_true([1, 2, 3].compare([1, 3]) < 0);
    expect_true([1, 3].compare([1, 2, 3]) > 0);
    expect_true([1, 2].compare([1, 2, 0]) < 0);
    expect_true([1, 2, 0].compare([1, 2]) > 0);
    expect_equal(Array<int>().compare(Array<int>()), 0);
    expect_true(Array<int>().compare([0]) < 0);
    expect_true(["b"].compare(["a", "z"]) > 0);
}

[Test]
rotate_moves_the_front_to_the_back() {
    var a = [1, 2, 3, 4, 5];
    a.rotate(2);
    expect_true(a == [3, 4, 5, 1, 2]);
    a.rotate(0);
    expect_true(a == [3, 4, 5, 1, 2]);
    a.rotate(5);
    expect_true(a == [3, 4, 5, 1, 2]);
    a.rotate(4);
    expect_true(a == [2, 3, 4, 5, 1]);
    var empty = Array<int>();
    empty.rotate(0);
    expect_equal(empty.count, 0);
    var one = [7];
    one.rotate(1);
    expect_true(one == [7]);
    var t = Tally();
    var items = Array<Tally>();
    items.append(t);
    items.append(Tally());
    items.rotate(1);
    expect_equal(__refcount<Tally>(t), 2);
    expect_true(items[1] == t);
}

[Test]
[ShouldPanic("Array rotate count out of bounds")]
rotate_past_the_end_panics() {
    var a = [1, 2];
    a.rotate(3);
}

[Test]
drain_removes_a_range() {
    var a = [1, 2, 3, 4, 5];
    var middle = a.drain(1, 3);
    expect_true(a == [1, 4, 5]);
    expect_true(middle == [2, 3]);
    expect_equal(a.drain(2, 2).count, 0);
    expect_true(a.drain(0, 3) == [1, 4, 5]);
    expect_equal(a.count, 0);
    var t = Tally();
    var u = Tally();
    var items = Array<Tally>();
    items.append(u);
    items.append(t);
    items.append(u);
    var taken = items.drain(1, 2);
    expect_equal(__refcount<Tally>(t), 2);
    expect_equal(__refcount<Tally>(u), 3);
    expect_true(items[1] == u);
    expect_true(taken[0] == t);
}

[Test]
[ShouldPanic("Array drain range out of bounds")]
drain_past_the_end_panics() {
    var a = [1, 2];
    a.drain(1, 3);
}

[Test]
extend_from_appends_a_slice() {
    var a = [1, 2];
    var b = [7, 8, 9];
    a.extend_from(b.slice(1, 3));
    expect_true(a == [1, 2, 8, 9]);
    a.extend_from(b.slice(0, 0));
    expect_equal(a.count, 4);
    # A slice of the same Array: read after the buffer grows.
    a.extend_from(a.slice(0, 4));
    expect_true(a == [1, 2, 8, 9, 1, 2, 8, 9]);
    var t = Tally();
    var items = Array<Tally>();
    items.append(t);
    var more = Array<Tally>();
    more.extend_from(items.slice(0, 1));
    expect_equal(__refcount<Tally>(t), 3);
}

[Test]
[ShouldPanic("Array modified while a slice of it is in use")]
extend_from_a_stale_slice_panics() {
    var a = [1, 2];
    var view = a.slice(0, 2);
    a.append(3);
    var b = Array<int>();
    b.extend_from(view);
}

[Test]
remove_if_drops_matches() {
    var a = [1, 2, 3, 4];
    a.remove_if((x) => x > 2);
    expect_true(a == [1, 2]);
    a.remove_if((x) => true);
    expect_equal(a.count, 0);
    var empty = Array<int>();
    empty.remove_if((x) => true);
    expect_equal(empty.count, 0);
}
