# BitSet: inserting, finding and removing members across word boundaries,
# growing, iterating in order, the set operations, and equality and hashing
# that ignore capacity.

# The members of `set` in iteration order, separated by spaces.
members(set: BitSet): String {
    var result = "";
    for (var n in set) {
        result = result.is_empty ? $"{n}" : $"{result} {n}";
    }
    return result;
}

[Test]
insert_contains_and_remove() {
    var set = BitSet();
    expect_true(set.is_empty);
    expect_true(set.insert(0));
    expect_true(set.insert(63));
    expect_true(set.insert(64));
    expect_true(set.insert(1000));
    expect_false(set.insert(64));
    expect_equal(set.count, 4);
    expect_true(set.contains(63));
    expect_true(set.contains(1000));
    expect_false(set.contains(1));
    expect_false(set.contains(-1));
    expect_false(set.contains(100000));
    expect_true(set.remove(63));
    expect_false(set.remove(63));
    expect_false(set.remove(-5));
    expect_false(set.remove(5000));
    expect_false(set.contains(63));
    expect_equal(set.count, 3);
}

[Test]
capacity_grows_and_clear_keeps_it() {
    var set = BitSet(100);
    expect_equal(set.capacity, 128);
    set.insert(200);
    expect_equal(set.capacity, 256);
    set.reserve(10);
    expect_equal(set.capacity, 256);
    set.clear();
    expect_true(set.is_empty);
    expect_equal(set.capacity, 256);
}

[Test]
iterates_in_ascending_order() {
    BitSet set = [130, 5, 64, 0, 63, 5];
    expect_equal(members(set), "0 5 63 64 130");
    expect_equal(members(BitSet()), "");
    expect_equal(members(BitSet(1000)), "");
}

[Test]
removing_while_iterating_is_safe() {
    BitSet set = [1, 2, 3, 70];
    var seen = "";
    for (var n in set) {
        seen = $"{seen}{n} ";
        set.remove(n + 1);
    }
    expect_equal(seen, "1 3 70 ");
}

[Test]
set_operations_by_value() {
    BitSet a = [1, 2, 3, 100];
    BitSet b = [2, 3, 4, 200];
    expect_equal(members(a.union(b)), "1 2 3 4 100 200");
    expect_equal(members(a.intersection(b)), "2 3");
    expect_equal(members(a.difference(b)), "1 100");
    expect_equal(members(a.symmetric_difference(b)), "1 4 100 200");
    # The operands are unchanged.
    expect_equal(members(a), "1 2 3 100");
    expect_equal(members(b), "2 3 4 200");
}

[Test]
set_operations_in_place() {
    BitSet a = [1, 2, 300];
    a.union_with([2, 5]);
    expect_equal(members(a), "1 2 5 300");
    a.intersect_with([1, 5, 7]);
    expect_equal(members(a), "1 5");
    a.difference_with([5]);
    expect_equal(members(a), "1");
    a.symmetric_difference_with([1, 400]);
    expect_equal(members(a), "400");
    a.symmetric_difference_with(a);
    expect_true(a.is_empty);
}

[Test]
subset_and_disjoint() {
    BitSet small = [1, 2];
    BitSet large = [1, 2, 3, 500];
    expect_true(small.is_subset(large));
    expect_false(large.is_subset(small));
    expect_true(BitSet().is_subset(small));
    expect_true(BitSet(1000).is_subset(BitSet()));
    expect_true(small.is_disjoint([3, 500]));
    expect_false(small.is_disjoint([2]));
}

[Test]
equality_and_hash_ignore_capacity() {
    BitSet a = [1, 70];
    var b = BitSet(1000);
    b.insert(70);
    b.insert(1);
    expect_true(a == b);
    expect_equal(hash<BitSet>(a), hash<BitSet>(b));
    b.insert(900);
    expect_true(a != b);
    b.remove(900);
    expect_true(a == b);
    expect_equal(hash<BitSet>(a), hash<BitSet>(b));

    var seen = HashSet<BitSet>();
    seen.insert(a);
    expect_true(seen.contains(b));
}

[Test]
copy_is_independent() {
    BitSet a = [3];
    var b = copy(a);
    b.insert(4);
    expect_equal(members(a), "3");
    expect_equal(members(b), "3 4");
}

[Test]
[ShouldPanic("BitSet.insert: negative member")]
inserting_a_negative_member_panics() {
    var set = BitSet();
    set.insert(-1);
}
