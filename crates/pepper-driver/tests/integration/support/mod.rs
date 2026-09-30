//! Helpers shared by the integration tests. A module that needs one
//! declares `use crate::support;`.

use std::sync::atomic::{AtomicUsize, Ordering};

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
                    // As much stack as the main thread gets: sema and codegen
                    // recurse over the program, deeper in unoptimized builds.
                    .stack_size(8 << 20)
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
