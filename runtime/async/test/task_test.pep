# Tasks on one worker: scheduling order, timers, joins, fiber reuse and deep
# stacks, cancellation, sleeping for a Duration, TaskLocal values, and the
# misuses that panic (a task joining itself, tasks joining each other).

import async;
import os;

struct Counter {
    var n: int;
    construct() {}
}

depth(n: int): int {
    if (n == 0) {
        return 0;
    }
    return depth(n - 1) + 1;
}

[Test]
tasks_take_turns_and_free_everything() {
    var log = Array<String>();
    async.run(
        () => {
            # yield_now takes turns in order.
            var a = async.Task<void>.spawn_local(() => {
                log.append("a1");
                async.yield_now();
                log.append("a2");
            });
            var b = async.Task<void>.spawn_local(() => {
                log.append("b1");
                async.yield_now();
                log.append("b2");
            });
            log.append("main");
            a.join();
            b.join();
            expect_true(a.is_finished());
            expect_true(b.is_finished());

            # Timers fire in deadline order, not start order.
            var order = Array<int>();
            var sleepers = Array<async.Task<void>>();
            var i = 0;
            while (i < 5) {
                var k = i;
                sleepers.append(async.Task<void>.spawn_local(() => {
                    async.sleep(((5 - k) * 10) as ulong);
                    order.append(k);
                }));
                i = i + 1;
            }
            for (var t in sleepers) {
                t.join();
            }
            expect_equal(order.count, 5);
            expect_equal(order[0], 4);
            expect_equal(order[1], 3);
            expect_equal(order[2], 2);
            expect_equal(order[3], 1);
            expect_equal(order[4], 0);

            # Many tasks, each with a deep stack, on reused fibers.
            var counter = Counter();
            var many = Array<async.Task<int>>();
            i = 0;
            while (i < 2000) {
                many.append(async.Task<int>.spawn_local(() => {
                    counter.n = counter.n + 1;
                    async.yield_now();
                    return depth(2000);
                }));
                i = i + 1;
            }
            var total = 0;
            for (var t in many) {
                total = total + t.join().value();
            }
            expect_equal(counter.n, 2000);
            expect_equal(total, 4000000);

            # A task joins a task that joins another.
            var inner = async.Task<int>.spawn_local(() => {
                async.sleep(5);
                return 7;
            });
            var outer = async.Task<int>.spawn_local(() => {
                return inner.join().value() * 6;
            });
            expect_equal(outer.join().value(), 42);
            # Join twice.
            expect_equal(inner.join().value(), 7);
        }
    );
    # Round robin.
    expect_equal(log.count, 5);
    expect_equal(log[0], "main");
    expect_equal(log[1], "a1");
    expect_equal(log[2], "b1");
    expect_equal(log[3], "a2");
    expect_equal(log[4], "b2");

    # A second runtime on the same thread, with small stacks.
    async.run_with(async.RuntimeOptions().stack_size(65536), () => {
        var t = async.Task<int>.spawn_local(() => { return depth(100); });
        expect_equal(t.join().value(), 100);
    });

    # Outside a runtime, sleep blocks and yield_now does nothing.
    async.sleep(1);
    async.yield_now();
    expect_false(async.is_cancelled());
}

# Cancellation: of a sleeper, of a joiner, and of the tasks still running
# when the first task returns; cancelled tasks are freed.
[Test]
tasks_are_cancelled_and_awaited() {
    var events = Array<String>();
    async.run(
        () => {
            var sleeper = async.Task<int>.spawn_local(
                () => {
                    async.sleep(100000000);
                    # Woken by cancel.
                    expect_true(async.is_cancelled());
                    return 1;
                }
            );
            async.yield_now();
            sleeper.cancel();
            var r = sleeper.join();
            # A cancelled task's join fails.
            expect_true(r.is_err());
            expect_true(r.error().is_cancelled());

            # A joiner cancelled while it waits stops waiting.
            var slow = async.Task<int>.spawn_local(() => {
                async.sleep(50);
                return 2;
            });
            var joiner = async.Task<bool>.spawn_local(() => {
                return slow.join().is_err();
            });
            async.yield_now();
            joiner.cancel();
            expect_true(joiner.join().is_err());
            # The joined task was not cancelled.
            expect_equal(slow.join().value(), 2);

            # Left running: cancelled when the first task returns, and awaited.
            async.Task<void>.spawn_local(() => {
                while (!async.is_cancelled()) {
                    async.sleep(2);
                }
                events.append("poller stopped");
            });
            async.Task<void>.spawn_local(() => {
                async.sleep(100000000);
                events.append("sleeper stopped");
            });
            async.sleep(10);
        }
    );
    # Both leftover tasks finished.
    expect_equal(events.count, 2);
}

# A task that joins itself, through a stored `Task`.
[Test]
[ShouldPanic("a task cannot join itself")]
joining_itself_panics() {
    async.run(() => {
        var holder = Array<async.Task<int>>();
        var a = async.Task<int>.spawn_local(() => {
            async.yield_now();
            return holder[0].join().value();
        });
        holder.append(a);
        a.join();
    });
}

# Two tasks that join each other: nothing can continue.
[Test]
[ShouldPanic("every task is waiting for another task")]
tasks_waiting_on_each_other_panic() {
    async.run(() => {
        var holder = Array<async.Task<int>>();
        var a = async.Task<int>.spawn_local(() => {
            async.yield_now();
            return holder[1].join().value();
        });
        var b = async.Task<int>.spawn_local(() => {
            async.yield_now();
            return holder[0].join().value();
        });
        holder.append(a);
        holder.append(b);
        a.join();
    });
}

[Test]
sleep_takes_a_duration() {
    # Outside a task the thread sleeps; a part millisecond rounds up.
    var start = os.Instant.now();
    async.sleep(os.Duration.from_microseconds(2500));
    expect_true(start.elapsed() >= os.Duration.from_microseconds(2500));

    # In a task, the shorter sleep finishes first.
    var order = Array<int>();
    async.run(() => {
        var slow = async.Task<void>.spawn_local(() => {
            async.sleep(os.Duration.from_milliseconds(40));
            order.append(1);
        });
        var fast = async.Task<void>.spawn_local(() => {
            async.sleep(os.Duration.from_milliseconds(5));
            order.append(0);
        });
        slow.join();
        fast.join();
    });
    expect_equal(order.count, 2);
    expect_equal(order[0], 0);
    expect_equal(order[1], 1);

    # The millisecond overload still works, and a zero duration returns.
    async.sleep(1);
    async.sleep(os.Duration());
}

const request_id = async.TaskLocal<long>();
const names = async.TaskLocal<Array<String>>();
const released = async.Atomic<long>(0);

struct Noisy {
    var n: long;

    construct(n: long) {
        this.n = n;
    }

    destruct {
        released.fetch_add(1);
    }
}

[Shared]
struct SharedCounter {
    const value: async.Atomic<long>;

    construct() {
        value = async.Atomic<long>(0);
    }
}

const counters = async.TaskLocal<SharedCounter>();
const noisy = async.TaskLocal<Noisy>();

handle(id: long) {
    # A new task has no value.
    expect_false(request_id.is_set());
    request_id.set(id);
    names.set(Array<String>());
    async.yield_now();
    with (var list = names.enter()) {
        list.append("step");
        # Each task has its own list.
        expect_equal(list.count, 1);
    }
    noisy.set(Noisy(id));
    noisy.set(Noisy(id));
    async.yield_now();
    # Still this task's id after the others ran.
    expect_equal(request_id.get(), id);
    counters.set(SharedCounter());
    counters.get().value.fetch_add(id);
    # Each task has its own counter.
    expect_equal(counters.get().value.load(), id);
}

# `TaskLocal<T>`: every task has its own value, released when it finishes;
# code outside a task has one per thread.
[Test]
task_locals_are_per_task() {
    request_id.set(99);
    async.run(
        () => {
            # The first task has no value.
            expect_false(request_id.is_set());
            var tasks = Array<async.Task<void>>();
            for (var id in [1, 2, 3, 4, 5, 6, 7, 8]) {
                tasks.append(async.spawn<void>(() => {
                    handle(id);
                }));
            }
            for (var task in tasks) {
                task.join();
            }
            request_id.set(5);
            request_id.clear();
            expect_false(request_id.is_set());
            expect_equal(request_id.get(), 0);
        }
    );
    # Replaced values and every task's values are released.
    expect_equal(released.load(), 16);
    # Outside a task, the thread's value.
    expect_equal(request_id.get(), 99);
    request_id.clear();
}
