//! `pepper` (`tools/pepper`, written in Pepper) runs `pep-<command>`. The
//! tests build it once into a directory beside a stand-in tool, `pep-echo`,
//! which prints its arguments and exits with a chosen status, plus a copy
//! named `pep-build`; another copy, `pep-elsewhere`, sits in a directory
//! that only the PATH names. `pep-ask` prints a line, then reads its
//! standard input to the end.

use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::OnceLock;
use std::sync::mpsc;
use std::time::Duration;

use crate::support;
use crate::support::{repo_root, stdout_of};

/// Prints its arguments joined by `|`, and exits with the number after an
/// argument `exit`, or 0.
const ECHO: &str = r#"
main(args: String[]): int {
    var shown = Array<String>();
    ulong index = 1;
    var code = 0;
    while (index < args.count) {
        shown.append(args[index]);
        if (args[index] == "exit" and index + 1 < args.count) {
            code = int.parse(args[index + 1]).value();
        }
        index += 1;
    }
    print("|".join(shown));
    return code;
}
"#;

/// Prints `ready`, then what it reads from standard input to the end.
const ASK: &str = r#"
import [File] from io;

main(): int {
    print("ready");
    var rest = File.stdin().read_string().value();
    print("got " + rest);
    return 0;
}
"#;

struct Layout {
    /// The directory holding `pepper`, `pep-echo` and `pep-build`.
    bin: PathBuf,
    /// The directory holding `pep-elsewhere`, reached through the PATH.
    elsewhere: PathBuf,
}

fn executable(dir: &Path, name: &str) -> PathBuf {
    dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() })
}

fn layout() -> &'static Layout {
    static LAYOUT: OnceLock<Layout> = OnceLock::new();
    LAYOUT.get_or_init(|| {
        let root = std::env::temp_dir().join(format!("pepper_entry_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let bin = root.join("bin");
        let elsewhere = root.join("elsewhere");
        std::fs::create_dir_all(&bin).unwrap();
        std::fs::create_dir_all(&elsewhere).unwrap();
        let entry = repo_root().join("tools").join("pepper").join("main.pep");
        support::build_executable(&entry, &[], &executable(&bin, "pepper"), &root.join("obj"));
        let echo_source = root.join("echo.pep");
        std::fs::write(&echo_source, ECHO).unwrap();
        let echo = executable(&bin, "pep-echo");
        support::build_executable(&echo_source, &[], &echo, &root.join("obj"));
        std::fs::copy(&echo, executable(&bin, "pep-build")).unwrap();
        std::fs::copy(&echo, executable(&elsewhere, "pep-elsewhere")).unwrap();
        let ask_source = root.join("ask.pep");
        std::fs::write(&ask_source, ASK).unwrap();
        support::build_executable(&ask_source, &[], &executable(&bin, "pep-ask"), &root.join("obj"));
        Layout { bin, elsewhere }
    })
}

/// Runs `pepper` with `args`, with only the `elsewhere` directory on the PATH.
fn pepper(args: &[&str]) -> Output {
    let layout = layout();
    Command::new(executable(&layout.bin, "pepper"))
        .args(args)
        .env("PATH", &layout.elsewhere)
        .output()
        .expect("run pepper")
}

fn stderr_of(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).replace('\r', "")
}

#[test]
fn pepper_runs_the_tool_next_to_it_with_the_remaining_arguments() {
    let output = pepper(&["echo", "a", "b c"]);
    assert_eq!(stdout_of(&output), "a|b c\n", "stderr: {}", stderr_of(&output));
    assert_eq!(output.status.code(), Some(0));
}

#[test]
fn pepper_streams_the_tool_s_output_and_input_while_it_runs() {
    // `pep-ask` prints a line and then waits for standard input, so the line
    // must reach this pipe before the tool exits: from `print` buffering it,
    // or `pepper` holding the tool's output, the read below never returns.
    let layout = layout();
    let mut child = Command::new(executable(&layout.bin, "pepper"))
        .arg("ask")
        .env("PATH", &layout.elsewhere)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("run pepper");
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let (sender, receiver) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        let mut first = String::new();
        stdout.read_line(&mut first).unwrap();
        sender.send(first).unwrap();
        let mut rest = String::new();
        std::io::Read::read_to_string(&mut stdout, &mut rest).unwrap();
        rest
    });
    let first = receiver.recv_timeout(Duration::from_secs(30));
    let mut stdin = child.stdin.take().unwrap();
    stdin.write_all(b"answer").unwrap();
    drop(stdin);
    let status = child.wait().unwrap();
    assert_eq!(first.map(|line| line.replace('\r', "")), Ok("ready\n".to_string()), "the first line arrived only at exit");
    assert_eq!(reader.join().unwrap().replace('\r', ""), "got answer\n");
    assert_eq!(status.code(), Some(0));
}

#[test]
fn pepper_exits_with_the_tool_s_exit_status() {
    let output = pepper(&["echo", "exit", "7"]);
    assert_eq!(output.status.code(), Some(7), "stderr: {}", stderr_of(&output));
}

#[test]
fn pepper_finds_a_tool_on_the_path() {
    let output = pepper(&["elsewhere", "x"]);
    assert_eq!(stdout_of(&output), "x\n", "stderr: {}", stderr_of(&output));
}

#[test]
fn pepper_suggests_the_closest_command_for_an_unknown_one() {
    let output = pepper(&["ecoh"]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stderr_of(&output),
        "pepper: error: 'ecoh' is not a pepper command; did you mean 'echo'?\n\n\
         Commands:\n  ask\n  build\n  echo\n  elsewhere\n"
    );
}

#[test]
fn pepper_rejects_a_command_that_names_a_path() {
    let output = pepper(&["../bin/pep-echo"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(stderr_of(&output).starts_with("pepper: error: '../bin/pep-echo' is not a pepper command\n"));
}

#[test]
fn pepper_help_lists_every_command_it_finds() {
    let output = pepper(&["help"]);
    assert_eq!(output.status.code(), Some(0));
    let text = stdout_of(&output);
    assert!(text.starts_with("usage: pepper <command> [arguments]\n"), "{}", text);
    assert!(text.ends_with("Commands:\n  ask\n  build\n  echo\n  elsewhere\n"), "{}", text);
}

#[test]
fn pepper_help_with_a_command_runs_its_help() {
    let output = pepper(&["help", "echo"]);
    assert_eq!(stdout_of(&output), "--help\n");
}

#[test]
fn pepper_with_a_source_file_runs_pep_build_and_warns() {
    let output = pepper(&["main.pep", "-o", "main"]);
    assert_eq!(stdout_of(&output), "main.pep|-o|main\n");
    assert_eq!(
        stderr_of(&output),
        "pepper: warning: 'pepper main.pep ...' is deprecated; use 'pepper build main.pep ...'\n"
    );
}

#[test]
fn pepper_version_is_the_workspace_version() {
    let output = pepper(&["--version"]);
    assert_eq!(stdout_of(&output), format!("pepper {}\n", env!("CARGO_PKG_VERSION")));
}

#[test]
fn pepper_without_arguments_prints_usage() {
    let output = pepper(&[]);
    assert_eq!(output.status.code(), Some(2));
    assert!(stderr_of(&output).starts_with("usage: pepper <command> [arguments]\n"));
}
