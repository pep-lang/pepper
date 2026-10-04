# Atomic<T>: every operation on numbers and on a `[Shared]` struct (with the
# reference counts its slot holds), and counters that many threads update
# at once.

import async;

# Atomic<T> needs a thread-safe struct T: `[Shared]`, with const fields.
[Shared]
struct Point {
    const x: int;
    construct(this.x = 0) {}
}

[Test]
load_store_pod() {
    var a = async.Atomic<int>(41);
    expect_equal(a.load(), 41);
    a.store(99);
    expect_equal(a.load(), 99);
}

[Test]
load_store_long() {
    var a = async.Atomic<long>(1234567890123);
    expect_equal(a.load(), 1234567890123);
    a.store(42);
    expect_equal(a.load(), 42);
}

[Test]
load_store_struct() {
    var a = async.Atomic<Point>();
    var p = Point(7);
    a.store(p);
    var q = a.load();
    expect_equal(q.x, 7);
    # Slot holds the ref, and load() returned an owned copy: p + slot + q.
    expect_equal(__refcount<Point>(p), 3);
}

[Test]
load_store_double() {
    var a = async.Atomic<double>(1.5);
    expect_equal(a.load(), 1.5);
    a.store(2.25);
    expect_equal(a.load(), 2.25);
    var b = async.Atomic<double>(3.0);
    expect_true(b.compare_exchange(3.0, 4.0));
    expect_equal(b.load(), 4.0);
}

[Test]
store_replaces_struct_ref() {
    var a = async.Atomic<Point>();
    var p1 = Point(1);
    a.store(p1);
    expect_equal(__refcount<Point>(p1), 2);
    var p2 = Point(2);
    a.store(p2);
    # Slot dropped p1's ref and took p2's.
    expect_equal(__refcount<Point>(p1), 1);
    expect_equal(__refcount<Point>(p2), 2);
    expect_equal(a.load().x, 2);
}

[Test]
compare_exchange_success_and_failure_pod() {
    var a = async.Atomic<int>(10);
    expect_true(a.compare_exchange(10, 20));
    expect_equal(a.load(), 20);
    # Failure: expected does not match the slot.
    expect_false(a.compare_exchange(10, 30));
    expect_equal(a.load(), 20);
}

[Test]
compare_exchange_struct_refcount() {
    var a = async.Atomic<Point>();
    var p1 = Point(1);
    a.store(p1);
    expect_equal(__refcount<Point>(p1), 2);
    var p2 = Point(2);
    # Success: slot takes p2, drops p1.
    expect_true(a.compare_exchange(p1, p2));
    expect_equal(__refcount<Point>(p1), 1);
    expect_equal(__refcount<Point>(p2), 2);
    # Failure: expected no longer matches (slot holds p2).
    var p3 = Point(3);
    expect_false(a.compare_exchange(p1, p3));
    expect_equal(__refcount<Point>(p3), 1);
    expect_equal(a.load().x, 2);
}

[Test]
exchange_pod() {
    var a = async.Atomic<int>(5);
    expect_equal(a.exchange(8), 5);
    expect_equal(a.load(), 8);
}

[Test]
exchange_struct_refcount() {
    var a = async.Atomic<Point>();
    var p1 = Point(1);
    a.store(p1);
    var p2 = Point(2);
    var old = a.exchange(p2);
    expect_equal(old.x, 1);
    # The returned old ref is owned by the caller: it must not be released.
    expect_equal(__refcount<Point>(p1), 2);
    expect_equal(__refcount<Point>(p2), 2);
    expect_equal(a.load().x, 2);
}

[Test]
fetch_ops_int() {
    var a = async.Atomic<int>(10);
    expect_equal(a.fetch_add(5), 10);
    expect_equal(a.load(), 15);
    expect_equal(a.fetch_sub(3), 15);
    expect_equal(a.load(), 12);
    expect_equal(a.fetch_and(12), 12);
    expect_equal(a.load(), 12);
    expect_equal(a.fetch_or(5), 12);
    expect_equal(a.load(), 13);
    expect_equal(a.fetch_xor(13), 13);
    expect_equal(a.load(), 0);
}

[Test]
fetch_ops_long() {
    var a = async.Atomic<long>(100);
    expect_equal(a.fetch_add(50), 100);
    expect_equal(a.load(), 150);
    expect_equal(a.fetch_sub(30), 150);
    expect_equal(a.load(), 120);
    expect_equal(a.fetch_and(128), 120);
    expect_equal(a.load(), 0);
    expect_equal(a.fetch_or(7), 0);
    expect_equal(a.load(), 7);
    expect_equal(a.fetch_xor(127), 7);
    expect_equal(a.load(), 120);
}

[Test]
is_lock_free() {
    expect_true(async.Atomic<int>(0).is_lock_free());
    expect_true(async.Atomic<long>(0).is_lock_free());
    expect_true(async.Atomic<Point>().is_lock_free());
}

const THREADS = 4;
const ADD_STEPS = 50000;
const COMPARE_EXCHANGE_STEPS = 25000;
const added = async.Atomic<long>(0);
const added_total = async.Atomic<long>(0);
const swapped = async.Atomic<long>(0);
const wins = async.Atomic<long>(0);

# Adds one ADD_STEPS times, summing the values fetch_add returned.
add_many() {
    long total = 0;
    var i = 0;
    while (i < ADD_STEPS) {
        total = total + added.fetch_add(1) + 1;
        i = i + 1;
    }
    added_total.fetch_add(total);
}

# Increments with a compare-exchange retry loop: each call wins exactly one
# step of the counter.
increment_many() {
    var i = 0;
    while (i < COMPARE_EXCHANGE_STEPS) {
        var current = swapped.load();
        while (!swapped.compare_exchange(current, current + 1)) {
            current = swapped.load();
        }
        wins.fetch_add(1);
        i = i + 1;
    }
}

# Spawns THREADS threads running `body` and joins them.
run_threads(body: async.ThreadBody) {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < THREADS) {
        workers.append(async.Thread.spawn(body));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
}

[Test]
contention() {
    run_threads(add_many);
    long n = THREADS * ADD_STEPS;
    # fetch_add returns the previous value: across all threads the returned
    # old values are exactly 0..n-1 (each once) iff no update was lost, so
    # the total is exact.
    expect_equal(added.load(), n);
    expect_equal(added_total.load(), n * (n - 1) / 2 + n);

    run_threads(increment_many);
    # Every call wins exactly one step, and the counter advances by exactly
    # one per win: any lost or duplicated update breaks final == wins.
    long steps = THREADS * COMPARE_EXCHANGE_STEPS;
    expect_equal(wins.load(), steps);
    expect_equal(swapped.load(), steps);
}
