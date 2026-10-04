//! The `os` module (runtime/os/) in linked programs: environment variables
//! the parent sets, and the system and architecture compared with the host.
//! The clocks, `Duration`, and the machine and user are `[Test]` functions in
//! `runtime/os/test/os_test.pep`. `io_tests::runtime_compiles_on_other_platforms`
//! checks every other platform's layer.

use crate::support;
use crate::support::stdout_of;

const ENVIRONMENT_PROGRAM: &str = r#"
import os;

main(): int {
    var set = os.environment("OS_TEST_SET");
    print($"set=[{set.value_or("<none>")}]");
    print($"empty=[{os.environment("OS_TEST_EMPTY").value_or("<none>")}]");
    print($"missing={os.environment("OS_TEST_MISSING").is_empty()}");
    print($"blank={os.environment("").is_empty()}");
    var count = 0;
    for (var (name, value) in os.environment_variables()) {
        if (name == "OS_TEST_SET" || name == "OS_TEST_EMPTY" || name == "OS_TEST_EQUALS") {
            print($"listed {name}=[{value}]");
            count = count + 1;
        }
    }
    var variables = os.environment_variables();
    if (!variables.contains("OS_TEST_SET") || variables.get("OS_TEST_EQUALS") != "a=b=c") {
        return 100;
    }
    return count;
}
"#;

#[test]
fn environment_reads_set_empty_and_missing_variables() {
    let output = support::run_linked("os_environment", ENVIRONMENT_PROGRAM, |command| {
        command
            .env("OS_TEST_SET", "héllo wörld")
            .env("OS_TEST_EMPTY", "")
            .env("OS_TEST_EQUALS", "a=b=c")
            .env_remove("OS_TEST_MISSING");
    });
    let stdout = stdout_of(&output);
    assert!(stdout.contains("set=[héllo wörld]\n"), "{stdout}");
    assert!(stdout.contains("empty=[]\n"), "{stdout}");
    assert!(stdout.contains("missing=true\n"), "{stdout}");
    assert!(stdout.contains("blank=true\n"), "{stdout}");
    assert!(stdout.contains("listed OS_TEST_SET=[héllo wörld]\n"), "{stdout}");
    assert!(stdout.contains("listed OS_TEST_EMPTY=[]\n"), "{stdout}");
    assert!(stdout.contains("listed OS_TEST_EQUALS=[a=b=c]\n"), "{stdout}");
    assert_eq!(output.status.code(), Some(3), "{stdout}");
}

#[test]
fn system_name_and_architecture_match_the_host() {
    let source = "import os;\nmain(): int {\n    print(os.system_name());\n    print(os.system_os().name());\n    print(os.architecture());\n    return 0;\n}\n";
    let output = support::run_linked("os_machine", source, |_| {});
    let (expected_os, expected_case) = match std::env::consts::OS {
        "macos" => ("macos", "Mac"),
        "windows" => ("windows", "Windows"),
        _ => ("linux", "Linux"),
    };
    let expected_arch = if cfg!(target_arch = "aarch64") { "aarch64" } else { "x64" };
    assert_eq!(stdout_of(&output), format!("{expected_os}\n{expected_case}\n{expected_arch}\n"));
}

