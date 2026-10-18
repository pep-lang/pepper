# Iterating the runtime's containers: a String yields its code points, and
# changing an Array or a String while a loop (or a sort) walks it panics.

[Test]
string_yields_code_points() {
    var s = "héllo, wörld ✓";
    var count = 0;
    var copy = "";
    for (var c in s) {
        expect_equal(c.length, 1);
        copy.append(c);
        count = count + 1;
    }
    expect_equal(copy, s);
    expect_equal(count, 14);
    for (var c in "") {
        panic("an empty String has no code points");
    }
}

[Test]
[ShouldPanic("Array modified during iteration")]
appending_to_an_array_during_iteration_panics() {
    var nums = [1, 2];
    for (var x in nums) {
        nums.append(4);
    }
}

[Test]
[ShouldPanic("Array modified during iteration")]
storing_into_an_array_during_iteration_panics() {
    var nums = [1, 2];
    for (var x in nums) {
        nums[0] = 7;
    }
}

[Test]
[ShouldPanic("Array modified during iteration")]
removing_from_an_array_during_iteration_panics() {
    var nums = [1, 2];
    for (var x in nums) {
        nums.remove_at(0);
    }
}

# sort permutes raw slots in place, so a compare that changes the Array
# would see (and could free) a half-permuted buffer.
[Test]
[ShouldPanic("Array modified during sort")]
modifying_an_array_during_sort_panics() {
    var nums = [2, 1];
    nums.sort((a, b) => {
        nums.append(3);
        return a - b;
    });
}

[Test]
[ShouldPanic("String modified during iteration")]
modifying_a_string_during_iteration_panics() {
    var s = "ab";
    for (var c in s) {
        s.append("!");
    }
}

[Test]
mutating_after_the_loop_is_fine() {
    var nums = Array<int>();
    nums.append(1);
    for (var x in nums) {}
    nums.append(2);
    for (var x in nums) {}
    expect_equal(nums.count, 2);
}

[Test]
take_and_skip_slice_an_iterator() {
    var nums = [1, 2, 3, 4, 5];
    var firsts = nums.iterate().take(2).to_array();
    expect_equal(firsts.count, 2);
    expect_equal(firsts[1], 2);
    expect_equal(nums.iterate().take(9).count(), 5);
    expect_equal(nums.iterate().take(0).count(), 0);
    var rest = nums.iterate().skip(3).to_array();
    expect_equal(rest.count, 2);
    expect_equal(rest[0], 4);
    expect_equal(nums.iterate().skip(9).count(), 0);
    expect_equal((1..>10).skip(2).take(3).sum(), 3 + 4 + 5);
}

[Test]
chain_yields_one_iterator_then_the_other() {
    var both = (1..>2).chain(7..>8).to_array();
    expect_equal(both.count, 4);
    expect_equal(both[1], 2);
    expect_equal(both[2], 7);
    expect_equal((1..1).chain(3..>3).count(), 1);
    var words = "";
    for (var w in ["a", "b"].iterate().chain(Array<String>().iterate())) {
        words += w;
    }
    expect_equal(words, "ab");
}

[Test]
consumers_leave_the_iterator_where_it_was() {
    var it = (1..>4);
    expect_equal(it.count(), 4);
    expect_equal(it.sum(), 10);
    expect_equal(it.fold(1, (product, n) => product * n), 24);
    expect_equal(it.to_array().count, 4);
}

[Test]
any_all_and_find_test_each_element() {
    var nums = [1, 3, 4, 6];
    expect_true(nums.iterate().any((n) => n % 2 == 0));
    expect_false(nums.iterate().any((n) => n > 10));
    expect_true(nums.iterate().all((n) => n > 0));
    expect_false(nums.iterate().all((n) => n % 2 == 1));
    expect_true(Array<int>().iterate().all((n) => false));
    expect_equal(nums.iterate().find((n) => n % 2 == 0).value(), 4);
    expect_true(nums.iterate().find((n) => n > 10).is_empty());
}

[Test]
fold_combines_into_another_type() {
    var joined = ["a", "b", "c"].iterate().fold("", (text, s) => text + s);
    expect_equal(joined, "abc");
    expect_equal(Array<int>().iterate().fold(7, (total, n) => total + n), 7);
}

[Test]
sum_min_and_max_of_numbers_and_strings() {
    expect_equal([2.5, 1.5].iterate().sum(), 4.0);
    expect_equal(Array<int>().iterate().sum(), 0);
    long wide = [2000000000, 2000000000].iterate().sum<long>();
    expect_equal(wide, 4000000000);
    expect_equal([3, 1, 2].iterate().min().value(), 1);
    expect_equal([3, 1, 2].iterate().max().value(), 3);
    expect_equal(["pear", "apple"].iterate().min().value(), "apple");
    expect_true(Array<int>().iterate().min().is_empty());
    expect_true(Array<int>().iterate().max().is_empty());
}

[Test]
take_while_and_skip_while_split_at_the_first_failure() {
    var nums = [1, 2, 7, 3];
    var small = nums.iterate().take_while((n) => n < 5).to_array();
    expect_equal(small.count, 2);
    expect_equal(small[1], 2);
    var rest = nums.iterate().skip_while((n) => n < 5).to_array();
    expect_equal(rest.count, 2);
    expect_equal(rest[0], 7);
    expect_equal(rest[1], 3);
    expect_equal(nums.iterate().skip_while((n) => true).count(), 0);
}

[Test]
step_by_yields_the_first_then_every_step() {
    var stepped = (0..10).step_by(3).to_array();
    expect_equal(stepped.count, 4);
    expect_equal(stepped[3], 9);
    expect_equal((0..3).step_by(1).count(), 3);
}

[Test]
[ShouldPanic("step_by step must be positive")]
step_by_zero_panics() {
    (0..3).step_by(0);
}

[Test]
peek_looks_ahead_without_moving() {
    var it = [1, 2].iterate().peekable();
    expect_equal(it.peek().value(), 1);
    expect_equal(it.peek().value(), 1);
    expect_true(it.next());
    expect_equal(it.current(), 1);
    expect_equal(it.peek().value(), 2);
    expect_true(it.next());
    expect_equal(it.current(), 2);
    expect_true(it.peek().is_empty());
    expect_false(it.next());
}

[Test]
chunks_and_windows_group_elements() {
    var rows = (1..>5).chunks(2).to_array();
    expect_equal(rows.count, 3);
    expect_equal(rows[1][0], 3);
    expect_equal(rows[2].count, 1);
    var pairs = (1..>4).windows(2).to_array();
    expect_equal(pairs.count, 3);
    expect_equal(pairs[0][1], 2);
    expect_equal(pairs[2][0], 3);
    expect_equal(pairs[2][1], 4);
    expect_equal((1..>2).windows(3).count(), 0);
}

[Test]
reduce_position_and_last() {
    var nums = [1, 2, 7, 3];
    expect_equal(nums.iterate().reduce((a, b) => a + b).value(), 13);
    expect_true(Array<int>().iterate().reduce((a, b) => a + b).is_empty());
    expect_equal(nums.iterate().position((n) => n > 5).value(), 2);
    expect_true(nums.iterate().position((n) => n > 50).is_empty());
    expect_equal(nums.iterate().last().value(), 3);
    expect_true(Array<int>().iterate().last().is_empty());
}

[Test]
for_each_calls_the_action_in_order() {
    var seen = "";
    var letters = ["a", "b"];
    letters.iterate().for_each((s) => seen.append(s));
    expect_equal(seen, "ab");
}

[Test]
min_by_and_max_by_use_the_comparer() {
    var words = ["abc", "a", "zz"];
    expect_equal(words.iterate().min_by((a, b) => a.size.compare(b.size)).value(), "a");
    expect_equal(words.iterate().max_by((a, b) => a.size.compare(b.size)).value(), "abc");
    expect_true(Array<String>().iterate().min_by((a, b) => 0).is_empty());
}

[Test]
to_set_to_map_and_join_collect() {
    var distinct = [1, 2, 1].iterate().to_set();
    expect_equal(distinct.count, 2);
    expect_true(distinct.contains(2));
    var ages = [("Ada", 36), ("Bo", 12), ("Ada", 37)].iterate().to_map<String, int>();
    expect_equal(ages.count, 2);
    expect_equal(ages["Ada"], 37);
    expect_equal([36, 12].iterate().map((n) => $"{n}").join(", "), "36, 12");
    expect_equal(Array<String>().iterate().join(", "), "");
}
