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
    use clap::Parser;
    let dir = std::env::temp_dir().join(format!("pepper_{name}_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let src_path = dir.join(format!("{name}.pep"));
    let out_path = dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() });
    std::fs::write(&src_path, source).unwrap();
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src_path.to_string_lossy().into_owned(),
        "-o".to_string(),
        out_path.to_string_lossy().into_owned(),
    ]);
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
