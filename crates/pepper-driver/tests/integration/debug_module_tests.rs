//! The `debug` module (#500): `capture()` resolves frames to functions and,
//! with `-g`, source lines; a panic prints a backtrace at `-O0`, none with
//! `-O`, and `PEPPER_BACKTRACE` overrides the build; `output`,
//! `is_debugger_attached` and `breakpoint` reach the platform.

use crate::support::{output_text, parallel_map, run_linked_with, stdout_of};

/// A method of a struct, called from a generic function, captures the
/// stack: each frame prints on its own line.
const CAPTURE: &str = "import debug;

struct Point {
    var x: int;
    construct(x: int) {
        this.x = x;
    }
    trace(): Array<debug.StackFrame> {
        return debug.capture().frames();
    }
}

helper<T>(value: T): Array<debug.StackFrame> {
    var p = Point(1);
    return p.trace();
}

main(): int {
    var frames = helper<int>(3);
    for (var frame in frames) {
        print($\"{frame.function}|{frame.file}|{frame.line}|{frame.column}\");
    }
    return 0;
}
";

#[test]
fn capture_names_functions_and_lines_with_debug_info() {
    let output = run_linked_with("debug_capture_lines", CAPTURE, &["-g"], |_| {});
    let text = stdout_of(&output);
    assert!(output.status.success(), "{}", output_text(&output));
    let frames: Vec<Vec<&str>> = text.lines().map(|l| l.split('|').collect()).collect();
    let names: Vec<&str> = frames.iter().map(|f| f[0]).collect();
    assert_eq!(names, ["Point.trace", "helper<int>", "main"], "{text}");
    for (frame, line) in frames.iter().zip(["9", "15", "19"]) {
        assert!(frame[1].ends_with("debug_capture_lines.pep"), "{text}");
        assert_eq!(frame[2], line, "{text}");
    }
    if !cfg!(windows) {
        // DbgHelp reports no columns.
        assert_eq!(frames[0][3], "16", "{text}");
    }
}

#[test]
fn capture_names_functions_without_debug_info() {
    let output = run_linked_with("debug_capture_names", CAPTURE, &[], |_| {});
    let text = stdout_of(&output);
    assert!(output.status.success(), "{}", output_text(&output));
    let names: Vec<&str> = text.lines().map(|l| l.split('|').next().unwrap()).collect();
    assert_eq!(names, ["Point.trace", "helper<int>", "main"], "{text}");
}

/// Each case: name, compiler arguments, `PEPPER_BACKTRACE`, and whether the
/// panic prints a backtrace.
const POLICY: &[(&str, &[&str], Option<&str>, bool)] = &[
    ("debug", &["-g"], None, true),
    ("optimized", &["-g", "-O"], None, false),
    ("optimized_on", &["-g", "-O"], Some("1"), true),
    ("debug_off", &["-g"], Some("0"), false),
];

const PANICS: &str = "inner(n: int): int {
    if (n > 2) {
        panic(\"boom\");
    }
    return n;
}

main(): int {
    return inner(5);
}
";

#[test]
fn a_panic_prints_a_backtrace_by_the_build_and_pepper_backtrace() {
    let results = parallel_map(POLICY, |&(name, args, setting, _)| {
        run_linked_with(&format!("debug_panic_{}", name), PANICS, args, |command| {
            command.env_remove("PEPPER_BACKTRACE");
            if let Some(setting) = setting {
                command.env("PEPPER_BACKTRACE", setting);
            }
        })
    });
    for (&(name, _, _, expected), output) in POLICY.iter().zip(results) {
        assert!(!output.status.success(), "{name}: expected a panic");
        let stderr = String::from_utf8_lossy(&output.stderr).replace('\r', "");
        assert!(stderr.contains(": panic: boom"), "{name}: {stderr}");
        assert_eq!(stderr.contains("backtrace:"), expected, "{name}: {stderr}");
        if expected && name == "debug" {
            // DbgHelp reports no columns, so on Windows the line ends there.
            let at = |function: &str, line: u32| {
                let position = format!("debug_panic_{name}.pep:{line}");
                stderr.lines().any(|l| {
                    l.contains(&format!(": {function} at "))
                        && (l.contains(&format!("{position}:")) || (cfg!(windows) && l.ends_with(&position)))
                })
            };
            assert!(at("inner", 3), "{stderr}");
            assert!(at("main", 9), "{stderr}");
            // The runtime's panic frames are left out.
            assert!(stderr.lines().find(|l| l.starts_with("  0: ")).is_some_and(|l| l.contains("inner")), "{stderr}");
        }
    }
}

#[test]
fn print_backtrace_writes_the_stack_to_standard_error() {
    let source = "import debug;

show() {
    debug.print_backtrace();
}

main(): int {
    show();
    return 0;
}
";
    let output = run_linked_with("debug_print_backtrace", source, &[], |_| {});
    assert!(output.status.success(), "{}", output_text(&output));
    let stderr = String::from_utf8_lossy(&output.stderr).replace('\r', "");
    let lines: Vec<&str> = stderr.lines().collect();
    assert_eq!(lines.first(), Some(&"backtrace:"), "{stderr}");
    assert!(lines.get(1).is_some_and(|l| l.trim_start().starts_with("0: show")), "{stderr}");
    assert!(lines.get(2).is_some_and(|l| l.trim_start().starts_with("1: main")), "{stderr}");
}

#[test]
fn output_and_the_debugger_without_one_attached() {
    let source = "import debug;

main(): int {
    debug.output(\"to the debugger\");
    print($\"attached: {debug.is_debugger_attached()}\");
    if (debug.is_debugger_attached()) {
        debug.breakpoint();
    }
    return 0;
}
";
    let output = run_linked_with("debug_output", source, &[], |_| {});
    assert!(output.status.success(), "{}", output_text(&output));
    assert_eq!(stdout_of(&output), "attached: false\n");
    let stderr = String::from_utf8_lossy(&output.stderr).replace('\r', "");
    // Windows sends it to OutputDebugStringW, not to a stream.
    assert_eq!(stderr.contains("to the debugger"), !cfg!(windows), "{stderr}");
}
