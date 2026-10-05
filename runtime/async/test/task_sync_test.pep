# Mutex, Condition, Channel, Select and Thread.sleep in tasks, on each I/O
# backend: a task that waits parks, and its worker runs other tasks.

import async;
import [has_io_uring] from "backends";

struct Tally {
    var count: long;
    var order: Array<long>;
    construct() {
        this.order = Array<long>();
    }
}

const tally = async.Mutex<Tally>(Tally());
private const changed = tally.condition();
private const ticks = async.Atomic<long>(0);
const pings = async.Channel<long>();
const pongs = async.Channel<long>();
private const slots = async.Channel<long>(1);
const results = async.Channel<long>();
const inbox = async.Channel<long>();

# Adds one to the tally, parking while holding the lock so that others
# must wait for it.
add_slowly(who: long) {
    with (var t = tally.lock()) {
        var seen = t.count;
        async.sleep(1);
        t.count = seen + 1;
        t.order.append(who);
    }
}

# Counts ticks until told to stop, proving the worker stays free.
tick_until(stop: async.Atomic<int>) {
    while (stop.load() == 0) {
        ticks.fetch_add(1);
        async.yield_now();
    }
}

one_worker() {
    var stop = async.Atomic<int>(0);
    var ticker = async.Task<void>.spawn_local(() => {
        tick_until(stop);
    });

    # A task holding the lock across a sleep; another waits for it.
    var first = async.Task<void>.spawn_local(() => {
        add_slowly(1);
    });
    var second = async.Task<void>.spawn_local(() => {
        add_slowly(2);
    });
    first.join();
    second.join();
    with (var t = tally.lock()) {
        # No increment was lost.
        expect_equal(t.count, 2);
        # The waiter ran after the holder.
        expect_equal(t.order[0], 1);
        expect_equal(t.order[1], 2);
        # The task holds the lock.
        expect_true(tally.is_held());
    }
    # Released after the block.
    expect_false(tally.is_held());

    # Ping-pong between two tasks on one worker.
    var ponger = async.Task<long>.spawn_local(() => {
        var sum: long = 0;
        for (var n in pings) {
            sum = sum + n;
            pongs.send(n + 1);
        }
        return sum;
    });
    var i: long = 0;
    while (i < 100) {
        pings.send(i);
        expect_equal(pongs.receive().value(), i + 1);
        i = i + 1;
    }
    pings.close();
    # Every ping arrived.
    expect_equal(ponger.join().value(), 4950);

    # A bounded channel parks a sender while it is full.
    var producer = async.Task<void>.spawn_local(() => {
        var n: long = 0;
        while (n < 20) {
            expect_true(slots.send(n));
            n = n + 1;
        }
        slots.close();
    });
    var expected: long = 0;
    for (var n in slots) {
        # Values arrive in order.
        expect_equal(n, expected);
        expected = expected + 1;
    }
    # All values received.
    expect_equal(expected, 20);
    producer.join();

    # A Condition wakes a task parked in wait().
    var waiter = async.Task<long>.spawn_local(() => {
        with (var t = tally.lock()) {
            while (t.count < 3) {
                changed.wait();
            }
            return t.count;
        }
        return 0 as long;
    });
    async.sleep(5);
    with (var t = tally.lock()) {
        t.count = 3;
        changed.notify_one();
    }
    # The waiter saw the change.
    expect_equal(waiter.join().value(), 3);

    # wait_for gives up in time; the lock is held again after.
    with (var t = tally.lock()) {
        # Nobody notified.
        expect_false(changed.wait_for(5));
        expect_true(tally.is_held());
    }

    # Cancels and time limits end channel waits.
    var receiver = async.Task<bool>.spawn_local(() => {
        return inbox.receive().is_err();
    });
    async.yield_now();
    receiver.cancel();
    # The cancelled receiver finished.
    expect_true(receiver.join().is_err());
    # Receive_for timed out.
    expect_true(inbox.receive_for(5).is_err());
    with (var deadline = async.timeout(5)) {
        # The task's timeout ends receive.
        expect_true(inbox.receive().is_err());
    }

    # Thread.sleep in a task lets others run.
    var before = ticks.load();
    async.Thread.sleep(10);
    # The worker ticked during Thread.sleep.
    expect_true(ticks.load() > before);

    stop.store(1);
    ticker.join();
}

many_workers() {
    # Tasks on every worker and a plain thread contend for one lock.
    with (var t = tally.lock()) {
        t.count = 0;
        t.order.clear();
    }
    var tasks = Array<async.Task<void>>();
    var i: long = 0;
    while (i < 16) {
        var who = i;
        tasks.append(async.spawn<void>(() => {
            add_slowly(who);
        }));
        i = i + 1;
    }
    var thread = async.Thread.spawn(() => {
        var n = 0;
        while (n < 8) {
            add_slowly(100);
            n = n + 1;
        }
    });
    for (var task in tasks) {
        task.join();
    }
    thread.join();
    with (var t = tally.lock()) {
        # No increment was lost across workers.
        expect_equal(t.count, 24);
    }

    # Producers on other workers and a thread feed a task parked in receive.
    var producers = Array<async.Task<void>>();
    i = 0;
    while (i < 8) {
        producers.append(async.spawn<void>(() => {
            var n: long = 0;
            while (n < 50) {
                results.send(1);
                async.yield_now();
                n = n + 1;
            }
        }));
        i = i + 1;
    }
    var feeder = async.Thread.spawn(() => {
        var n = 0;
        while (n < 100) {
            results.send(1);
            n = n + 1;
        }
    });
    var total: long = 0;
    while (total < 500) {
        total = total + results.receive().value();
    }
    for (var p in producers) {
        p.join();
    }
    feeder.join();
    # Nothing extra arrived.
    expect_true(results.try_receive().is_err());

    # A task waits on a Condition that a thread signals.
    var waiter = async.spawn<long>(() => {
        with (var t = tally.lock()) {
            while (t.count < 1000) {
                changed.wait();
            }
            return t.count;
        }
        return 0 as long;
    });
    async.sleep(5);
    var signaller = async.Thread.spawn(() => {
        with (var t = tally.lock()) {
            t.count = 1000;
            changed.notify_all();
        }
    });
    # The thread's notify reached the task.
    expect_equal(waiter.join().value(), 1000);
    signaller.join();
}

sync_objects_park_tasks_on(backend: async.Backend) {
    async.run_with(async.RuntimeOptions().workers(1).backend(backend), one_worker);
    async.run_with(async.RuntimeOptions().workers(4).backend(backend), many_workers);
    # Drop the order's grown buffer.
    tally.replace(Tally());
}

# A task that waits on a Mutex, Condition, Channel or Thread.sleep parks and
# its worker runs other tasks, on one worker and across several, with plain
# threads taking part; cancels and time limits end channel waits.
[Test]
sync_objects_park_tasks() {
    sync_objects_park_tasks_on(async.Backend.Automatic);
}

[Test]
sync_objects_park_tasks_with_poll() {
    sync_objects_park_tasks_on(async.Backend.Poll);
}

[Test]
sync_objects_park_tasks_with_io_uring() {
    if (has_io_uring()) {
        sync_objects_park_tasks_on(async.Backend.IoUring);
    }
}

private enum Event {
    Number(value: long),
    Word(text: String),
}

private const numbers = async.Channel<long>();
private const words = async.Channel<String>();
private const jobs = async.Mutex<Array<long>>(Array<long>());
private const ready = jobs.condition();
const COUNT = 50;

from_thread() {
    var i = 0;
    while (i < COUNT) {
        words.send("w");
        i = i + 1;
    }
    words.close();
}

# A select parks its task on several channels at once while other tasks on
# the same worker keep running and feed it, values from a thread wake it
# too, a select's own timeout ends a wait, and `wait_while` parks a task
# whose producer is another task.
[Test]
select_and_wait_while_park_tasks() {
    async.run(
        () => {
            var select = async.Select<Event>();
            select.receive(numbers, (value: long): Event => Event.Number(value));
            select.receive(words, (text: String): Event => Event.Word(text));
            # A channel closed from the start is never joined: the select still
            # sleeps (not spins) while the others are empty, so the feeder on
            # this worker gets to run.
            var closed_early = async.Channel<long>();
            closed_early.close();
            select.receive(closed_early, (value: long): Event => Event.Number(value));

            # A task on this worker feeds one channel; a thread feeds the other.
            var feeder = async.Task<void>.spawn_local(() => {
                var n: long = 0;
                while (n < COUNT) {
                    numbers.send(n);
                    async.yield_now();
                    n = n + 1;
                }
                numbers.close();
            });
            var thread = async.Thread.spawn(from_thread);
            var sum: long = 0;
            var letters = 0;
            var running = true;
            while (running) {
                match (select.wait_for(10000)) {
                    Ok(event) => {
                        match (event) {
                            Number(value) => {
                                sum = sum + value;
                            }
                            Word(text) => {
                                letters = letters + text.length as int;
                            }
                        }
                    }
                    Err(error) => {
                        expect_equal(error.message, "every channel is closed");
                        running = false;
                    }
                }
            }
            feeder.join();
            thread.join();
            # Every number arrived once.
            expect_equal(sum, COUNT * (COUNT - 1) / 2);
            # Every word arrived once.
            expect_equal(letters, COUNT);

            # A select's own timeout ends a task's wait.
            var quiet = async.Channel<long>();
            var waiting = async.Select<long>();
            waiting.receive(quiet, (n: long): long => n);
            var timed = waiting.wait_for(20);
            # Nothing arrives on a quiet channel.
            expect_true(timed.is_err());
            expect_equal(timed.error().message, "the time ran out");

            # wait_while parks the task while another task fills the queue.
            var producer = async.Task<void>.spawn_local(() => {
                var i: long = 0;
                while (i < 5) {
                    async.sleep(1);
                    with (var list = jobs.lock()) {
                        list.append(i);
                        ready.notify_all();
                    }
                    i = i + 1;
                }
            });
            var taken: long = 0;
            while (taken < 5) {
                with (var list = jobs.lock()) {
                    ready.wait_while((queue: Array<long>): bool => queue.count == 0);
                    taken = taken + list.count as long;
                    list.clear();
                }
            }
            producer.join();
        }
    );
    # Release the grown buffer the global holds.
    jobs.replace(Array<long>());
}

# A select's send arm parks its task while the bounded channel is full, and
# a task on the same worker that takes a value wakes it.
[Test]
select_send_arm_parks_a_task() {
    async.run(
        () => {
            var out = async.Channel<long>(1);
            var drained = async.Atomic<long>(0);
            var drainer = async.Task<void>.spawn_local(() => {
                for (var n in out) {
                    drained.fetch_add(n);
                    async.yield_now();
                }
            });
            var select = async.Select<long>();
            long n = 1;
            while (n <= COUNT) {
                select.send(out, n, (): long => 1);
                # The only arm: wait() returns once `out` takes the value.
                expect_equal(select.wait_for(10000).value(), 1);
                n = n + 1;
            }
            out.close();
            drainer.join();
            expect_equal(drained.load(), COUNT * (COUNT + 1) / 2);
        }
    );
}
