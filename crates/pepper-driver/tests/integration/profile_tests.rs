//! pep-profile (`tools/pep-profile`, written in Pepper): reading each
//! recording format it supports into folded stacks with readable names,
//! and drawing them with the built-in renderer. The recordings here are
//! written by hand, so the tests need no profiler; one test profiles a real
//! program when samply or a working perf is installed.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use crate::support;

fn pep_profile() -> &'static Path {
    support::pepper_tool("pep-profile")
}

/// A fresh scratch directory for one test.
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_profile_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn run(arguments: &[&str]) -> Output {
    Command::new(pep_profile()).args(arguments).output().expect("run pep-profile")
}

/// The folded stacks pep-profile reads from `recording`, with no
/// symbolizer, so names come from the recording alone.
fn folded(dir: &Path, recording: &str, contents: &str) -> String {
    let input = dir.join(recording);
    std::fs::write(&input, contents).unwrap();
    let folded = dir.join("stacks.folded");
    let svg = dir.join("graph.svg");
    let output = run(&[
        "--input",
        input.to_str().unwrap(),
        "--symbolizer",
        "none",
        "--folded",
        folded.to_str().unwrap(),
        "-o",
        svg.to_str().unwrap(),
    ]);
    assert!(output.status.success(), "pep-profile failed:\n{}", String::from_utf8_lossy(&output.stderr));
    std::fs::read_to_string(folded).unwrap()
}

#[test]
fn pep_profile_version_is_the_workspace_version() {
    let output = run(&["--version"]);
    assert_eq!(support::stdout_of(&output), format!("pep-profile {}\n", env!("CARGO_PKG_VERSION")));
}

#[test]
fn folded_stacks_draw_as_a_flame_graph() {
    let dir = scratch("draw");
    let input = dir.join("in.folded");
    std::fs::write(&input, "main;work;Box<int>.get 3\nmain;work 1\nmain;other 4\n").unwrap();
    let svg = dir.join("out.svg");
    let output = run(&["-i", input.to_str().unwrap(), "-o", svg.to_str().unwrap(), "--title", "A & B"]);
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    assert!(String::from_utf8_lossy(&output.stderr).contains("(8 samples)"));
    let svg = std::fs::read_to_string(svg).unwrap();
    assert!(svg.starts_with("<?xml"), "{svg}");
    assert!(svg.contains(">A &amp; B</text>"), "the title, escaped");
    assert!(svg.contains("<title>all (8 samples, 100.00%)</title>"), "{svg}");
    assert!(svg.contains("<title>main (8 samples, 100.00%)</title>"), "{svg}");
    assert!(svg.contains("<title>work (4 samples, 50.00%)</title>"), "{svg}");
    assert!(svg.contains("<title>Box&lt;int&gt;.get (3 samples, 37.50%)</title>"), "{svg}");
    assert!(svg.contains("<title>other (4 samples, 50.00%)</title>"), "{svg}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn perf_script_frames_are_demangled_and_folded() {
    let dir = scratch("perf");
    // `perf script -F ip,sym,symoff,dso`: the innermost frame first; the
    // program is not on this machine, so the symbols name the frames.
    let script = "\
\t    5598c6d7a1af _PArray_3cint_3e.count+0x3f (/missing/program)
\t    5598c6d7a59c _Pwork_40main+0x1fc (/missing/program)
\t    5598c6d7a59c main+0x10 (/missing/program)
\t    7f9ac822a28b __libc_start_main@@GLIBC_2.34+0x8b (/usr/lib/libc.so.6)

\t    5598c6d7a361 _P____closure__3_40geo_2fshapes.____call+0x11 (/missing/program)
\t    5598c6d7a59c main+0x10 (/missing/program)
\t    7f9ac822a28b __libc_start_main@@GLIBC_2.34+0x8b (/usr/lib/libc.so.6)

\t    5598c6d7a59c _Pwork_40main+0x1fc (/missing/program)
\t    5598c6d7a59c main+0x10 (/missing/program)
\t    7f9ac822a28b __libc_start_main@@GLIBC_2.34+0x8b (/usr/lib/libc.so.6)

\t    ffffffff8123 [unknown] ([unknown])
\t    5598c6d7a59c _Parea_40geo_2fshapes_242+0x4 (/missing/program)
";
    assert_eq!(
        folded(&dir, "perf.txt", script),
        "\
__libc_start_main;main;closure #3 in geo/shapes 1
__libc_start_main;main;work 1
__libc_start_main;main;work;Array<int>.count 1
area;[unknown] 1
"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn samply_profiles_name_frames_from_their_symbol_file() {
    let dir = scratch("samply");
    // Two samples of one thread: stacks 2 (main > work > get) and 1
    // (main > work); frame 2's address no symbol covers, so it keeps the
    // profile's own name for it.
    let profile = r#"{
  "libs": [{"name": "program", "path": "/missing/program", "debugName": "program"}],
  "threads": [{
    "stringArray": ["0x1000", "0x2010", "0x9999"],
    "samples": {"length": 3, "stack": [2, 1, 2], "weight": null},
    "stackTable": {"length": 3, "prefix": [null, 0, 1], "frame": [0, 1, 2]},
    "frameTable": {"length": 3, "address": [4096, 8208, 39321], "func": [0, 1, 2]},
    "funcTable": {"length": 3, "name": [0, 1, 2], "resource": [0, 0, 0]},
    "resourceTable": {"length": 1, "lib": [0]}
  }]
}"#;
    let symbols = r#"{
  "string_table": ["main", "Pwork_40main", "work"],
  "data": [{"debug_name": "program", "symbol_table": [
    {"rva": 4000, "size": 200, "symbol": 0},
    {"rva": 8200, "size": 50, "symbol": 1, "frames": [{"function": 2}]}
  ]}]
}"#;
    std::fs::write(dir.join("profile.syms.json"), symbols).unwrap();
    assert_eq!(folded(&dir, "profile.json", profile), "main;work 1\nmain;work;[program] 2\n");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn sample_reports_fold_their_call_trees() {
    let dir = scratch("sample");
    let report = "\
Analysis of sampling program (pid 4242) every 1 millisecond
Process:         program [4242]

Call graph:
    10 Thread_1   DispatchQueue_1: com.apple.main-thread  (serial)
      10 start  (in dyld) + 1942  [0x18bd8b154]
        10 main  (in program) + 120  [0x100003f2f]  main.pep:26
          6 _Pwork_40main  (in program) + 40  [0x100003e00]  main.pep:17
          + 4 _PArray_3cint_3e.count  (in program) + 8  [0x100003d00]  array.pep:9
          3 _pep_malloc  (in program) + 12  [0x100003c00]

Total number in stack (recursive counted multiple times):
";
    assert_eq!(
        folded(&dir, "sample.txt", report),
        "\
start;main 1
start;main;_pep_malloc 3
start;main;work 2
start;main;work;Array<int>.count 4
"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn an_unreadable_recording_is_an_error() {
    let dir = scratch("bad");
    let input = dir.join("notes.txt");
    std::fs::write(&input, "just some words\n").unwrap();
    let output = run(&["-i", input.to_str().unwrap(), "-o", dir.join("x.svg").to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("is not a recording pep-profile can read"));
    let output = run(&[]);
    assert_eq!(output.status.code(), Some(2), "nothing to profile is a usage error");
    let _ = std::fs::remove_dir_all(&dir);
}

/// A profiler that can record this machine: samply, or a perf that runs
/// (in a container, perf events are often not allowed).
fn working_profiler() -> Option<&'static str> {
    let works = |program: &str, arguments: &[&str]| {
        Command::new(program).args(arguments).output().is_ok_and(|o| o.status.success())
    };
    if works("samply", &["--version"]) {
        return Some("samply");
    }
    if cfg!(target_os = "linux") && works("perf", &["record", "-o", "/dev/null", "--", "true"]) {
        return Some("perf");
    }
    None
}

#[test]
fn a_program_profiles_end_to_end_when_a_profiler_is_installed() {
    let Some(profiler) = working_profiler() else {
        eprintln!("skipped: no samply, and no perf that can record here");
        return;
    };
    let dir = scratch("live");
    let source = dir.join("spin.pep");
    std::fs::write(
        &source,
        "spin(n: long): long {\n    long total = 0;\n    for (var i in 0..n) {\n        total += i % 7;\n    }\n    return total;\n}\n\n\
main(): int {\n    print(to_string(spin(200000000)));\n    return 0;\n}\n",
    )
    .unwrap();
    // Built as pep-profile builds a `.pep` file.
    let program = dir.join(if cfg!(windows) { "spin.exe" } else { "spin" });
    std::env::set_current_dir(support::repo_root()).unwrap();
    let build = dir.join("build");
    let argv = ["pep-build", source.to_str().unwrap(), "-O2", "-g", "--frame-pointers", "-o", program.to_str().unwrap(), "--build", build.to_str().unwrap()];
    use clap::Parser;
    assert_eq!(pepper_driver::run(pepper_driver::Options::parse_from(argv)).expect("compile"), 0);
    let folded = dir.join("spin.folded");
    let output = Command::new(pep_profile())
        .args(["--profiler", profiler, "--folded", folded.to_str().unwrap(), "-o", dir.join("spin.svg").to_str().unwrap()])
        .arg(&program)
        .output()
        .expect("run pep-profile");
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() && stderr.contains("did not record a profile") {
        eprintln!("skipped: {profiler} cannot record here:\n{stderr}");
        return;
    }
    assert!(output.status.success(), "{stderr}");
    let stacks = std::fs::read_to_string(&folded).unwrap();
    // `spin` is inlined into `main`; the debug info, when a symbolizer
    // reads it, names it as well.
    assert!(stacks.lines().any(|line| line.contains("main")), "no stack through 'main' in:\n{stacks}");
    let _ = std::fs::remove_dir_all(&dir);
}
