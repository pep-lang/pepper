//! Tasks in the `async` module (`runtime/async/task.pep` over the fibers in
//! `fiber_posix.pep` / `fiber_windows.pep`): programs are compiled, linked
//! and run on the host. Each asserts internally and returns 0.
//!
//! `task_programs_compile_on_other_platforms` pushes them through sema and
//! codegen with the host simulated as each other platform, so the Windows
//! Fibers layer, the other architecture's context switch, and each OS's I/O
//! driver (epoll, kqueue, IOCP) produce valid IR on any host.

use crate::io_tests::{SIMULATED_HOSTS, assert_runs, with_codegen_as};
use crate::support;

/// Scheduling order, timers, joins, fiber reuse and deep stacks, and that a
/// run frees everything it allocated.
const SCHEDULING_PROGRAM: &str = r##"
import async;

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

main(): int {
    # Runs start worker threads: warm up the lazily allocated state of
    # threads (the main thread's Thread) first.
    async.Thread.current();
    var before = _pep_live_allocs();
    var log = Array<String>();
    async.run(() => {
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
        assert(a.is_finished() && b.is_finished(), "joined tasks are finished");

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
        assert(order.count() == 5, "every sleeper woke");
        assert(order[0] == 4 && order[1] == 3 && order[2] == 2, "deadline order");
        assert(order[3] == 1 && order[4] == 0, "deadline order");

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
        assert(counter.n == 2000 && total == 4000000, "2000 tasks ran");

        # A task joins a task that joins another.
        var inner = async.Task<int>.spawn_local(() => {
            async.sleep(5);
            return 7;
        });
        var outer = async.Task<int>.spawn_local(() => {
            return inner.join().value() * 6;
        });
        assert(outer.join().value() == 42, "nested join");
        assert(inner.join().value() == 7, "join twice");
    });
    assert(log.count() == 5, "five entries");
    assert(log[0] == "main" && log[1] == "a1" && log[2] == "b1", "round robin");
    assert(log[3] == "a2" && log[4] == "b2", "round robin");
    log.clear();

    # A second runtime on the same thread, with small stacks.
    async.run_with(async.RuntimeOptions().stack_size(65536), () => {
        var t = async.Task<int>.spawn_local(() => { return depth(100); });
        assert(t.join().value() == 100, "second run");
    });

    # Outside a runtime, sleep blocks and yield_now does nothing.
    async.sleep(1);
    async.yield_now();
    assert(!async.is_cancelled(), "not cancelled outside a task");

    assert(_pep_live_allocs() == before + 2, "a run frees what it allocated");
    return 0;
}
"##;

/// Cancellation: of a sleeper, of a joiner, and of the tasks still running
/// when the first task returns.
const CANCEL_PROGRAM: &str = r##"
import async;

main(): int {
    # Runs start worker threads: warm up the lazily allocated state of
    # threads (the main thread's Thread) first.
    async.Thread.current();
    var before = _pep_live_allocs();
    var events = Array<String>();
    async.run(() => {
        var sleeper = async.Task<int>.spawn_local(() => {
            async.sleep(100000000);
            assert(async.is_cancelled(), "woken by cancel");
            return 1;
        });
        async.yield_now();
        sleeper.cancel();
        var r = sleeper.join();
        assert(r.is_err() && r.error().is_cancelled(), "a cancelled task's join fails");

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
        var joined = joiner.join();
        assert(joined.is_err(), "the cancelled joiner's own join fails");
        assert(slow.join().value() == 2, "the joined task was not cancelled");

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
    });
    assert(events.count() == 2, "both leftover tasks finished");
    events.clear();
    assert(_pep_live_allocs() == before + 2, "cancelled tasks are freed");
    return 0;
}
"##;

/// A task that joins itself, through a stored `Task`.
const SELF_JOIN_PROGRAM: &str = r##"
import async;

main(): int {
    async.run(() => {
        var holder = Array<async.Task<int>>();
        var a = async.Task<int>.spawn_local(() => {
            async.yield_now();
            return holder[0].join().value();
        });
        holder.append(a);
        a.join();
    });
    return 0;
}
"##;

/// Two tasks that join each other: nothing can continue.
const DEADLOCK_PROGRAM: &str = r##"
import async;

main(): int {
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
    return 0;
}
"##;

/// Sockets in tasks: an echo server with many clients on one thread, a large
/// write that fills the send buffer, timeouts on accept, join and sleep,
/// cancelling a task parked on a socket, and that a run frees everything.
const SOCKETS_PROGRAM: &str = r##"
import async;
import io;

serve(stream: io.TcpStream) {
    var buffer = Array<u8>();
    while (true) {
        var r = stream.read(buffer, 4096);
        if (r.is_err() || r.value() == 0) {
            return;
        }
        assert(stream.write_all(buffer).is_ok(), "echo");
        buffer.clear();
    }
}

main(): int {
    # Runs start worker threads: warm up the lazily allocated state of
    # threads (the main thread's Thread) first.
    async.Thread.current();
    var before = _pep_live_allocs();
    async.run(() => {
        print(async.current_backend().name());
        var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var address = listener.local_address().value();
        var clients = 40;

        # One server task per connection, all on this thread.
        var server = async.Task<void>.spawn_local(() => {
            var connections = Array<async.Task<void>>();
            var i = 0;
            while (i < clients) {
                var (stream, peer) = listener.accept().value();
                connections.append(async.Task<void>.spawn_local(() => { serve(stream); }));
                i = i + 1;
            }
            for (var c in connections) {
                c.join();
            }
        });
        var tasks = Array<async.Task<int>>();
        var n = 0;
        while (n < clients) {
            var k = n;
            tasks.append(async.Task<int>.spawn_local(() => {
                var stream = io.TcpStream.connect(address).value();
                var echoed = 0;
                var round = 0;
                while (round < 10) {
                    var message = $"message {k} {round}";
                    assert(stream.write_string(message).is_ok(), "write");
                    var buffer = Array<u8>();
                    assert(stream.read_exact(buffer, message.size()).is_ok(), "read");
                    echoed = echoed + buffer.count() as int;
                    async.yield_now();
                    round = round + 1;
                }
                return echoed;
            }));
            n = n + 1;
        }
        for (var t in tasks) {
            assert(t.join().value() > 0, "client finished");
        }
        server.join();

        # A write far larger than the socket buffers waits for the reader.
        var big = Array<u8>();
        var size: ulong = 8388608;
        while (big.count() < size) {
            big.append((big.count() % 251) as u8);
        }
        var sender = async.Task<void>.spawn_local(() => {
            var (stream, peer) = listener.accept().value();
            assert(stream.write_all(big).is_ok(), "big write");
        });
        var receiver = io.TcpStream.connect(address).value();
        var received = Array<u8>();
        assert(receiver.read_exact(received, size).is_ok(), "big read");
        assert(received[size - 1] == big[size - 1], "big data");
        sender.join();

        # Timeouts: accept gives up, join gives up (the task carries on), and
        # sleep returns early.
        with (var deadline = async.timeout(30)) {
            var accepted = listener.accept();
            assert(accepted.is_err() && accepted.error().is_timed_out(), "accept timed out");
            assert(deadline.is_expired(), "deadline expired");
        }
        var sleeper = async.Task<void>.spawn_local(() => { async.sleep(100000); });
        with (async.timeout(20)) {
            var joined = sleeper.join();
            assert(joined.error().is_timed_out() && !joined.error().is_cancelled(), "join timed out");
            async.sleep(100000);   # returns at the limit
        }
        assert(!sleeper.is_finished(), "the sleeper carries on");
        sleeper.cancel();
        sleeper.join();

        # Nested timeouts: the outer one still applies after the inner ends.
        with (async.timeout(40)) {
            with (async.timeout(100000)) {
                assert(listener.accept().error().is_timed_out(), "outer limit applies inside");
            }
        }

        # Cancelling a task parked on a socket.
        var waiter = async.Task<bool>.spawn_local(() => {
            return listener.accept().error().is_cancelled();
        });
        async.yield_now();
        waiter.cancel();
        assert(waiter.join().is_err(), "cancelled");
        assert(waiter.is_finished(), "finished");

        # A refused connection fails like a blocking one.
        var closed = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var gone = closed.local_address().value();
        closed.close();
        assert(io.TcpStream.connect(gone).error().is_connection_refused(), "refused");
    });
    assert(_pep_live_allocs() == before, "a run frees everything it allocated");
    return 0;
}
"##;

/// Tasks from `spawn` on several workers: they run in parallel, return
/// thread-safe results, nest, are cancelled across workers (asleep or
/// computing), time out, are cancelled when the runtime stops, and use
/// sockets on whichever worker they run; and a run frees what it allocated.
const SPAWN_PROGRAM: &str = r##"
import async;
import io;

const running = Atomic<long>(0);
const overlapped = Atomic<long>(0);
const total = Atomic<long>(0);

# Waits (without yielding) until another task runs at the same time, for up
# to two seconds: only another worker can run it meanwhile.
meet(): long {
    running.fetch_add(1);
    var until = async.Thread.current().id();
    var spins: long = 0;
    while (running.load() < 2 && spins < 200000000) {
        spins = spins + 1;
    }
    if (running.load() >= 2) {
        overlapped.fetch_add(1);
    }
    return until as long;
}

sum(from: long, to: long): long {
    var result: long = 0;
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
    var read: ulong = 0;
    while (read < 3) {
        read = read + client.read(reply, 64).value();
    }
    return server.join().value() + reply.count() as long;
}

main(): int {
    # Runs start worker threads: warm up the lazily allocated state of
    # threads (the main thread's Thread) first.
    async.Thread.current();
    var before = _pep_live_allocs();

    async.run_with(async.RuntimeOptions().workers(4), () => {
        # Two spawned tasks run at the same time on different workers.
        var a = async.spawn<long>(meet);
        var b = async.spawn<long>(meet);
        var thread_a = a.join().value();
        var thread_b = b.join().value();
        assert(overlapped.load() == 2, "spawned tasks run in parallel");
        assert(thread_a != thread_b, "on different workers");

        # Results of several types.
        var low = async.spawn<long>(() => { return sum(0, 500000); });
        var high = async.spawn<long>(() => { return sum(500000, 1000000); });
        assert(low.join().value() + high.join().value() == 499999500000, "long results");
        var counter = async.spawn<Atomic<long>>(() => { return Atomic<long>(42); });
        assert(counter.join().value().load() == 42, "a [Shared] result");
        var nothing = async.spawn<void>(() => { total.fetch_add(1); });
        assert(nothing.join().is_ok(), "a void task");
        assert(nothing.is_finished(), "finished");

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
        var results: long = 0;
        for (var task in tasks) {
            results = results + task.join().value();
        }
        assert(results == 150, "nested spawns");
        assert(total.load() == 51, "every task ran");

        # Cancelling a task that sleeps on another worker wakes it.
        var sleeper = async.spawn<long>(() => {
            async.sleep(100000);
            return 1 as long;
        });
        async.sleep(10);
        sleeper.cancel();
        assert(sleeper.join().error().is_cancelled(), "a cancelled sleeper");

        # A computing task sees the cancel through is_cancelled(). It yields
        # now and then, in case it runs on this task's worker.
        var spinner = async.spawn<long>(() => {
            var n: long = 0;
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
        assert(spinner.join().error().is_cancelled(), "a cancelled computation");

        # Cancelled before any worker starts it.
        var early = async.spawn<long>(() => { return async.is_cancelled() ? 1 as long : 0 as long; });
        early.cancel();
        assert(early.join().error().is_cancelled(), "cancelled before it started");

        # A timeout around a join.
        var slow = async.spawn<long>(() => {
            async.sleep(100000);
            return 1 as long;
        });
        with (var deadline = async.timeout(20)) {
            assert(slow.join().error().is_timed_out(), "join timed out");
        }

        # Sockets on whichever worker a task runs on.
        var echoes = Array<async.Task<long>>();
        var j = 0;
        while (j < 8) {
            echoes.append(async.spawn<long>(echo_once));
            j = j + 1;
        }
        for (var echo in echoes) {
            assert(echo.join().value() == 6, "echoed on another worker");
        }

        # Still running when the first task returns: `slow`, cancelled.
        async.spawn<void>(() => { async.sleep(100000); });
    });

    # One worker runs spawned tasks too.
    async.run_with(async.RuntimeOptions().workers(1), () => {
        var t = async.spawn<long>(() => { return 5 as long; });
        assert(t.join().value() == 5, "one worker");
    });

    # The default: one worker per logical CPU.
    async.run(() => {
        assert(async.spawn<long>(() => { return 6 as long; }).join().value() == 6, "default workers");
    });

    assert(_pep_live_allocs() == before, "a run frees everything it allocated");
    print("ok");
    return 0;
}
"##;

const BLOCKING_PROGRAM: &str = r##"
import async;
import io;

const inside = Atomic<long>(0);
const most = Atomic<long>(0);
const finished = Atomic<long>(0);
const ticks = Atomic<long>(0);
const served = Atomic<long>(0);

# Blocks its thread for `milliseconds`, counting how many run at once.
block_for(milliseconds: ulong): long {
    var now = inside.fetch_add(1) + 1;
    var seen = most.load();
    while (now > seen && !most.compare_exchange(seen, now)) {
        seen = most.load();
    }
    async.Thread.sleep(milliseconds);
    inside.fetch_sub(1);
    finished.fetch_add(1);
    return milliseconds as long;
}

# Runs `count` blocking calls from as many tasks at once.
block_many(count: int) {
    var tasks = Array<async.Task<long>>();
    var i = 0;
    while (i < count) {
        tasks.append(async.Task<long>.spawn_local(() => {
            return async.run_blocking<long>(() => { return block_for(30); });
        }));
        i = i + 1;
    }
    for (var t in tasks) {
        assert(t.join().value() == 30, "each blocking call returns its value");
    }
}

main(): int {
    async.Thread.current();
    var before = _pep_live_allocs();

    # One worker: it keeps running tasks while a pool thread blocks.
    async.run_with(async.RuntimeOptions().workers(1), () => {
        var ticker = async.Task<void>.spawn_local(() => {
            while (ticks.load() < 5) {
                async.sleep(2);
                ticks.fetch_add(1);
            }
        });
        assert(async.run_blocking<long>(() => { return block_for(100); }) == 100, "a value comes back");
        assert(ticks.load() > 0, "the worker ran other tasks meanwhile");
        ticker.join();

        async.run_blocking<void>(() => { block_for(1); });

        # Blocking inside a blocking call just calls the body.
        var nested = async.run_blocking<long>(() => {
            return async.run_blocking<long>(() => { return 3 as long; });
        });
        assert(nested == 3, "nested blocking call");

        # Neither a cancel nor a timeout cuts the body short.
        var cancelled = async.Task<long>.spawn_local(() => {
            return async.run_blocking<long>(() => { return block_for(40); });
        });
        async.sleep(5);
        cancelled.cancel();
        assert(cancelled.join().error().is_cancelled(), "the task still reports the cancel");
        with (var deadline = async.timeout(5)) {
            assert(async.run_blocking<long>(() => { return block_for(40); }) == 40, "the body outlives the timeout");
        }

        # Calls run in parallel on the pool.
        most.store(0);
        block_many(8);
        assert(most.load() >= 2, "blocking calls overlap");
    });

    # The pool never grows past its limit.
    most.store(0);
    async.run_with(async.RuntimeOptions().workers(2).blocking_threads(1), () => {
        block_many(4);
    });
    assert(most.load() == 1, "one blocking thread at a time");

    # `run` waits for a blocking call still running when the first task
    # returns.
    finished.store(0);
    async.run_with(async.RuntimeOptions().workers(2), () => {
        async.Task<long>.spawn_local(() => {
            return async.run_blocking<long>(() => { return block_for(50); });
        });
        async.yield_now();
    });
    assert(finished.load() == 1, "the blocking call finished before run returned");

    # Outside a task the body just runs.
    assert(async.run_blocking<int>(() => { return 5; }) == 5, "outside run");

    # Streams move between workers.
    async.run_with(async.RuntimeOptions().workers(3), () => {
        var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var port = listener.local_address().value().port();
        var client = async.spawn<long>(() => {
            var total: long = 0;
            var i = 0;
            while (i < 6) {
                var stream = io.TcpStream.connect_host("127.0.0.1", port).value();
                # The last server closes without reading, so the peer may
                # see a reset rather than an end.
                stream.write_string("ping");
                var reply = Array<u8>();
                while (true) {
                    var got = stream.read(reply, 64);
                    if (got.is_err() || got.value() == 0) {
                        break;
                    }
                }
                total = total + reply.count() as long;
                i = i + 1;
            }
            return total;
        });
        var handlers = Array<async.Task<void>>();
        var i = 0;
        while (i < 6) {
            var (stream, peer) = listener.accept().value();
            var transfer = stream.into_transfer();
            assert(!stream.is_open(), "the stream gives its socket up");
            i = i + 1;
            if (i == 6) {
                # Never adopted: closing the token closes the connection.
                continue;
            }
            handlers.append(async.spawn<void>(() => {
                var mine = io.TcpStream.adopt(transfer).value();
                var buffer = Array<u8>();
                mine.read_exact(buffer, 4).value();
                mine.write_string("pong!").value();
                assert(io.TcpStream.adopt(transfer).is_err(), "a token is adopted once");
            }));
        }
        for (var handler in handlers) {
            handler.join();
        }
        assert(client.join().value() == 25, "five replies, then a closed connection");
        assert(io.TcpStream.adopt(io.TcpStream().into_transfer()).is_err(), "a closed stream has nothing to move");
    });

    # Every worker accepts on one shared listener.
    async.run_with(async.RuntimeOptions().workers(4), () => {
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
                stream.write_string("hi").value();
            }
        });
        assert(loops.count() == 4, "one loop per worker");
        var i = 0;
        while (i < 20) {
            var client = io.TcpStream.connect_host("127.0.0.1", port).value();
            var reply = Array<u8>();
            while (client.read(reply, 64).value() > 0) {
            }
            assert(reply.count() == 2, "served");
            i = i + 1;
        }
        var seen = Array<ulong>();
        while (seen.count() < 4) {
            var id = threads.receive().value();
            for (var other in seen) {
                assert(other != id, "each loop on its own worker");
            }
            seen.append(id);
        }
        # Returning cancels the loops; the last one closes the listener.
    });
    assert(served.load() == 20, "every connection accepted once");

    assert(_pep_live_allocs() == before, "a run frees everything it allocated");
    print("ok");
    return 0;
}
"##;

fn programs() -> Vec<(&'static str, &'static str)> {
    vec![("sockets", SOCKETS_PROGRAM), ("spawn", SPAWN_PROGRAM), ("blocking", BLOCKING_PROGRAM)]
}

#[test]
fn tasks_take_turns_and_free_everything() {
    assert_runs("task_scheduling", SCHEDULING_PROGRAM);
}

#[test]
fn sockets_park_their_task() {
    let stdout = assert_runs("task_sockets", SOCKETS_PROGRAM);
    let expected = if cfg!(target_os = "linux") {
        "Epoll"
    } else if cfg!(target_os = "macos") {
        "Kqueue"
    } else {
        "Iocp"
    };
    assert_eq!(stdout.lines().next(), Some(expected), "the system's best backend runs by default");
}

/// The same program on the portable poll() backend, the reference the
/// others are checked against.
#[test]
fn sockets_park_their_task_with_poll() {
    let source = SOCKETS_PROGRAM.replace(
        "async.run(() => {",
        "async.run_with(async.RuntimeOptions().backend(async.Backend.Poll), () => {",
    );
    let stdout = assert_runs("task_sockets_poll", &source);
    assert_eq!(stdout.lines().next(), Some("Poll"));
}

#[test]
fn spawned_tasks_run_on_any_worker() {
    assert_runs("task_spawn", SPAWN_PROGRAM);
}

/// The same on the poll() backend, whose doorbell is a self-pipe (or a
/// loopback UDP socket on Windows).
#[test]
fn spawned_tasks_run_on_any_worker_with_poll() {
    let source = SPAWN_PROGRAM.replace("async.RuntimeOptions()", "async.RuntimeOptions().backend(async.Backend.Poll)");
    assert_runs("task_spawn_poll", &source);
}

#[test]
fn blocking_calls_and_shared_sockets() {
    assert_runs("task_blocking", BLOCKING_PROGRAM);
}

#[test]
fn blocking_calls_and_shared_sockets_with_poll() {
    let source = BLOCKING_PROGRAM.replace("async.RuntimeOptions()", "async.RuntimeOptions().backend(async.Backend.Poll)");
    assert_runs("task_blocking_poll", &source);
}

#[test]
fn tasks_are_cancelled_and_awaited() {
    assert_runs("task_cancel", CANCEL_PROGRAM);
}

/// Runs `source`, which must panic with `message`.
fn assert_panics(name: &str, source: &str, message: &str) {
    let exe = crate::io_tests::build(name, source).expect("build");
    let output = std::process::Command::new(&exe).output().expect("spawn");
    let text = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
    assert!(!output.status.success(), "{name} should panic");
    assert!(text.contains(message), "{name} output: {text}");
}

#[test]
fn joining_itself_panics() {
    assert_panics("task_self_join", SELF_JOIN_PROGRAM, "a task cannot join itself");
}

#[test]
fn tasks_waiting_on_each_other_panic() {
    assert_panics("task_deadlock", DEADLOCK_PROGRAM, "every task is waiting for another task");
}

/// Every platform's fiber layer and I/O driver type-check and produce valid
/// IR: Windows calls the Fibers API, the others define the naked switch and
/// call epoll, kqueue or AFD poll through IOCP, each with its doorbell.
#[test]
fn task_programs_compile_on_other_platforms() {
    let cases: Vec<_> = SIMULATED_HOSTS.iter().flat_map(|&host| programs().into_iter().map(move |p| (host, p))).collect();
    let failures: Vec<String> = support::parallel_map(&cases, |((os, arch), (name, source))| {
        with_codegen_as(os, arch, &format!("task_{name}"), source, |generator, module| {
            generator.generate(module).map_err(|d| module.sources.render(&d))?;
            generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
            let ir = generator.module.to_string();
            let switch = match (*os, *arch) {
                ("windows", _) => "@SwitchToFiber(",
                (_, "aarch64") => "stp x19, x20",
                _ => "pushq %rbp",
            };
            let driver = match *os {
                "windows" => "@NtDeviceIoControlFile(",
                "macos" => "@kevent(",
                _ => "@epoll_wait(",
            };
            // The doorbell that wakes a worker from another thread.
            let doorbell = match *os {
                "windows" => "@PostQueuedCompletionStatus(",
                "macos" => "@kevent(",
                _ => "@eventfd(",
            };
            for expect in [switch, driver, doorbell] {
                if !ir.contains(expect) {
                    return Err(format!("IR does not contain {expect}"));
                }
            }
            Ok(())
        })
        .err()
        .map(|e| format!("{os}/{arch} {name}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
