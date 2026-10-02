//! How long each sema pass takes, for `-T passes`: off unless the driver
//! turns it on, then summed per pass across its runs in the process.

use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

static ENABLED: AtomicBool = AtomicBool::new(false);
static TIMES: Mutex<Option<HashMap<&'static str, (Duration, u32)>>> = Mutex::new(None);

/// Start recording.
pub fn enable() {
    ENABLED.store(true, Ordering::Relaxed);
}

/// Add the time since `started` to pass `name`'s, when recording.
pub fn record(name: &'static str, started: Instant) {
    if !ENABLED.load(Ordering::Relaxed) {
        return;
    }
    let mut times = TIMES.lock().unwrap_or_else(|e| e.into_inner());
    let entry = times.get_or_insert_with(HashMap::new).entry(name).or_default();
    entry.0 += started.elapsed();
    entry.1 += 1;
}

/// The name of the pass `call` runs: its function, and the file it is in
/// when the two differ (`check_casts` for `check_casts::check_casts(module)`,
/// `value_structs::check` for `crate::value_structs::check(module)`).
fn pass_name(call: &str) -> String {
    let function = call.split('(').next().unwrap_or(call);
    let path: Vec<&str> = function.split("::").filter(|part| !matches!(*part, "crate" | "passes")).collect();
    match path.as_slice() {
        [.., file, name] if file != name => format!("{}::{}", file, name),
        [.., name] => name.to_string(),
        [] => function.to_string(),
    }
}

/// What was recorded since the last call, slowest pass first: each pass's
/// name ([`pass_name`]), total time and number of runs.
pub fn take() -> Vec<(String, Duration, u32)> {
    let times = TIMES.lock().unwrap_or_else(|e| e.into_inner()).take().unwrap_or_default();
    let mut by_pass: HashMap<String, (Duration, u32)> = HashMap::new();
    for (call, (time, runs)) in times {
        let entry = by_pass.entry(pass_name(call)).or_default();
        entry.0 += time;
        entry.1 += runs;
    }
    let mut out: Vec<(String, Duration, u32)> = by_pass.into_iter().map(|(name, (time, runs))| (name, time, runs)).collect();
    out.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    out
}

#[cfg(test)]
mod tests {
    use super::pass_name;

    #[test]
    fn a_pass_is_named_by_its_function_and_file() {
        assert_eq!(pass_name("resolve_implicit_types(module)"), "resolve_implicit_types");
        assert_eq!(pass_name("check_casts::check_casts(module)"), "check_casts");
        assert_eq!(pass_name("crate::value_structs::check(module)"), "value_structs::check");
        assert_eq!(pass_name("resolve_resolvables(module, false)"), "resolve_resolvables");
    }
}
