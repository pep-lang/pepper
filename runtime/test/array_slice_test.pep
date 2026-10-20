# ArraySlice views: split_at, chunks, windows, ==, compare, and how each
# stays fail-fast when the Array changes underneath it.

struct Tally {
    int alive;
    construct(this.alive = 1) {}
    destruct {
        alive = 0;
    }
}

# The first element of each run, then the run's count, flattened.
runs(iterator: ArrayChunks<int>): Array<int> {
    var result = Array<int>();
    for (var run in iterator) {
        result.append(run.count == 0 ? -1 : run[0]);
        result.append(run.count as int);
    }
    return result;
}

[Test]
split_at_splits_in_two() {
    var a = [1, 2, 3, 4, 5];
    var (head, tail) = a.slice(0, 5).split_at(2);
    expect_true(head.to_array() == [1, 2]);
    expect_true(tail.to_array() == [3, 4, 5]);
    var (none, all) = a.slice(1, 4).split_at(0);
    expect_equal(none.count, 0);
    expect_true(all.to_array() == [2, 3, 4]);
    var (whole, rest) = a.slice(1, 4).split_at(3);
    expect_equal(whole.count, 3);
    expect_true(rest.is_empty);
    var (left, right) = Array<int>().slice(0, 0).split_at(0);
    expect_true(left.is_empty && right.is_empty);
}

[Test]
[ShouldPanic("ArraySlice slice out of bounds")]
split_at_past_the_end_panics() {
    var a = [1, 2];
    a.slice(0, 2).split_at(3);
}

[Test]
chunks_cover_the_slice() {
    var a = [1, 2, 3, 4, 5];
    expect_true(runs(a.chunks(2)) == [1, 2, 3, 2, 5, 1]);
    expect_true(runs(a.chunks(5)) == [1, 5]);
    expect_true(runs(a.chunks(9)) == [1, 5]);
    expect_true(runs(a.chunks(1)) == [1, 1, 2, 1, 3, 1, 4, 1, 5, 1]);
    expect_true(runs(a.slice(1, 5).chunks(2)) == [2, 2, 4, 2]);
    expect_equal(runs(Array<int>().chunks(3)).count, 0);
    expect_true(runs([7].chunks(3)) == [7, 1]);
}

[Test]
windows_overlap() {
    var a = [1, 2, 3, 4];
    expect_true(runs(a.windows(2)) == [1, 2, 2, 2, 3, 2]);
    expect_true(runs(a.windows(4)) == [1, 4]);
    expect_equal(runs(a.windows(5)).count, 0);
    expect_true(runs(a.windows(1)) == [1, 1, 2, 1, 3, 1, 4, 1]);
    expect_true(runs(a.slice(1, 4).windows(3)) == [2, 3]);
    expect_equal(runs(Array<int>().windows(1)).count, 0);
    var same = [5, 5, 5];
    for (var pair in same.windows(2)) {
        expect_true(pair[0] == pair[1]);
    }
}

[Test]
chunks_iterator_ends_and_stays_ended() {
    var it = [1, 2, 3].chunks(2);
    expect_true(it.next());
    expect_true(it.next());
    expect_false(it.next());
    expect_false(it.next());
}

[Test]
[ShouldPanic("ArraySlice chunk size is 0")]
chunks_of_zero_panic() {
    var a = [1, 2];
    a.chunks(0);
}

[Test]
[ShouldPanic("ArraySlice chunk size is 0")]
windows_of_zero_panic() {
    var a = [1, 2];
    a.windows(0);
}

[Test]
[ShouldPanic("ArrayChunks.current() past the end")]
chunks_current_past_the_end_panics() {
    var it = [1].chunks(1);
    it.next();
    it.next();
    it.current();
}

[Test]
[ShouldPanic("Array modified while a slice of it is in use")]
chunks_after_append_panic() {
    var a = [1, 2, 3, 4];
    for (var run in a.chunks(2)) {
        a.append(run[0]);
    }
}

[Test]
[ShouldPanic("Array modified while a slice of it is in use")]
a_run_kept_after_a_change_panics() {
    var a = [1, 2, 3, 4];
    var it = a.windows(2);
    it.next();
    var run = it.current();
    a.pop();
    run[0];
}

[Test]
slices_compare_by_elements() {
    var a = [1, 2, 3, 1, 2];
    expect_true(a.slice(0, 2) == a.slice(3, 5));
    expect_false(a.slice(0, 2) != a.slice(3, 5));
    expect_true(a.slice(0, 2) != a.slice(1, 3));
    expect_true(a.slice(0, 2) != a.slice(0, 3));
    expect_true(a.slice(1, 1) == Array<int>().slice(0, 0));
    expect_equal(a.slice(0, 2).compare(a.slice(3, 5)), 0);
    expect_true(a.slice(0, 2).compare(a.slice(1, 3)) < 0);
    expect_true(a.slice(0, 2).compare(a.slice(0, 3)) < 0);
    expect_true(a.slice(2, 3).compare(a.slice(0, 5)) > 0);
    expect_equal(a.slice(0, 0).compare(a.slice(4, 4)), 0);
    var words = ["b", "a", "b"];
    expect_true(words.slice(0, 1) == words.slice(2, 3));
}

[Test]
[ShouldPanic("Array modified while a slice of it is in use")]
comparing_a_stale_slice_panics() {
    var a = [1, 2];
    var view = a.slice(0, 1);
    a[0] = 3;
    view == a.slice(1, 2);
}

[Test]
runs_keep_their_array_alive() {
    var t = Tally();
    var it = Array<Tally>().chunks(1);
    {
        var items = Array<Tally>();
        items.append(t);
        items.append(t);
        it = items.chunks(1);
    }
    var seen = 0;
    for (var run in it) {
        expect_equal(run[0].alive, 1);
        seen = seen + 1;
    }
    expect_equal(seen, 2);
    expect_equal(__refcount<Tally>(t), 3);
}
