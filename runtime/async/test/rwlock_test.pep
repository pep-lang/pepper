# RwLock<T> across threads: readers that hold the lock at the same time,
# writers that exclude everyone, writers coming before new readers, and the
# misuse that panics.

import async;

[Shared]
struct Pair {
    const left: async.Atomic<long>;
    const right: async.Atomic<long>;
    construct(value: long = 0) {
        left = async.Atomic<long>(value);
        right = async.Atomic<long>(value);
    }
}

const READERS = 4;

const pair = async.RwLock<Pair>(Pair());
const torn = async.Atomic<long>(0);

const shared_read = async.RwLock<Pair>(Pair());
const all_reading = async.Barrier(READERS);

const gate = async.RwLock<Pair>(Pair());
const writer_done = async.Atomic<long>(0);

# Changes both halves one after the other; a reader that saw them differ
# would have read in the middle of a write.
write_pairs() {
    var i = 0;
    while (i < 2000) {
        with (var p = pair.write()) {
            p.left.fetch_add(1);
            async.Thread.sleep(0);
            p.right.fetch_add(1);
        }
        i = i + 1;
    }
}

read_pairs() {
    var i = 0;
    while (i < 2000) {
        with (var p = pair.read()) {
            if (p.left.load() != p.right.load()) {
                torn.fetch_add(1);
            }
        }
        i = i + 1;
    }
}

# Every reader waits at the barrier while it holds the read lock, so the
# barrier opens only if all of them hold it at once.
read_together() {
    with (var p = shared_read.read()) {
        all_reading.wait();
    }
}

write_gate() {
    with (var p = gate.write()) {
        p.left.store(1);
    }
    writer_done.store(1);
}

private spawn_all(body: shared () => void, count: long): Array<async.Thread> {
    var threads = Array<async.Thread>();
    var i: long = 0;
    while (i < count) {
        threads.append(async.Thread.spawn(body));
        i = i + 1;
    }
    return threads;
}

[Test]
readers_hold_the_lock_together() {
    for (var thread in spawn_all(read_together, READERS)) {
        thread.join();
    }
    with (var p = shared_read.try_write()) {
        expect_equal(p.left.load(), 0 as long);
    } else {
        expect_true(false);  # the lock was left held
    }
}

[Test]
writers_exclude_readers_and_writers() {
    var threads = spawn_all(write_pairs, 2);
    for (var reader in spawn_all(read_pairs, 2)) {
        threads.append(reader);
    }
    for (var thread in threads) {
        thread.join();
    }
    expect_equal(torn.load(), 0 as long);
    with (var p = pair.read()) {
        expect_equal(p.left.load(), 4000 as long);
        expect_equal(p.right.load(), 4000 as long);
    }
}

[Test]
a_waiting_writer_comes_before_new_readers() {
    var writer: async.Thread = __null;
    with (var held = gate.read()) {
        with (var again = gate.try_write()) {
            expect_true(false);  # try_write took a lock a reader holds
        }
        writer = async.Thread.spawn(write_gate);
        # Give the writer time to start waiting behind this reader.
        async.Thread.sleep(50);
        with (var late = gate.try_read()) {
            expect_true(false);  # a new reader went ahead of a waiting writer
        }
        expect_equal(writer_done.load(), 0 as long);
    }
    writer.join();
    expect_equal(writer_done.load(), 1 as long);
    with (var p = gate.read()) {
        expect_equal(p.left.load(), 1 as long);
    }
}

[Test]
replace_swaps_the_value() {
    var lock = async.RwLock<Pair>(Pair(1));
    var old = lock.replace(Pair(2));
    expect_equal(old.left.load(), 1 as long);
    with (var p = lock.read()) {
        expect_equal(p.right.load(), 2 as long);
    }
    with (var w = lock.write()) {
        with (var again = lock.try_write()) {
            expect_true(false);  # try_write by the writer took the lock again
        }
        with (var r = lock.try_read()) {
            expect_true(false);  # try_read by the writer took the lock
        }
    }
}
