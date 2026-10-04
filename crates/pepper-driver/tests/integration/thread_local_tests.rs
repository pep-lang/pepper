//! `[ThreadLocal]` module-scope variables (#625): how they compile. What
//! they do on threads, and `async.ThreadLocal<T>` built on them, is tested
//! by the `[Test]` functions in `runtime/async/test/thread_test.pep`.
//!
//! The JIT runs here twice: with LLVM thread-locals (x86-64 Linux, where
//! MCJIT relocates TLS) and with the emulation the JIT uses on every other
//! host, forced on, so both paths run on the Linux machines CI uses.

use pepper_codegen::CodeGenerator;

use crate::support;

/// Each thread counts on its own copy, starting from the initializer, and a
/// `[Shared]` struct a thread leaves in a thread-local is released when it
/// exits; `ThreadLocal<T>` keeps working on top of the same machinery.
const PROGRAM: &str = r#"
import async;

const released = async.Atomic<int>(0);

[Shared]
struct Token {
    const id: int;

    construct(id: int) {
        this.id = id;
    }

    destruct {
        released.fetch_add(1);
    }
}

[ThreadLocal]
var calls: int = 7;
[ThreadLocal]
var scale: double = -1.5;
[ThreadLocal]
var token: Token;

const total = async.Atomic<long>(0);
const library = async.ThreadLocal<Token>();

count() {
    calls = calls + 100;
    total.fetch_add(calls);
    token = Token(1);
    token = Token(2);
    library.set(Token(3));
}

per_thread(): int {
    calls = calls + 1;
    var a = async.Thread.spawn(count);
    var b = async.Thread.spawn(count);
    a.join();
    b.join();
    if (calls != 8 || total.load() != 214 || scale != -1.5) {
        return 1;
    }
    calls = 7;
    return 0;
}

released_at_exit(): int {
    released.store(0);
    var a = async.Thread.spawn(count);
    a.join();
    # Token(1) when Token(2) replaced it, Token(2) and Token(3) at the exit.
    if (released.load() != 3 || token !== __null || library.is_set()) {
        return 1;
    }
    return 0;
}
"#;

/// JIT-runs `PROGRAM`'s cases, which must each return 0, with the
/// thread-locals emulated or not. (Not under `jit_cases`' allocation count:
/// the first thread a program starts makes the runtime's lasting state.)
fn run_cases(emulate: bool) {
    let mut module = support::sema(PROGRAM).unwrap_or_else(|e| panic!("compile:\n{}", e));
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_emulates_thread_locals = emulate;
    let ee = generator.jit_engine(&mut module).expect("jit");
    for name in ["per_thread", "released_at_exit"] {
        assert_eq!(CodeGenerator::jit_call_i32(&ee, name), Ok(0), "{name} (emulated: {emulate})");
    }
}

#[test]
fn thread_locals_run_under_the_jit() {
    run_cases(pepper_codegen::thread_locals::JIT_EMULATES_BY_DEFAULT);
}

#[test]
fn emulated_thread_locals_run_under_the_jit() {
    run_cases(true);
}

/// Codegen emits an initial-exec `thread_local` global with the constant
/// initializer, and the release function the runtime declares.
#[test]
fn a_thread_local_is_an_initial_exec_tls_global() {
    let mut module = support::sema("[ThreadLocal]\nvar depth: int = -3;\ntest(): int { depth += 1; return depth; }\n").unwrap();
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.generate(&mut module).unwrap();
    let ir = generator.module.print_to_string().to_string();
    assert!(ir.contains("@depth = thread_local(initialexec) global i32 -3"), "{}", ir.lines().filter(|l| l.contains("depth")).collect::<Vec<_>>().join("\n"));
    assert!(ir.contains("define void @_pep_release_thread_locals()"), "no release function");
}

/// A linked program, built in units through the build cache: the program
/// module defines the release function that the `async` unit calls.
#[test]
fn a_linked_program_releases_thread_locals() {
    let source = format!("{}\nmain(): int {{ return per_thread() + released_at_exit(); }}\n", PROGRAM);
    for args in [&[][..], &["-O2"][..]] {
        let output = support::run_linked_with("thread_local_linked", &source, args, |_| {});
        assert!(output.status.success(), "{:?}: {}", args, support::output_text(&output));
    }
}
