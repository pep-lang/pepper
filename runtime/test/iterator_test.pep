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
