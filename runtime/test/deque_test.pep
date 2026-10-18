# Deque: pushing and popping at both ends across the ring's wrap and its
# growth, indexing, iteration, and releasing the elements it removes.

# The elements of `deque` front to back, separated by spaces.
elements(deque: Deque<int>): String {
    var result = "";
    for (var n in deque) {
        result = result.is_empty ? $"{n}" : $"{result} {n}";
    }
    return result;
}

[Test]
pushes_and_pops_at_both_ends() {
    var deque = Deque<int>();
    expect_true(deque.is_empty);
    deque.push_back(2);
    deque.push_back(3);
    deque.push_front(1);
    deque.push_front(0);
    expect_equal(deque.count, 4);
    expect_equal(deque.front(), 0);
    expect_equal(deque.back(), 3);
    expect_equal(elements(deque), "0 1 2 3");
    expect_equal(deque.pop_front(), 0);
    expect_equal(deque.pop_back(), 3);
    expect_equal(deque.pop_back(), 2);
    expect_equal(deque.pop_front(), 1);
    expect_true(deque.is_empty);
}

[Test]
wraps_and_grows_in_order() {
    var deque = Deque<int>(4);
    expect_equal(deque.capacity, 4);
    # Move the front around the ring so the elements wrap past its end.
    for (var n in 0..3) {
        deque.push_back(n);
    }
    deque.pop_front();
    deque.pop_front();
    deque.push_back(3);
    deque.push_back(4);
    deque.push_back(5);
    expect_equal(deque.capacity, 4);
    expect_equal(elements(deque), "2 3 4 5");
    # Full and wrapped: growing keeps the order.
    deque.push_front(1);
    deque.push_back(6);
    expect_equal(deque.capacity, 8);
    expect_equal(elements(deque), "1 2 3 4 5 6");
    expect_equal(deque[0], 1);
    expect_equal(deque[5], 6);
}

[Test]
works_as_a_queue_far_past_its_capacity() {
    var deque = Deque<int>();
    var total = 0;
    for (var n in 0..1000) {
        deque.push_back(n);
        if (n % 3 == 0) {
            total = total + deque.pop_front();
        }
    }
    expect_equal(deque.count, 666);
    expect_equal(deque.front(), 334);
    while (!deque.is_empty) {
        total = total + deque.pop_front();
    }
    expect_equal(total, 499500);
    expect_true(deque.capacity <= 1024);
}

[Test]
indexes_writes_and_clears() {
    Deque<int> deque = [1, 2, 3];
    deque.push_front(0);
    deque[2] = 20;
    expect_equal(elements(deque), "0 1 20 3");
    deque.reserve(100);
    expect_equal(deque.capacity, 100);
    expect_equal(elements(deque), "0 1 20 3");
    deque.clear();
    expect_true(deque.is_empty);
    expect_equal(deque.capacity, 100);
    expect_equal(elements(deque), "");
    deque.push_front(7);
    expect_equal(elements(deque), "7");
}

[Test]
an_array_literal_converts() {
    Deque<String> names = ["ada", "grace"];
    expect_equal(names.front(), "ada");
    expect_equal(names.back(), "grace");
    expect_equal(names.count, 2);
}

# Fills and drains a deque of strings, front and back.
churn() {
    var deque = Deque<String>();
    for (var n in 0..20) {
        deque.push_back($"item {n}");
        deque.push_front($"front {n}");
    }
    deque.pop_back();
    deque.pop_front();
    deque[3] = "replaced";
    var kept = deque.pop_front();
    expect_equal(kept, "front 18");
    deque.clear();
    deque.push_back("last");
}

[Test]
releases_what_it_removes() {
    var before = _pep_live_allocs();
    churn();
    expect_equal(_pep_live_allocs(), before);
}

[Test]
[ShouldPanic("Deque modified during iteration")]
changing_while_iterating_panics() {
    Deque<int> deque = [1, 2, 3];
    for (var n in deque) {
        deque.push_back(n);
    }
}

[Test]
[ShouldPanic("Deque pop_front on empty Deque")]
pop_front_on_empty_panics() {
    var deque = Deque<int>();
    deque.pop_front();
}

[Test]
[ShouldPanic("Deque pop_back on empty Deque")]
pop_back_on_empty_panics() {
    Deque<int> deque = [1];
    deque.pop_front();
    deque.pop_back();
}

[Test]
[ShouldPanic("Deque index read out of bounds")]
reading_past_the_back_panics() {
    Deque<int> deque = [1, 2];
    deque.pop_front();
    expect_equal(deque[1], 0);
}
