//! Unit tests in Pepper: `[Test]` and `[ShouldPanic]` functions, the
//! `expect_*` checks, `pep-build --test` (a test program that lists its
//! tests and runs one), and `pep-test` (`tools/pep-test`), which builds and
//! runs them.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use crate::support;
use crate::support::{output_text, stdout_of};

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

/// A fresh scratch directory for one test.
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_test_harness_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// `source`, written to `math_test.pep` in `dir` and built with `options`.
fn build(dir: &Path, source: &str, options: &[&str]) -> PathBuf {
    let file = dir.join("math_test.pep");
    std::fs::write(&file, source).unwrap();
    let out = dir.join(if cfg!(windows) { "math_test.exe" } else { "math_test" });
    support::build_executable_with(&file, &[], options, &out, &dir.join("obj"));
    out
}

fn run(program: &Path, arguments: &[&str]) -> Output {
    Command::new(program).args(arguments).env("PEPPER_BACKTRACE", "0").output().expect("run the test program")
}

#[test]
fn a_build_without_test_leaves_tests_out() {
    let dir = scratch("normal");
    // The test's body does not even type-check: it is never built.
    let source = format!("{}\n[Test]\nbroken() {{ expect_equal(1, \"one\"); }}\n", MATH_TEST);
    let program = build(&dir, &source, &[]);
    let output = run(&program, &[]);
    assert!(output.status.success(), "{}", output_text(&output));
    assert_eq!(stdout_of(&output), "the program's own main\n");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_test_build_lists_and_runs_each_test() {
    let dir = scratch("test_build");
    let program = build(&dir, MATH_TEST, &["--test"]);
    let file = dir.join("math_test.pep");
    let file = file.to_string_lossy();

    let listed = run(&program, &["--list"]);
    assert!(listed.status.success(), "{}", output_text(&listed));
    assert_eq!(
        stdout_of(&listed),
        format!(
            "doubles\t{file}:7\treturns\t\n\
             doubles_wrongly\t{file}:15\treturns\t\n\
             reads_past_the_end\t{file}:21\tpanics\tout of bounds\n\
             returns_instead\t{file}:28\tpanics\t\n\
             spins\t{file}:31\treturns\t\n"
        )
    );

    let passed = run(&program, &["--run", "doubles"]);
    assert!(passed.status.success(), "{}", output_text(&passed));
    assert_eq!(output_text(&passed), "", "the program's own main does not run");

    let failed = run(&program, &["--run", "doubles_wrongly"]);
    assert!(!failed.status.success());
    assert_eq!(
        output_text(&failed),
        format!("{file}:16:5: panic: expect_equal failed\n  actual:   4\n  expected: 5\n")
    );

    let panicked = run(&program, &["--run", "reads_past_the_end"]);
    assert!(!panicked.status.success());
    assert!(output_text(&panicked).contains("panic: Array index read out of bounds"), "{}", output_text(&panicked));

    let timed_out = run(&program, &["--run", "spins", "--timeout", "1"]);
    assert_eq!(timed_out.status.code(), Some(124));
    assert_eq!(output_text(&timed_out), "error: test 'spins' timed out after 1 second\n");

    let missing = run(&program, &["--run", "nope"]);
    assert_eq!(missing.status.code(), Some(2));
    assert_eq!(output_text(&missing), format!("error: no test named 'nope' in {file}\n"));

    let bare = run(&program, &[]);
    assert_eq!(bare.status.code(), Some(2));
    assert!(output_text(&bare).contains("run it with 'pepper test'"), "{}", output_text(&bare));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn test_only_code_is_marked_with_the_test_build_option() {
    let dir = scratch("build_option");
    let source = r#"
[BuildOption("TEST")]
fixture(): Array<int> {
    var numbers = Array<int>();
    numbers.append(3);
    return numbers;
}

[Test]
uses_the_fixture() {
    expect_equal(fixture().count, 1);
}
"#;
    let program = build(&dir, source, &["--test"]);
    let output = run(&program, &["--run", "uses_the_fixture"]);
    assert!(output.status.success(), "{}", output_text(&output));
    let _ = std::fs::remove_dir_all(&dir);
}

/// `pep-test` with `arguments`, run in `dir`, finding the compiler cargo
/// built through the PATH; `None` when it has not been built.
fn pep_test(dir: &Path, arguments: &[&str]) -> Option<Output> {
    let Some(compiler) = support::compiler_binary() else {
        eprintln!("skipped: build pep-build first (cargo build --workspace)");
        return None;
    };
    let path = std::env::join_paths(
        std::iter::once(compiler.parent().unwrap().to_path_buf()).chain(std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default())),
    )
    .unwrap();
    let output = Command::new(support::pepper_tool("pep-test"))
        .args(arguments)
        .current_dir(dir)
        .env("PATH", path)
        .env("PEPPER_RUNTIME", support::repo_root().join("runtime"))
        .env_remove("PEPPER_BACKTRACE")
        .output()
        .expect("run pep-test");
    Some(output)
}

#[test]
fn pep_test_runs_every_test_in_a_folder() {
    let dir = scratch("pep_test");
    std::fs::write(dir.join("math_test.pep"), MATH_TEST).unwrap();
    std::fs::create_dir_all(dir.join("more")).unwrap();
    std::fs::write(dir.join("more").join("text_test.pep"), "[Test]\nrepeats() {\n    expect_equal(\"ab\".repeat(2), \"abab\");\n}\n").unwrap();
    // No `[Test]` line: not built.
    std::fs::write(dir.join("more").join("broken.pep"), "this does not parse").unwrap();

    let Some(output) = pep_test(&dir, &["--jobs", "1", "--timeout", "1"]) else {
        return;
    };
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
    assert!(text.ends_with("3 passed, 3 failed\n"), "{}", text);

    let listed = pep_test(&dir, &["--list", "-f", "doubles"]).unwrap();
    assert!(listed.status.success(), "{}", output_text(&listed));
    assert_eq!(stdout_of(&listed), format!("{math}::doubles\n{math}::doubles_wrongly\n"));

    let filtered = pep_test(&dir, &["math_test.pep", "--filter", "reads", "-f", "doubles"]).unwrap();
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
    let Some(output) = pep_test(&dir, &[]) else {
        return;
    };
    let text = output_text(&output);
    assert_eq!(output.status.code(), Some(1), "{}", text);
    assert!(text.contains("error: cannot build the tests of 'bad_test.pep':\n"), "{}", text);
    assert!(text.contains("bad_test.pep:3:5: error: call to undeclared function 'nope'"), "{}", text);
    let summary = stdout_of(&output);
    assert!(summary.contains("test good_test.pep::passes ... ok\n"), "{}", summary);
    assert!(summary.ends_with("1 passed, 0 failed; 1 file did not build\n"), "{}", summary);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn pep_test_version_is_the_workspace_version() {
    let output = Command::new(support::pepper_tool("pep-test")).arg("--version").output().expect("run pep-test");
    assert_eq!(stdout_of(&output), format!("pep-test {}\n", env!("CARGO_PKG_VERSION")));
}

/// The unit tests chapter's example passes its own tests: the
/// documentation examples test builds it without `--test`, which leaves
/// them out.
#[test]
fn the_documented_tests_pass() {
    let dir = scratch("docs_example");
    let example = support::repo_root().join("docs").join("examples").join("testing-basics.pep");
    let program = dir.join(if cfg!(windows) { "words.exe" } else { "words" });
    support::build_executable_with(&example, &[], &["--test"], &program, &dir.join("obj"));
    let listed = run(&program, &["--list"]);
    let names: Vec<String> = stdout_of(&listed).lines().map(|line| line.split('\t').next().unwrap().to_string()).collect();
    assert_eq!(names, ["counts_the_words", "an_empty_string_has_no_words", "reading_past_the_last_word_panics"]);
    for name in &names[..2] {
        let output = run(&program, &["--run", name]);
        assert!(output.status.success(), "{}: {}", name, output_text(&output));
    }
    let panicked = run(&program, &["--run", &names[2]]);
    assert!(!panicked.status.success());
    assert!(output_text(&panicked).contains("out of bounds"), "{}", output_text(&panicked));
    let _ = std::fs::remove_dir_all(&dir);
}
