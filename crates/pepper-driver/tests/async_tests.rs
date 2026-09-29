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

var ran = Atomic<long>(0);
var names_ok = Atomic<long>(0);

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

var released = Atomic<long>(0);
var counter = async.ThreadLocal<int>();
var tracker = async.ThreadLocal<Tracker>();
var sum = Atomic<long>(0);

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

var config = Config(8080);
var total = Atomic<long>(0);

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

#[test]
fn shared_counts_are_atomic() {
    assert_runs("shared_counts", SHARED_COUNTS_PROGRAM);
}

fn all_programs() -> Vec<(&'static str, &'static str)> {
    vec![
        ("threads", THREAD_PROGRAM),
        ("thread_local", THREAD_LOCAL_PROGRAM),
        ("cpus", CPUS_PROGRAM),
        ("shared_counts", SHARED_COUNTS_PROGRAM),
        ("closure_body", CLOSURE_BODY_PROGRAM),
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
        Ok(())
    });
    let _ = std::fs::remove_dir_all(dir);
    result
}

#[test]
fn other_platforms_compile() {
    let mut failures = vec![];
    for (os, arch) in SIMULATED_HOSTS {
        for (name, source) in all_programs() {
            if let Err(e) = codegen_as(os, arch, name, source) {
                failures.push(format!("{os}/{arch} {name}: {e}"));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
