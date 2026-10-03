//! Calling Pepper from C: `[Export]`, `--lib static|shared` and the
//! generated header. The end-to-end test builds both kinds of library,
//! compiles a C program against each with the clang the compiler links
//! with, and runs it, on every platform CI covers.

use crate::support::{repo_root, sema};
use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::{Path, PathBuf};
use std::process::Command;

/// A library that exercises each kind of value that crosses to C: numbers,
/// `bool`, a C function pointer, a `String` in both directions, a struct
/// handle in both directions, and a module-scope variable whose initializer
/// must have run.
const LIBRARY: &str = r#"
import async;

const freed = async.Atomic<int>(0);
const started = async.Atomic<int>(7);

struct Counter {
    var count: int;

    construct(this.count = 0) {}

    destruct {
        freed.fetch_add(1);
    }
}

[Export]
add(a: int, b: int): int {
    return a + b;
}

[Export(name = "counter_new")]
make_counter(start: int): Counter {
    return Counter(start);
}

[Export]
counter_increment(counter: Counter): int {
    counter.count += 1;
    return counter.count;
}

[Export]
freed_count(): int {
    return freed.load();
}

[Export]
started_value(): int {
    return started.load();
}

[Export]
is_even(n: long): bool {
    return n % 2 == 0;
}

[Export]
scale(x: double, factor: float): double {
    return x * factor;
}

[Export]
narrow(x: short): short {
    return x;
}

[Export]
apply(f: extern (int) => int, x: int): int {
    return f(x);
}

[Export]
shout(text: String, times: int): String {
    var out = "";
    for (var i in 0..times) {
        out += text.upper();
    }
    return out + "!";
}

[Export]
live_allocations(): long {
    return _pep_live_allocs();
}
"#;

const PROGRAM: &str = r#"
#include <stdio.h>
#include <string.h>
#include "counter.h"

static int32_t twice(int32_t x) { return 2 * x; }

int main(void) {
    int64_t live = live_allocations();
    char* shouted = shout("h\xc3\xa9", 3, 2);
    char* empty = shout(NULL, 0, 1);
    printf("%s %s %d\n", shouted, empty, (int)strlen(shouted));
    pepper_string_free(shouted);
    pepper_string_free(empty);
    Counter* counter = counter_new(10);
    counter_increment(counter);
    int32_t count = counter_increment(counter);
    counter_retain(counter);
    counter_release(counter);
    int32_t freed_before = freed_count();
    counter_release(counter);
    printf("%d %d %d %d %d %d %d %g %d %d\n", add(2, 3), count, freed_before, freed_count(), started_value(),
           is_even(4), is_even(7), scale(1.5, 2.0f), narrow(-3), apply(twice, 21));
    printf("leaked %d\n", (int)(live_allocations() - live));
    return 0;
}
"#;

const EXPECTED: &str = "HéHé! ! 7\n5 12 0 1 7 1 0 3 -3 42\nleaked 0";

/// Build `LIBRARY` as a `kind` library in `dir`, returning its path.
fn build_library(dir: &Path, kind: &str) -> PathBuf {
    std::env::set_current_dir(repo_root()).unwrap();
    std::fs::create_dir_all(dir).unwrap();
    let source = dir.join("counter.pep");
    std::fs::write(&source, LIBRARY).unwrap();
    let file = pepper_driver::library::LibraryKind::parse(kind).unwrap().file_name("counter");
    let library = dir.join(file);
    let options = pepper_driver::Options::parse_from([
        "pepper".to_string(),
        source.to_string_lossy().into_owned(),
        "--lib".to_string(),
        kind.to_string(),
        "-o".to_string(),
        library.to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
    ]);
    assert_eq!(pepper_driver::run(options).expect("build the library"), 0);
    assert!(library.is_file(), "{} was not written", library.display());
    library
}

/// Compile `PROGRAM` in `dir` against the library there with `link`
/// arguments, run it, and return what it printed.
fn run_program(dir: &Path, link: &[String]) -> String {
    std::fs::write(dir.join("main.c"), PROGRAM).unwrap();
    let exe = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let output = Command::new(pepper_driver::linker::link_driver())
        .arg(dir.join("main.c"))
        .arg(format!("-I{}", dir.display()))
        .args(link)
        .arg("-o")
        .arg(&exe)
        .output()
        .expect("run clang");
    assert!(output.status.success(), "clang failed:\n{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
    let output = Command::new(&exe).output().expect("run the C program");
    assert!(output.status.success(), "the C program failed: {}\n{}", output.status, String::from_utf8_lossy(&output.stderr));
    String::from_utf8_lossy(&output.stdout).trim().replace("\r\n", "\n")
}

#[test]
fn c_program_calls_a_static_library() {
    let dir = std::env::temp_dir().join(format!("pepper_c_export_static_{}", std::process::id()));
    let library = build_library(&dir, "static");
    let header = std::fs::read_to_string(dir.join("counter.h")).expect("the header is written");
    assert!(header.contains("Counter* counter_new(int32_t start);"), "{}", header);
    // The header names the libraries the static library needs.
    let mut link = vec![library.to_string_lossy().into_owned()];
    if let Some(line) = header.lines().find_map(|l| l.strip_prefix("/* Link the static library with: ")) {
        link.extend(line.trim_end_matches(" */").split(' ').map(str::to_string));
    }
    assert_eq!(run_program(&dir, &link), EXPECTED);
}

#[test]
fn c_program_calls_a_shared_library() {
    let dir = std::env::temp_dir().join(format!("pepper_c_export_shared_{}", std::process::id()));
    let library = build_library(&dir, "shared");
    let link = if cfg!(windows) {
        // clang links the DLL through its import library, `counter.lib`;
        // the program finds `counter.dll` beside it.
        vec![dir.join("counter.lib").to_string_lossy().into_owned()]
    } else {
        vec![library.to_string_lossy().into_owned(), format!("-Wl,-rpath,{}", dir.display())]
    };
    assert_eq!(run_program(&dir, &link), EXPECTED);
}

#[test]
fn header_declares_exports_and_handles() {
    std::env::set_current_dir(repo_root()).unwrap();
    let module = sema(LIBRARY).expect("compile");
    assert_eq!(
        pepper_sema::passes::exports::header_declarations(&module.exports),
        "/* Opaque handles to Pepper objects. A handle a function returns is one\n \
         * reference, which the caller releases; a handle passed in stays the\n \
         * caller's. */\n\
         typedef struct Counter Counter;\n\
         \n\
         void counter_retain(Counter* handle);\n\
         void counter_release(Counter* handle);\n\
         \n\
         /* A string a function returns is a NUL-terminated UTF-8 copy, which the\n \
         * caller frees with this. */\n\
         void pepper_string_free(char* text);\n\
         \n\
         int32_t add(int32_t a, int32_t b);\n\
         int32_t apply(int32_t (*f)(int32_t), int32_t x);\n\
         int32_t counter_increment(Counter* counter);\n\
         Counter* counter_new(int32_t start);\n\
         int32_t freed_count(void);\n\
         bool is_even(int64_t n);\n\
         int64_t live_allocations(void);\n\
         int16_t narrow(int16_t x);\n\
         double scale(double x, float factor);\n\
         char* shout(const char* text, size_t text_size, int32_t times);\n\
         int32_t started_value(void);\n"
    );
}

#[test]
fn handles_follow_the_reference_counts() {
    // A returned handle is one reference; release frees the object, and
    // nothing leaks.
    std::env::set_current_dir(repo_root()).unwrap();
    let mut module = sema(LIBRARY).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let prefix = pepper_codegen::exports::EXPORT_PREFIX;
    unsafe {
        let live = ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").unwrap();
        let new = ee.get_function::<unsafe extern "C" fn(i32) -> *mut u8>(&format!("{}counter_new", prefix)).unwrap();
        let increment = ee.get_function::<unsafe extern "C" fn(*mut u8) -> i32>(&format!("{}counter_increment", prefix)).unwrap();
        let retain = ee.get_function::<unsafe extern "C" fn(*mut u8)>(&format!("{}counter_retain", prefix)).unwrap();
        let release = ee.get_function::<unsafe extern "C" fn(*mut u8)>(&format!("{}counter_release", prefix)).unwrap();
        let freed = ee.get_function::<unsafe extern "C" fn() -> i32>(&format!("{}freed_count", prefix)).unwrap();
        let before = live.call();
        let counter = new.call(1);
        assert_eq!(increment.call(counter), 2);
        retain.call(counter);
        release.call(counter);
        assert_eq!(freed.call(), 0, "a retained handle keeps its object");
        release.call(counter);
        assert_eq!(freed.call(), 1, "the last release frees the object");
        assert_eq!(live.call(), before, "nothing leaks");
    }
}
