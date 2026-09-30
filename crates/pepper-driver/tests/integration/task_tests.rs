//! Tasks in the `async` module (`runtime/async/task.pep` over the fibers in
//! `fiber_posix.pep` / `fiber_windows.pep`): programs are compiled, linked
//! and run on the host. Each asserts internally and returns 0.
//!
//! `task_programs_compile_on_other_platforms` pushes them through sema and
//! codegen with the host simulated as each other platform, so the Windows
//! Fibers layer, the other architecture's context switch, and each OS's I/O
//! driver (epoll, kqueue, WSAPoll) produce valid IR on any host.

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
    var before = _pep_live_allocs();
    async.run(() => {
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

fn programs() -> Vec<(&'static str, &'static str)> {
    vec![("sockets", SOCKETS_PROGRAM)]
}

#[test]
fn tasks_take_turns_and_free_everything() {
    assert_runs("task_scheduling", SCHEDULING_PROGRAM);
}

#[test]
fn sockets_park_their_task() {
    assert_runs("task_sockets", SOCKETS_PROGRAM);
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
/// call epoll, kqueue or WSAPoll.
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
                "windows" => "@WSAPoll(",
                "macos" => "@kevent(",
                _ => "@epoll_wait(",
            };
            for expect in [switch, driver] {
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
