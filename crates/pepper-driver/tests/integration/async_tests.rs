//! The `async` runtime module (`runtime/async/`) and the thread-safety model
//! it relies on: programs that `import async` are compiled, linked and run
//! on the host. Each Pepper program asserts internally (a failed `assert`
//! prints its message and aborts) and returns 0 on success.
//!
//! `other_platforms_compile` also pushes every program through the platform
//! filter, sema and LLVM codegen with the host simulated as every other
//! platform, so each platform layer type-checks and produces valid IR
//! wherever the tests run.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::PathBuf;
use std::process::Command;

use crate::support;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

fn source_dir(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("pepper_async_{}_{}", name, std::process::id()))
}

/// Write `source` as `main.pep` in a fresh directory for `name`; return its
/// path and the directory.
fn write_source(name: &str, source: &str) -> (PathBuf, PathBuf) {
    let dir = source_dir(name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let src = dir.join("main.pep");
    std::fs::write(&src, source).unwrap();
    (src, dir)
}

/// Compile, link and run `source`; panic with its output unless it exits 0.
fn assert_runs(name: &str, source: &str) -> String {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let (src, dir) = write_source(name, source);
    let exe = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src.to_string_lossy().into_owned(),
        "-o".to_string(),
        exe.to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
    ]);
    let code = pepper_driver::run(options).unwrap_or_else(|e| panic!("{name}: compile failed: {e}"));
    assert_eq!(code, 0);
    let output = Command::new(&exe).output().expect("spawn");
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let code = output.status.code().unwrap_or(-1);
    // A failed assert prints its message as the last line of stdout.
    let failed = stdout.lines().last().unwrap_or("");
    assert_eq!(code, 0, "{name} exited with {code}; failed assert: {failed:?}\nstdout:\n{stdout}\nstderr:\n{stderr}");
    let _ = std::fs::remove_dir_all(dir);
    stdout
}

/// Spawned threads run their body, see themselves as `Thread.current()`,
/// finish, and join; the main thread is named "main"; everything a thread
/// allocated is freed once its Thread is joined and dropped.
const THREAD_PROGRAM: &str = r#"
import async;

const ran = Atomic<long>(0);
const names_ok = Atomic<long>(0);
# The runtime's globals are initialized before this file's, so an
# initializer may already use the async module.
const initializing_thread = async.Thread.current();

work() {
    var me = async.Thread.current();
    if (me.name() == "worker" && !me.is_finished()) {
        names_ok.fetch_add(1);
    }
    ran.fetch_add(1);
}

unnamed() {}

run_threads() {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 8) {
        workers.append(async.Thread.spawn(work, "worker"));
        i = i + 1;
    }
    var ids = HashSet<async.ThreadId>();
    for (var worker in workers) {
        assert(worker.is_joinable(), "joinable before join");
        worker.join();
        assert(worker.is_finished(), "finished after join");
        assert(!worker.is_joinable(), "not joinable after join");
        ids.insert(worker.id());
    }
    assert(ids.count() == 8, "every thread has its own id");
    assert(ran.load() == 8, "every thread ran");
    assert(names_ok.load() == 8, "every thread saw its own Thread");

    async.ThreadBody body = unnamed;
    var anonymous = async.Thread.spawn(body);
    anonymous.join();
    assert(anonymous.name() == "", "unnamed by default");
}

main(): int {
    var main_thread = async.Thread.current();
    assert(main_thread.name() == "main", "main thread name");
    assert(initializing_thread.id() == main_thread.id(), "initializers run on the main thread");
    assert(async.Thread.current().id() == main_thread.id(), "current() is stable");
    assert(!main_thread.is_joinable(), "main thread cannot be joined");

    # Warm up the lazily allocated state (the main thread's Thread above),
    # then check that threads leave nothing behind.
    var before = _pep_live_allocs();
    run_threads();
    assert(_pep_live_allocs() == before, "threads leak nothing");

    # A dropped, unjoined thread is detached and still runs to completion.
    async.Thread.spawn(work, "worker");
    while (ran.load() < 9) {
        async.Thread.sleep(1);
    }
    return 0;
}
"#;

/// Each thread has its own ThreadLocal value, and a thread's struct value is
/// released when the thread exits.
const THREAD_LOCAL_PROGRAM: &str = r#"
import async;

struct Tracker {
    int Value;
    construct(this.Value = 0) {}
    destruct {
        released.fetch_add(1);
    }
}

const released = Atomic<long>(0);
const counter = async.ThreadLocal<int>();
const tracker = async.ThreadLocal<Tracker>();
const sum = Atomic<long>(0);

work() {
    assert(!counter.is_set(), "a new thread starts without a value");
    assert(counter.get() == 0, "default value");
    var i = 0;
    while (i < 1000) {
        counter.set(counter.get() + 1);
        i = i + 1;
    }
    sum.fetch_add(counter.get());
    tracker.set(Tracker(counter.get()));
}

main(): int {
    counter.set(-5);
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(work));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    assert(sum.load() == 4000, "each thread counted on its own value");
    assert(counter.get() == -5, "the main thread's value is untouched");
    assert(released.load() == 4, "each exiting thread released its value");

    tracker.set(Tracker(1));
    tracker.set(Tracker(2));
    assert(released.load() == 5, "set releases the value it replaces");
    assert(tracker.get().Value == 2, "get returns the latest value");
    tracker.clear();
    assert(released.load() == 6, "clear releases the value");
    assert(!tracker.is_set(), "cleared");
    return 0;
}
"#;

/// Processor counts are positive, and hyperthreads count only in the
/// logical count.
const CPUS_PROGRAM: &str = r#"
import [logical_cpus, physical_cpus] from async;

main(): int {
    var logical = logical_cpus();
    var physical = physical_cpus();
    assert(logical >= 1, "at least one logical processor");
    assert(physical >= 1, "at least one core");
    assert(physical <= logical, "no more cores than logical processors");
    print("logical ", logical, " physical ", physical, "\n");
    return 0;
}
"#;

/// Many threads copying and dropping references to one `[Shared]` object at
/// once: the atomic counts end exactly where they started.
const SHARED_COUNTS_PROGRAM: &str = r#"
import async;

[Shared]
struct Config {
    const Port: int;
    construct(this.Port = 0) {}
}

const config = Config(8080);
const total = Atomic<long>(0);

copy_references() {
    var i = 0;
    while (i < 100000) {
        var copy = config;
        total.fetch_add(copy.Port - 8079);
        i = i + 1;
    }
}

main(): int {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(copy_references));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    assert(total.load() == 400000, "every copy saw the object");
    assert(__refcount<Config>(config) == 1, "the count is back to the global's own reference");
    return 0;
}
"#;

/// Exported module-scope variables are implicitly shared: `const` and
/// thread-safe (a number, an `Atomic`, a `[Shared]` struct), so threads may
/// use them directly.
const EXPORTED_GLOBALS_PROGRAM: &str = r#"
import async;

[Shared]
struct Limits {
    const Step: long;
    construct(this.Step = 1) {}
}

export const rounds = 50000;
export const limits = Limits(2);
export const hits = Atomic<long>(0);

bump() {
    var i = 0;
    while (i < rounds) {
        hits.fetch_add(limits.Step);
        i = i + 1;
    }
}

main(): int {
    var a = async.Thread.spawn(bump);
    var b = async.Thread.spawn(bump);
    a.join();
    b.join();
    assert(hits.load() == 200000, "both threads updated the exported Atomic");
    return 0;
}
"#;

#[test]
fn threads_spawn_and_join() {
    assert_runs("threads", THREAD_PROGRAM);
}

#[test]
fn thread_local_values() {
    assert_runs("thread_local", THREAD_LOCAL_PROGRAM);
}

#[test]
fn processor_counts() {
    let stdout = assert_runs("cpus", CPUS_PROGRAM);
    eprintln!("{stdout}");
}

/// A closure as the thread body carries its captured values to the thread.
const CLOSURE_BODY_PROGRAM: &str = r#"
import async;

main(): int {
    var total = Atomic<long>(0);
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        var step: long = i + 1;
        workers.append(async.Thread.spawn(() => { total.fetch_add(step); }));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    assert(total.load() == 10, "each closure added its captured step");
    return 0;
}
"#;

#[test]
fn closure_thread_bodies() {
    assert_runs("closure_body", CLOSURE_BODY_PROGRAM);
}

/// `shared` function types: thread bodies built from thread-safe captures
/// (an `Atomic`, a `[Shared]` struct, another `shared` function value, a
/// number), a named function, a `[Shared]` struct holding a `shared`
/// function field, and `shared` values used where plain ones are expected.
/// Plain closures capturing a `String` keep working on one thread.
const SHARED_FUNCTIONS_PROGRAM: &str = r#"
import async;

[Shared]
struct Job {
    const Weight: long;
    const Run: shared (long) => void;
    construct(this.Weight = 1, this.Run = (n: long) => {}) {}
}

const total = Atomic<long>(0);
const named_runs = Atomic<long>(0);

count_named() {
    named_runs.fetch_add(1);
}

apply_plain(f: (long) => long, x: long): long {
    return f(x);
}

make_adder(step: long): shared (long) => long {
    return (x: long) => x + step;
}

main(): int {
    var add: shared (long) => void = (n: long) => { total.fetch_add(n); };
    var job = Job(5, add);
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(() => { job.Run(job.Weight); }));
        workers.append(async.Thread.spawn(() => { add(1); }));
        workers.append(async.Thread.spawn(count_named));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    assert(total.load() == 24, "every thread ran its shared closure");
    assert(named_runs.load() == 4, "named functions are thread bodies");

    # A shared value converts to the plain type of the same signature.
    var add_two = make_adder(2);
    assert(apply_plain(add_two, 40) == 42, "shared value passed as plain");
    var plain: (long) => long = add_two;
    assert(plain(1) == 3, "shared value stored as plain");

    # Plain closures still capture anything, on one thread.
    var greeting = "hello";
    var greet: () => String = () => greeting + " world";
    assert(greet() == "hello world", "plain closure captures a String");
    return 0;
}
"#;

#[test]
fn shared_function_types() {
    assert_runs("shared_functions", SHARED_FUNCTIONS_PROGRAM);
}

/// A C function pointer (`extern (P) => R`) is a code address: thread
/// bodies may capture and call one.
const C_FUNCTION_POINTERS_PROGRAM: &str = r#"
import async;

twice(x: int): int { return x * 2; }

main(): int {
    extern (int) => int f = twice;
    var total = Atomic<int>(0);
    var worker = async.Thread.spawn(() => { total.fetch_add(f(21)); });
    worker.join();
    assert(total.load() == 42, "the thread called the C function pointer");
    return 0;
}
"#;

#[test]
fn threads_share_c_function_pointers() {
    assert_runs("c_function_pointers", C_FUNCTION_POINTERS_PROGRAM);
}

#[test]
fn shared_counts_are_atomic() {
    assert_runs("shared_counts", SHARED_COUNTS_PROGRAM);
}

#[test]
fn exported_globals_are_shared() {
    assert_runs("exported_globals", EXPORTED_GLOBALS_PROGRAM);
}

/// Compile, link and run `source`, which must panic: a nonzero exit whose
/// last line of stdout (the panic message) contains `message`.
fn assert_panics(name: &str, source: &str, message: &str) {
    std::env::set_current_dir(repo_root()).unwrap();
    let (src, dir) = write_source(name, source);
    let exe = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src.to_string_lossy().into_owned(),
        "-o".to_string(),
        exe.to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
    ]);
    let code = pepper_driver::run(options).unwrap_or_else(|e| panic!("{name}: compile failed: {e}"));
    assert_eq!(code, 0);
    let output = Command::new(&exe).output().expect("spawn");
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(!output.status.success(), "{name} was expected to panic\nstdout:\n{stdout}");
    let last = stdout.lines().last().unwrap_or("");
    assert!(last.contains(message), "{name}: expected a panic containing {message:?}, got {last:?}\nstdout:\n{stdout}");
    let _ = std::fs::remove_dir_all(dir);
}

/// `Mutex<T>`: N threads each add to a counter M times under the lock and
/// the total is exact (the counter's slot is a plain, non-atomic `long`, so
/// only the lock keeps the increments apart); `try_lock` takes the body when
/// the lock is free and `else` when it is busy; every path out of a `with`
/// body unlocks and leaks nothing.
const MUTEX_PROGRAM: &str = r#"
import async;

[Shared]
struct Counter {
    const Slot: __ptr<long>;
    construct() {
        Slot = _pep_malloc(sizeof<long>());
    }
    destruct {
        _pep_free(Slot);
    }
}

[Shared]
struct Label {
    const Id: long;
    construct(this.Id = 0) {}
}

const counter = async.Mutex<Counter>(Counter());
const busy_seen = Atomic<long>(0);
const free_seen = Atomic<long>(0);

add_many() {
    var i = 0;
    while (i < 20000) {
        with (var c = counter.lock()) {
            c.Slot[0] = c.Slot[0] + 1;
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
long read_and_return(async.Mutex<Label> labels) {
    with (var label = labels.lock()) {
        var copy = label;
        var extra = Label(label.Id + 1);
        return copy.Id + extra.Id;
    }
    return -1;
}

# Breaks and continues out of the body.
long loop_paths(async.Mutex<Label> labels) {
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
            seen = seen + local.Id + label.Id;
        }
    }
    return seen;
}

main(): int {
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
        assert(c.Slot[0] == 160000, "every locked increment counted");
        assert(counter.is_held(), "held inside the block");
    }
    assert(!counter.is_held(), "released after the block");

    # try_lock: busy while this thread holds the lock, from here and from
    # another thread; free afterwards.
    with (var c = counter.lock()) {
        with (var again = counter.try_lock()) {
            assert(false, "try_lock on the holding thread must not take the lock");
        } else {
            busy_seen.fetch_add(1);
        }
        async.Thread.spawn(try_from_other_thread).join();
    }
    assert(busy_seen.load() == 2, "try_lock reported busy twice");
    async.Thread.spawn(try_from_other_thread).join();
    assert(free_seen.load() == 1, "try_lock took the free lock");

    # Every exit path unlocks and releases.
    var labels = async.Mutex<Label>(Label(10));
    var before = _pep_live_allocs();
    assert(read_and_return(labels) == 21, "return from the body");
    assert(loop_paths(labels) == 1 + 10 + 3 + 10 + 5 + 10, "continue and break out of the body");
    assert(_pep_live_allocs() == before, "lock paths leak nothing");
    with (var label = labels.try_lock()) {
        assert(label.Id == 10, "the Mutex is unlocked and still holds its value");
    } else {
        assert(false, "a return or break left the Mutex locked");
    }

    # A Mutex and its value are freed with the last reference.
    var start = _pep_live_allocs();
    make_and_drop();
    assert(_pep_live_allocs() == start, "a dropped Mutex frees its lock and releases its value");
    return 0;
}

make_and_drop() {
    var m = async.Mutex<Label>(Label(3));
    var cond = m.condition();
    with (var label = m.lock()) {
        assert(label.Id == 3, "the value");
    }
}
"#;

/// Locking a Mutex again on the thread that holds it panics instead of
/// deadlocking.
const MUTEX_RELOCK_PROGRAM: &str = r#"
import async;

[Shared]
struct Box {
    const N: long;
    construct(this.N = 0) {}
}

main(): int {
    var m = async.Mutex<Box>(Box(1));
    with (var a = m.lock()) {
        with (var b = m.lock()) {
            return 1;
        }
    }
    return 2;
}
"#;

/// Waiting on a Condition without holding its Mutex panics.
const CONDITION_UNHELD_PROGRAM: &str = r#"
import async;

[Shared]
struct Box {
    const N: long;
    construct(this.N = 0) {}
}

main(): int {
    var m = async.Mutex<Box>(Box(1));
    var c = m.condition();
    c.wait();
    return 1;
}
"#;

/// `Condition<T>`: a producer and consumers hand jobs over through a
/// counter in a Mutex; `wait_for` with nothing to wake it times out.
const CONDITION_PROGRAM: &str = r#"
import async;

[Shared]
struct Queue {
    const Waiting: __ptr<long>;
    const Done: __ptr<long>;
    construct() {
        Waiting = _pep_malloc(sizeof<long>());
        Done = _pep_malloc(sizeof<long>());
    }
    destruct {
        _pep_free(Waiting);
        _pep_free(Done);
    }
}

const queue = async.Mutex<Queue>(Queue());
const changed = queue.condition();
const taken = Atomic<long>(0);

consumer() {
    while (true) {
        with (var q = queue.lock()) {
            while (q.Waiting[0] == 0 && q.Done[0] == 0) {
                changed.wait();
            }
            if (q.Waiting[0] == 0) {
                return;
            }
            q.Waiting[0] = q.Waiting[0] - 1;
            taken.fetch_add(1);
            changed.notify_all();
        }
    }
}

main(): int {
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
            while (q.Waiting[0] >= 4) {
                changed.wait();
            }
            q.Waiting[0] = q.Waiting[0] + 1;
            changed.notify_one();
        }
        i = i + 1;
    }
    with (var q = queue.lock()) {
        q.Done[0] = 1;
        changed.notify_all();
    }
    for (var c in consumers) {
        c.join();
    }
    assert(taken.load() == 300, "every job was taken exactly once");

    # Nobody notifies: wait_for runs out and reports it.
    with (var q = queue.lock()) {
        var woken = changed.wait_for(30);
        # A spurious wakeup is allowed to return true; wait again to be sure.
        if (woken) {
            woken = changed.wait_for(30);
        }
        assert(!woken, "wait_for timed out");
        assert(queue.is_held(), "wait_for locks again before returning");
    }
    return 0;
}
"#;

/// `Once` runs its body exactly once under racing threads; `Lazy<T>` builds
/// its value once and every thread gets the same one.
const ONCE_PROGRAM: &str = r#"
import async;

[Shared]
struct Settings {
    const Workers: long;
    construct(this.Workers = 0) {}
}

const once = async.Once();
const once_runs = Atomic<long>(0);
const lazy_runs = Atomic<long>(0);
const same = Atomic<long>(0);

slow_setup() {
    async.Thread.sleep(20);
    once_runs.fetch_add(1);
}

build_settings(): Settings {
    lazy_runs.fetch_add(1);
    async.Thread.sleep(20);
    return Settings(7);
}

const settings = async.Lazy<Settings>(build_settings);
const first = Atomic<Settings>();

race() {
    once.call(slow_setup);
    # Everything the body did is visible once call returns.
    assert(once_runs.load() == 1, "the body finished before call returned");
    var s = settings.get();
    first.compare_exchange(__default<Settings>(), s);
    if (__address<Settings>(s) == __address<Settings>(first.load())) {
        same.fetch_add(1);
    }
}

main(): int {
    assert(!once.is_done(), "nothing ran yet");
    assert(!settings.is_built(), "nothing built yet");
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 8) {
        workers.append(async.Thread.spawn(race));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    assert(once_runs.load() == 1, "Once ran its body once");
    assert(once.is_done(), "done");
    once.call(slow_setup);
    assert(once_runs.load() == 1, "later calls do not run a body");
    assert(lazy_runs.load() == 1, "Lazy built its value once");
    assert(same.load() == 8, "every thread got the same value");
    assert(settings.get().Workers == 7, "the value");
    assert(settings.is_built(), "built");

    # A dropped Lazy releases its value.
    var before = _pep_live_allocs();
    make_lazy();
    assert(_pep_live_allocs() == before, "a dropped Lazy frees everything");
    return 0;
}

make_settings(): Settings {
    return Settings(1);
}

make_lazy() {
    var l = async.Lazy<Settings>(make_settings);
    assert(l.get().Workers == 1, "built");
}
"#;

/// A Once's body that calls `call` on the same Once panics instead of
/// waiting for itself.
const ONCE_REENTER_PROGRAM: &str = r#"
import async;

const once = async.Once();

again() {
    once.call(again);
}

main(): int {
    once.call(again);
    return 1;
}
"#;

/// `Channel<T>`: FIFO order, a bounded send waits for room, `close` wakes
/// blocked senders and receivers, `for` ends after close, `receive_for`
/// times out, many producers and consumers deliver every value once, and a
/// channel dropped with values queued releases them.
const CHANNEL_PROGRAM: &str = r#"
import async;

[Shared]
struct Message {
    const Id: long;
    construct(this.Id = 0) {}
    destruct {
        released.fetch_add(1);
    }
}

const released = Atomic<long>(0);
const fifo = async.Channel<long>();
const bounded = async.Channel<long>(1);
const second_sent = Atomic<long>(0);
const empty = async.Channel<long>();
const full = async.Channel<long>(1);
const woken = Atomic<long>(0);
const work = async.Channel<long>(8);
const sum = Atomic<long>(0);
const received_count = Atomic<long>(0);

check_order() {
    var expected: long = 0;
    for (var n in fifo) {
        assert(n == expected, "values arrive in the order they were sent");
        expected = expected + 1;
    }
    assert(expected == 1000, "the loop ended after the last value");
}

send_second() {
    bounded.send(2);
    second_sent.store(1);
}

receive_until_closed() {
    var r = empty.receive();
    assert(r.is_err(), "a receiver woken by close gets an error");
    woken.fetch_add(1);
}

send_into_full() {
    assert(!full.send(2), "a sender woken by close fails");
    woken.fetch_add(1);
}

produce() {
    var i: long = 1;
    while (i <= 1000) {
        work.send(i);
        i = i + 1;
    }
}

consume() {
    for (var n in work) {
        sum.fetch_add(n);
        received_count.fetch_add(1);
    }
}

drop_with_queued() {
    var c = async.Channel<Message>();
    var i: long = 0;
    while (i < 40) {
        c.send(Message(i));
        i = i + 1;
    }
    var r = c.receive();
    assert(r.value().Id == 0, "the oldest message comes first");
    assert(c.count() == 39, "39 left");
}

main(): int {
    # FIFO from one sender, across growth of the unbounded buffer.
    var checker = async.Thread.spawn(check_order);
    var i: long = 0;
    while (i < 1000) {
        assert(fifo.send(i), "an open channel accepts values");
        i = i + 1;
    }
    fifo.close();
    checker.join();
    assert(!fifo.send(1), "a closed channel refuses values");
    assert(fifo.is_closed(), "closed");
    assert(fifo.receive().is_err(), "closed and empty");

    # A bounded send waits for room.
    assert(bounded.send(1), "room for one");
    assert(!bounded.try_send(9), "try_send on a full channel fails");
    var sender = async.Thread.spawn(send_second);
    async.Thread.sleep(50);
    assert(second_sent.load() == 0, "the second send waits while the channel is full");
    assert(bounded.receive().value() == 1, "first value");
    sender.join();
    assert(second_sent.load() == 1, "the send finished once there was room");
    assert(bounded.receive().value() == 2, "second value");
    assert(bounded.try_receive().is_err(), "nothing waiting");
    assert(!bounded.is_closed(), "empty is not closed");

    # close wakes blocked receivers and senders.
    full.send(1);
    var blocked = Array<async.Thread>();
    blocked.append(async.Thread.spawn(receive_until_closed));
    blocked.append(async.Thread.spawn(receive_until_closed));
    blocked.append(async.Thread.spawn(send_into_full));
    async.Thread.sleep(50);
    assert(woken.load() == 0, "all three are waiting");
    empty.close();
    full.close();
    for (var t in blocked) {
        t.join();
    }
    assert(woken.load() == 3, "close woke them all");
    assert(full.receive().value() == 1, "values queued before close are still received");
    assert(full.receive().is_err(), "then the closed channel is empty");

    # receive_for runs out.
    var quiet = async.Channel<long>();
    assert(quiet.receive_for(30).is_err(), "receive_for timed out");
    quiet.send(5);
    assert(quiet.receive_for(30).value() == 5, "receive_for returns a waiting value");

    # Many producers and consumers: every value arrives exactly once.
    var producers = Array<async.Thread>();
    var consumers = Array<async.Thread>();
    i = 0;
    while (i < 4) {
        producers.append(async.Thread.spawn(produce));
        consumers.append(async.Thread.spawn(consume));
        i = i + 1;
    }
    for (var p in producers) {
        p.join();
    }
    work.close();
    for (var c in consumers) {
        c.join();
    }
    assert(received_count.load() == 4000, "every value was received once");
    assert(sum.load() == 4 * 500500, "and none was changed");

    # Generic and function payloads (a pointer to a pointer to a generic
    # type in the buffer field once crashed the thread-safety check).
    var counters = async.Channel<Atomic<long>>();
    var one = Atomic<long>(1);
    counters.send(one);
    assert(counters.receive().value().load() == 1, "an Atomic crosses by reference");
    var bodies = async.Channel<async.ThreadBody>();
    bodies.send(() => { woken.fetch_add(10); });
    bodies.receive().value()();
    assert(woken.load() == 13, "a shared function value crosses");

    # A channel dropped with values still queued releases them.
    var before = _pep_live_allocs();
    drop_with_queued();
    assert(released.load() == 40, "every message was released");
    assert(_pep_live_allocs() == before, "a dropped channel frees everything");
    return 0;
}
"#;

/// `Channel<T>` for a `T` that is not thread-safe: `send` copies, so the
/// receiver owns a value the sender cannot change or release; many
/// producers and consumers exchange Strings and Arrays; and nothing leaks.
const CHANNEL_COPY_PROGRAM: &str = r#"
import async;

struct Order {
    String customer;
    Array<String> items;
    construct(this.customer = "") {
        items = Array<String>();
    }
}

const orders = async.Channel<Order>(8);
const received_items = Atomic<long>(0);
const received_letters = Atomic<long>(0);
const first = async.Channel<String>();

produce() {
    var i = 0;
    while (i < 500) {
        var order = Order("ada");
        order.items.append("tea");
        order.items.append("cake");
        orders.send(order);
        # Changing the original after sending does not reach the receiver.
        order.items.append("extra");
        order.customer.append("!");
        i = i + 1;
    }
}

consume() {
    for (var order in orders) {
        assert(order.customer == "ada", "the copy was taken before the change");
        received_items.fetch_add(order.items.count() as long);
        for (var item in order.items) {
            received_letters.fetch_add(item.length() as long);
        }
    }
}

exchange() {
    var producers = Array<async.Thread>();
    var consumers = Array<async.Thread>();
    var i = 0;
    while (i < 3) {
        producers.append(async.Thread.spawn(produce));
        consumers.append(async.Thread.spawn(consume));
        i = i + 1;
    }
    for (var p in producers) {
        p.join();
    }
    orders.close();
    for (var c in consumers) {
        c.join();
    }
    assert(received_items.load() == 3 * 500 * 2, "every item arrived once");
    assert(received_letters.load() == 3 * 500 * 7, "and unchanged");
}

main(): int {
    var line = "hello";
    first.send(line);
    line.append(" world");
    assert(first.receive().value() == "hello", "a String is sent as a copy");

    # Warm up the main thread's lazily made Thread (join() asks for it).
    async.Thread.current();
    var before = _pep_live_allocs();
    exchange();
    assert(_pep_live_allocs() == before, "sending copies leaks nothing");
    return 0;
}
"#;

#[test]
fn channels_copy_values_that_are_not_thread_safe() {
    assert_runs("channel_copy", CHANNEL_COPY_PROGRAM);
}

#[test]
fn mutex_locks() {
    assert_runs("mutex", MUTEX_PROGRAM);
}

#[test]
fn mutex_relock_panics() {
    assert_panics("mutex_relock", MUTEX_RELOCK_PROGRAM, "Mutex.lock: the calling thread already holds this Mutex");
}

#[test]
fn condition_wait_requires_the_lock() {
    assert_panics("condition_unheld", CONDITION_UNHELD_PROGRAM, "Condition.wait: the calling thread does not hold the Mutex");
}

#[test]
fn condition_producer_consumer() {
    assert_runs("condition", CONDITION_PROGRAM);
}

#[test]
fn once_and_lazy() {
    assert_runs("once", ONCE_PROGRAM);
}

#[test]
fn once_reentry_panics() {
    assert_panics("once_reenter", ONCE_REENTER_PROGRAM, "Once.call: the body called 'call' on the Once that is running it");
}

#[test]
fn channels() {
    assert_runs("channel", CHANNEL_PROGRAM);
}

fn all_programs() -> Vec<(&'static str, &'static str)> {
    vec![
        ("threads", THREAD_PROGRAM),
        ("thread_local", THREAD_LOCAL_PROGRAM),
        ("cpus", CPUS_PROGRAM),
        ("shared_counts", SHARED_COUNTS_PROGRAM),
        ("exported_globals", EXPORTED_GLOBALS_PROGRAM),
        ("closure_body", CLOSURE_BODY_PROGRAM),
        ("shared_functions", SHARED_FUNCTIONS_PROGRAM),
        ("c_function_pointers", C_FUNCTION_POINTERS_PROGRAM),
        ("mutex", MUTEX_PROGRAM),
        ("condition", CONDITION_PROGRAM),
        ("once", ONCE_PROGRAM),
        ("channel", CHANNEL_PROGRAM),
        ("channel_copy", CHANNEL_COPY_PROGRAM),
    ]
}

const SIMULATED_HOSTS: [(&str, &str); 6] = [
    ("windows", "x86_64"),
    ("windows", "aarch64"),
    ("macos", "x86_64"),
    ("macos", "aarch64"),
    ("linux", "x86_64"),
    ("linux", "aarch64"),
];

/// Compile `source` with the host simulated as `os`/`arch` and check the
/// generated module: valid IR that calls that platform's thread API.
fn codegen_as(os: &str, arch: &str, name: &str, source: &str) -> Result<(), String> {
    std::env::set_current_dir(repo_root()).unwrap();
    let (src, dir) = write_source(&format!("{name}_{os}_{arch}"), source);
    let result = pepper_sema::with_simulated_host(os, arch, || {
        let options = pepper_driver::Options::parse_from(vec!["pepper".to_string(), src.to_string_lossy().into_owned()]);
        let mut module = pepper_driver::compiler::compile(&options, "main")?;
        let ctx = inkwell::context::Context::create();
        let mut generator = CodeGenerator::new(&ctx, "main");
        generator.generate(&mut module).map_err(|d| module.sources.render(&d))?;
        generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
        let ir = generator.module.to_string();
        let expect = match os {
            "windows" => "@FlsAlloc(",
            _ => "@pthread_key_create(",
        };
        if !ir.contains(expect) {
            return Err(format!("IR does not reference {expect}"));
        }
        // The sync programs also reach that platform's locks and timed waits.
        if ["mutex", "condition", "once", "channel", "channel_copy"].contains(&name) {
            let expect: &[&str] = match os {
                "windows" => &["@AcquireSRWLockExclusive(", "@SleepConditionVariableSRW("],
                "macos" => &["@pthread_mutex_lock(", "@pthread_cond_timedwait_relative_np("],
                _ => &["@pthread_mutex_lock(", "@pthread_cond_timedwait("],
            };
            if let Some(missing) = expect.iter().find(|e| !ir.contains(*e)) {
                return Err(format!("IR does not reference {missing}"));
            }
        }
        Ok(())
    });
    let _ = std::fs::remove_dir_all(dir);
    result
}

#[test]
fn other_platforms_compile() {
    let cases: Vec<_> = SIMULATED_HOSTS.iter().flat_map(|&host| all_programs().into_iter().map(move |p| (host, p))).collect();
    let failures: Vec<String> = support::parallel_map(&cases, |&((os, arch), (name, source))| {
        codegen_as(os, arch, name, source).err().map(|e| format!("{os}/{arch} {name}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
