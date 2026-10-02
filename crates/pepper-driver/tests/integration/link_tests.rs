//! `[Link("name")]` end-to-end: the attribute on a surviving extern must add
//! `-l{name}` to the real link command, and the linked binary must resolve
//! the symbol. The probe library is deliberately *not* in the default link
//! set (version.dll on Windows, libpthread elsewhere), so a missing flag
//! fails the link with an unresolved symbol; a green test proves the flag
//! reached the linker and the call ran.

use clap::Parser;
use std::path::PathBuf;
use std::process::Command;
use crate::support::repo_root;

#[test]
fn link_attribute_reaches_linker() {
    // chdir so `Options` paths and runtime discovery resolve like the CLI.
    let root = repo_root();
    std::env::set_current_dir(&root).unwrap();

    let dir = std::env::temp_dir().join(format!("pepper_link_attr_test_{}", std::process::id()));
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

    let dir = std::env::temp_dir().join(format!("pepper_link_{name}_{}", std::process::id()));
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
    // `pep_abs` exists in no library: the call only links if [Link(name)]
    // made the object reference `llabs` (libc / the UCRT) instead. `llabs`
    // takes a 64-bit `long long` on every target, matching Pepper's `long`.
    let out_path = build_binary(
        "link_name_probe",
        r#"
[Link(name = "llabs")] extern long pep_abs(long v);

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
[Target(OS(Windows))] [Link(name = "llabs")] extern long pep_abs(long v);
[Target(!OS(Windows))] [Link(lib = "m", name = "labs")] extern long pep_abs(long v);

main(): int {
    return pep_abs(-9) == 9 ? 0 : 1;
}"#,
    )
    .expect("compile + link");
    let status = Command::new(&out_path).status().expect("spawn linked binary");
    assert!(status.success(), "linked binary exited with {}", status);
}

#[test]
fn link_attribute_errors() {
    for (name, attr, expected) in [
        ("link_bare", "[Link]", "'Link' needs a library or a symbol"),
        ("link_name_empty", "[Link(name = \"\")]", "'Link' argument 'name' must not be empty"),
        ("link_two_positional", "[Link(\"a\", \"b\")]", "'Link' takes one positional argument"),
        ("link_unknown_key", "[Link(symbol = \"a\")]", "'Link' has no argument named 'symbol'"),
        ("link_not_string", "[Link(name = 3)]", "'Link' argument 'name' must be a string"),
        ("link_lib_twice", "[Link(\"m\", lib = \"c\")]", "library given twice in one 'Link'"),
        ("link_path_twice", "[Link(\"m\", path = \"a\", path = \"b\")]", "path given twice in one 'Link'"),
        ("link_path_empty", "[Link(\"m\", path = \"\")]", "'Link' argument 'path' must not be empty"),
        ("link_name_twice", "[Link(name = \"labs\")] [Link(name = \"llabs\")]", "has more than one symbol name"),
        ("link_name_removed", "[LinkName(\"llabs\")]", "'LinkName' was removed; use '[Link(name = \"llabs\")]'"),
    ] {
        let source = format!("{attr} extern long pep_abs(long v);\nmain(): int {{ return pep_abs(-1) as int - 1; }}");
        let err = build_binary(name, &source).expect_err(attr);
        assert!(err.contains(expected), "{attr}: unexpected error: {err}");
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
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stdout.contains("before") && stderr.contains("the assert message"), "stdout: {stdout:?}\nstderr: {stderr:?}");
}

/// Under the JIT, a declared C function the test process cannot resolve
/// (here, one no library defines) must not crash the engine as long as
/// nothing calls it. On Windows the runtime's ws2_32 socket functions are
/// exactly that whenever a JIT test imports `io`.
#[test]
fn the_jit_tolerates_an_unresolvable_c_function_nothing_calls() {
    let source = r#"
[Link("pepper_no_such_library")]
extern int pepper_no_such_function();

unused(): int {
    return pepper_no_such_function();
}

test(): int {
    return 7;
}
"#;
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = pepper_codegen::CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    assert_eq!(pepper_codegen::CodeGenerator::jit_call_i32(&ee, "test"), Ok(7));
}

/// A fresh folder `<dir>/libs` holding a static library `name` (`lib<name>.a`,
/// or `<name>.lib` on Windows) whose `<name>()` returns 42, and a program
/// in `<dir>` declaring that function under `attribute`, which exits 0 when
/// the call returns 42. Returns `(dir, libs)`.
fn search_probe(name: &str, attribute: &str) -> (PathBuf, PathBuf) {
    let dir = std::env::temp_dir().join(format!("pepper_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let libs = dir.join("libs");
    std::fs::create_dir_all(&libs).unwrap();
    let c_path = dir.join(format!("{name}.c"));
    let object = dir.join(format!("{name}.o"));
    std::fs::write(&c_path, format!("int {name}(void) {{ return 42; }}\n")).unwrap();
    let clang = pepper_driver::linker::link_driver();
    let status = Command::new(&clang).arg("-c").arg(&c_path).arg("-o").arg(&object).status().expect("run clang");
    assert!(status.success(), "clang -c failed");
    let status = if cfg!(windows) {
        // llvm-lib ships beside clang in the LLVM the compiler uses.
        let beside = clang.with_file_name("llvm-lib.exe");
        let archiver = if beside.is_file() { beside } else { PathBuf::from("llvm-lib") };
        Command::new(archiver).arg(format!("/out:{}", libs.join(format!("{name}.lib")).display())).arg(&object).status().expect("run llvm-lib")
    } else {
        Command::new("ar").arg("rcs").arg(libs.join(format!("lib{name}.a"))).arg(&object).status().expect("run ar")
    };
    assert!(status.success(), "archiving {name} failed");
    std::fs::write(
        dir.join(format!("{name}.pep")),
        format!("{attribute}\nextern int {name}();\n\nmain(): int {{\n    return {name}() == 42 ? 0 : 1;\n}}\n"),
    )
    .unwrap();
    (dir, libs)
}

/// Build `<dir>/<name>.pep` with the extra command-line `arguments`, run it,
/// and require that it exits 0.
fn build_and_run_search_probe(name: &str, dir: &std::path::Path, arguments: &[String]) {
    let out_path = dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() });
    let mut command = vec!["pepper".to_string(), dir.join(format!("{name}.pep")).to_string_lossy().into_owned()];
    command.extend(arguments.iter().cloned());
    command.extend(["-o".to_string(), out_path.to_string_lossy().into_owned()]);
    let options = pepper_driver::Options::parse_from(command);
    assert_eq!(pepper_driver::run(options).expect("compile + link"), 0);
    let status = Command::new(&out_path).status().expect("spawn linked binary");
    assert!(status.success(), "linked binary exited with {}", status);
}

/// `-L dir` adds a library search directory: a `[Link]` library that only
/// exists in that folder links, and the call into it runs.
#[test]
fn library_search_directory_reaches_linker() {
    std::env::set_current_dir(repo_root()).unwrap();
    let name = "pepper_search_flag_probe";
    let (dir, libs) = search_probe(name, &format!("[Link(\"{name}\")]"));
    build_and_run_search_probe(name, &dir, &["-L".to_string(), libs.to_string_lossy().into_owned()]);
}

/// `[Link(lib = ..., path = "libs")]` searches `libs` beside the source
/// file, wherever the compiler runs.
#[test]
fn link_attribute_path_is_relative_to_the_source() {
    std::env::set_current_dir(repo_root()).unwrap();
    let name = "pepper_search_attribute_probe";
    let (dir, _) = search_probe(name, &format!("[Link(lib = \"{name}\", path = \"libs\")]"));
    build_and_run_search_probe(name, &dir, &[]);
    // The second build skips sema; the folder comes from the cache record.
    std::fs::remove_file(dir.join(name).with_extension(if cfg!(windows) { "exe" } else { "" })).unwrap();
    build_and_run_search_probe(name, &dir, &[]);
}

/// `$PEPPER_LIBRARY_PATH` adds library search directories too.
#[test]
fn library_path_variable_reaches_linker() {
    std::env::set_current_dir(repo_root()).unwrap();
    let name = "pepper_search_variable_probe";
    let (dir, libs) = search_probe(name, &format!("[Link(\"{name}\")]"));
    let value = std::env::join_paths([dir.join("missing"), libs]).unwrap();
    // SAFETY: no other test reads or writes this variable; links running
    // alongside only see one more folder to search.
    unsafe { std::env::set_var("PEPPER_LIBRARY_PATH", &value) };
    let result = std::panic::catch_unwind(|| build_and_run_search_probe(name, &dir, &[]));
    unsafe { std::env::remove_var("PEPPER_LIBRARY_PATH") };
    if let Err(panic) = result {
        std::panic::resume_unwind(panic);
    }
}
