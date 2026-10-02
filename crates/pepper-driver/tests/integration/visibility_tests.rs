//! Cross-file visibility through the driver's compile path: every top-level
//! declaration (functions, structs, type aliases, traits, extensions, module
//! variables) is private to its file unless `export`ed, and the runtime's
//! public surface is exported.

use clap::Parser;
use crate::support::repo_root;

/// Write `lib.pep` and `main.pep` (which imports lib) to a fresh directory
/// and run sema over them, with the runtime.
fn compile(test: &str, lib: &str, main: &str) -> Result<(), String> {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_visibility_{}_{}", test, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("lib.pep"), lib).unwrap();
    let main_path = dir.join("main.pep");
    std::fs::write(&main_path, format!("import \"lib\";\n{}", main)).unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", main_path.to_str().unwrap()]);
    pepper_driver::compiler::compile(&options, "main").map(|_| ())
}

const LIB: &str = r#"
struct Hidden { var v: int; }
type HiddenId = int;
helper(): int { return 1; }

export struct Point { var x: int; }
export type Id = int;
export make(x: int): Point {
    var p = Point();
    p.x = x + helper();
    return p;
}

trait HiddenTrait { int hiddenGet(); }
export trait Getter { int get(); }
const hidden_count = 1;
export const shown_count = 2;
extend Point { int hiddenExt() { return x; } }
export extend Point with Getter { int get() { return hiddenExt(); } }
"#;

#[test]
fn exported_symbols_are_usable_from_another_file() {
    let main = r#"
main(): int {
    var p: Point = make(1);
    var id: Id = p.x;
    var s = String("runtime types are exported");
    return id + p.get() + shown_count;
}
"#;
    compile("exported", LIB, main).expect("exported symbols resolve");
}

#[test]
fn private_function_is_rejected() {
    let err = compile("private_fn", LIB, "main(): int { return helper(); }").unwrap_err();
    assert!(err.contains("'helper' is private to") && err.contains("lib.pep"), "{}", err);
}

#[test]
fn private_function_reference_is_rejected() {
    let err = compile("private_fn_ref", LIB, "main(): int { var f = helper; return f(); }").unwrap_err();
    assert!(err.contains("'helper' is private to") && err.contains("lib.pep"), "{}", err);
}

#[test]
fn private_runtime_helper_is_rejected() {
    // `_pep_check_sync_enabled` reads `PEP_CHECK_SYNC` for the runtime's own
    // census; it is not API.
    let source = "main(): int { var on = _pep_check_sync_enabled(); return 0; }";
    let err = compile("private_runtime", LIB, source).unwrap_err();
    assert!(err.contains("'_pep_check_sync_enabled' is private to") && err.contains("internals.pep"), "{}", err);
}

#[test]
fn a_struct_override_of_a_runtime_generic_is_honored() {
    // `hash<Pt>` overrides the runtime's `hash<T>` for `Pt`, as `hash<int>`
    // would: it compiles, and must not be reported as a private duplicate.
    let main = "struct Pt { var x: int; ==(other: Pt): bool { return x == other.x; } }\nhash<Pt>(Pt p): u64 { return 42; }\n\
                main(): int { var s = HashSet<Pt>(); s.insert(Pt()); return hash<Pt>(Pt()) as int; }";
    compile("override", LIB, main).expect("a struct override");
}

#[test]
fn runtime_file_as_entry_is_compiled_once() {
    // The entry's relative path and discovery's canonical path name the same
    // file; loading it twice would report every private symbol as duplicated.
    std::env::set_current_dir(repo_root()).unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", "runtime/internals.pep"]);
    pepper_driver::compiler::compile(&options, "main").map(|_| ()).expect("compiles once");
}

#[test]
fn forced_import_listed_twice_is_loaded_once() {
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_visibility_forced_twice_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("extra.pep"), "helper(): int { return 1; }\nexport extra(): int { return helper(); }").unwrap();
    let main_path = dir.join("main.pep");
    std::fs::write(&main_path, "main(): int { return extra(); }").unwrap();
    let options = pepper_driver::Options::parse_from([
        "pepper",
        main_path.to_str().unwrap(),
        "-I",
        dir.to_str().unwrap(),
        "--import",
        "extra",
        "--import",
        "extra",
    ]);
    pepper_driver::compiler::compile(&options, "main").map(|_| ()).expect("forced import loads once");
}
