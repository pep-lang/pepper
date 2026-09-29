//! Cross-file visibility through the driver's compile path: every top-level
//! declaration (functions, structs, type aliases, traits, extensions, module
//! variables) is private to its file unless `export`ed, and the runtime's
//! public surface is exported.

use clap::Parser;
use std::path::PathBuf;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf()
}

/// Write `lib.pep` and `main.pep` (which imports lib) to a fresh directory
/// and run sema over them, with the runtime.
fn compile(test: &str, lib: &str, main: &str) -> Result<(), String> {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_visibility_{}", test));
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
fn exported_function_reference_is_usable() {
    compile("exported_fn_ref", LIB, "main(): int { var f: (int) => Point = make; return f(1).x; }").expect("exported function as a value");
}

#[test]
fn private_struct_is_rejected() {
    let err = compile("private_struct", LIB, "main(): int { var h = Hidden(); return 0; }").unwrap_err();
    assert!(err.contains("'Hidden' is private to"), "{}", err);
}

#[test]
fn private_type_alias_is_rejected() {
    let err = compile("private_alias", LIB, "main(): int { var i: HiddenId = 0; return i; }").unwrap_err();
    assert!(err.contains("'HiddenId' is private to"), "{}", err);
}

#[test]
fn private_runtime_helper_is_rejected() {
    // `dec` formats integers for the runtime's own printing; it is not API.
    let err = compile("private_runtime", LIB, "main(): int { var s = dec(5); return 0; }").unwrap_err();
    assert!(err.contains("'dec' is private to") && err.contains("internals.pep"), "{}", err);
}

#[test]
fn private_trait_is_rejected() {
    let err = compile("private_trait", LIB, "extend Point with HiddenTrait { int hiddenGet() { return 0; } }\nmain(): int { return 0; }")
        .unwrap_err();
    assert!(err.contains("'HiddenTrait' is private to"), "{}", err);
}

#[test]
fn private_module_variable_is_rejected() {
    let err = compile("private_var", LIB, "main(): int { return hidden_count; }").unwrap_err();
    assert!(err.contains("'hidden_count' is private to"), "{}", err);
}

#[test]
fn private_extension_method_is_rejected() {
    let err = compile("private_ext", LIB, "main(): int { var p = make(1); return p.hiddenExt(); }").unwrap_err();
    assert!(err.contains("'hiddenExt' is declared in a private extension in") && err.contains("lib.pep"), "{}", err);
}

#[test]
fn private_name_declared_in_two_files_is_allowed() {
    // Each file's private names live in its own namespace.
    compile("duplicate", LIB, "helper(): int { return 2; }\nmain(): int { return helper(); }").expect("private names per file");
}

#[test]
fn leak_census_helper_is_exported() {
    compile("census", LIB, "main(): int { return _pep_live_allocs() as int; }").expect("_pep_live_allocs is exported");
}

#[test]
fn private_generic_named_like_a_runtime_export_stays_in_its_file() {
    // Only primitive and String overrides exist; `hash<Pt>` is a second
    // generic base, private to this file: it does not replace the runtime's
    // `hash<T>`, which the runtime's own hash tables still call.
    let main = "struct Pt { var x: int; }\nhash<Pt>(Pt p): u64 { return 42; }\n\
                main(): int { var s = HashSet<int>(); s.insert(1); return hash<Pt>(Pt()) as int; }";
    compile("override", LIB, main).expect("a private generic stays in its file");
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
    let dir = std::env::temp_dir().join("pepper_visibility_forced_twice");
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
