# Array algorithms (binary search, fill, retain, dedup, resize, split_off)
# and ArraySlice, including how each keeps the counts of struct elements.

struct Tally {
    int alive;
    construct(this.alive = 1) {}
    destruct {
        alive = 0;
    }
}

[Test]
binary_search_finds_the_first_match() {
    var a = [1, 3, 3, 3, 5, 7];
    expect_equal(a.binary_search(3).value(), 1);
    expect_equal(a.binary_search(7).value(), 5);
    expect_true(a.binary_search(4).is_empty());
    expect_true(a.binary_search(0).is_empty());
    expect_true(a.binary_search(8).is_empty());
    expect_true(Array<int>().binary_search(1).is_empty());
}

[Test]
binary_search_on_strings() {
    var a = ["apple", "fig", "pear"];
    expect_equal(a.binary_search("fig").value(), 1);
    expect_true(a.binary_search("kiwi").is_empty());
}

[Test]
binary_search_by_uses_the_order() {
    var a = [10, 20, 30];
    expect_equal(a.binary_search_by((x) => x.compare(20)).value(), 1);
    expect_true(a.binary_search_by((x) => x.compare(25)).is_empty());
}

[Test]
bounds_bracket_equal_runs() {
    var a = [1, 3, 3, 5];
    expect_equal(a.lower_bound(3), 1);
    expect_equal(a.upper_bound(3), 3);
    expect_equal(a.lower_bound(0), 0);
    expect_equal(a.upper_bound(9), 4);
    expect_equal(a.lower_bound(4), 3);
    expect_equal(a.upper_bound(4), 3);
}

[Test]
is_sorted_checks_neighbors() {
    expect_true(Array<int>().is_sorted());
    expect_true([1].is_sorted());
    expect_true([1, 1, 2].is_sorted());
    expect_false([2, 1].is_sorted());
}

[Test]
fill_replaces_every_element_and_counts() {
    var a = [1, 2, 3];
    a.fill(9);
    expect_true(a == [9, 9, 9]);
    var t = Tally();
    var old = Tally();
    var items = Array<Tally>();
    items.append(old);
    items.append(old);
    items.fill(t);
    expect_equal(__refcount<Tally>(t), 3);
    expect_equal(__refcount<Tally>(old), 1);
}

[Test]
retain_keeps_order_and_releases_the_rest() {
    var a = [1, 2, 3, 4, 5, 6];
    a.retain((x) => x % 2 == 0);
    expect_true(a == [2, 4, 6]);
    var keep = Tally();
    var drop = Tally();
    var items = Array<Tally>();
    items.append(drop);
    items.append(keep);
    items.append(drop);
    items.append(keep);
    items.retain((t) => t == keep);
    expect_equal(items.count, 2);
    expect_equal(__refcount<Tally>(keep), 3);
    expect_equal(__refcount<Tally>(drop), 1);
}

[Test]
[ShouldPanic("Array modified during retain")]
retain_that_modifies_the_array_panics() {
    var a = [1, 2, 3];
    a.retain((x) => {
        a.append(x);
        return true;
    });
}

[Test]
dedup_removes_adjacent_repeats() {
    var a = [1, 1, 2, 3, 3, 3, 1];
    a.dedup();
    expect_true(a == [1, 2, 3, 1]);
    var t = Tally();
    var items = Array<Tally>();
    items.append(t);
    items.append(t);
    items.append(t);
    items.dedup();
    expect_equal(items.count, 1);
    expect_equal(__refcount<Tally>(t), 2);
}

[Test]
resize_grows_and_shrinks() {
    var a = [1, 2];
    a.resize(4, 0);
    expect_true(a == [1, 2, 0, 0]);
    a.resize(1, 0);
    expect_true(a == [1]);
}

[Test]
split_off_moves_the_tail() {
    var a = [1, 2, 3, 4];
    var tail = a.split_off(1);
    expect_true(a == [1]);
    expect_true(tail == [2, 3, 4]);
    expect_equal(a.split_off(1).count, 0);
    var t = Tally();
    var items = Array<Tally>();
    items.append(t);
    items.append(t);
    var moved = items.split_off(0);
    expect_equal(items.count, 0);
    expect_equal(moved.count, 2);
    expect_equal(__refcount<Tally>(t), 3);
}

sum(values: ArraySlice<int>): int {
    var total = 0;
    for (var x in values) {
        total = total + x;
    }
    return total;
}

[Test]
slice_views_part_of_the_array() {
    var a = [1, 2, 3, 4, 5];
    var middle = a.slice(1, 4);
    expect_equal(middle.count, 3);
    expect_equal(middle[0], 2);
    expect_equal(middle[2], 4);
    expect_equal(sum(middle), 9);
    expect_equal(sum(a.slice(2, 2)), 0);
    expect_true(a.slice(5, 5).is_empty);
    var inner = middle.slice(1, 3);
    expect_true(inner.to_array() == [3, 4]);
    expect_equal(middle.find(4).value(), 2);
    expect_true(middle.contains(2));
    expect_false(middle.contains(5));
    expect_equal(middle.binary_search(3).value(), 1);
    expect_equal(middle.lower_bound(9), 3);
    expect_true(middle.is_sorted());
}

[Test]
slice_keeps_its_array_alive() {
    var t = Tally();
    var view = ArraySlice<Tally>();
    {
        var items = Array<Tally>();
        items.append(t);
        view = items.slice(0, 1);
    }
    expect_equal(view[0].alive, 1);
    expect_equal(__refcount<Tally>(t), 2);
}

[Test]
[ShouldPanic("Array slice out of bounds")]
slice_past_the_end_panics() {
    var a = [1, 2];
    a.slice(1, 3);
}

[Test]
[ShouldPanic("ArraySlice index out of bounds")]
slice_index_past_its_end_panics() {
    var a = [1, 2, 3];
    var view = a.slice(0, 2);
    view[2];
}

[Test]
[ShouldPanic("Array modified while a slice of it is in use")]
slice_after_append_panics() {
    var a = [1, 2];
    var view = a.slice(0, 2);
    a.append(3);
    view[0];
}

[Test]
[ShouldPanic("Array modified while a slice of it is in use")]
slice_after_store_panics() {
    var a = [1, 2];
    var view = a.slice(0, 2);
    a[0] = 5;
    for (var x in view) {}
}
