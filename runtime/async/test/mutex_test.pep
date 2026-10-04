# Mutex<T> and Condition<T>: exact counts under contention, try_lock, every
# path out of a `with` body unlocking, values that are not thread-safe kept
# behind the lock, waits and notifications, and the misuses that panic.

import async;

[Shared]
struct Counter {
    const slot: __ptr<long>;
    construct() {
        slot = _pep_malloc(sizeof<long>());
        slot[0] = 0;
    }
    destruct {
        _pep_free(slot);
    }
}

[Shared]
struct Label {
    const id: long;
    construct(this.id = 0) {}
}

const counter = async.Mutex<Counter>(Counter());
const busy_seen = async.Atomic<long>(0);
const free_seen = async.Atomic<long>(0);

add_many() {
    var i = 0;
    while (i < 20000) {
        with (var c = counter.lock()) {
            c.slot[0] = c.slot[0] + 1;
        }
        i = i + 1;
    }
}

try_from_other_thread() {
    with (var c = counter.try_lock()) {
        free_seen.fetch_add(1);
    } else {
        busy_seen.fetch_add(1);
    }
}

# Returns from inside the body: the body's locals, the binding and the guard
# are all released, and the Mutex is unlocked.
read_and_return(labels: async.Mutex<Label>): long {
    with (var label = labels.lock()) {
        var copy = label;
        var extra = Label(label.id + 1);
        return copy.id + extra.id;
    }
    return -1;
}

# Breaks and continues out of the body.
loop_paths(labels: async.Mutex<Label>): long {
    long seen = 0;
    var i = 0;
    while (i < 10) {
        i = i + 1;
        with (var label = labels.lock()) {
            var local = Label(i);
            if (i % 2 == 0) {
                continue;
            }
            if (i > 6) {
                break;
            }
            seen = seen + local.id + label.id;
        }
    }
    return seen;
}

make_and_drop() {
    var m = async.Mutex<Label>(Label(3));
    var condition = m.condition();
    with (var label = m.lock()) {
        expect_equal(label.id, 3);
    }
}

# N threads each add to a counter M times under the lock and the total is
# exact: the counter's slot is a plain, non-atomic `long`, so only the lock
# keeps the increments apart.
[Test]
mutex_locks() {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 8) {
        workers.append(async.Thread.spawn(add_many));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    with (var c = counter.lock()) {
        expect_equal(c.slot[0], 160000);
        expect_true(counter.is_held());
    }
    expect_false(counter.is_held());

    # try_lock: busy while this thread holds the lock, from here and from
    # another thread; free afterwards.
    with (var c = counter.lock()) {
        with (var again = counter.try_lock()) {
            panic("try_lock on the holding thread must not take the lock");
        } else {
            busy_seen.fetch_add(1);
        }
        async.Thread.spawn(try_from_other_thread).join();
    }
    expect_equal(busy_seen.load(), 2);
    async.Thread.spawn(try_from_other_thread).join();
    expect_equal(free_seen.load(), 1);

    # Every exit path unlocks and releases.
    var labels = async.Mutex<Label>(Label(10));
    var before = _pep_live_allocs();
    expect_equal(read_and_return(labels), 21);
    expect_equal(loop_paths(labels), 1 + 10 + 3 + 10 + 5 + 10);
    expect_equal(_pep_live_allocs(), before);
    with (var label = labels.try_lock()) {
        expect_equal(label.id, 10);
    } else {
        panic("a return or break left the Mutex locked");
    }

    # A Mutex and its value are freed with the last reference.
    var start = _pep_live_allocs();
    make_and_drop();
    expect_equal(_pep_live_allocs(), start);
}

[Shared]
struct Box {
    const n: long;
    construct(this.n = 0) {}
}

# Locking a Mutex again on the thread that holds it panics instead of
# deadlocking.
[Test]
[ShouldPanic("Mutex.lock: the caller already holds this Mutex")]
mutex_relock_panics() {
    var m = async.Mutex<Box>(Box(1));
    with (var a = m.lock()) {
        with (var b = m.lock()) {
            return;
        }
    }
}

# Waiting on a Condition without holding its Mutex panics.
[Test]
[ShouldPanic("Condition.wait: the caller does not hold the Mutex")]
condition_wait_requires_the_lock() {
    var m = async.Mutex<Box>(Box(1));
    var c = m.condition();
    c.wait();
}

[Shared]
struct Queue {
    const waiting: __ptr<long>;
    const done: __ptr<long>;
    construct() {
        waiting = _pep_malloc(sizeof<long>());
        done = _pep_malloc(sizeof<long>());
        waiting[0] = 0;
        done[0] = 0;
    }
    destruct {
        _pep_free(waiting);
        _pep_free(done);
    }
}

const queue = async.Mutex<Queue>(Queue());
const changed = queue.condition();
const taken = async.Atomic<long>(0);

consumer() {
    while (true) {
        with (var q = queue.lock()) {
            while (q.waiting[0] == 0 && q.done[0] == 0) {
                changed.wait();
            }
            if (q.waiting[0] == 0) {
                return;
            }
            q.waiting[0] = q.waiting[0] - 1;
            taken.fetch_add(1);
            changed.notify_all();
        }
    }
}

# A producer and consumers hand jobs over through a counter in a Mutex;
# `wait_for` with nothing to wake it times out.
[Test]
condition_producer_consumer() {
    var consumers = Array<async.Thread>();
    var i = 0;
    while (i < 3) {
        consumers.append(async.Thread.spawn(consumer));
        i = i + 1;
    }
    i = 0;
    while (i < 300) {
        with (var q = queue.lock()) {
            # Bound the queue at 4: wait for the consumers to catch up.
            while (q.waiting[0] >= 4) {
                changed.wait();
            }
            q.waiting[0] = q.waiting[0] + 1;
            changed.notify_one();
        }
        i = i + 1;
    }
    with (var q = queue.lock()) {
        q.done[0] = 1;
        changed.notify_all();
    }
    for (var c in consumers) {
        c.join();
    }
    # Every job was taken exactly once.
    expect_equal(taken.load(), 300);

    # Nobody notifies: wait_for runs out and reports it.
    with (var q = queue.lock()) {
        var woken = changed.wait_for(30);
        # A spurious wakeup is allowed to return true; wait again to be sure.
        if (woken) {
            woken = changed.wait_for(30);
        }
        expect_false(woken);
        # wait_for locks again before returning.
        expect_true(queue.is_held());
    }
}

struct Log {
    Array<String> lines;
    int dropped;
    construct() {
        lines = Array<String>();
    }
}

const log = async.Mutex<Log>(Log());
const scratch = async.ThreadLocal<String>();

write_lines() {
    var i = 0;
    while (i < 500) {
        with (var l = log.lock()) {
            l.lines.append("line");
            if (l.lines.count % 100 == 0) {
                l.dropped = l.dropped + 1;
            }
        }
        i = i + 1;
    }
    scratch.set("mine");
    with (var mine = scratch.enter()) {
        mine.append("!");
        expect_equal(mine, "mine!");
    } else {
        panic("set gave this thread a value");
    }
}

# A fresh result may leave the block; the locked String itself may not.
first_line(): String {
    with (var l = log.lock()) {
        return l.lines[0].copy();
    }
    return "";
}

count_lines(): ulong {
    with (var l = log.lock()) {
        return l.lines.count;
    }
    return 0;
}

swap_out() {
    var old = log.replace(Log());
    # replace returns the whole old value.
    expect_equal(old.lines.count, 2001);
}

# Threads append Strings to a locked Array and the count is exact; values
# leave only as copies or fresh results; `replace` hands back the whole
# value; `ThreadLocal<String>` is reached through `with`.
[Test]
mutex_of_values_that_are_not_thread_safe() {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(write_lines));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    workers.clear();
    expect_equal(count_lines(), 2000);
    with (var l = log.lock()) {
        # Numbers change under the lock.
        expect_equal(l.dropped, 20);
    }
    var first = first_line();
    first.append(" (copy)");
    with (var l = log.lock()) {
        # The copy is independent.
        expect_equal(l.lines[0], "line");
        # A copy may move into the locked value.
        l.lines.append(copy(first));
    }
    var before = _pep_live_allocs();
    swap_out();
    # The old value is freed with its last reference.
    expect_true(_pep_live_allocs() < before);
    expect_equal(count_lines(), 0);
}

const jobs = async.Mutex<Array<String>>(Array<String>());
const ready = jobs.condition();
const JOB_COUNT = 200;

produce_jobs() {
    var i = 0;
    while (i < JOB_COUNT) {
        with (var list = jobs.lock()) {
            list.append("job");
            ready.notify_all();
        }
        i = i + 1;
    }
}

# `Condition.wait_while` and `wait_while_for` across threads.
[Test]
condition_waits_while_a_predicate_holds() {
    var thread = async.Thread.spawn(produce_jobs);
    var jobs_taken = 0;
    while (jobs_taken < JOB_COUNT) {
        with (var list = jobs.lock()) {
            ready.wait_while((queue: Array<String>): bool => queue.count == 0);
            # The predicate held when it returned.
            expect_true(list.count > 0);
            list.remove_at(0);
            jobs_taken = jobs_taken + 1;
        }
    }
    thread.join();
    with (var list = jobs.lock()) {
        # The time ran out.
        expect_false(ready.wait_while_for(20, (queue: Array<String>): bool => queue.count == 0));
        list.append("late");
        # Already true.
        expect_true(ready.wait_while_for(20, (queue: Array<String>): bool => queue.count == 0));
    }
    # Release the grown buffer the global holds.
    jobs.replace(Array<String>());
}
