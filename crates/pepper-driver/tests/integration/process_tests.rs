//! `arguments()` and `exit(code)` (runtime/process.pep) in linked programs.

use clap::Parser;
use std::process::{Command, Output};

/// Compile and link `source` to an executable, then run it with `arguments`.
fn run_with(name: &str, source: &str, arguments: &[&str]) -> Output {
    let dir = std::env::temp_dir().join(format!("pepper_process_{name}_{}", std::process::id()));
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
    let output = Command::new(&out_path).args(arguments).output().expect("spawn linked binary");
    let _ = std::fs::remove_dir_all(&dir);
    output
}

fn stdout_of(output: &Output) -> String {
    // Windows' C runtime writes text-mode stdout with CRLF line endings.
    String::from_utf8_lossy(&output.stdout).replace("\r\n", "\n")
}

#[test]
fn arguments_follow_the_program_name() {
    let output = run_with(
        "arguments",
        "main(): int {\n    var parts = arguments();\n    var index = 1;\n    while (index < parts.count()) {\n        print(\"[\" + parts[index] + \"]\");\n        index = index + 1;\n    }\n    return parts.count() as int;\n}\n",
        &["one", "two words", "", "three"],
    );
    assert_eq!(stdout_of(&output), "[one]\n[two words]\n[]\n[three]\n");
    assert_eq!(output.status.code(), Some(5));
}

#[test]
fn argument_zero_names_the_program() {
    let output = run_with(
        "program_name",
        "main(): int {\n    return arguments()[0].contains(\"program_name\") ? 0 : 1;\n}\n",
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
}

#[test]
fn exit_ends_with_the_code_and_keeps_printed_output() {
    // stdout is a pipe here, so it is fully buffered: exit must flush it.
    let output = run_with(
        "exit_code",
        "stop() {\n    print(\"before\");\n    exit(7);\n}\nmain(): int {\n    stop();\n    print(\"after\");\n    return 0;\n}\n",
        &[],
    );
    assert_eq!(stdout_of(&output), "before\n");
    assert_eq!(output.status.code(), Some(7));
}
