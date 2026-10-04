//! The `async` runtime module's checks that stay outside `pep-test`: the
//! link summaries a checked runtime keeps, and the `PEP_CHECK_SYNC` debug
//! switch, which the runtime reads once at start, so it is set for the
//! whole program. The module's behaviour is tested by the `[Test]`
//! functions in `runtime/async/test/`.
//!
//! `io_tests::runtime_compiles_on_other_platforms` checks each platform's
//! threads and locks under every simulated host.

use std::process::Command;

use crate::io_tests::{assert_runs, build, source_dir};
use crate::support;

/// Checked alone, the runtime keeps the link summaries of its functions
/// that reach no trait call, so a program checked against it neither
/// summarizes nor checks them again (#405).
#[test]
fn a_checked_runtime_keeps_its_link_summaries() {
    let program = pepper_driver::compiler::load_with_runtime("test.pep", "import async;\ntest(): int { return 0; }\n").unwrap();
    let in_runtime = pepper_sema::checked::runtime_files(&program).unwrap();
    let runtime = pepper_sema::checked::checked_runtime(&program, &in_runtime, None).unwrap();
    let summaries = &runtime.module.checked.summaries;
    for key in ["Channel@async/channel<ulong>.send", "Channel@async/channel<ulong>.receive"] {
        assert!(summaries.contains_key(key), "no summary of '{}' among {} kept", key, summaries.len());
    }
}

/// Compile, link and run `source` with the extra environment variables
/// `env`; it must panic: a nonzero exit whose last line of stdout (the panic
/// message) contains `message`.
fn assert_panics_with(name: &str, source: &str, message: &str, env: &[(&str, &str)]) {
    let exe = build(name, source).unwrap_or_else(|e| panic!("{name}: compile failed: {e}"));
    let output = support::run_program(Command::new(&exe).envs(env.iter().copied()), source).expect("spawn");
    let stdout = support::output_text(&output);
    assert!(!output.status.success(), "{name} was expected to panic\nstdout:\n{stdout}");
    let last = stdout.lines().last().unwrap_or("");
    assert!(last.contains(message), "{name}: expected a panic containing {message:?}, got {last:?}\nstdout:\n{stdout}");
    let _ = std::fs::remove_dir_all(source_dir(name));
}

/// A reference into the locked value kept in raw memory, which the
/// compiler cannot follow, fails the census at unlock.
const CHECK_SYNC_LEAK_PROGRAM: &str = r#"
import async;

struct Box {
    var items: Array<String>;
    construct() {
        items = Array<String>();
    }
}

main(): int {
    var m = async.Mutex<Box>(Box());
    with (var b = m.lock()) {
        __ptr<Array<String>> cell = _pep_malloc(8);
        cell[0] = b.items;
    }
    return 0;
}
"#;

#[test]
fn check_sync_catches_a_reference_kept_in_raw_memory() {
    assert_runs("check_sync_off", CHECK_SYNC_LEAK_PROGRAM);
    assert_panics_with(
        "check_sync_leak",
        CHECK_SYNC_LEAK_PROGRAM,
        "PEP_CHECK_SYNC: an object in the value locked by a 'Mutex<Box>' is still referenced from outside it",
        &[("PEP_CHECK_SYNC", "1")],
    );
}

/// Under `PEP_CHECK_SYNC=1`, which walks the locked value at every unlock,
/// a program the compiler accepts passes: the `[Test]` functions of
/// `runtime/async/test/mutex_test.pep` that lock values that are not
/// thread-safe, built as a test program and run with the switch set.
#[test]
fn check_sync_passes_what_the_compiler_accepts() {
    std::env::set_current_dir(support::repo_root()).unwrap();
    let dir = source_dir("check_sync_tests");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let exe = dir.join(if cfg!(windows) { "mutex_test.exe" } else { "mutex_test" });
    let main = support::repo_root().join("runtime/async/test/mutex_test.pep");
    support::build_executable_with(&main, &[], &["--test"], &exe, &dir.join("build"));
    for test in ["mutex_of_values_that_are_not_thread_safe", "condition_waits_while_a_predicate_holds"] {
        let output = Command::new(&exe)
            .args(["--run", test])
            .env("PEP_CHECK_SYNC", "1")
            .env("PEPPER_BACKTRACE", "0")
            .output()
            .expect("spawn");
        assert!(output.status.success(), "{test}:\n{}", support::output_text(&output));
    }
    let _ = std::fs::remove_dir_all(&dir);
}
