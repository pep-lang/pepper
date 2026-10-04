//! The `io` runtime module (`runtime/io/`). Its behavior is tested in
//! Pepper by `pep-test`, in `runtime/io/test/`; this file keeps what checks
//! the compiler: `io` is a module rather than part of the prelude, the
//! order of `print` and `File.stdout()` output in a whole program, and the
//! platform layers. `other_platforms_compile` pushes the io test files with
//! `[Target]` blocks through the platform filter, sema and LLVM codegen
//! with the host simulated as every other platform, so each platform's
//! code type-checks and produces valid IR wherever the tests run; and
//! `path_functions_on_every_platform` runs the (pure) path tests by JIT
//! under each simulated platform's path rules.
//!
//! `build` and `assert_runs` compile, link and run a program on the host
//! for the other runtime modules' tests.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::PathBuf;
use std::process::Command;

use crate::support;
use crate::support::repo_root;

pub(crate) fn source_dir(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("pepper_io_{}_{}", name, std::process::id()))
}

/// Write `source` as `main.pep` in a fresh directory for `name`; return its
/// path and the directory.
fn write_source(name: &str, source: &str) -> (PathBuf, PathBuf) {
    let dir = source_dir(name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let src = dir.join("main.pep");
    std::fs::write(&src, source).unwrap();
    (src, dir)
}

/// Compile + link `source` into a native binary; return its path.
pub(crate) fn build(name: &str, source: &str) -> Result<PathBuf, String> {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let (src, dir) = write_source(name, source);
    let out = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src.to_string_lossy().into_owned(),
        "-o".to_string(),
        out.to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
    ]);
    let code = pepper_driver::run(options)?;
    assert_eq!(code, 0);
    Ok(out)
}

/// Build and run `source`; panic with its output unless it exits 0, and
/// return its stdout.
pub(crate) fn assert_runs(name: &str, source: &str) -> String {
    assert_runs_each(name, source, &[&[]]).pop().unwrap()
}

/// [`assert_runs`], but the program, built once, runs once per set of extra
/// environment variables in `runs`; returns each run's stdout. For settings
/// the runtime reads when it starts (`PEP_CHECK_SYNC`, `PEPPER_IO_BACKEND`).
pub(crate) fn assert_runs_each(name: &str, source: &str, runs: &[&[(&str, &str)]]) -> Vec<String> {
    let exe = build(name, source).unwrap_or_else(|e| panic!("{name}: compile failed: {e}"));
    let outputs = runs
        .iter()
        .map(|env| {
            let output = support::run_program(Command::new(&exe).envs(env.iter().copied()), source).expect("spawn");
            let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
            let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
            let code = output.status.code().unwrap_or(-1);
            // A failed assert prints its message (the second argument of the
            // assert) as the last line of stdout, then aborts.
            let failed = stdout.lines().last().unwrap_or("");
            assert_eq!(
                code, 0,
                "{name} {env:?} exited with {code}; failed assert: {failed:?}\nstdout:\n{stdout}\nstderr:\n{stderr}"
            );
            stdout
        })
        .collect();
    // Keep a failing program's directory for inspection; drop a passing one.
    let _ = std::fs::remove_dir_all(source_dir(name));
    outputs
}

const IMPORT_NAMES_PROGRAM: &str =
    "import [Path as P] from io;\nmain(): int { return P(\"ab\").to_string().size as int - 2; }";

const PRINT_ORDER_PROGRAM: &str = r##"
import io;

main(): int {
    print("one");
    assert(io.File.stdout().write_all("two\n").is_ok(), "write two");
    print("three");
    assert(io.File.stdout().write_all("four\n").is_ok(), "write four");
    print("five");
    return 0;
}
"##;

/// `print` buffers in C stdio and `File.stdout()` writes the descriptor
/// directly; with stdout a pipe, the File write flushes `print`'s buffer
/// first so the lines come out in program order.
#[test]
fn print_and_stdout_keep_order() {
    let out = assert_runs("print_order", PRINT_ORDER_PROGRAM);
    // On Windows, C stdio writes `print`'s newline as "\r\n".
    assert_eq!(out.replace("\r\n", "\n"), "one\ntwo\nthree\nfour\nfive\n");
}

#[test]
fn io_is_a_module_not_prelude() {
    std::env::set_current_dir(repo_root()).unwrap();
    // Without an import, io is not loaded at all: Path is unknown.
    // Sema leaves an unknown type to codegen, so this has to build.
    let err = build("no_import", "main(): int { var p = Path(\"a\"); return p.to_string().size as int; }")
        .expect_err("Path visible without importing io");
    assert!(err.contains("Path"), "unexpected error: {err}");
    let _ = std::fs::remove_dir_all(source_dir("no_import"));
    // `import io` finds runtime/io through the runtime search path, and
    // `import [..] from io` binds names unqualified. Linked programs
    // throughout this file run what it binds.
    support::sema(IMPORT_NAMES_PROGRAM).expect("import [Path as P] from io");
    // The platform layer and helpers are not part of the module's API.
    let err = pepper_driver::compiler::check_with_runtime(
        "private.pep",
        "import io;\nmain(): int { var t = io._io_sys_temp_dir(); return 0; }",
    )
    .expect_err("io exports its platform layer");
    assert!(err.contains("_io_sys_temp_dir"), "unexpected error: {err}");
    // The discovered prelude is the top-level runtime/*.pep only.
    let (sources, _, _) = pepper_driver::runtime::discover();
    assert!(!sources.is_empty());
    assert!(sources.iter().all(|p| p.parent().unwrap().file_name().unwrap() == "runtime"), "{sources:?}");
    assert!(repo_root().join("runtime/io/module.pep").is_file());
}

/// The text of the runtime file `path` (relative to the repository root).
fn runtime_file(path: &str) -> String {
    let file = repo_root().join(path);
    std::fs::read_to_string(&file).unwrap_or_else(|e| panic!("read {}: {e}", file.display()))
}

/// The io test files with `[Target]` blocks of their own, which only a
/// compile for each OS checks; `runtime_compiles_on_other_platforms`
/// covers the runtime's own platform layer.
fn target_programs() -> Vec<(&'static str, String)> {
    vec![
        ("path", runtime_file("runtime/io/test/path_test.pep")),
        ("file_system", runtime_file("runtime/io/test/file_system_test.pep")),
    ]
}

/// `source`, a file of `[Test]` functions, with a `main` that calls each
/// in turn, for a build with the build option `TEST` but not `--test`
/// (whose `main` takes the program's arguments, which a JIT call cannot
/// give it).
fn with_test_calls(source: &str) -> String {
    let mut calls = String::new();
    let mut lines = source.lines();
    while let Some(line) = lines.next() {
        if line.trim() == "[Test]" {
            let declaration = lines.find(|l| !l.trim_start().starts_with('[')).expect("a declaration after [Test]");
            let name = declaration.split('(').next().unwrap().trim();
            calls.push_str(&format!("    {name}();\n"));
        }
    }
    format!("{source}\nmain(): int {{\n{calls}    return 0;\n}}\n")
}

pub(crate) const SIMULATED_HOSTS: [(&str, &str); 6] = [
    ("windows", "x86_64"),
    ("windows", "aarch64"),
    ("macos", "x86_64"),
    ("macos", "aarch64"),
    ("linux", "x86_64"),
    ("linux", "aarch64"),
];

/// Pairs each program with every simulated OS, on one architecture per
/// program, alternating from one program to the next. The architecture
/// changes only the runtime's non-generic fiber switch and calling
/// convention, which every program compiles, so building each program for
/// both architectures of an OS checks nothing the alternation does not;
/// what a program adds (its own `[Target]` blocks, its generic
/// instantiations) depends on the OS. Halves the simulated compiles.
fn simulated_cases<P: Clone>(programs: impl IntoIterator<Item = P>) -> Vec<((&'static str, &'static str), P)> {
    programs
        .into_iter()
        .enumerate()
        .flat_map(|(index, program)| {
            SIMULATED_HOSTS
                .iter()
                .enumerate()
                .filter(move |(host, _)| host % 2 == index % 2)
                .map(move |(_, &host)| (host, program.clone()))
        })
        .collect()
}

/// Compile `source` with the host simulated as `os`/`arch` — the same
/// platform filter, sema and LLVM codegen that host runs, with the extra
/// command-line `options` (`--test` for a file of tests) — and hand the
/// generated module to `then`. The result can be neither linked nor run as
/// a native program here.
pub(crate) fn with_codegen_as<R>(
    os: &str,
    arch: &str,
    name: &str,
    source: &str,
    options: &[&str],
    then: impl FnOnce(&mut CodeGenerator, &mut pepper_sema::Module) -> Result<R, String>,
) -> Result<R, String> {
    std::env::set_current_dir(repo_root()).unwrap();
    let (src, dir) = write_source(&format!("{name}_{os}_{arch}"), source);
    let result = pepper_sema::with_simulated_host(os, arch, || {
        let mut arguments = vec!["pepper".to_string(), src.to_string_lossy().into_owned()];
        arguments.extend(options.iter().map(|option| option.to_string()));
        let options = pepper_driver::Options::parse_from(arguments);
        let mut module = pepper_driver::compiler::compile(&options, "main")?;
        let ctx = inkwell::context::Context::create();
        let mut generator = CodeGenerator::new(&ctx, "main");
        then(&mut generator, &mut module)
    });
    let _ = std::fs::remove_dir_all(dir);
    result
}

/// The platform layer for `os`/`arch` must type-check and produce a valid
/// module that references that platform's C functions.
fn codegen_as(os: &str, arch: &str, name: &str, source: &str) -> Result<(), String> {
    with_codegen_as(os, arch, name, source, &["--test"], |generator, module| {
        generator.generate(module).map_err(|d| module.sources.render(&d))?;
        generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
        let ir = generator.module.to_string();
        // Spot-check that the simulated platform's layer is the one that
        // survived.
        let expect = match os {
            "windows" => "CreateFileW",
            "macos" if arch == "x86_64" => "stat$INODE64",
            "macos" => "@lstat(",
            _ => "@statx(",
        };
        if !ir.contains(expect) {
            return Err(format!("IR does not reference {expect}"));
        }
        Ok(())
    })
}

#[test]
fn other_platforms_compile() {
    let cases = simulated_cases(target_programs());
    let failures: Vec<String> = support::parallel_map(&cases, |((os, arch), (name, source))| {
        codegen_as(os, arch, name, source).err().map(|e| format!("{os}/{arch} {name}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// Every platform layer of the runtime type-checks and generates valid IR
/// on every simulated host. Codegen emits every non-generic function of
/// each module a program loads, and the platform code is non-generic, so
/// one program that loads async, io, os, process, tls and http (the http
/// tests, built with `--test`) reaches all of it: the fiber switch, the
/// I/O driver and its doorbell, threads, locks, files, sockets, clocks and
/// processes.
#[test]
fn runtime_compiles_on_other_platforms() {
    let http_tests = runtime_file("runtime/http/test/http_test.pep");
    let source = format!("import os;\nimport process;\nimport time;\n{http_tests}");
    let failures: Vec<String> = support::parallel_map(&SIMULATED_HOSTS, |&(os, arch)| {
        with_codegen_as(os, arch, "runtime_platform", &source, &["--test"], |generator, module| {
            generator.generate(module).map_err(|d| module.sources.render(&d))?;
            generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
            let ir = generator.module.to_string();
            let mut expected = vec![match (os, arch) {
                ("windows", _) => "@SwitchToFiber(",
                (_, "aarch64") => "stp x19, x20",
                _ => "pushq %rbp",
            }];
            expected.extend(match os {
                "windows" => [
                    "@NtDeviceIoControlFile(",
                    "@PostQueuedCompletionStatus(",
                    "@FlsAlloc(",
                    "@WaitOnAddress(",
                    "@WakeByAddressSingle(",
                    "CreateFileW",
                    "@WSASocketW(",
                    "QueryPerformanceCounter",
                    "CreateProcessW",
                    "@ucal_open(",
                ],
                "macos" => [
                    "@kevent(",
                    "@pthread_key_create(",
                    "@__ulock_wait(",
                    "@__ulock_wake(",
                    if arch == "x86_64" { "stat$INODE64" } else { "@lstat(" },
                    "@fcntl(",
                    "@socket(",
                    "clock_gettime",
                    "posix_spawnp",
                    "@localtime_r(",
                ],
                _ => [
                    "@epoll_wait(",
                    "@eventfd(",
                    "@pthread_key_create(",
                    "@syscall(",
                    "@__errno_location(",
                    "@statx(",
                    "@accept4(",
                    "clock_gettime",
                    "posix_spawnp",
                    "@localtime_r(",
                ],
            });
            let missing: Vec<&str> = expected.into_iter().filter(|e| !ir.contains(e)).collect();
            if missing.is_empty() { Ok(()) } else { Err(format!("IR does not reference {}", missing.join(", "))) }
        })
        .err()
        .map(|e| format!("{os}/{arch}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n\n"));
}

#[cfg(unix)]
unsafe extern "C" {
    fn dlsym(handle: *mut std::ffi::c_void, name: *const std::ffi::c_char) -> *mut std::ffi::c_void;
}

/// Stands in for a C function this host does not have (kernel32 on a
/// simulated Windows): the path tests never call one.
#[cfg(unix)]
extern "C" fn unresolved_extern() {
    eprintln!("the program called a C function this host does not have");
    std::process::abort();
}

/// async's module-scope variables set up thread-local keys and note the main
/// thread when the program starts, and io imports async, so a Windows path
/// test program calls these before `main`. On a Unix host they answer 0: a valid
/// key index and thread id, and a failed (ignored) free.
#[cfg(unix)]
const WINDOWS_STARTUP_CALLS: [&str; 5] = ["FlsAlloc", "FlsFree", "TlsAlloc", "TlsFree", "GetCurrentThreadId"];

#[cfg(unix)]
extern "C" fn startup_call() -> usize {
    0
}

/// Path syntax is pure Pepper, so the path tests (`runtime/io/test/
/// path_test.pep`) run, in-process by JIT, one after another,
/// with every simulated host's rules: Windows separators, drives and UNC
/// prefixes are checked on any Unix host. (A failed assert aborts the test
/// process after printing its message.) Only this host's architecture is
/// simulated: io imports async, whose fibers carry inline assembly for the
/// simulated architecture, and the JIT can only assemble its own.
#[cfg(unix)]
#[test]
fn path_functions_on_every_platform() {
    #[cfg(target_os = "macos")]
    let rtld_default = -2isize as *mut std::ffi::c_void;
    #[cfg(not(target_os = "macos"))]
    let rtld_default: *mut std::ffi::c_void = std::ptr::null_mut();
    // The raw handle is not Sync; carry it across threads as an address.
    let rtld_default = rtld_default as usize;
    let hosts: Vec<(&str, &str)> =
        SIMULATED_HOSTS.iter().copied().filter(|&(_, arch)| arch == std::env::consts::ARCH).collect();
    let source = with_test_calls(&runtime_file("runtime/io/test/path_test.pep"));
    let codes = support::parallel_map(&hosts, |&(os, arch)| {
        with_codegen_as(os, arch, "path_jit", &source, &["-D", "TEST"], |generator, module| {
            let ee = generator.jit_engine_mapped(module, |name| {
                let c = std::ffi::CString::new(name).ok()?;
                let found = unsafe { dlsym(rtld_default as *mut std::ffi::c_void, c.as_ptr()) };
                if !found.is_null() {
                    None
                } else if WINDOWS_STARTUP_CALLS.contains(&name) {
                    Some(startup_call as *const () as usize)
                } else {
                    Some(unresolved_extern as *const () as usize)
                }
            })?;
            CodeGenerator::jit_call_i32(&ee, "main")
        })
    });
    for ((os, arch), code) in hosts.iter().zip(codes) {
        assert_eq!(code, Ok(0), "path tests as {os}/{arch}");
    }
}