//! The `os` module (runtime/os/) in linked programs: environment variables,
//! the clocks and `Duration`, and what it reports about the machine and the
//! user. Every other platform's layer is type-checked through simulated
//! hosts.

use crate::support;
use crate::support::{jit_census, stdout_of};

/// Runs `test()` in `source` (which imports `os`) through the JIT and
/// returns its result, failing on a leak.
fn value(source: &str) -> i32 {
    let (result, leaked) = jit_census(source);
    assert_eq!(leaked, 0, "leaked allocations");
    result
}

const ENVIRONMENT_PROGRAM: &str = r#"
import os;

main(): int {
    var set = os.environment("OS_TEST_SET");
    print($"set=[{set.value_or("<none>")}]");
    print($"empty=[{os.environment("OS_TEST_EMPTY").value_or("<none>")}]");
    print($"missing={os.environment("OS_TEST_MISSING").is_none()}");
    print($"blank={os.environment("").is_none()}");
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
fn duration_arithmetic_comparison_and_text() {
    let source = r#"
import os;

test(): int {
    var a = os.Duration.from_seconds(2) + os.Duration.from_milliseconds(500);
    if (a.milliseconds() != 2500 || a.seconds() != 2 || a.microseconds() != 2500000) { return 1; }
    if (a.nanoseconds() != 2500000000) { return 2; }
    if (a != os.Duration.from_microseconds(2500000) || !(a == os.Duration.from_nanoseconds(2500000000))) { return 3; }
    if (!(os.Duration.from_seconds(1) < a) || !(a <= a) || !(a > os.Duration()) || !(a >= a)) { return 4; }
    var b = a - os.Duration.from_milliseconds(1500);
    if (b != os.Duration.from_seconds(1)) { return 5; }
    if (b * 3 != os.Duration.from_seconds(3) || b / 4 != os.Duration.from_milliseconds(250)) { return 6; }
    if (!os.Duration().is_zero() || b.is_zero()) { return 7; }
    if (a.seconds_fraction() != 2.5) { return 8; }
    if (a.to_string() != "2.5s" || os.Duration.from_milliseconds(15).to_string() != "15ms") { return 9; }
    if (os.Duration.from_nanoseconds(1250).to_string() != "1.25µs" || os.Duration.from_nanoseconds(40).to_string() != "40ns") { return 10; }
    if (os.Duration().to_string() != "0s" || $"{os.Duration.from_nanoseconds(1000000001)}" != "1.000000001s") { return 11; }
    return 0;
}
"#;
    assert_eq!(value(source), 0);
}

#[test]
fn instants_measure_forward() {
    let source = r#"
import os;

test(): int {
    var start = os.Instant.now();
    var later = os.Instant.now();
    var elapsed = later - start;
    os.Duration typed = elapsed;
    if (later < start || !(start <= later)) { return 1; }
    var moved = start + os.Duration.from_seconds(5);
    if (moved - start != os.Duration.from_seconds(5) || moved - os.Duration.from_seconds(5) != start) { return 2; }
    if (!(moved > later)) { return 3; }
    if (start.elapsed() < elapsed) { return 4; }
    return 0;
}
"#;
    assert_eq!(value(source), 0);
}

#[test]
fn system_time_counts_from_the_unix_epoch() {
    let source = r#"
import os;

test(): int {
    var now = os.SystemTime.now();
    # 2023-11-14 and 2200-01-01.
    if (now.unix_seconds() < 1700000000 || now.unix_seconds() > 7258118400) { return 1; }
    var epoch = os.SystemTime();
    if (epoch.unix_nanoseconds() != 0 || now.duration_since(epoch).is_none()) { return 2; }
    if (epoch.duration_since(now).is_some()) { return 3; }
    var before = os.SystemTime.from_unix_nanoseconds(-1);
    if (before.unix_seconds() != -1 || before.unix_milliseconds() != -1) { return 4; }
    var ten = os.SystemTime.from_unix_seconds(10);
    if (ten.duration_since(epoch).value() != os.Duration.from_seconds(10)) { return 5; }
    if (ten - os.Duration.from_seconds(10) != epoch || epoch + os.Duration.from_seconds(10) != ten) { return 6; }
    if (!(epoch < ten) || ten.unix_milliseconds() != 10000) { return 7; }
    if (ten.elapsed().is_none()) { return 8; }
    return 0;
}
"#;
    assert_eq!(value(source), 0);
}

#[test]
fn machine_and_user() {
    let source = r#"
import os;

test(): int {
    var name = os.system_name();
    if (name != "linux" && name != "macos" && name != "windows") { return 1; }
    if (os.architecture() != "x64" && os.architecture() != "aarch64") { return 2; }
    if (os.hostname().is_empty) { return 3; }
    if (os.logical_cpus() < 1 || os.physical_cpus() < 1 || os.physical_cpus() > os.logical_cpus()) { return 4; }
    if (os.total_memory() < 16777216) { return 5; }
    var page = os.page_size();
    if (page < 4096 || (page & (page - 1)) != 0) { return 6; }
    if (os.system_version().is_empty) { return 7; }
    if (os.user_name().is_none()) { return 8; }
    if (os.home_directory().is_none()) { return 9; }
    if (os.temp_directory().to_string() != io.Directory.temp().to_string()) { return 10; }
    return 0;
}
"#;
    assert_eq!(value(&format!("import io;\n{source}")), 0);
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

/// The platform layer of every other OS type-checks and generates valid IR.
#[test]
fn os_compiles_for_other_platforms() {
    let program = r#"
import os;

main(): int {
    var home = os.environment("HOME");
    var count = os.environment_variables().count;
    var start = os.Instant.now();
    var now = os.SystemTime.now();
    print($"{os.system_name()} {os.system_os().name()} {os.system_version()} {os.architecture()} {os.hostname()}");
    print($"{os.total_memory()} {os.page_size()} {os.user_name().value_or("")} {os.home_directory().is_some()}");
    print($"{home.is_some()} {count} {now.unix_seconds()} {start.elapsed()}");
    return 0;
}
"#;
    let failures: Vec<String> = support::parallel_map(&crate::io_tests::SIMULATED_HOSTS, |&(os, arch)| {
        crate::io_tests::with_codegen_as(os, arch, "os_platform", program, |generator, module| {
            generator.generate(module).map_err(|d| module.sources.render(&d))?;
            generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
            let expect = if os == "windows" { "QueryPerformanceCounter" } else { "clock_gettime" };
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
