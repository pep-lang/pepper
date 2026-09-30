//! Helpers shared by the integration tests. A module that needs one
//! declares `use crate::support;`.

use std::process::{Command, Output};
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
