//! `pep-test` (`tools/pep-test`) end to end: it finds the files that hold
//! `[Test]` functions, builds each with `pep-build --test`, runs every test
//! in a process of its own, and reports. It lives in the root package, not
//! with the other test harness tests in pepper-driver, so that cargo builds
//! the `pep-build` it runs (`CARGO_BIN_EXE_pep-build`) from this source: a
//! `pep-build` left in the target folder by an older build would not know
//! `--test`.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::OnceLock;

const MATH_TEST: &str = r#"
helper(x: int): int {
    return x * 2;
}

[Test]
doubles() {
    expect_equal(helper(2), 4);
    expect_true(helper(1) == 2);
    expect_false(helper(0) == 1);
    expect_not_equal("a", "b");
}

[Test]
doubles_wrongly() {
    expect_equal(helper(2), 5);
}

[Test]
[ShouldPanic("out of bounds")]
reads_past_the_end() {
    var numbers = Array<int>();
    var value = numbers[0];
}

[Test]
[ShouldPanic]
returns_instead() {}

[Test]
spins() {
    while (true) {}
}

main(): int {
    print("the program's own main");
    return 0;
}
"#;

/// The repository root.
fn repo_root() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
}

/// A fresh scratch directory for one test.
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_pep_test_tool_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn executable(name: &str) -> String {
    if cfg!(windows) { format!("{name}.exe") } else { name.to_string() }
}

/// `pep-test`, built once with this source's `pep-build`.
fn pep_test_binary() -> &'static Path {
    static BUILT: OnceLock<PathBuf> = OnceLock::new();
    BUILT.get_or_init(|| {
        let dir = scratch("tool");
        let out = dir.join(executable("pep-test"));
        let tools = repo_root().join("tools");
        let output = Command::new(env!("CARGO_BIN_EXE_pep-build"))
            .arg(tools.join("pep-test").join("main.pep"))
            .arg("-I")
            .arg(&tools)
            .arg("-o")
            .arg(&out)
            .arg("--build")
            .arg(dir.join("obj"))
            .env("PEPPER_RUNTIME", repo_root().join("runtime"))
            .output()
            .expect("run pep-build");
        assert!(output.status.success(), "building pep-test failed:\n{}", output_text(&output));
        out
    })
}

/// `pep-test` with `arguments`, run in `dir`, finding `pep-build` through
/// the PATH.
fn pep_test(dir: &Path, arguments: &[&str]) -> Output {
    let compiler = Path::new(env!("CARGO_BIN_EXE_pep-build"));
    let path = std::env::join_paths(
        std::iter::once(compiler.parent().unwrap().to_path_buf()).chain(std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default())),
    )
    .unwrap();
    Command::new(pep_test_binary())
        .args(arguments)
        .current_dir(dir)
        .env("PATH", path)
        .env("PEPPER_RUNTIME", repo_root().join("runtime"))
        .env_remove("PEPPER_BACKTRACE")
        .output()
        .expect("run pep-test")
}

/// A program's standard output, without Windows' "\r".
fn stdout_of(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).replace('\r', "")
}

/// A program's standard output followed by its standard error.
fn output_text(output: &Output) -> String {
    format!("{}{}", stdout_of(output), String::from_utf8_lossy(&output.stderr).replace('\r', ""))
}

#[test]
fn pep_test_runs_every_test_in_a_folder() {
    let dir = scratch("pep_test");
    std::fs::write(dir.join("math_test.pep"), MATH_TEST).unwrap();
    std::fs::create_dir_all(dir.join("more")).unwrap();
    std::fs::write(dir.join("more").join("text_test.pep"), "[Test]\nrepeats() {\n    expect_equal(\"ab\".repeat(2), \"abab\");\n}\n").unwrap();
    // No `[Test]` line: not built.
    std::fs::write(dir.join("more").join("broken.pep"), "this does not parse").unwrap();

    let output = pep_test(&dir, &["--jobs", "1", "--timeout", "1"]);
    let text = output_text(&output);
    assert_eq!(output.status.code(), Some(1), "{}", text);
    let math = "math_test.pep";
    let text_test = Path::new("more").join("text_test.pep");
    let text_test = text_test.to_string_lossy();
    assert!(text.starts_with("running 6 tests\n"), "{}", text);
    for line in [
        format!("test {math}::doubles ... ok"),
        format!("test {math}::doubles_wrongly ... FAILED"),
        format!("test {math}::reads_past_the_end ... ok"),
        format!("test {math}::returns_instead ... FAILED"),
        format!("test {math}::spins ... FAILED"),
        format!("test {text_test}::repeats ... ok"),
    ] {
        assert!(text.contains(&format!("{line}\n")), "missing '{line}' in:\n{text}");
    }
    assert!(text.contains(&format!("---- {math}::doubles_wrongly ({math}:15) ----\n{math}:16:5: panic: expect_equal failed\n")), "{}", text);
    assert!(text.contains("note: the test returned, but should have panicked\n"), "{}", text);
    assert!(text.contains("error: test 'spins' timed out after 1 second\n"), "{}", text);
    // The failing test ends on its panic, not by the timeout (on Windows,
    // the program turns off the crash reporting that held it up).
    assert_eq!(text.matches("timed out").count(), 1, "{}", text);
    assert!(text.ends_with("3 passed, 3 failed\n"), "{}", text);

    let listed = pep_test(&dir, &["--list", "-f", "doubles"]);
    assert!(listed.status.success(), "{}", output_text(&listed));
    assert_eq!(stdout_of(&listed), format!("{math}::doubles\n{math}::doubles_wrongly\n"));

    let filtered = pep_test(&dir, &["math_test.pep", "--filter", "reads", "-f", "doubles"]);
    let text = output_text(&filtered);
    assert_eq!(filtered.status.code(), Some(1), "{}", text);
    assert!(text.contains("test doubles ... ok\n"), "one file: names alone\n{}", text);
    assert!(text.ends_with("2 passed, 1 failed, 2 filtered out\n"), "{}", text);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn pep_test_reports_a_file_that_does_not_build() {
    let dir = scratch("pep_test_broken");
    std::fs::write(dir.join("good_test.pep"), "[Test]\npasses() {}\n").unwrap();
    std::fs::write(dir.join("bad_test.pep"), "[Test]\nfails_to_build() {\n    nope();\n}\n").unwrap();
    let output = pep_test(&dir, &[]);
    let text = output_text(&output);
    assert_eq!(output.status.code(), Some(1), "{}", text);
    assert!(text.contains("error: cannot build the tests of 'bad_test.pep':\n"), "{}", text);
    assert!(text.contains("bad_test.pep:3:5: error: call to undeclared function 'nope'"), "{}", text);
    let summary = stdout_of(&output);
    assert!(summary.contains("test good_test.pep::passes ... ok\n"), "{}", summary);
    assert!(summary.ends_with("1 passed, 0 failed; 1 file did not build\n"), "{}", summary);
    let _ = std::fs::remove_dir_all(&dir);
}

