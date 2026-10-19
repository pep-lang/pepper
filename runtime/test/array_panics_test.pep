# Array's documented panics (runtime/array.pep's `@panics`), one test each.
# The I/O pin panic is left to the io tests, which can hold a pin.

[Test]
[ShouldPanic("Array index read out of bounds")]
reading_past_the_end_panics() {
    var a = [1, 2];
    var x = a[a.count];
}

[Test]
[ShouldPanic("Array index write out of bounds")]
writing_past_the_end_panics() {
    var a = [1, 2];
    a[a.count] = 3;
}

[Test]
[ShouldPanic("Array insert index out of bounds")]
inserting_past_the_end_panics() {
    var a = [1, 2];
    a.insert(a.count + 1, 3);
}

[Test]
[ShouldPanic("Array remove index out of bounds")]
removing_past_the_end_panics() {
    var a = [1, 2];
    a.remove_at(a.count);
}

[Test]
[ShouldPanic("Array pop on empty Array")]
popping_an_empty_array_panics() {
    var a = Array<int>();
    a.pop();
}

[Test]
[ShouldPanic("Array first on empty Array")]
first_of_an_empty_array_panics() {
    var a = Array<int>();
    a.first();
}

[Test]
[ShouldPanic("Array last on empty Array")]
last_of_an_empty_array_panics() {
    var a = Array<int>();
    a.last();
}

[Test]
[ShouldPanic("Array swap index out of bounds")]
swapping_from_past_the_end_panics() {
    var a = [1, 2];
    a.swap(a.count, 0);
}

[Test]
[ShouldPanic("Array swap index out of bounds")]
swapping_to_past_the_end_panics() {
    var a = [1, 2];
    a.swap(0, a.count);
}

[Test]
[ShouldPanic("Array split_off index out of bounds")]
splitting_past_the_end_panics() {
    var a = [1, 2];
    a.split_off(a.count + 1);
}

[Test]
[ShouldPanic("ArrayIterator.current() before next()")]
current_before_next_panics() {
    var a = [1, 2];
    var it = a.iterate();
    it.current();
}

[Test]
[ShouldPanic("ArrayIterator.current() past the end")]
current_past_the_end_panics() {
    var a = [1];
    var it = a.iterate();
    while (it.next()) {}
    it.current();
}

# The edges that must not panic: the last index, insert and split_off at
# the end.
[Test]
the_edges_do_not_panic() {
    var a = [1, 2];
    expect_equal(a[a.count - 1], 2);
    a.insert(a.count, 3);
    expect_equal(a.split_off(a.count).count, 0 as ulong);
    a.swap(0, a.count - 1);
    expect_equal(a[0], 3);
}
