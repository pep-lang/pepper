# Nested Arrays: `Array<Array<T>>` must release every inner Array, String and
# buffer exactly once when the outer one dies, whatever was done to it (the
# runner's leak check catches a miss or a double release).

# The outer Array holds one reference per inner Array; dropping the
# creators' references and the outer must free every inner Array, its
# buffer, and the outer's own buffer.
[Test]
nested_array_release_frees_inner_arrays() {
    var outer = Array<Array<int>>(4);
    var a = Array<int>(2);
    a.append(1);
    a.append(2);
    var b = Array<int>(2);
    b.append(3);
    b.append(4);
    var c = Array<int>(2);
    c.append(5);
    c.append(6);
    outer.append(a);
    outer.append(b);
    outer.append(c);
    expect_equal(outer.count, 3);
    expect_equal(outer[0][1], 2);
    expect_equal(outer[2][0], 5);
}

# Shift-based insert/remove and the raw-pointer swap must keep each inner
# Array's count at exactly one per slot.
[Test]
nested_array_insert_remove_swap_release_frees_all() {
    var outer = Array<Array<int>>(2);
    var a = Array<int>(1);
    a.append(1);
    var b = Array<int>(1);
    b.append(2);
    var c = Array<int>(1);
    c.append(3);
    var d = Array<int>(1);
    d.append(4);
    outer.append(a);
    outer.append(b);
    outer.insert(0, c);
    # order: c, a, b
    expect_equal(outer[0][0], 3);
    expect_equal(outer[1][0], 1);
    var removed = outer.remove_at(1);
    expect_equal(removed[0], 1);
    # order: c, b
    expect_equal(outer.count, 2);
    expect_equal(outer[1][0], 2);
    outer.append(d);
    outer.swap(0, 2);
    # order: d, b, c
    expect_equal(outer[0][0], 4);
    expect_equal(outer[1][0], 2);
    expect_equal(outer[2][0], 3);
}

# Appending past capacity reallocates the outer buffer; the old buffer must
# be freed and every inner Array released exactly once.
[Test]
nested_array_growth_release_frees_all() {
    var outer = Array<Array<int>>(1);
    for (var i in 0..10) {
        var inner = Array<int>(1);
        inner.append(i * 10);
        outer.append(inner);
    }
    expect_equal(outer.count, 10);
    expect_equal(outer[9][0], 90);
}

# Strings are struct elements too: each inner Array's String slots and the
# outer's inner-Array slots must all release on destruction.
[Test]
nested_array_of_strings_release_frees_all() {
    var outer = Array<Array<String>>(2);
    var a = Array<String>(1);
    var s1 = "one";
    a.append(s1);
    expect_equal(a.count, 1);
    expect_equal(s1.size, 3);
    var b = Array<String>(1);
    var s2 = "two";
    b.append(s2);
    outer.append(a);
    outer.append(b);
    expect_equal(outer.count, 2);
    expect_equal(outer[0][0], s1);
    expect_equal(outer[1][0], s2);
}

# clear() releases every slot; the later destruct must then find nothing to
# release: no double free, no leak.
[Test]
nested_array_clear_release_frees_all() {
    var outer = Array<Array<int>>(2);
    var a = Array<int>(1);
    a.append(1);
    var b = Array<int>(1);
    b.append(2);
    outer.append(a);
    outer.append(b);
    expect_equal(outer.count, 2);
    outer.clear();
    expect_true(outer.is_empty);
}

# clone() copies the reference slots (each copy acquires), so the original
# and the clone share the inner Arrays; both owners must be released for
# every inner Array to free.
[Test]
nested_array_clone_release_frees_all() {
    var outer = Array<Array<int>>(2);
    var a = Array<int>(1);
    a.append(7);
    outer.append(a);
    var copy = outer.clone();
    expect_equal(copy.count, 1);
    expect_equal(copy[0][0], 7);
    copy[0].append(8);
    expect_equal(outer[0].count, 2);
    expect_equal(outer[0][1], 8);
}
