# Threads: spawning and joining, thread names and ids, ThreadLocal values,
# processor counts, closures and `shared` functions as thread bodies, and
# `[Shared]` objects and exported globals used from many threads at once.

import async;

const ran = async.Atomic<long>(0);
const names_ok = async.Atomic<long>(0);
# The runtime's globals are initialized before this file's, so an
# initializer may already use the async module.
const initializing_thread = async.Thread.current();

private work() {
    var me = async.Thread.current();
    if (me.name() == "worker" && !me.is_finished()) {
        names_ok.fetch_add(1);
    }
    ran.fetch_add(1);
}

unnamed() {}

[Test]
threads_spawn_and_join() {
    var main_thread = async.Thread.current();
    expect_equal(main_thread.name(), "main");
    expect_equal(initializing_thread.id(), main_thread.id());
    expect_equal(async.Thread.current().id(), main_thread.id());
    expect_false(main_thread.is_joinable());

    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 8) {
        workers.append(async.Thread.spawn(work, "worker"));
        i = i + 1;
    }
    var ids = HashSet<async.ThreadId>();
    for (var worker in workers) {
        expect_true(worker.is_joinable());
        worker.join();
        expect_true(worker.is_finished());
        expect_false(worker.is_joinable());
        ids.insert(worker.id());
    }
    # Every thread has its own id, ran, and saw its own Thread.
    expect_equal(ids.count, 8);
    expect_equal(ran.load(), 8);
    expect_equal(names_ok.load(), 8);

    async.ThreadBody body = unnamed;
    var anonymous = async.Thread.spawn(body);
    anonymous.join();
    expect_equal(anonymous.name(), "");
}

[Test]
dropped_thread_runs_to_completion() {
    # A dropped, unjoined thread is detached and still runs to completion.
    async.Thread.spawn(work, "worker");
    while (ran.load() < 1) {
        async.Thread.sleep(1);
    }
    expect_equal(names_ok.load(), 1);
}

struct Tracker {
    int value;
    construct(this.value = 0) {}
    destruct {
        released.fetch_add(1);
    }
}

private const released = async.Atomic<long>(0);
private const counter = async.ThreadLocal<int>();
const tracker = async.ThreadLocal<Tracker>();
private const sum = async.Atomic<long>(0);

count_locally() {
    expect_false(counter.is_set());
    expect_equal(counter.get(), 0);
    var i = 0;
    while (i < 1000) {
        counter.set(counter.get() + 1);
        i = i + 1;
    }
    sum.fetch_add(counter.get());
    tracker.set(Tracker(counter.get()));
}

[Test]
thread_local_values() {
    counter.set(-5);
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(count_locally));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    # Each thread counted on its own value, and released it as it exited.
    expect_equal(sum.load(), 4000);
    expect_equal(counter.get(), -5);
    expect_equal(released.load(), 4);

    tracker.set(Tracker(1));
    tracker.set(Tracker(2));
    # set releases the value it replaces.
    expect_equal(released.load(), 5);
    with (var latest = tracker.enter()) {
        expect_equal(latest.value, 2);
    } else {
        panic("this thread set a value");
    }
    tracker.clear();
    expect_equal(released.load(), 6);
    expect_false(tracker.is_set());
    counter.clear();
}

[Test]
processor_counts() {
    var logical = async.logical_cpus();
    var physical = async.physical_cpus();
    expect_true(logical >= 1);
    expect_true(physical >= 1);
    # Hyperthreads count only in the logical count.
    expect_true(physical <= logical);
}

[Test]
closure_thread_bodies() {
    var total = async.Atomic<long>(0);
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        var step: long = i + 1;
        workers.append(async.Thread.spawn(() => {
            total.fetch_add(step);
        }));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    # Each closure added its captured step.
    expect_equal(total.load(), 10);
}

[Shared]
struct Job {
    const weight: long;
    const run: shared (long) => void;
    construct(this.weight = 1, this.run = (n: long) => {}) {}
}

private const total = async.Atomic<long>(0);
const named_runs = async.Atomic<long>(0);

count_named() {
    named_runs.fetch_add(1);
}

apply_plain(f: (long) => long, x: long): long {
    return f(x);
}

make_adder(step: long): shared (long) => long {
    return (x: long) => x + step;
}

# Thread bodies built from thread-safe captures (an `Atomic`, a `[Shared]`
# struct, another `shared` function value, a number), a named function, a
# `[Shared]` struct holding a `shared` function field, and `shared` values
# used where plain ones are expected.
[Test]
shared_function_types() {
    var add: shared (long) => void = (n: long) => {
        total.fetch_add(n);
    };
    var job = Job(5, add);
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(() => {
            job.run(job.weight);
        }));
        workers.append(async.Thread.spawn(() => {
            add(1);
        }));
        workers.append(async.Thread.spawn(count_named));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    expect_equal(total.load(), 24);
    expect_equal(named_runs.load(), 4);

    # A shared value converts to the plain type of the same signature.
    var add_two = make_adder(2);
    expect_equal(apply_plain(add_two, 40), 42);
    var plain: (long) => long = add_two;
    expect_equal(plain(1), 3);

    # Plain closures still capture anything, on one thread.
    var greeting = "hello";
    var greet: () => String = () => greeting + " world";
    expect_equal(greet(), "hello world");
}

twice(x: int): int {
    return x * 2;
}

# A C function pointer (`extern (P) => R`) is a code address: thread bodies
# may capture and call one.
[Test]
threads_share_c_function_pointers() {
    extern (int) => int f = twice;
    var result = async.Atomic<int>(0);
    var worker = async.Thread.spawn(() => {
        result.fetch_add(f(21));
    });
    worker.join();
    expect_equal(result.load(), 42);
}

[Shared]
struct Config {
    const port: int;
    construct(this.port = 0) {}
}

const config = Config(8080);
const copies_seen = async.Atomic<long>(0);

copy_references() {
    var i = 0;
    while (i < 100000) {
        var copy = config;
        copies_seen.fetch_add(copy.port - 8079);
        i = i + 1;
    }
}

# Many threads copying and dropping references to one `[Shared]` object at
# once: the atomic counts end exactly where they started.
[Test]
shared_counts_are_atomic() {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(copy_references));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    expect_equal(copies_seen.load(), 400000);
    # The count is back to the global's own reference.
    expect_equal(__refcount<Config>(config), 1);
}

[Shared]
struct Limits {
    const step: long;
    construct(this.step = 1) {}
}

export const ROUNDS = 50000;
export const limits = Limits(2);
export const hits = async.Atomic<long>(0);

bump() {
    var i = 0;
    while (i < ROUNDS) {
        hits.fetch_add(limits.step);
        i = i + 1;
    }
}

# Exported module-scope variables are implicitly shared: `const` and
# thread-safe (a number, an `Atomic`, a `[Shared]` struct), so threads may
# use them directly.
[Test]
exported_globals_are_shared() {
    var a = async.Thread.spawn(bump);
    var b = async.Thread.spawn(bump);
    a.join();
    b.join();
    expect_equal(hits.load(), 200000);
}
