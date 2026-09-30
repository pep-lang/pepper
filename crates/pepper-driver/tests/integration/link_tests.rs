//! `[Link("name")]` end-to-end: the attribute on a surviving extern must add
//! `-l{name}` to the real link command, and the linked binary must resolve
//! the symbol. The probe library is deliberately *not* in the default link
//! set (version.dll on Windows, libpthread elsewhere), so a missing flag
//! fails the link with an unresolved symbol; a green test proves the flag
//! reached the linker and the call ran.

use clap::Parser;
use std::path::PathBuf;
use std::process::Command;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}

#[test]
fn link_attribute_reaches_linker() {
    // chdir so `Options` paths and runtime discovery resolve like the CLI.
    let root = repo_root();
    std::env::set_current_dir(&root).unwrap();

    let dir = std::env::temp_dir().join("pepper_link_attr_test");
    std::fs::create_dir_all(&dir).unwrap();
    let src_path = dir.join("link_probe.pep");
    let out_path = dir.join(if cfg!(windows) { "link_probe.exe" } else { "link_probe" });
    let source = if cfg!(windows) {
        r#"
[Target(OS(Windows))] [Link("gdi32")] extern ulong GetStockObject(int objid);

main(): int {
    # gdi32 is not in the default link set: without -lgdi32 this module
    # fails to link. NULL_BRUSH (5) is a stock object with a nonzero handle
    # on any system, headless included.
    return GetStockObject(5) != 0 ? 0 : 1;
}"#
    } else {
        r#"
[Target(!OS(Windows))] [Link("pthread")] extern long pthread_self();

main(): int {
    # A live thread id is never zero.
    return pthread_self() != 0 ? 0 : 1;
}"#
    };
    std::fs::write(&src_path, source).unwrap();

    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src_path.to_string_lossy().into_owned(),
        "-o".to_string(),
        out_path.to_string_lossy().into_owned(),
    ]);
    let code = pepper_driver::run(options).expect("compile + link");
    assert_eq!(code, 0);

    // The binary only runs (and exits 0) if the symbol resolved from the
    // library named by [Link].
    let status = Command::new(&out_path).status().expect("spawn linked binary");
    assert!(status.success(), "linked binary exited with {}", status);
}

/// Compile `source` to a native binary in a fresh temp dir named `name`, link
/// it, and return the path of the executable.
fn build_binary(name: &str, source: &str) -> Result<PathBuf, String> {
    let root = repo_root();
    std::env::set_current_dir(&root).unwrap();

    let dir = std::env::temp_dir().join(format!("pepper_link_{name}"));
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
    let code = pepper_driver::run(options)?;
    assert_eq!(code, 0);
    Ok(out_path)
}

#[test]
fn link_name_binds_extern_to_c_symbol() {
    // `pep_abs` exists in no library: the call only links if [LinkName]
    // made the object reference `llabs` (libc / the UCRT) instead. `llabs`
    // takes a 64-bit `long long` on every target, matching Pepper's `long`.
    let out_path = build_binary(
        "link_name_probe",
        r#"
[LinkName("llabs")] extern long pep_abs(long v);

main(): int {
    return pep_abs(-7) == 7 ? 0 : 1;
}"#,
    )
    .expect("compile + link");
    let status = Command::new(&out_path).status().expect("spawn linked binary");
    assert!(status.success(), "linked binary exited with {}", status);
}

#[test]
fn link_name_combines_with_target() {
    // Each platform binds the same Pepper name to its own symbol; the
    // dropped declaration's symbol must never reach the object. (`labs` is
    // 64-bit only on LP64 targets; Windows' `long` is 32-bit.)
    let out_path = build_binary(
        "link_name_target_probe",
        r#"
[Target(OS(Windows))] [LinkName("llabs")] extern long pep_abs(long v);
[Target(!OS(Windows))] [LinkName("labs")] extern long pep_abs(long v);

main(): int {
    return pep_abs(-9) == 9 ? 0 : 1;
}"#,
    )
    .expect("compile + link");
    let status = Command::new(&out_path).status().expect("spawn linked binary");
    assert!(status.success(), "linked binary exited with {}", status);
}

#[test]
fn link_name_requires_one_string() {
    for (name, attr) in [
        ("link_name_bare", "[LinkName]"),
        ("link_name_empty", "[LinkName(\"\")]"),
        ("link_name_two", "[LinkName(\"a\", \"b\")]"),
        ("link_name_twice", "[LinkName(\"labs\")] [LinkName(\"llabs\")]"),
    ] {
        let source = format!("{attr} extern long pep_abs(long v);\nmain(): int {{ return pep_abs(-1) as int - 1; }}");
        let err = build_binary(name, &source).expect_err(attr);
        assert!(err.contains("LinkName"), "{attr}: unexpected error: {err}");
    }
}

#[test]
fn failed_assert_message_survives_a_pipe() {
    // stdout is fully buffered when it is a pipe; panic() flushes it before
    // abort(), or the message (and anything printed before it) is lost.
    let out_path = build_binary(
        "panic_flush_probe",
        r#"
main(): int {
    print("before");
    assert(false, "the assert message");
    return 0;
}"#,
    )
    .expect("compile + link");
    let output = Command::new(&out_path).output().expect("spawn linked binary");
    assert!(!output.status.success(), "a failed assert must abort");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("before") && stdout.contains("the assert message"), "stdout: {stdout:?}");
}
