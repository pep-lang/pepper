//! Helpers shared by the integration tests. A module that needs one
//! declares `use crate::support;` or imports it by name. A helper a second
//! test file needs moves here; it is never copied into that file.

use std::path::PathBuf;
use std::process::{Command, Output};

use pepper_codegen::CodeGenerator;
use pepper_sema::model::Module as SemaModule;
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};

/// Runs `command`, a compiled test program built from `source`, and waits
/// for its output.
///
/// A program that calls `async.run` goes wide: its scheduler starts one
/// worker thread per logical CPU. With the harness running many tests at
/// once, several such programs together put hundreds of busy threads on the
/// host, and each one ran about ten times slower than alone. So those run
/// one at a time; everything else, compiling included, stays parallel.
pub fn run_program(command: &mut Command, source: &str) -> std::io::Result<Output> {
    static WIDE: Mutex<()> = Mutex::new(());
    // A test that panicked while holding the lock poisons it; the lock
    // guards no data, so carry on.
    let _wide = source.contains("async.run").then(|| WIDE.lock().unwrap_or_else(|e| e.into_inner()));
    command.output()
}

/// Compiles and links `source` to an executable named after `name`, runs
/// it with the arguments and environment `configure` sets, and returns its
/// output.
pub fn run_linked(name: &str, source: &str, configure: impl FnOnce(&mut Command)) -> Output {
    run_linked_with(name, source, &[], configure)
}

/// [`run_linked`], compiled with the extra command-line arguments `args`
/// (`-O2`, `--no-runtime-checks=overflow`).
pub fn run_linked_with(name: &str, source: &str, args: &[&str], configure: impl FnOnce(&mut Command)) -> Output {
    use clap::Parser;
    let dir = std::env::temp_dir().join(format!("pepper_{name}_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let src_path = dir.join(format!("{name}.pep"));
    let out_path = dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() });
    std::fs::write(&src_path, source).unwrap();
    let mut argv = vec![
        "pepper".to_string(),
        src_path.to_string_lossy().into_owned(),
        "-o".to_string(),
        out_path.to_string_lossy().into_owned(),
    ];
    argv.extend(args.iter().map(|a| a.to_string()));
    let options = pepper_driver::Options::parse_from(pepper_driver::options::normalize_args(argv.into_iter().map(std::ffi::OsString::from)));
    pepper_driver::run(options).expect("compile + link");
    let mut command = Command::new(&out_path);
    configure(&mut command);
    let output = run_program(&mut command, source).expect("spawn linked binary");
    let _ = std::fs::remove_dir_all(&dir);
    output
}

/// A program's standard output as text. Windows' C runtime writes text-mode
/// stdout with CRLF line endings (and a child's CRLF printed again by its
/// parent gains another CR), so carriage returns are dropped.
pub fn stdout_of(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).replace('\r', "")
}

/// Calls `f` on every item, spread over one thread per logical CPU, and
/// returns the results in item order.
///
/// For a test that loops over many independent programs (every example,
/// every fixture, every simulated host): cargo runs test binaries one after
/// another, so a serial loop in one test is wall-clock time for the whole
/// suite. The compiler keeps its state in thread-locals, so programs compile
/// independently on separate threads. `RUST_TEST_THREADS=1` makes it serial,
/// like the test harness.
pub fn parallel_map<T: Sync, R: Send>(items: &[T], f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    let threads = std::env::var("RUST_TEST_THREADS")
        .ok()
        .and_then(|n| n.parse::<usize>().ok())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()))
        .clamp(1, items.len().max(1));
    let next = AtomicUsize::new(0);
    let mut results: Vec<(usize, R)> = std::thread::scope(|scope| {
        let workers: Vec<_> = (0..threads)
            .map(|_| {
                std::thread::Builder::new()
                    .stack_size(pepper_driver::STACK_SIZE)
                    .spawn_scoped(scope, || {
                        let mut done = vec![];
                        loop {
                            let i = next.fetch_add(1, Ordering::Relaxed);
                            let Some(item) = items.get(i) else { break };
                            done.push((i, f(item)));
                        }
                        done
                    })
                    .expect("spawn test worker")
            })
            .collect();
        workers
            .into_iter()
            .flat_map(|w| w.join().unwrap_or_else(|panic| std::panic::resume_unwind(panic)))
            .collect()
    });
    results.sort_by_key(|(i, _)| *i);
    results.into_iter().map(|(_, r)| r).collect()
}

/// The repository root, two levels above this crate.
pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

/// `source` compiled with the runtime as `test.pep`, or the rendered error.
pub fn sema(source: &str) -> Result<SemaModule, String> {
    pepper_driver::compiler::compile_with_runtime("test.pep", source)
}

/// The rendered error `source` fails to compile with.
///
/// Panics if `source` compiles.
pub fn compile_error(source: &str) -> String {
    match sema(source) {
        Ok(_) => panic!("expected a compile error for:
{}", source),
        Err(e) => e,
    }
}

/// A scratch file or directory name for one test program, unique per test
/// run: put it under `io.Directory.temp()`.
pub fn scratch_name(test: &str) -> String {
    format!("pepper_io_scratch_{}_{}", test, std::process::id())
}

/// Compiles `source` with the runtime and JIT-runs its `test` function,
/// returning what it returns.
pub fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = sema(source).unwrap_or_else(|e| panic!("compile:
{}", e));
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

/// Like [`compile_jit_with_runtime`], also returning the net change in live
/// runtime allocations across the call: 0 when nothing leaked.
pub fn jit_census(source: &str) -> (i32, i64) {
    let mut module = sema(source).unwrap_or_else(|e| panic!("compile:
{}", e));
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs = unsafe {
        ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").expect("_pep_live_allocs")
    };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    (result, after - before)
}

/// Compiles `source` with the runtime once and JIT-runs each of its
/// `(): int` functions in `names`, which must each return 0 and leave no
/// runtime allocation behind (see [`jit_census`]). For checks that each pay
/// for an expensive import (`async`, `io`, `os`): one compile serves them
/// all, and a failure names the function and what went wrong.
pub fn jit_cases(source: &str, names: &[&str]) {
    let mut module = sema(source).unwrap_or_else(|e| panic!("compile:\n{}", e));
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs = unsafe {
        ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").expect("_pep_live_allocs")
    };
    let failures: Vec<String> = names
        .iter()
        .filter_map(|name| {
            let before = unsafe { live_allocs.call() };
            let result = CodeGenerator::jit_call_i32(&ee, name);
            let leaked = unsafe { live_allocs.call() } - before;
            match result {
                Ok(0) if leaked == 0 => None,
                Ok(0) => Some(format!("{name} leaked {leaked} allocations")),
                Ok(code) => Some(format!("{name} returned {code}")),
                Err(e) => Some(format!("{name}: {e}")),
            }
        })
        .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// (name, entry point) of every documentation example, sorted by name: a
/// single `docs/examples/name.pep`, or a folder `name/` whose entry point is
/// `main.pep`.
pub fn docs_examples() -> Vec<(String, PathBuf)> {
    let dir = repo_root().join("docs").join("examples");
    let mut out: Vec<(String, PathBuf)> = std::fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("cannot read {}: {}", dir.display(), e))
        .flatten()
        .filter_map(|e| {
            let path = e.path();
            let name = e.file_name().to_string_lossy().into_owned();
            if path.is_dir() {
                let main = path.join("main.pep");
                main.is_file().then_some((name, main))
            } else {
                name.strip_suffix(".pep").map(|stem| (stem.to_string(), path.clone()))
            }
        })
        .collect();
    out.sort();
    out
}

/// Documentation examples that between them reach most of the compiler and
/// runtime: tasks, threads and their locks, sockets, TLS and HTTP,
/// processes, files and streams, generics, overloads, modules of several
/// files, closures, enums, tuples, weak and value structs. Tests that would
/// otherwise repeat a check over all of `docs/examples` use these.
const DOCS_EXAMPLE_SAMPLE: &[&str] = &[
    "cli-commands",
    "compression-tar",
    "enums-match-values",
    "function-types-closures",
    "generics-constrained-bodies",
    "generics-overrides",
    "hashing-custom",
    "http-basics",
    "interpolation-format",
    "iteration-streams",
    "maps-sorted",
    "memory-weak",
    "modules-same-name",
    "networking-tls",
    "os-environment",
    "overloading-modules",
    "processes-spawn",
    "regex-basics",
    "structs-operators",
    "tasks-select-sockets",
    "tasks-transfer",
    "threads-channel",
    "threads-local",
    "threads-mutex",
    "traits-values",
    "tuples-match",
    "tutorial-word-count",
    "value-structs-basics",
];

/// The [`docs_examples`] named in [`DOCS_EXAMPLE_SAMPLE`].
///
/// Panics if a sampled example no longer exists, so a rename updates the
/// sample instead of silently shrinking it.
pub fn docs_example_sample() -> Vec<(String, PathBuf)> {
    let all = docs_examples();
    DOCS_EXAMPLE_SAMPLE
        .iter()
        .map(|name| {
            all.iter()
                .find(|(n, _)| n == name)
                .cloned()
                .unwrap_or_else(|| panic!("docs/examples has no '{name}'; update DOCS_EXAMPLE_SAMPLE"))
        })
        .collect()
}
