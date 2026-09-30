//! Tasks in the `async` module (`runtime/async/task.pep` over the fibers in
//! `fiber_posix.pep` / `fiber_windows.pep`): programs are compiled, linked
//! and run on the host. Each asserts internally and returns 0.
//!
//! `task_programs_compile_on_other_platforms` pushes them through sema and
//! codegen with the host simulated as each other platform, so the Windows
//! Fibers layer and the other architecture's context switch produce valid
//! IR on any host.

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

fn programs() -> Vec<(&'static str, &'static str)> {
    vec![("scheduling", SCHEDULING_PROGRAM)]
}

#[test]
fn tasks_take_turns_and_free_everything() {
    assert_runs("task_scheduling", SCHEDULING_PROGRAM);
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

/// Every platform's fiber layer type-checks and produces valid IR: Windows
/// calls the Fibers API, the others define the naked switch.
#[test]
fn task_programs_compile_on_other_platforms() {
    let cases: Vec<_> = SIMULATED_HOSTS.iter().flat_map(|&host| programs().into_iter().map(move |p| (host, p))).collect();
    let failures: Vec<String> = support::parallel_map(&cases, |((os, arch), (name, source))| {
        with_codegen_as(os, arch, &format!("task_{name}"), source, |generator, module| {
            generator.generate(module).map_err(|d| module.sources.render(&d))?;
            generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
            let ir = generator.module.to_string();
            let expect = match (*os, *arch) {
                ("windows", _) => "@SwitchToFiber(",
                (_, "aarch64") => "stp x19, x20",
                _ => "pushq %rbp",
            };
            if !ir.contains(expect) {
                return Err(format!("IR does not contain {expect}"));
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
