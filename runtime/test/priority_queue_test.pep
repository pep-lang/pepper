# PriorityQueue: the greatest element first under compare<T> or a given
# comparer, building from an array, heap sort, and releasing elements.

# Pops every element of `queue`, separated by spaces.
drain(queue: PriorityQueue<int>): String {
    var result = "";
    while (!queue.is_empty) {
        var n = queue.pop();
        result = result.is_empty ? $"{n}" : $"{result} {n}";
    }
    return result;
}

[Test]
pops_the_greatest_first() {
    var queue = PriorityQueue<int>();
    expect_true(queue.is_empty);
    for (var n in [5, 1, 8, 3, 8, 2, 9, 0]) {
        queue.push(n);
    }
    expect_equal(queue.count, 8);
    expect_equal(queue.peek(), 9);
    expect_equal(drain(queue), "9 8 8 5 3 2 1 0");
    expect_true(queue.is_empty);
}

[Test]
a_reversed_comparer_pops_the_smallest_first() {
    var queue = PriorityQueue<int>((a, b) => b.compare(a));
    for (var n in [5, 1, 8, 3]) {
        queue.push(n);
    }
    expect_equal(drain(queue), "1 3 5 8");
}

[Test]
builds_from_an_array() {
    var items = [4, 10, 3, 5, 1, 7, 7, 2, 6];
    PriorityQueue<int> queue = items;
    expect_equal(drain(queue), "10 7 7 6 5 4 3 2 1");
    # The array was copied, not taken over.
    expect_equal(items.count, 9);
    expect_equal(items[0], 4);
    var smallest = PriorityQueue<int>(items, (a, b) => b.compare(a));
    expect_equal(smallest.pop(), 1);
}

[Test]
into_sorted_array_sorts_ascending() {
    PriorityQueue<int> queue = [3, 9, 1, 4, 1, 5];
    var sorted = queue.into_sorted_array();
    expect_true(sorted == [1, 1, 3, 4, 5, 9]);
    expect_true(queue.is_empty);
    queue.push(2);
    expect_equal(queue.pop(), 2);
    expect_equal(PriorityQueue<int>().into_sorted_array().count, 0);
}

[Test]
orders_strings_and_by_a_key() {
    PriorityQueue<String> words = ["pear", "apple", "fig"];
    expect_equal(words.pop(), "pear");
    var by_length = PriorityQueue<String>(["pear", "apple", "fig"], (a, b) => a.length.compare(b.length));
    expect_equal(by_length.pop(), "apple");
    expect_equal(by_length.pop(), "pear");
    expect_equal(by_length.pop(), "fig");
}

# Pushes and pops strings, then clears the queue with some left.
churn() {
    var queue = PriorityQueue<String>();
    for (var n in 0..30) {
        queue.push($"item {n}");
    }
    expect_equal(queue.pop(), "item 9");
    queue.clear();
    queue.push("last");
    PriorityQueue<String> built = ["b", "c", "a"];
    expect_equal(built.into_sorted_array()[0], "a");
}

[Test]
releases_what_it_removes() {
    var before = _pep_live_allocs();
    churn();
    expect_equal(_pep_live_allocs(), before);
}

[Test]
[ShouldPanic("PriorityQueue pop on empty PriorityQueue")]
pop_on_empty_panics() {
    var queue = PriorityQueue<int>();
    queue.pop();
}

[Test]
[ShouldPanic("PriorityQueue peek on empty PriorityQueue")]
peek_on_empty_panics() {
    PriorityQueue<int> queue = [1];
    queue.pop();
    queue.peek();
}
