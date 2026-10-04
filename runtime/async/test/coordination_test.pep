# Semaphore, Barrier and Latch across threads: a semaphore that bounds how
# many threads are inside at once, a barrier with one leader per round over
# many rounds, and a latch that holds its waiters until the last count.

import async;

private const THREADS = 6;
private const ROUNDS = 200;

private const slots = async.Semaphore(2);
private const inside = async.Atomic<long>(0);
const most_inside = async.Atomic<long>(0);

const round_done = async.Barrier(THREADS);
const leaders = async.Atomic<long>(0);
const arrivals = async.Atomic<long>(0);
const bad_rounds = async.Atomic<long>(0);

const started = async.Latch(THREADS);
const passed = async.Atomic<long>(0);

# Holds a permit for a moment and records how many holders it saw.
use_slot() {
    var i = 0;
    while (i < 50) {
        with (slots.permit()) {
            var now = inside.fetch_add(1) + 1;
            var most = most_inside.load();
            while (now > most && !most_inside.compare_exchange(most, now)) {
                most = most_inside.load();
            }
            async.Thread.sleep(0);
            inside.fetch_sub(1);
        }
        i = i + 1;
    }
}

# Every thread arrives once per round; the leader checks that the whole
# round arrived before anyone went on.
private meet() {
    var round: long = 0;
    while (round < ROUNDS) {
        arrivals.fetch_add(1);
        if (round_done.wait()) {
            leaders.fetch_add(1);
            if (arrivals.load() != (round + 1) * THREADS) {
                bad_rounds.fetch_add(1);
            }
        }
        # Nobody starts the next round until this one's leader has looked.
        round_done.wait();
        round = round + 1;
    }
}

count_and_wait() {
    started.count_down();
    started.wait();
    passed.fetch_add(1);
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
semaphore_bounds_concurrency() {
    for (var thread in spawn_all(use_slot, THREADS)) {
        thread.join();
    }
    expect_true(most_inside.load() <= 2);
    expect_equal(inside.load(), 0 as long);

    var pool = async.Semaphore(1);
    expect_true(pool.try_acquire());
    expect_false(pool.try_acquire());
    pool.release();
    with (pool.permit()) {
        expect_false(pool.try_acquire());
    }
    expect_true(pool.try_acquire());
}

[Test]
barrier_has_one_leader_per_round() {
    for (var thread in spawn_all(meet, THREADS)) {
        thread.join();
    }
    expect_equal(leaders.load(), ROUNDS as long);
    expect_equal(bad_rounds.load(), 0 as long);

    var alone = async.Barrier(0);
    expect_true(alone.wait());
}

[Test]
latch_releases_waiters_at_the_last_count() {
    expect_false(started.is_ready());
    for (var thread in spawn_all(count_and_wait, THREADS)) {
        thread.join();
    }
    expect_true(started.is_ready());
    expect_equal(passed.load(), THREADS as long);

    var open = async.Latch(0);
    expect_true(open.is_ready());
    open.wait();
}
