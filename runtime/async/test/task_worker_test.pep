# Tasks on several workers, on each I/O backend: `spawn` runs in parallel,
# returns thread-safe results, nests, is cancelled across workers and when
# the runtime stops, and uses sockets on any worker; `run_blocking` keeps a
# worker free; streams move between workers; every worker accepts on one
# shared listener.

import async;
import io;
import os;
import [has_io_uring] from "backends";

const running = async.Atomic<long>(0);
const overlapped = async.Atomic<long>(0);
private const total = async.Atomic<long>(0);

# How long a test waits for something another thread must do: long enough
# for a busy machine, short enough that a regression fails rather than hangs.
const PATIENCE_SECONDS = 10;

# Waits until `ready` returns true, for up to PATIENCE_SECONDS; false if it
# never did.
wait_until(ready: () => bool): bool {
    var start = os.Instant.now();
    while (!ready()) {
        if (start.elapsed() > os.Duration.from_seconds(PATIENCE_SECONDS)) {
            return false;
        }
        async.Thread.sleep(1);
    }
    return true;
}

# Waits (without yielding) until another task runs at the same time, for up
# to PATIENCE_SECONDS: only another worker can run it meanwhile.
meet(): long {
    running.fetch_add(1);
    var until = async.Thread.current().id();
    var start = os.Instant.now();
    while (running.load() < 2 && start.elapsed() < os.Duration.from_seconds(PATIENCE_SECONDS)) {}
    if (running.load() >= 2) {
        overlapped.fetch_add(1);
    }
    return until as long;
}

private sum(from: long, to: long): long {
    long result = 0;
    var i = from;
    while (i < to) {
        result = result + i;
        i = i + 1;
    }
    return result;
}

# Echoes one connection on the worker this task runs on.
echo_once(): long {
    var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
    var address = listener.local_address().value();
    var server = async.Task<long>.spawn_local(() => {
        var (stream, peer) = listener.accept().value();
        var buffer = Array<u8>();
        var got = stream.read(buffer, 64).value();
        stream.write_all(buffer).value();
        return got as long;
    });
    var client = io.TcpStream.connect(address).value();
    var message = Array<u8>();
    message.append(1);
    message.append(2);
    message.append(3);
    client.write_all(message).value();
    var reply = Array<u8>();
    ulong read = 0;
    while (read < 3) {
        read = read + client.read(reply, 64).value();
    }
    return server.join().value() + reply.count as long;
}

spawned_tasks_run_on_any_worker_on(backend: async.Backend) {
    async.run_with(
        async.RuntimeOptions().workers(4).backend(backend),
        () => {
            # Two spawned tasks run at the same time on different workers.
            var a = async.spawn<long>(meet);
            var b = async.spawn<long>(meet);
            var thread_a = a.join().value();
            var thread_b = b.join().value();
            expect_equal(overlapped.load(), 2);
            expect_not_equal(thread_a, thread_b);

            # Results of several types.
            var low = async.spawn<long>(() => { return sum(0, 500000); });
            var high = async.spawn<long>(() => { return sum(500000, 1000000); });
            expect_equal(low.join().value() + high.join().value(), 499999500000);
            var counter = async.spawn<async.Atomic<long>>(() => { return async.Atomic<long>(42); });
            expect_equal(counter.join().value().load(), 42);
            var nothing = async.spawn<void>(() => {
                total.fetch_add(1);
            });
            expect_true(nothing.join().is_ok());
            expect_true(nothing.is_finished());

            # Many tasks, spawned from spawned tasks.
            var tasks = Array<async.Task<long>>();
            var i = 0;
            while (i < 50) {
                tasks.append(async.spawn<long>(() => {
                    var inner = async.spawn<long>(() => { return 2 as long; });
                    var local = async.Task<long>.spawn_local(() => { return 1 as long; });
                    total.fetch_add(1);
                    return inner.join().value() + local.join().value();
                }));
                i = i + 1;
            }
            long results = 0;
            for (var task in tasks) {
                results = results + task.join().value();
            }
            expect_equal(results, 150);
            # Every task ran.
            expect_equal(total.load(), 51);

            # Cancelling a task that sleeps on another worker wakes it.
            var sleeper = async.spawn<long>(() => {
                async.sleep(100000);
                return 1 as long;
            });
            async.sleep(10);
            sleeper.cancel();
            expect_true(sleeper.join().error().is_cancelled());

            # A computing task sees the cancel through is_cancelled(). It yields
            # now and then, in case it runs on this task's worker.
            var spinner = async.spawn<long>(() => {
                long n = 0;
                while (!async.is_cancelled()) {
                    n = n + 1;
                    if (n % 100000 == 0) {
                        async.yield_now();
                    }
                }
                return n;
            });
            async.sleep(10);
            spinner.cancel();
            expect_true(spinner.join().error().is_cancelled());

            # Cancelled before any worker starts it.
            var early = async.spawn<long>(() => { return async.is_cancelled() ? 1 as long : 0 as long; });
            early.cancel();
            expect_true(early.join().error().is_cancelled());

            # A timeout around a join.
            var slow = async.spawn<long>(() => {
                async.sleep(100000);
                return 1 as long;
            });
            with (var deadline = async.timeout(20)) {
                expect_true(slow.join().error().is_timed_out());
            }

            # Sockets on whichever worker a task runs on.
            var echoes = Array<async.Task<long>>();
            var j = 0;
            while (j < 8) {
                echoes.append(async.spawn<long>(echo_once));
                j = j + 1;
            }
            for (var echo in echoes) {
                expect_equal(echo.join().value(), 6);
            }

            # Still running when the first task returns: `slow`, cancelled.
            async.spawn<void>(() => {
                async.sleep(100000);
            });
        }
    );

    # One worker runs spawned tasks too.
    async.run_with(async.RuntimeOptions().workers(1).backend(backend), () => {
        var t = async.spawn<long>(() => { return 5 as long; });
        expect_equal(t.join().value(), 5);
    });

    # The default: one worker per logical CPU.
    async.run_with(async.RuntimeOptions().backend(backend), () => {
        expect_equal(async.spawn<long>(() => { return 6 as long; }).join().value(), 6);
    });
}

[Test]
spawned_tasks_run_on_any_worker() {
    spawned_tasks_run_on_any_worker_on(async.Backend.Automatic);
}

[Test]
spawned_tasks_run_on_any_worker_with_poll() {
    spawned_tasks_run_on_any_worker_on(async.Backend.Poll);
}

[Test]
spawned_tasks_run_on_any_worker_with_io_uring() {
    if (has_io_uring()) {
        spawned_tasks_run_on_any_worker_on(async.Backend.IoUring);
    }
}

private const inside = async.Atomic<long>(0);
const most = async.Atomic<long>(0);
const finished = async.Atomic<long>(0);
private const ticks = async.Atomic<long>(0);
const served = async.Atomic<long>(0);
# Set when a call to `block_for` gave up waiting for another to overlap it.
private const alone = async.Atomic<long>(0);

# Blocks its thread for `milliseconds`, counting how many run at once. With
# `overlap`, it first waits until two calls have been inside at once, so a
# busy machine cannot run them one after another.
block_for(milliseconds: ulong, overlap: bool = false): long {
    var now = inside.fetch_add(1) + 1;
    var seen = most.load();
    while (now > seen && !most.compare_exchange(seen, now)) {
        seen = most.load();
    }
    # Once one call gives up, the rest do not wait too.
    if (overlap && !wait_until(() => { return most.load() >= 2 || alone.load() != 0; })) {
        alone.store(1);
    }
    async.Thread.sleep(milliseconds);
    inside.fetch_sub(1);
    finished.fetch_add(1);
    return milliseconds as long;
}

# Runs `count` blocking calls from as many tasks at once; with `overlap`,
# two of them must overlap (see `block_for`).
block_many(count: int, overlap: bool = false) {
    alone.store(0);
    var tasks = Array<async.Task<long>>();
    var i = 0;
    while (i < count) {
        tasks.append(async.Task<long>.spawn_local(() => {
            return async.run_blocking<long>(() => { return block_for(30, overlap); });
        }));
        i = i + 1;
    }
    for (var t in tasks) {
        # Each blocking call returns its value.
        expect_equal(t.join().value(), 30);
    }
}

blocking_calls_and_shared_sockets_on(backend: async.Backend) {
    # One worker: it keeps running tasks while a pool thread blocks.
    async.run_with(
        async.RuntimeOptions().workers(1).backend(backend),
        () => {
            var ticker = async.Task<void>.spawn_local(() => {
                while (ticks.load() < 5) {
                    async.sleep(2);
                    ticks.fetch_add(1);
                }
            });
            # The worker runs other tasks while the pool thread waits for them.
            expect_true(async.run_blocking<bool>(() => { return wait_until(() => { return ticks.load() > 0; }); }));
            ticker.join();

            async.run_blocking<void>(() => {
                block_for(1);
            });

            # Blocking inside a blocking call just calls the body.
            var nested = async.run_blocking<long>(() => {
                return async.run_blocking<long>(() => { return 3 as long; });
            });
            expect_equal(nested, 3);

            # Neither a cancel nor a timeout cuts the body short. The body
            # waits to be released, so the cancel comes while it runs.
            var started = async.Channel<long>();
            var release = async.Channel<long>();
            var cancelled = async.Task<long>.spawn_local(() => {
                return async.run_blocking<long>(() => {
                    started.close();
                    release.receive_for(PATIENCE_SECONDS * 1000);
                    return block_for(40);
                });
            });
            started.receive_for(PATIENCE_SECONDS * 1000);
            cancelled.cancel();
            release.close();
            # The task still reports the cancel.
            expect_true(cancelled.join().error().is_cancelled());
            with (var deadline = async.timeout(5)) {
                # The body outlives the timeout.
                expect_equal(async.run_blocking<long>(() => { return block_for(40); }), 40);
            }

            # Calls run in parallel on the pool.
            most.store(0);
            block_many(8, true);
            expect_true(most.load() >= 2);
        }
    );

    # The pool never grows past its limit.
    most.store(0);
    async.run_with(async.RuntimeOptions().workers(2).blocking_threads(1).backend(backend), () => {
        block_many(4);
    });
    expect_equal(most.load(), 1);

    # `run` waits for a blocking call still running when the first task
    # returns.
    finished.store(0);
    async.run_with(async.RuntimeOptions().workers(2).backend(backend), () => {
        async.Task<long>.spawn_local(() => {
            return async.run_blocking<long>(() => { return block_for(50); });
        });
        async.yield_now();
    });
    expect_equal(finished.load(), 1);

    # Outside a task the body just runs.
    expect_equal(async.run_blocking<int>(() => { return 5; }), 5);

    # Streams move between workers.
    async.run_with(
        async.RuntimeOptions().workers(3).backend(backend),
        () => {
            var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var port = listener.local_address().value().port();
            var client = async.spawn<long>(
                () => {
                    long received = 0;
                    var i = 0;
                    while (i < 6) {
                        var stream = io.TcpStream.connect_host("127.0.0.1", port).value();
                        # The last server closes without reading, so the peer may
                        # see a reset rather than an end.
                        stream.write_all("ping");
                        var reply = Array<u8>();
                        while (true) {
                            var got = stream.read(reply, 64);
                            if (got.is_err() || got.value() == 0) {
                                break;
                            }
                        }
                        received = received + reply.count as long;
                        i = i + 1;
                    }
                    return received;
                }
            );
            var handlers = Array<async.Task<void>>();
            var i = 0;
            while (i < 6) {
                var (stream, peer) = listener.accept().value();
                var transfer = stream.into_transfer();
                # The stream gives its socket up.
                expect_false(stream.is_open());
                i = i + 1;
                if (i == 6) {
                    # Never adopted: closing the token closes the connection.
                    continue;
                }
                handlers.append(
                    async.spawn<void>(
                        () => {
                            var mine = io.TcpStream.adopt(transfer).value();
                            var buffer = Array<u8>();
                            mine.read_exact(buffer, 4).value();
                            mine.write_all("pong!").value();
                            # A token is adopted once.
                            expect_true(io.TcpStream.adopt(transfer).is_err());
                        }
                    )
                );
            }
            for (var handler in handlers) {
                handler.join();
            }
            # Five replies, then a closed connection.
            expect_equal(client.join().value(), 25);
            # A closed stream has nothing to move.
            expect_true(io.TcpStream.adopt(io.TcpStream().into_transfer()).is_err());
        }
    );

    # Every worker accepts on one shared listener.
    async.run_with(
        async.RuntimeOptions().workers(4).backend(backend),
        () => {
            var listener = io.SharedTcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var port = listener.local_address().value().port();
            var threads = async.Channel<ulong>();
            var loops = async.spawn_on_each_worker(() => {
                threads.send(async.Thread.current().id());
                while (true) {
                    var accepted = listener.accept();
                    if (accepted.is_err()) {
                        return;
                    }
                    var (stream, peer) = accepted.value();
                    served.fetch_add(1);
                    stream.write_all("hi").value();
                }
            });
            # One loop per worker.
            expect_equal(loops.count, 4);
            var i = 0;
            while (i < 20) {
                var client = io.TcpStream.connect_host("127.0.0.1", port).value();
                var reply = Array<u8>();
                while (client.read(reply, 64).value() > 0) {}
                expect_equal(reply.count, 2);
                i = i + 1;
            }
            var seen = Array<ulong>();
            while (seen.count < 4) {
                var id = threads.receive().value();
                for (var other in seen) {
                    # Each loop on its own worker.
                    expect_not_equal(other, id);
                }
                seen.append(id);
            }
            # Returning cancels the loops; the last one closes the listener.
        }
    );
    # Every connection accepted once.
    expect_equal(served.load(), 20);
}

[Test]
blocking_calls_and_shared_sockets() {
    blocking_calls_and_shared_sockets_on(async.Backend.Automatic);
}

[Test]
blocking_calls_and_shared_sockets_with_poll() {
    blocking_calls_and_shared_sockets_on(async.Backend.Poll);
}

[Test]
blocking_calls_and_shared_sockets_with_io_uring() {
    if (has_io_uring()) {
        blocking_calls_and_shared_sockets_on(async.Backend.IoUring);
    }
}
