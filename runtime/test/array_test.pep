# Array: growth, indexing, insert/remove, search, copy, concatenation,
# equality, sort, and how each operation keeps the counts of the elements
# it holds, moves or drops.

struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}
}

struct Tally {
    int alive;
    construct(this.alive = 1) {}
    destruct {
        alive = 0;
    }
}

struct Item {
    int key;
    int tag;
    construct(key: int, tag: int) {
        this.key = key;
        this.tag = tag;
    }
}

[Test]
append_and_count() {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    expect_equal(a.count, 3);
    expect_equal(a[0], 1);
    expect_equal(a[1], 2);
    expect_equal(a[2], 3);
}

[Test]
ctor_capacity() {
    var a = Array<int>(8);
    expect_true(a.capacity >= 8);
    expect_equal(a.count, 0);
    expect_true(a.is_empty);
}

[Test]
reserve_never_shrinks() {
    var a = Array<int>();
    a.reserve(8);
    a.reserve(2);
    expect_true(a.capacity >= 8);
}

[Test]
index_get_and_set() {
    var a = Array<int>(4);
    a.append(1);
    a.append(2);
    a.append(3);
    a[1] = 7;
    expect_equal(a[1], 7);
    expect_equal(a[0], 1);
    expect_equal(a[2], 3);
}

[Test]
insert_front_middle_end() {
    var a = Array<int>();
    a.append(5);
    a.insert(0, 1);
    a.insert(1, 3);
    a.insert(a.count, 9);
    expect_true(a == [1, 3, 5, 9]);
}

[Test]
remove_at_shifts() {
    var a = [1, 2, 3];
    expect_equal(a.remove_at(1), 2);
    expect_true(a == [1, 3]);
}

[Test]
pop_returns_last() {
    var a = [1, 2];
    expect_equal(a.pop(), 2);
    expect_true(a == [1]);
}

[Test]
first_and_last() {
    var a = [1, 2, 3];
    expect_equal(a.first(), 1);
    expect_equal(a.last(), 3);
}

[Test]
clear_then_reuse() {
    var a = Array<int>();
    a.append(1);
    a.clear();
    expect_true(a.is_empty);
    a.append(9);
    expect_true(a == [9]);
}

[Test]
truncate_drops_tail() {
    var a = [1, 2, 3];
    a.truncate(1);
    expect_true(a == [1]);
    a.truncate(5);
    expect_equal(a.count, 1);
}

[Test]
swap_and_reverse() {
    var a = [1, 2, 3];
    a.swap(0, 2);
    expect_true(a == [3, 2, 1]);
    a.reverse();
    expect_true(a == [1, 2, 3]);
}

[Test]
find_and_contains() {
    var a = [1, 2, 3];
    expect_equal(a.find(2).value(), 1);
    expect_false(a.find(99).is_value());
    expect_true(a.contains(3));
    expect_false(a.contains(99));
}

[Test]
clone_is_independent() {
    var a = [1];
    var b = a.clone();
    b.append(2);
    expect_true(a == [1]);
    expect_true(b == [1, 2]);
}

[Test]
plus_operator_concatenates() {
    var a = [1];
    var b = [2];
    var c = a + b;
    expect_true(c == [1, 2]);
    expect_true(a == [1]);
    expect_true(b == [2]);
}

[Test]
equality_pod() {
    var a = [1, 2];
    var b = [1, 2];
    expect_true(a == b);
    b.append(3);
    expect_false(a == b);
    b[0] = 9;
    var c = [1, 2];
    expect_false(b == c);
}

[Test]
inequality_operator() {
    var a = [1];
    var b = [1];
    expect_false(a != b);
    b.append(2);
    expect_true(a != b);
}

[Test]
array_of_structs() {
    var points = Array<Point>();
    var p = Point();
    p.x = 3;
    p.y = 4;
    points.append(p);
    var q = points[0];
    expect_equal(q.x, 3);
    expect_equal(q.y, 4);
}

[Test]
refcount_clear_destroys_elements() {
    var t = Tally();
    var a = Array<Tally>();
    a.append(t);
    a.append(Tally());
    expect_equal(__refcount<Tally>(t), 2);
    a.clear();
    expect_equal(t.alive, 1);
    expect_equal(__refcount<Tally>(t), 1);
}

# A tuple holding a reference is not plain data (`__is_pod`), so `clear`
# still releases the references inside its elements.
[Test]
refcount_clear_releases_references_in_tuples() {
    var t = Tally();
    var a = Array<(int, Tally)>();
    a.append((1, t));
    expect_equal(__refcount<Tally>(t), 2);
    a.clear();
    expect_equal(__refcount<Tally>(t), 1);
    var plain = Array<(int, long)>();
    plain.append((1, 2));
    plain.clear();
    expect_true(plain.is_empty);
}

[Test]
refcount_truncate_releases_tail_only() {
    var a = Array<Tally>();
    var t = Tally();
    a.append(t);
    a.append(Tally());
    a.append(Tally());
    a.truncate(2);
    expect_equal(__refcount<Tally>(t), 2);
    expect_equal(a.count, 2);
    expect_equal(t.alive, 1);
    a.truncate(0);
    expect_equal(__refcount<Tally>(t), 1);
    expect_equal(t.alive, 1);
}

# insert shifts each moved reference into its new slot by moving the raw
# pointer (shared_ptr move semantics): no count changes at all.
[Test]
refcount_insert_shifts_without_churn() {
    var a = Array<Point>();
    var p1 = Point(1);
    var p2 = Point(2);
    a.append(p1);
    a.append(p2);
    expect_equal(__refcount<Point>(p1), 2);
    expect_equal(__refcount<Point>(p2), 2);
    var p3 = Point(3);
    a.insert(0, p3);
    expect_equal(__refcount<Point>(p1), 2);
    expect_equal(__refcount<Point>(p2), 2);
    expect_equal(__refcount<Point>(p3), 2);
    expect_equal(a[0].x, 3);
    expect_equal(a[1].x, 1);
    expect_equal(a[2].x, 2);
    a.clear();
    expect_equal(__refcount<Point>(p1), 1);
    expect_equal(__refcount<Point>(p2), 1);
    expect_equal(__refcount<Point>(p3), 1);
}

# The Array is the sole owner of these elements. A shift implemented as
# per-slot release/acquire stores would destroy them mid-move (their only
# reference), so shifts must move raw pointer slots instead.
[Test]
refcount_shift_of_unreferenced_element() {
    var a = Array<Tally>();
    a.append(Tally());
    a.append(Tally());
    a.insert(0, Tally());
    expect_equal(a.count, 3);
    expect_equal(a[0].alive, 1);
    expect_equal(a[1].alive, 1);
    expect_equal(a[2].alive, 1);
    var r = a.remove_at(0);
    expect_equal(r.alive, 1);
    expect_equal(a.count, 2);
    expect_equal(a[0].alive, 1);
    expect_equal(a[1].alive, 1);
    a.clear();
    expect_equal(r.alive, 1);
}

[Test]
empty_array_boundaries() {
    var e = Array<int>();
    expect_true(e.is_empty);
    expect_equal(e.count, 0);
    expect_false(e.find(1).is_value());
    expect_false(e.contains(1));
    var f = Array<int>();
    expect_true(e == f);
    e.truncate(0);
    expect_true(e.is_empty);
}

[Test]
growth_from_zero_capacity() {
    var g = Array<int>();
    for (var i in 0..10) {
        g.append(i * i);
    }
    expect_true(g.capacity >= 10);
    expect_equal(g.count, 10);
    for (var i in 0..10) {
        expect_equal(g[i], i * i);
    }
}

[Test]
self_append_terminates_and_doubles() {
    var h = [1, 2];
    h += h;
    expect_true(h == [1, 2, 1, 2]);
}

[Test]
plus_with_empty_operand() {
    var p = [5];
    var q = p + Array<int>();
    expect_true(q == [5]);
    expect_true(p == [5]);
    var r = Array<int>() + p;
    expect_true(r == [5]);
}

[Test]
insert_into_empty_and_remove_only_element() {
    var r = Array<int>();
    r.insert(0, 7);
    expect_true(r == [7]);
    expect_equal(r.remove_at(0), 7);
    expect_true(r.is_empty);
}

[Test]
truncate_at_and_beyond_size() {
    var t = [1, 2];
    t.truncate(2);
    expect_equal(t.count, 2);
    t.truncate(99);
    expect_true(t == [1, 2]);
}

[Test]
self_swap_and_tiny_reverses() {
    var w = [1];
    w.swap(0, 0);
    expect_true(w == [1]);
    w.reverse();
    expect_true(w == [1]);
    var z = Array<int>();
    z.reverse();
    expect_true(z.is_empty);
    var two = [1, 2];
    two.reverse();
    expect_true(two == [2, 1]);
}

[Test]
index_set_returns_stored_value() {
    var v = [0];
    var stored = v[0] = 42;
    expect_equal(stored, 42);
    expect_equal(v[0], 42);
}

[Test]
reserve_zero_then_append() {
    var s = Array<int>();
    s.reserve(0);
    s.append(3);
    expect_true(s == [3]);
}

# Struct-typed elements are references: the clone shares the inner Array,
# so an append through one view is visible through both.
[Test]
nested_clone_shares_inner_arrays() {
    var n = Array<Array<int>>();
    n.append([1, 2]);
    var copy = n.clone();
    copy[0].append(3);
    expect_equal(copy[0][2], 3);
    expect_equal(n[0].count, 3);
    expect_equal(copy[0].count, 3);
}

[Test]
array_of_strings_compares_by_value() {
    var strings = Array<String>();
    strings.append("ab");
    strings.append("cd");
    expect_equal(strings.find("cd").value(), 1);
    expect_true(strings.contains("ab"));
    expect_equal(strings[0], "ab");
    var other = Array<String>();
    other.append("ab");
    other.append("cd");
    expect_true(strings == other);
}

[Test]
sort_is_ordered_and_stable() {
    var names = ["pear", "apple", "fig"];
    names.sort((a, b) => a.compare(b));
    expect_true(names == ["apple", "fig", "pear"]);
    var numbers = Array<int>();
    for (var i in 0..100) {
        numbers.append((i * 37) % 101);
    }
    numbers.sort((a, b) => a - b);
    for (var i in 1..100) {
        expect_true(numbers[i - 1] <= numbers[i]);
    }
    numbers.sort((a, b) => b - a);
    expect_true(numbers[0] >= numbers[99]);
    var items = Array<Item>();
    for (var i in 0..20) {
        items.append(Item(i % 3, i));
    }
    items.sort((a, b) => a.key - b.key);
    for (var i in 1..20) {
        expect_true(items[i - 1].key <= items[i].key);
        expect_true(items[i - 1].key != items[i].key || items[i - 1].tag < items[i].tag);
    }
    var empty = Array<int>();
    empty.sort((a, b) => a - b);
    expect_equal(empty.count, 0);
}

# sort, reverse and swap permute raw slots; append_all, `+` and clone copy a
# block and acquire each copy; truncate and the destructor release without
# per-slot stores. Every count must come back to 1.
[Test]
refcount_bulk_operations_keep_counts() {
    var p = Point(5);
    var q = Point(1);
    var r = Point(3);
    {
        var a = Array<Point>();
        a.append(p);
        a.append(q);
        a.append(r);
        a.sort((m, n) => m.x - n.x);
        expect_equal(a[0].x, 1);
        expect_equal(a[1].x, 3);
        expect_equal(a[2].x, 5);
        expect_equal(__refcount<Point>(p), 2);
        expect_equal(__refcount<Point>(q), 2);
        a.reverse();
        a.swap(0, 2);
        expect_equal(a[0].x, 1);
        expect_equal(a[2].x, 5);
        a += a;
        expect_equal(a.count, 6);
        expect_equal(__refcount<Point>(p), 3);
        var b = a + a.clone();
        expect_equal(b.count, 12);
        expect_equal(__refcount<Point>(p), 7);
        b.truncate(1);
        expect_equal(__refcount<Point>(q), 4);
        expect_equal(__refcount<Point>(p), 3);
        var popped = a.pop();
        expect_equal(popped.x, 5);
        expect_equal(__refcount<Point>(p), 3);
        var removed = a.remove_at(0);
        expect_equal(removed.x, 1);
        expect_equal(__refcount<Point>(q), 4);
    }
    expect_equal(__refcount<Point>(p), 1);
    expect_equal(__refcount<Point>(q), 1);
    expect_equal(__refcount<Point>(r), 1);
}

# Tuples holding a String are not plain data: every path that drops or moves
# them must release or move the String exactly once (the runner's leak check
# catches a miss).
[Test]
value_elements_holding_references_are_released() {
    var a = Array<(int, String)>();
    for (var i in 0..20) {
        a.append((20 - i, "item {i}"));
    }
    a.insert(3, (100, "inserted"));
    var gone = a.remove_at(5);
    a.sort((m, n) => m.0 - n.0);
    expect_equal(a[0].0, 1);
    expect_equal(a[a.count - 1].1, "inserted");
    a.reverse();
    a.append_all(a);
    a.truncate(30);
    var last = a.pop();
    a.clear();
    a.append((1, "again"));
}

[Test]
sort_is_stable_and_handles_odd_lengths() {
    var a = Array<(int, int)>();
    for (var i in 0..37) {
        a.append((i % 5, i));
    }
    a.sort((m, n) => m.0 - n.0);
    for (var i in 1..37) {
        var before = a[i - 1];
        var here = a[i];
        expect_true(before.0 <= here.0);
        expect_true(before.0 != here.0 || before.1 <= here.1);
    }
}

# String and Array declare `==`/`!=`: comparisons of the raw buffer pointers
# inside Array must not dispatch to them.
[Test]
sort_and_destroy_elements_with_their_own_comparison() {
    var names = ["pear", "apple", "fig"];
    names.sort((a, b) => a.compare(b));
    expect_equal(names[0], "apple");
    expect_equal(names[2], "pear");
    var nested = Array<Array<int>>();
    nested.append([3, 4]);
    nested.append([1]);
    nested.sort((a, b) => (a.count as int) - (b.count as int));
    expect_equal(nested[0][0], 1);
}

# An empty Array is not allocated until it is written or shared:
# creating one, reading it and iterating it allocate nothing.
[Test]
empty_array_allocates_nothing() {
    var before = _pep_live_allocs();
    var a = Array<int>();
    var b = Array<String>();
    expect_equal(a.count, 0);
    expect_true(a.is_empty);
    expect_equal(a.capacity, 0);
    expect_false(a.contains(3));
    expect_true(a == Array<int>());
    for (var x in b) {
        expect_true(false);
    }
    expect_equal(_pep_live_allocs(), before);
}

[Test]
first_append_allocates() {
    var a = Array<int>();
    var before = _pep_live_allocs();
    a.append(1);
    # The Array object and its buffer.
    expect_equal(_pep_live_allocs(), before + 2);
    expect_equal(a.count, 1);
    expect_equal(a[0], 1);
}

struct Holder {
    Array<int> items = Array<int>();
    construct() {}
}

# A second name for an empty Array shares one object with the first, so
# each sees what the other appends.
[Test]
empty_array_shares_when_copied() {
    var a = Array<int>();
    var b = a;
    b.append(4);
    expect_equal(a.count, 1);
    var holder = Holder();
    expect_equal(holder.items.count, 0);
    var items = holder.items;
    items.append(5);
    expect_equal(holder.items[0], 5);
    holder.items.append(6);
    expect_equal(items.count, 2);
    var nested = Array<Array<int>>();
    nested.append(Array<int>());
    nested[0].append(7);
    expect_equal(nested[0][0], 7);
}

[Value]
struct ValueHolder {
    var items: Array<int>;

    construct(this.items = Array<int>()) {}
}

[Test]
empty_array_in_a_value_is_shared_by_its_copies() {
    var pair = (1, Array<int>());
    var pair_copy = pair;
    pair_copy.1.append(2);
    expect_equal(pair.1.count, 1);
    var holder = ValueHolder();
    var holder_copy = holder;
    holder_copy.items.append(3);
    expect_equal(holder.items.count, 1);
    int[]? found = Optional<int[]>.Value(Array<int>());
    found.value().append(4);
    expect_equal(found.value().count, 1);
}

[Test]
data_of_empty_array_is_null() {
    var a = Array<int>(8);
    expect_true(unsafe_cast<__ptr<u8>>(a.data()) == __null);
    a.append(1);
    a.remove_at(0);
    expect_true(unsafe_cast<__ptr<u8>>(a.data()) == __null);
}

[Test]
data_points_at_the_elements() {
    var a = Array<int>();
    a.append(10);
    a.append(20);
    var p = a.data();
    expect_equal(p[0], 10);
    expect_equal(p[1], 20);
    p[1] = 21;
    expect_equal(a[1], 21);
}

[Test]
append_from_round_trips_through_data() {
    var a = Array<u8>();
    a.append(1);
    a.append(2);
    a.append(3);
    var b = Array<u8>();
    b.append(0);
    b.append_from(a.data(), a.count);
    expect_equal(b.count, 4);
    expect_equal(b[0], 0);
    expect_equal(b[1], 1);
    expect_equal(b[3], 3);
    b.append_from(__null, 0);
    expect_equal(b.count, 4);
}

[Test]
append_from_acquires_struct_elements() {
    var t = Tally();
    var a = Array<Tally>();
    a.append(t);
    a.append(t);
    var b = Array<Tally>();
    b.append_from(a.data(), a.count);
    expect_equal(b.count, 2);
    # One reference in `t`, two in `a`, two in `b`.
    expect_equal(__refcount<Tally>(t), 5);
}

[Test]
append_from_nothing_keeps_a_loop_running() {
    var a = Array<Tally>();
    a.append(Tally());
    var seen = 0;
    for (var t in a) {
        a.append_from(__null, 0);
        seen = seen + t.alive;
    }
    expect_equal(seen, 1);
}
