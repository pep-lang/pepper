//! The `process` module (runtime/process/) in linked programs: the running
//! process's arguments and exit, and child processes. The deprecated prelude
//! `arguments()` and `exit()` (runtime/process.pep) still work.

use crate::support;
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
    let output = support::run_program(Command::new(&out_path).args(arguments), source).expect("spawn linked binary");
    let _ = std::fs::remove_dir_all(&dir);
    output
}

fn stdout_of(output: &Output) -> String {
    // Windows' C runtime writes text-mode stdout with CRLF line endings (and
    // a child's CRLF printed again by its parent gains another CR).
    String::from_utf8_lossy(&output.stdout).replace('\r', "")
}

#[test]
fn arguments_follow_the_program_name() {
    let output = run_with(
        "arguments",
        "import process;\nmain(): int {\n    var parts = process.arguments();\n    var index = 1;\n    while (index < parts.count()) {\n        print(\"[\" + parts[index] + \"]\");\n        index = index + 1;\n    }\n    return parts.count() as int;\n}\n",
        &["one", "two words", "", "three"],
    );
    assert_eq!(stdout_of(&output), "[one]\n[two words]\n[]\n[three]\n");
    assert_eq!(output.status.code(), Some(5));
}

#[test]
fn argument_zero_names_the_program() {
    let output = run_with(
        "program_name",
        "import process;\nmain(): int {\n    return process.arguments()[0].contains(\"program_name\") ? 0 : 1;\n}\n",
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
}

#[test]
fn exit_ends_with_the_code_and_keeps_printed_output() {
    // stdout is a pipe here, so it is fully buffered: exit must flush it.
    let output = run_with(
        "exit_code",
        "import process;\nstop() {\n    print(\"before\");\n    process.exit(7);\n}\nmain(): int {\n    stop();\n    print(\"after\");\n    return 0;\n}\n",
        &[],
    );
    assert_eq!(stdout_of(&output), "before\n");
    assert_eq!(output.status.code(), Some(7));
}

#[test]
fn main_receives_the_arguments_when_it_declares_them() {
    let output = run_with(
        "main_args",
        "main(args: String[]): int {\n    var index = 1;\n    while (index < args.count()) {\n        print(\"[\" + args[index] + \"]\");\n        index = index + 1;\n    }\n    return args[0].contains(\"main_args\") ? args.count() as int : 100;\n}\n",
        &["one", "two words", ""],
    );
    assert_eq!(stdout_of(&output), "[one]\n[two words]\n[]\n");
    assert_eq!(output.status.code(), Some(4));
}

#[test]
fn main_with_arguments_falls_off_its_end_with_zero() {
    let output = run_with(
        "main_args_implicit",
        "main(args: String[]) {\n    if (args.count() > 1) {\n        return 3;\n    }\n}\n",
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
}

#[test]
fn a_void_main_with_arguments_exits_zero() {
    let output = run_with(
        "main_args_void",
        "main(args: String[]): void {\n    print($\"{args.count()}\");\n}\n",
        &["x"],
    );
    assert_eq!(stdout_of(&output), "2\n");
    assert_eq!(output.status.code(), Some(0));
}

#[test]
fn main_arguments_ignore_a_program_function_named_arguments() {
    let output = run_with(
        "main_args_shadow",
        "arguments(): int {\n    return 9;\n}\nmain(args: String[]): int {\n    return (args.count() as int) * 10 + arguments();\n}\n",
        &["a", "b"],
    );
    assert_eq!(output.status.code(), Some(39));
}

#[test]
fn the_deprecated_prelude_functions_still_work() {
    let output = run_with(
        "deprecated_prelude",
        "main(): int {\n    if (arguments().count() == 2) {\n        exit(4);\n    }\n    return 0;\n}\n",
        &["x"],
    );
    assert_eq!(output.status.code(), Some(4));
}

/// Starts copies of itself as children (its first argument says what the
/// child does), so it needs no other program on any platform.
const COMMAND_PROGRAM: &str = r#"import async;
import io;
import process;

extern char* getenv(char* name);

# The child side: what the parent asked for in `args[1]`.
child(args: String[]): int {
    var mode = args[1];
    if (mode == "arguments") {
        var index = 2;
        while (index < args.count()) {
            print("[" + args[index] + "]");
            index = index + 1;
        }
        return 0;
    }
    if (mode == "streams") {
        io.File.stdout().write_all("out");
        io.File.stderr().write_all("err");
        return 3;
    }
    if (mode == "environment") {
        var name = "PROCESS_TEST_VALUE";
        var value = getenv(name.c_str());
        print(value == __null ? "<unset>" : String(value));
        var home = "PROCESS_TEST_KEEP";
        print(getenv(home.c_str()) == __null ? "<unset>" : "kept");
        return 0;
    }
    if (mode == "upper") {
        var text = io.File.stdin().read_string().value();
        io.File.stdout().write_all(text.upper());
        return 0;
    }
    if (mode == "directory") {
        print(process.working_directory().value().file_name().value());
        return 0;
    }
    if (mode == "sleep") {
        async.Thread.sleep(30000);
        return 0;
    }
    if (mode == "big") {
        # More than a pipe holds, on both streams.
        var line = "0123456789012345678901234567890123456789012345678901234567890123\n";
        var index = 0;
        while (index < 4096) {
            io.File.stdout().write_all(line);
            io.File.stderr().write_all(line);
            index = index + 1;
        }
        return 0;
    }
    return 100;
}

main(args: String[]): int {
    if (args.count() > 1) {
        return child(args);
    }
    var self = process.executable_path().value().to_string();
    print(process.executable_path().value().file_name().value().contains("process_command") ? "path ok" : "path wrong");

    var arguments = process.Command(self).arguments(["arguments", "two words", "", "quote\"d", "back\\slash\\", "tab\there"]).run().value();
    print(arguments.stdout);

    var streams = process.Command(self).argument("streams").run().value();
    print($"{streams.stdout}|{streams.stderr}|{streams.status.code().value()}|{streams.status.success()}");

    var environment = process.Command(self).argument("environment").environment("PROCESS_TEST_VALUE", "set").environment("PROCESS_TEST_KEEP", "1").remove_environment("PROCESS_TEST_KEEP").run().value();
    print(environment.stdout);

    var upper = process.Command(self).argument("upper").stdin(process.Stream.Pipe).stdout(process.Stream.Pipe).spawn().value();
    upper.stdin().write_all("pear and apple");
    upper.stdin().close();
    print(upper.stdout().read_string().value());
    print($"{upper.wait().value().success()}");

    var directory = io.Directory.temp().join("process_command_directory");
    io.Directory.create_all(directory);
    var moved = process.Command(self).argument("directory").working_directory(directory).run().value();
    print(moved.stdout);

    var sleeper = process.Command(self).argument("sleep").spawn().value();
    print($"{sleeper.try_wait().value().is_none()}");
    sleeper.kill();
    var killed = sleeper.wait().value();
    print($"killed {killed.success()}");

    var missing = process.Command("no-such-program-for-pepper").run();
    print($"missing {missing.is_err() && missing.error().is_not_found()}");

    var silent = process.Command(self).argument("streams").stdout(process.Stream.Null).stderr(process.Stream.Null).run().value();
    print($"null {silent.stdout.size()} {silent.stderr.size()}");

    async.run(() => {
        var tasks = Array<async.Task<int>>();
        var index = 0;
        while (index < 3) {
            tasks.append(async.spawn<int>(() => {
                var me = process.executable_path().value().to_string();
                var big = process.Command(me).argument("big").run().value();
                return (big.stdout.size() + big.stderr.size()) as int;
            }));
            index = index + 1;
        }
        for (var task in tasks) {
            print($"task {task.join().value()}");
        }
    });
    return 0;
}
"#;

#[test]
fn command_starts_children_and_collects_their_output() {
    let output = run_with("process_command", COMMAND_PROGRAM, &[]);
    assert_eq!(
        stdout_of(&output),
        "path ok\n\
         [two words]\n[]\n[quote\"d]\n[back\\slash\\]\n[tab\there]\n\n\
         out|err|3|false\n\
         set\n<unset>\n\n\
         PEAR AND APPLE\n\
         true\n\
         process_command_directory\n\n\
         true\n\
         killed false\n\
         missing true\n\
         null 0 0\n\
         task 532480\ntask 532480\ntask 532480\n",
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(output.status.code(), Some(0));
}

/// The platform layer of every other OS type-checks and generates valid IR.
#[test]
fn process_compiles_for_other_platforms() {
    let failures: Vec<String> = support::parallel_map(&crate::io_tests::SIMULATED_HOSTS, |&(os, arch)| {
        crate::io_tests::with_codegen_as(os, arch, "process_platform", COMMAND_PROGRAM, |generator, module| {
            generator.generate(module).map_err(|d| module.sources.render(&d))?;
            generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
            let expect = if os == "windows" { "CreateProcessW" } else { "posix_spawnp" };
            if !generator.module.to_string().contains(expect) {
                return Err(format!("IR does not reference {expect}"));
            }
            Ok(())
        })
        .err()
        .map(|e| format!("{os}/{arch}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
