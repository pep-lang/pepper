# The futex-based locks under contention (lock.pep): many threads hammering
# one Mutex with short and long critical sections, threads taking turns
# through one Condition, and a bounded Channel between several senders and
# receivers. A lost wakeup hangs the test; a broken lock miscounts.

import async;

[Shared]
private struct Counter {
    const slot: __ptr<long>;
    construct() {
        slot = _pep_malloc(sizeof<long>());
    }
    destruct {
        _pep_free(slot);
    }
}

private const THREADS = 8;
const INCREMENTS = 50000;
private const ROUNDS = 2000;
const MESSAGES = 20000;

const hammered = async.Mutex<Counter>(Counter());
const turns = async.Mutex<Counter>(Counter());
const next_turn = turns.condition();
const messages = async.Channel<long>(4);
const received = async.Atomic<long>(0);
const received_sum = async.Atomic<long>(0);

# Mostly short critical sections, which the spin covers, and now and then a
# long one, so the other threads sleep on the word and must be woken.
hammer() {
    var i = 0;
    while (i < INCREMENTS) {
        with (var c = hammered.lock()) {
            c.slot[0] = c.slot[0] + 1;
            if (i % 5000 == 0) {
                async.Thread.sleep(1);
            }
        }
        i = i + 1;
    }
}

# Thread `id` of `THREADS` waits for the turn count to reach its own turns,
# so every round wakes all the waiters and exactly one may go on.
take_turns(id: long) {
    var round = 0;
    while (round < ROUNDS) {
        with (var t = turns.lock()) {
            while (t.slot[0] % THREADS != id) {
                next_turn.wait();
            }
            t.slot[0] = t.slot[0] + 1;
            next_turn.notify_all();
        }
        round = round + 1;
    }
}

send_messages() {
    var i: long = 0;
    while (i < MESSAGES / 4) {
        messages.send(i);
        i = i + 1;
    }
}

receive_messages() {
    for (var value in messages) {
        received.fetch_add(1);
        received_sum.fetch_add(value);
    }
}

[Test]
mutex_counts_exactly_under_contention() {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < THREADS) {
        workers.append(async.Thread.spawn(hammer));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    with (var c = hammered.lock()) {
        expect_equal(c.slot[0], (THREADS * INCREMENTS) as long);
    }
}

[Test]
condition_hands_turns_around_without_losing_a_wakeup() {
    var workers = Array<async.Thread>();
    var id: long = 0;
    while (id < THREADS) {
        var mine = id;
        workers.append(async.Thread.spawn(() => take_turns(mine)));
        id = id + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    with (var t = turns.lock()) {
        expect_equal(t.slot[0], (THREADS * ROUNDS) as long);
    }
}

[Test]
bounded_channel_passes_every_message() {
    var threads = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        threads.append(async.Thread.spawn(receive_messages));
        i = i + 1;
    }
    var senders = Array<async.Thread>();
    i = 0;
    while (i < 4) {
        senders.append(async.Thread.spawn(send_messages));
        i = i + 1;
    }
    for (var sender in senders) {
        sender.join();
    }
    messages.close();
    for (var thread in threads) {
        thread.join();
    }
    long per_sender = MESSAGES / 4;
    expect_equal(received.load(), MESSAGES as long);
    expect_equal(received_sum.load(), 4 * per_sender * (per_sender - 1) / 2);
}
