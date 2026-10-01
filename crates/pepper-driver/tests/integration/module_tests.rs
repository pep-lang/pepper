//! Modules and imports through the driver's compile path: a folder holding a
//! `module.pep` is a module; `import m [as q]`, `import [x as y] from m`,
//! `import "file" [as q]`, and `export x as y` bind and rewrite names before
//! the files are merged. Each test writes a file tree, compiles it with the
//! runtime, and JIT-runs its `test` entry.
//!
//! `import m` finds modules on the search paths only, so the harness passes
//! `-I deps` and writes every module folder a test lists at its top level
//! (`geo/module.pep`, `geo/impl.pep`) under `deps/`. Other files stay where
//! the test puts them, next to `main.pep`.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::PathBuf;
use crate::support::repo_root;

/// Write `files` (path, text) under a fresh directory named for `test`, then
/// compile `main.pep` there.
fn compile(test: &str, files: &[(&str, &str)]) -> Result<pepper_sema::model::Module, String> {
    compile_with(test, files, &[])
}

/// Write `files` under a fresh directory for `test`: top-level module folders
/// go under `deps/`. Returns the directory.
fn write_tree(test: &str, files: &[(&str, &str)]) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_modules_{}_{}", test, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let is_module = |top: &str| files.iter().any(|(p, _)| *p == format!("{}/module.pep", top));
    // A top-level folder listed as `./name/...` is local, not a dependency.
    for (path, text) in files {
        let path = match path.split_once('/') {
            // `./name/...` stays next to main.pep: a local module folder.
            _ if path.starts_with("./") => dir.join(&path[2..]),
            Some((top, _)) if is_module(top) => dir.join("deps").join(path),
            _ => dir.join(path),
        };
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
    std::fs::create_dir_all(dir.join("deps")).unwrap();
    dir
}

/// `compile`, with extra command-line arguments.
fn compile_with(test: &str, files: &[(&str, &str)], args: &[&str]) -> Result<pepper_sema::model::Module, String> {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = write_tree(test, files);
    let main_path = dir.join("main.pep");
    let deps = dir.join("deps");
    let mut argv = vec!["pepper", main_path.to_str().unwrap(), "-I", deps.to_str().unwrap()];
    argv.extend_from_slice(args);
    let options = pepper_driver::Options::parse_from(argv);
    pepper_driver::compiler::compile(&options, "main")
}

fn run(test: &str, files: &[(&str, &str)]) -> i32 {
    run_with(test, files, &[])
}

fn run_with(test: &str, files: &[(&str, &str)], args: &[&str]) -> i32 {
    let mut module = compile_with(test, files, args).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

fn error(test: &str, files: &[(&str, &str)]) -> String {
    match compile(test, files) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e,
    }
}

/// A module: `module.pep` exports some of its own declarations and
/// re-exports from a file of the same module.
const GEOMETRY: &[(&str, &str)] = &[
    (
        "geometry/module.pep",
        r#"
import "shapes";

export struct Point { var x: int; var y: int; }
export make(x: int, y: int): Point {
    var p = Point();
    p.x = x;
    p.y = y;
    return p;
}
secret(): int { return 1000; }
export secret as revealed;
export area as rect_area;
export Box;
"#,
    ),
    (
        "geometry/shapes.pep",
        r#"
export area(w: int, h: int): int { return w * h + helper(); }
export struct Box<T> { var value: T; }
helper(): int { return 0; }
"#,
    ),
];

fn with_geometry<'a>(main: &'a str) -> Vec<(&'a str, &'a str)> {
    let mut files: Vec<(&str, &str)> = GEOMETRY.to_vec();
    files.push(("main.pep", main));
    files
}

#[test]
fn bare_module_import_is_qualified_by_module_name() {
    let main = r#"
import geometry;
test(): int {
    var p: geometry.Point = geometry.make(3, 4);
    return p.x * 10 + p.y;
}
"#;
    assert_eq!(run("bare", &with_geometry(main)), 34);
}

#[test]
fn module_import_as_alias() {
    let main = r#"
import geometry as g;
test(): int {
    var p = g.make(1, 2);
    var b = g.Box<int>();
    b.value = g.rect_area(2, 5);
    return p.y + b.value + g.revealed();
}
"#;
    assert_eq!(run("alias", &with_geometry(main)), 1012);
}

#[test]
fn imported_functions_are_function_values() {
    let main = r#"
import geometry as g;
import [rect_area as area] from geometry;
combine(f: (int, int) => int, a: int, b: int): int { return f(a, b); }
test(): int {
    var qualified = g.rect_area;
    return combine(qualified, 2, 3) * 100 + combine(area, 1, 4);
}
"#;
    assert_eq!(run("function_values", &with_geometry(main)), 604);
}

#[test]
fn symbol_list_import_binds_local_names() {
    let main = r#"
import [make, Point as Pt, rect_area as area, revealed] from geometry;
test(): int {
    var p: Pt = make(2, 3);
    return area(p.x, p.y) + revealed();
}
"#;
    assert_eq!(run("list", &with_geometry(main)), 1006);
}

#[test]
fn file_import_brings_exports_unqualified_and_as_qualifies() {
    let files = [
        ("util.pep", "export twice(x: int): int { return x * 2; }\nexport const base = 5;"),
        ("more.pep", "export thrice(x: int): int { return x * 3; }"),
        ("main.pep", "import \"util\";\nimport \"more\" as m;\ntest(): int { return twice(base) + m.thrice(1); }"),
    ];
    assert_eq!(run("file", &files), 13);
}

#[test]
fn globals_are_initialized_after_the_globals_they_import() {
    // main imports a and b, and a imports b: b's globals are initialized
    // first, then a's, then main's, whatever order the files were loaded in.
    let files = [
        ("b.pep", "import async;\nexport const start = async.Atomic<int>(40);"),
        ("a.pep", "import async;\nimport \"b\";\nexport const next = async.Atomic<int>(start.load() + 1);"),
        (
            "main.pep",
            "import async;\nimport \"a\";\nimport \"b\";\nconst answer = async.Atomic<int>(next.load() + 1);\ntest(): int { return answer.load() + start.load(); }",
        ),
    ];
    assert_eq!(run("init_order", &files), 82);
}

#[test]
fn locals_and_parameters_shadow_imports() {
    let main = r#"
import geometry as g;
import [rect_area as area] from geometry;
calc(area: int): int { return area; }
test(): int {
    var g = 7;
    return calc(g) + area(1, 1);
}
"#;
    assert_eq!(run("shadow", &with_geometry(main)), 8);
}

#[test]
fn files_of_a_module_may_import_each_other() {
    let files = [
        ("pair/module.pep", "import \"a\";\nexport ping as start;"),
        ("pair/a.pep", "import \"b\";\nexport ping(n: int): int { return n == 0 ? 0 : pong(n - 1) + 1; }"),
        ("pair/b.pep", "import \"a\";\nexport pong(n: int): int { return n == 0 ? 0 : ping(n - 1) + 1; }"),
        ("main.pep", "import pair;\ntest(): int { return pair.start(6); }"),
    ];
    assert_eq!(run("cycle", &files), 6);
}

#[test]
fn file_exports_are_not_module_exports() {
    // `shapes.pep` exports `area`, but only `module.pep`'s exports and
    // re-exports are the module's (it re-exports `area` as `rect_area`).
    let err = error("not_module_export", &with_geometry("import geometry;\ntest(): int { return geometry.area(1, 2); }"));
    assert!(err.contains("'area' is not exported by 'geometry'"), "{}", err);
}

#[test]
fn private_symbol_is_not_importable() {
    let err = error("private_import", &with_geometry("import [secret] from geometry;\ntest(): int { return secret(); }"));
    assert!(err.contains("'secret' is not exported by module 'geometry'"), "{}", err);
}

#[test]
fn another_files_export_needs_an_import() {
    // `main.pep` imports geometry, whose module file imports shapes; that does
    // not make shapes' exports visible to main.
    let err = error("not_imported", &with_geometry("import geometry;\ntest(): int { return area(1, 2); }"));
    assert!(err.contains("'area' is exported by") && err.contains("which this file does not import"), "{}", err);
}

#[test]
fn unknown_module_and_file_are_reported_at_the_import() {
    let err = error("unknown", &[("main.pep", "import nowhere;\nimport \"missing\";\ntest(): int { return 0; }")]);
    assert!(err.contains("main.pep:1:8: error: cannot find module 'nowhere'"), "{}", err);
    assert!(err.contains("main.pep:2:8: error: cannot find \"missing.pep\" or the module folder \"missing\" next to this file"), "{}", err);
}

#[test]
fn qualifier_must_name_an_imported_module() {
    let err = error("bad_qualifier", &with_geometry("test(): int { var p: geometry.Point = 0; return 0; }"));
    assert!(err.contains("'geometry' is not an imported module"), "{}", err);
}

#[test]
fn import_may_not_redeclare_a_local_name() {
    let err = error(
        "redeclare",
        &with_geometry("import [make] from geometry;\nmake(): int { return 0; }\ntest(): int { return 0; }"),
    );
    assert!(err.contains("'make' is imported but also declared in this file"), "{}", err);
}

#[test]
fn re_export_of_unknown_symbol_is_rejected() {
    let err = error("bad_reexport", &[("main.pep", "export nothing as something;\ntest(): int { return 0; }")]);
    assert!(err.contains("cannot export 'nothing'"), "{}", err);
}

#[test]
fn runtime_prelude_needs_no_import() {
    let main = "test(): int { var s: String = \"abc\"; return s.length() as int; }";
    assert_eq!(run("prelude", &[("main.pep", main)]), 3);
}

#[test]
fn modules_may_export_the_same_name() {
    // Each module's exports are its own (#244): `a.f` and `b.f`, and the two
    // `Point`s, are different declarations.
    let files = [
        ("a/module.pep", "export f(): int { return 1; }\nexport struct Point { var x: int; }"),
        ("b/module.pep", "export f(): int { return 2; }\nexport struct Point { var y: int; }"),
        (
            "main.pep",
            "import a;\nimport b;\ntest(): int {\n    var p = a.Point();\n    var q = b.Point();\n    p.x = 3;\n    q.y = 4;\n    return a.f() * 10 + b.f() + p.x + q.y - 19;\n}",
        ),
    ];
    assert_eq!(run("same_export", &files), 0);
}

#[test]
fn the_same_export_from_two_imports_is_ambiguous_only_where_used() {
    let files = [
        ("x.pep", "export f(): int { return 1; }\nexport g(): int { return 3; }"),
        ("y.pep", "export f(): int { return 2; }"),
        ("main.pep", "import \"x\";\nimport \"y\";\ntest(): int { return f(); }"),
    ];
    let err = error("same_export_ambiguous", &files);
    assert!(err.contains("'f' is ambiguous: more than one import provides it"), "{}", err);
    // An import list tells them apart; `g`, which only one provides, needs none.
    let files = [
        ("x.pep", "export f(): int { return 1; }\nexport g(): int { return 3; }"),
        ("y.pep", "export f(): int { return 2; }"),
        ("main.pep", "import \"x\";\nimport [f as fy] from \"y\";\ntest(): int { return f() * 10 + fy() + g() - 15; }"),
    ];
    assert_eq!(run("same_export_aliased", &files), 0);
}

#[test]
fn export_may_not_repeat_a_runtime_name() {
    let err = error("runtime_duplicate", &[("main.pep", "export struct String { }\ntest(): int { return 0; }")]);
    assert!(err.contains("exported 'String' is also declared in"), "{}", err);
}

#[test]
fn a_local_does_not_capture_an_imported_name() {
    // `g.rect_area` is `area` in shapes.pep, mangled apart from the
    // parameter `area`.
    assert_eq!(run("capture", &with_geometry("import geometry as g;
calc(area: int): int { return area + g.rect_area(1, 1); }
test(): int { return calc(1); }")), 2);
}

#[test]
fn forced_module_import_keeps_its_re_exports() {
    let files = [
        ("counter/module.pep", "import \"impl\";
export step as increment_size;"),
        ("counter/impl.pep", "export step(): int { return 2; }"),
        ("main.pep", "test(): int { return increment_size(); }"),
    ];
    assert_eq!(run_with("forced_reexport", &files, &["--import", "counter"]), 2);
}

#[test]
fn named_import_wins_over_a_whole_file_import() {
    let files = [
        ("a.pep", "export one(): int { return 1; }"),
        ("b.pep", "export two(): int { return 2; }"),
        ("main.pep", "import [two as one] from \"b\";
import \"a\";
test(): int { return one(); }"),
    ];
    assert_eq!(run("explicit_first", &files), 2);
    let files = [
        ("a.pep", "export one(): int { return 1; }"),
        ("b.pep", "export two(): int { return 2; }"),
        ("main.pep", "import \"a\";
import [two as one] from \"b\";
test(): int { return one(); }"),
    ];
    assert_eq!(run("explicit_last", &files), 2);
}

#[test]
fn an_extension_in_a_file_not_imported_does_not_shadow_imports() {
    // main.pep's extension adds `bump` to Counter through a qualified target,
    // but c/module.pep does not import main.pep, so in Counter's own `total`
    // `bump` is still c's import.
    let files = [
        (
            "c/module.pep",
            "import [bump_impl as bump] from \"helpers\";
             export struct Counter { var n: int; total(): int { return bump(); } }
             export use_bump(): int { return bump(); }",
        ),
        ("c/helpers.pep", "export bump_impl(): int { return 100; }"),
        ("main.pep", "import c as m;
export extend m.Counter { bump(): int { return 1; } }
test(): int { var k = m.Counter(); return k.total() + m.use_bump(); }"),
    ];
    assert_eq!(run("ext_members", &files), 200);
}

#[test]
fn file_imports_stay_inside_their_module() {
    let files = [
        ("escape.pep", "export f(): int { return 1; }"),
        ("./inner/module.pep", "import \"../escape\";\nexport g(): int { return f(); }"),
        ("main.pep", "import \"inner\";\ntest(): int { return g(); }"),
    ];
    let err = error("escape", &files);
    assert!(err.contains("\"../escape.pep\" is outside this file's module"), "{}", err);

    let files = [
        ("./geo/module.pep", "import \"shapes\";\nexport area as rect_area;"),
        ("./geo/shapes.pep", "export area(w: int, h: int): int { return w * h; }"),
        ("main.pep", "import \"geo/shapes\";\ntest(): int { return area(1, 2); }"),
    ];
    let err = error("nested_module", &files);
    assert!(err.contains("\"geo/shapes.pep\" belongs to another module"), "{}", err);

    // A subfolder that is not a module is still this module.
    let files = [
        ("lib/deep.pep", "export f(): int { return 4; }"),
        ("main.pep", "import \"lib/deep\";\ntest(): int { return f(); }"),
    ];
    assert_eq!(run("subfolder", &files), 4);
}

#[test]
fn a_local_module_folder_is_imported_by_path() {
    // `import "geo"` names the module folder next to the file; `import geo`
    // would search only `-I` and the runtime.
    let files = [
        ("./geo/module.pep", "import \"shapes\";\nexport area as rect_area;"),
        ("./geo/shapes.pep", "export area(w: int, h: int): int { return w * h; }"),
        ("main.pep", "import \"geo\" as g;\ntest(): int { return g.rect_area(2, 3); }"),
    ];
    assert_eq!(run("local_module", &files), 6);
    let files = [
        ("./geo/module.pep", "export f(): int { return 1; }"),
        ("main.pep", "import geo;\ntest(): int { return geo.f(); }"),
    ];
    let err = error("local_module_by_name", &files);
    assert!(err.contains("cannot find module 'geo'"), "{}", err);
}

#[test]
fn a_qualified_use_does_not_unlock_the_bare_name() {
    // `g.revealed` is geometry's private `secret`, and `g.make` is `make`;
    // neither makes the bare spelling visible.
    let err = error(
        "bare_after_qualified",
        &with_geometry("import geometry as g;\ntest(): int { g.revealed(); return secret(); }"),
    );
    assert!(err.contains("'secret' is private to"), "{}", err);
    let err = error(
        "bare_after_list",
        &with_geometry("import [rect_area] from geometry;\ntest(): int { rect_area(1, 1); return area(1, 2); }"),
    );
    assert!(err.contains("'area' is exported by") && err.contains("which this file does not import"), "{}", err);
}

#[test]
fn private_extensions_elsewhere_do_not_shadow_imports() {
    // Another file's private extension adds `g` to Counter; Counter's own file
    // cannot see it, so `g.area2` there is still the module qualifier.
    let files = [
        ("geo/module.pep", "export area2(): int { return 7; }"),
        (
            "c/module.pep",
            "import geo as g;\nimport \"other\";\nexport struct Counter { var n: int; f(): int { return g.area2(); } }",
        ),
        ("c/other.pep", "import \"module\";\nextend Counter { g(): int { return 0; } }"),
        ("main.pep", "import c;\ntest(): int { var k = c.Counter(); return k.f(); }"),
    ];
    assert_eq!(run("private_ext", &files), 7);
}

/// Load `main.pep` as the language server does (lenient), without the
/// runtime.
fn load_lenient(test: &str, files: &[(&str, &str)]) -> pepper_sema::program::Program {
    let dir = write_tree(test, files);
    let main = dir.join("main.pep");
    let search_paths = pepper_driver::imports::search_paths(&[dir.join("deps")], &[]);
    pepper_sema::program::load_file(&main, &[], &search_paths, pepper_sema::program::Mode::Lenient).expect("load")
}

#[test]
fn a_module_that_fails_to_parse_is_reported_at_the_import() {
    let program = load_lenient(
        "broken_module",
        &[("geo/module.pep", "export struct P { var x: int; "), ("main.pep", "import geo;\nf(p: geo.P): int { return 0; }")],
    );
    let messages: Vec<&str> = program.errors.iter().filter(|e| e.file == 0).map(|e| e.message.as_str()).collect();
    assert!(messages.iter().any(|m| m.starts_with("cannot load module 'geo':")), "{:?}", messages);
}

#[test]
fn an_unsaved_root_imports_its_siblings() {
    // The root is an editor buffer with no file on disk yet.
    let dir = std::env::temp_dir().join(format!("pepper_modules_unsaved_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("helper.pep"), "export seven(): int { return 7; }").unwrap();
    let root = pepper_sema::program::Root {
        name: "untitled".to_string(),
        source: "import \"helper\";\nf(): int { return seven(); }".to_string(),
        path: dir.join("untitled.pep"),
    };
    let search_paths = pepper_driver::imports::search_paths(&[], &[]);
    let program = pepper_sema::program::load(root, &[], &search_paths, pepper_sema::program::Mode::Lenient).expect("load");
    assert!(program.check().is_ok(), "{:?}", program.check());
}

#[test]
fn member_comparisons_in_arguments_need_no_import() {
    let main = r#"
struct P { var b: int; }
two(x: bool, y: bool): int { return (x ? 1 : 0) + (y ? 1 : 0); }
test(): int {
    var a = P();
    a.b = 1;
    var c = 2;
    var d = 3;
    var e = 1;
    return two(a.b < c, d > (e));
}
"#;
    assert_eq!(run("comparisons", &[("main.pep", main)]), 2);
}

#[test]
fn qualified_c_style_return_type() {
    let main = r#"
import geometry as g;
g.Point origin() { return g.make(5, 6); }
test(): int { return origin().y; }
"#;
    assert_eq!(run("c_style_return", &with_geometry(main)), 6);
}

#[test]
fn re_exports_that_flip_through_an_ambiguity_are_reported() {
    let files = [
        ("a.pep", "import \"bb\";\nimport \"cc\";\nexport foo as bar;"),
        ("bb.pep", "import \"a\";\nimport \"dd\";\nexport bar as foo;"),
        ("cc.pep", "export foo(): int { return 1; }"),
        ("dd.pep", "export bar(): int { return 2; }"),
        ("main.pep", "import \"a\";\ntest(): int { return 0; }"),
    ];
    let err = error("flip", &files);
    assert!(err.contains("depends on itself through an import that is ambiguous"), "{}", err);
    assert!(!err.contains("did not settle"), "{}", err);
}

#[test]
fn file_import_may_spell_the_extension() {
    let files = [("lib.pep", "export f(): int { return 9; }"), ("main.pep", "import \"lib.pep\";\ntest(): int { return f(); }")];
    assert_eq!(run("with_extension", &files), 9);
}

#[test]
fn an_editor_warns_on_modules_it_cannot_find() {
    // An editor knows no `-I` directories: `util`, next to `geo`, is found
    // only by the compile that passes `-I`, so the editor warns rather than
    // errs. A local module folder is always found.
    let dir = std::env::temp_dir().join(format!("pepper_modules_editor_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("geo/local")).unwrap();
    std::fs::create_dir_all(dir.join("util")).unwrap();
    std::fs::write(dir.join("util/module.pep"), "export one(): int { return 1; }").unwrap();
    std::fs::write(dir.join("geo/local/module.pep"), "export three(): int { return 3; }").unwrap();
    let module = dir.join("geo/module.pep");
    std::fs::write(&module, "import util;\nimport \"local\";\nexport two(): int { return three() - 1; }").unwrap();
    let search_paths = pepper_driver::imports::search_paths(&[], &[]);
    let program =
        pepper_sema::program::load_file(&module, &[], &search_paths, pepper_sema::program::Mode::Lenient).expect("load");
    let errors: Vec<(&str, bool)> = program.errors.iter().map(|e| (e.message.as_str(), e.unresolved)).collect();
    assert_eq!(errors.len(), 1, "{:?}", errors);
    assert!(errors[0].0.starts_with("cannot find module 'util'") && errors[0].1, "{:?}", errors);
}

#[test]
fn a_re_export_chain_may_bounce_between_files_of_a_module() {
    let files = [
        (
            "m/module.pep",
            "import \"a\";\nf(): int { return 3; }\nexport f as m1;\nexport a1 as m2;\nexport a2 as m3;",
        ),
        ("m/a.pep", "import \"module\";\nexport m1 as a1;\nexport m2 as a2;"),
        ("main.pep", "import m;\ntest(): int { return m.m3(); }"),
    ];
    assert_eq!(run("bounce", &files), 3);
}

#[test]
fn an_unresolved_import_is_reported_once() {
    let err = error("unresolved_once", &[("main.pep", "import nosuch;\nf(p: nosuch.Point): int { return 0; }\ntest(): int { return 0; }")]);
    assert!(err.contains("cannot find module 'nosuch'"), "{}", err);
    assert!(!err.contains("not an imported module"), "{}", err);
}

#[test]
fn a_file_import_spelled_with_its_extension_is_named_once_in_errors() {
    let err = error("missing_with_extension", &[("main.pep", "import \"util.pep\";\ntest(): int { return 0; }")]);
    assert!(err.contains("cannot find \"util.pep\" or the module folder \"util\" next to this file"), "{}", err);
}

#[test]
fn forced_module_bare_re_exports_are_visible() {
    let files = [
        ("counter/module.pep", "import \"impl\";\nexport step;\nhelper(): int { return 5; }\nexport helper;"),
        ("counter/impl.pep", "export step(): int { return 2; }"),
        ("main.pep", "test(): int { return step() + helper(); }"),
    ];
    assert_eq!(run_with("forced_bare_reexport", &files, &["--import", "counter"]), 7);
}

#[test]
fn a_concrete_override_may_sit_next_to_an_imported_generic() {
    let files = [
        ("geo/module.pep", "export pick<T>(x: T): int { return 1; }"),
        ("main.pep", "import [pick] from geo;\npick<int>(x: int): int { return 40; }\ntest(): int { return pick<int>(3) + pick<bool>(true); }"),
    ];
    assert_eq!(run("override_imported", &files), 41);
}

#[test]
fn a_field_does_not_hide_a_module_in_a_type() {
    let main = r#"
import geometry as g;
struct S {
    var g: int;
    at(): g.Point { return g.make(g, 2); }
}
test(): int { var s = S(); s.g = 4; return s.at().x; }
"#;
    // Only the return type needs the module there; whatever the expression
    // makes of the field, the type must not be reported.
    if let Err(err) = compile("field_type", &with_geometry(main)) {
        assert!(!err.contains("'g' is not an imported module"), "{}", err);
    }
    let main = r#"
import geometry as g;
struct S {
    var g: int;
    at(p: g.Point): int { return p.x + g; }
}
test(): int { var s = S(); s.g = 4; var p = g.make(3, 0); return s.at(p); }
"#;
    assert_eq!(run("field_type_ok", &with_geometry(main)), 7);
}

#[test]
fn a_member_product_statement_is_an_expression() {
    let main = r#"
struct P { var b: int; }
test(): int {
    var a = P();
    a.b = 3;
    var c = 2;
    a.b * c;
    return c;
}
"#;
    assert_eq!(run("product_statement", &[("main.pep", main)]), 2);
}

#[test]
fn code_this_platform_drops_may_name_exports_it_lacks() {
    // Never true: both the declaration and its call are dropped everywhere.
    let never = "[Target(OS(Windows) && OS(Linux))]";
    let files = [
        ("plat/module.pep", format!("{} export only_there(): int {{ return 1; }}\nexport always(): int {{ return 2; }}", never)),
        (
            "main.pep",
            format!("import plat;\n{} use_it(): int {{ return plat.only_there(); }}\ntest(): int {{ return plat.always(); }}", never),
        ),
    ];
    let files: Vec<(&str, &str)> = files.iter().map(|(p, t)| (*p, t.as_str())).collect();
    assert_eq!(run("platform_dropped", &files), 2);
}

#[test]
fn an_override_of_an_aliased_generic_takes_the_generic_name() {
    let files = [
        ("geo/module.pep", "export pick<T>(x: T): int { return 1; }"),
        ("main.pep", "import [pick as choose] from geo;\nchoose<int>(x: int): int { return 40; }\ntest(): int { return choose<int>(3); }"),
    ];
    assert_eq!(run("override_alias", &files), 40);
}

#[test]
fn an_imported_type_specializes_an_extension() {
    let files = [
        ("geo/module.pep", "export struct Point { var x: int; }"),
        (
            "main.pep",
            "import [Point as Pt] from geo;\nstruct Box<T> { var v: int; }\n\
             extend Box<Pt> { make(): Pt { var p = Pt(); p.x = 8; return p; } }\n\
             test(): int { var b = Box<Pt>(); return b.make().x; }",
        ),
    ];
    // `Pt` is the import, not a generic parameter: the extension is of
    // `Box<Point>`, and `Pt` inside it is `Point`, so `make` returns a
    // struct reference.
    assert_eq!(run("extend_import", &files), 8);
}

#[test]
fn a_re_export_through_an_unresolved_import_is_reported_once() {
    let err = error("reexport_unresolved", &[("main.pep", "import nosuch;\nexport nosuch.Point as P;\ntest(): int { return 0; }")]);
    assert!(err.contains("cannot find module 'nosuch'"), "{}", err);
    assert!(!err.contains("not an imported module"), "{}", err);
}

#[test]
fn imports_come_before_declarations() {
    let files = [
        ("util.pep", "export f(): int { return 1; }"),
        ("main.pep", "test(): int { return f(); }\nimport \"util\";"),
    ];
    let err = error("imports_first", &files);
    assert!(err.contains("main.pep:2:1: error: imports must come before all declarations"), "{}", err);
}

#[test]
fn a_member_of_a_qualified_generic_type() {
    let files = [
        ("r/module.pep", "export struct Box<T> { var v: T; static make(): int { return 6; } }"),
        ("main.pep", "import r as q;\ntest(): int { return q.Box<int>.make(); }"),
    ];
    // Parses and links; a static on a generic struct is otherwise ordinary.
    compile("qualified_generic_member", &files).expect("links and checks");
}

#[test]
fn extend_with_an_unimported_type_is_rejected() {
    let files = [
        ("geo/module.pep", "export struct Point { var x: int; }"),
        ("lib.pep", "import geo;\nexport f(): int { return 0; }"),
        ("main.pep", "import \"lib\";\nstruct Box<T> { var v: int; }\nextend Box<Point> { g(): int { return 1; } }\ntest(): int { return f(); }"),
    ];
    let err = error("extend_unimported", &files);
    assert!(err.contains("'Point' is exported by") && err.contains("which this file does not import"), "{}", err);
}

#[test]
fn an_override_does_not_unlock_the_generic_name() {
    let files = [
        ("geo/module.pep", "export pick<T>(x: T): int { return 1; }"),
        (
            "main.pep",
            "import [pick as choose] from geo;\nchoose<int>(x: int): int { return 40; }\ntest(): int { return pick<bool>(true); }",
        ),
    ];
    let err = error("override_leak", &files);
    assert!(err.contains("'pick' is exported by") && err.contains("which this file does not import"), "{}", err);
}

#[test]
fn a_name_may_not_be_both_a_module_and_a_symbol() {
    let files = [
        ("m/module.pep", "export f(): int { return 1; }"),
        ("n/module.pep", "export m(): int { return 2; }"),
        ("main.pep", "import m;\nimport [m] from n;\ntest(): int { return m.f() + m(); }"),
    ];
    let err = error("module_and_symbol", &files);
    assert!(err.contains("'m' is imported both as a module and as a symbol"), "{}", err);
}

#[test]
fn code_this_platform_drops_may_use_unqualified_imports() {
    let never = "[Target(OS(Windows) && OS(Linux))]";
    let main = format!(
        "import [always] from plat;\n\
         {never} use_it(): int {{ return always(); }}\n\
         struct S {{ var n: int; {never} m(): int {{ return always(); }} }}\n\
         test(): int {{ {never} {{ always(); }} return always(); }}"
    );
    let files = [("plat/module.pep", "export always(): int { return 2; }"), ("main.pep", main.as_str())];
    assert_eq!(run("platform_unqualified", &files), 2);
}

#[test]
fn a_dropped_own_declaration_does_not_hide_a_missing_import() {
    let never = "[Target(OS(Windows) && OS(Linux))]";
    let main = format!("import \"lib\";\n{never} helper(): int {{ return 5; }}\ntest(): int {{ return helper() + user(); }}");
    let files = [
        ("other.pep", "export helper(): int { return 1; }"),
        ("lib.pep", "import \"other\";\nexport user(): int { return helper(); }"),
        ("main.pep", main.as_str()),
    ];
    let err = error("dropped_own", &files);
    assert!(err.contains("'helper' is exported by") && err.contains("which this file does not import"), "{}", err);
}

#[test]
fn an_unresolved_forced_import_is_an_error() {
    let err = match compile_with("forced_missing", &[("main.pep", "test(): int { return 0; }")], &["--import", "no_such_module"]) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e,
    };
    assert!(err.contains("--import no_such_module: cannot find module 'no_such_module'"), "{}", err);
}

#[test]
fn a_hidden_extension_method_does_not_capture_an_imported_name() {
    let files = [
        ("geo/module.pep", "export area2(): int { return 7; }"),
        (
            "c/module.pep",
            "import geo as g;\nimport \"other\";\nexport struct Counter { var n: int; f(): int { return g.area2(); } }",
        ),
        ("c/other.pep", "import \"module\";\nextend Counter { area2(): int { return 100; } }"),
        ("main.pep", "import c;\ntest(): int { var k = c.Counter(); return k.f(); }"),
    ];
    // `g.area2` is geo's export, mangled apart from the method `area2`.
    assert_eq!(run("hidden_capture", &files), 7);
}

#[test]
fn platform_specific_imports_and_re_exports() {
    let never = "[Target(OS(Windows) && OS(Linux))]";
    let module = format!("import \"impl\";\n{never} export only_there as there;\nexport always(): int {{ return 2; }}");
    let main = format!(
        "import plat;\n{never} import [there] from plat;\n{never} import nowhere;\n\
         {never} use_it(): int {{ return there(); }}\ntest(): int {{ return plat.always(); }}"
    );
    let files = [
        ("plat/impl.pep", format!("{never} export only_there(): int {{ return 1; }}")),
        ("plat/module.pep", module),
        ("main.pep", main),
    ];
    let files: Vec<(&str, &str)> = files.iter().map(|(p, t)| (*p, t.as_str())).collect();
    assert_eq!(run("platform_imports", &files), 2);
}

#[test]
fn a_missing_whole_file_import_is_reported_once() {
    let err = error("missing_whole_file", &[("main.pep", "import \"missing\";\nexport foo;\ntest(): int { return 0; }")]);
    assert!(err.contains("cannot find \"missing.pep\""), "{}", err);
    assert!(!err.contains("cannot export"), "{}", err);
}

#[test]
fn a_missing_file_import_is_not_downgraded_for_the_editor() {
    let program = load_lenient(
        "editor_missing_file",
        &[("main.pep", "import \"helperz\";\nimport nowhere;\nf(): int { return 0; }")],
    );
    let flags: Vec<(bool, &str)> = program.errors.iter().map(|e| (e.unresolved, e.message.as_str())).collect();
    assert!(flags.iter().any(|(u, m)| !u && m.contains("helperz")), "{:?}", flags);
    assert!(flags.iter().any(|(u, m)| *u && m.contains("nowhere")), "{:?}", flags);
}

#[test]
fn a_module_imports_a_module_nested_in_its_folder() {
    let files = [
        ("a/module.pep", "import \"sub\" as sub;\nexport f(): int { return sub.g(); }"),
        ("a/sub/module.pep", "export g(): int { return 4; }"),
        ("main.pep", "import a;\ntest(): int { return a.f(); }"),
    ];
    assert_eq!(run("nested_module", &files), 4);
}

#[test]
fn platform_dropped_members_neither_shadow_nor_capture() {
    let never = "[Target(OS(Windows) && OS(Linux))]";
    // A dropped extension method `ar` does not shadow the alias `ar`.
    let module = format!(
        "import [area2 as ar] from geo;\nexport struct Counter {{ var n: int; f(): int {{ return ar(); }} }}\n\
         {never} extend Counter {{ ar(): int {{ return 100; }} }}"
    );
    let files = [
        ("geo/module.pep", "export area2(): int { return 7; }".to_string()),
        ("c/module.pep", module),
        ("main.pep", "import c;\ntest(): int { var k = c.Counter(); return k.f(); }".to_string()),
    ];
    let files: Vec<(&str, &str)> = files.iter().map(|(p, t)| (*p, t.as_str())).collect();
    assert_eq!(run("dropped_member_alias", &files), 7);

    // A dropped extension method `area2` does not capture `g.area2`.
    let other = format!("import \"module\";\n{never} extend Counter {{ area2(): int {{ return 100; }} }}");
    let files = [
        ("geo/module.pep", "export area2(): int { return 7; }".to_string()),
        (
            "c/module.pep",
            "import geo as g;\nimport \"other\";\nexport struct Counter { var n: int; f(): int { return g.area2(); } }".to_string(),
        ),
        ("c/other.pep", other),
        ("main.pep", "import c;\ntest(): int { var k = c.Counter(); return k.f(); }".to_string()),
    ];
    let files: Vec<(&str, &str)> = files.iter().map(|(p, t)| (*p, t.as_str())).collect();
    assert_eq!(run("dropped_member_capture", &files), 7);
}

#[test]
fn malformed_target_on_imports_and_re_exports_is_an_error() {
    let files = [
        ("geo/module.pep", "export g(): int { return 7; }"),
        ("main.pep", "[Target(OS(Windoze))] import geo;\ntest(): int { return geo.g(); }"),
    ];
    let err = error("bad_target_import", &files);
    assert!(err.contains("Windoze"), "{}", err);
    let files = [("main.pep", "helper(): int { return 1; }\n[Target(Bogus(1))] export helper as h;\ntest(): int { return 0; }")];
    let err = error("bad_target_reexport", &files);
    assert!(err.contains("Bogus"), "{}", err);
}

#[test]
fn an_unaliased_import_is_not_captured_by_a_hidden_extension_method() {
    let files = [
        ("geo/module.pep", "export area2(): int { return 7; }"),
        (
            "c/module.pep",
            "import [area2] from geo;\nimport \"other\";\nexport struct Counter { var n: int; f(): int { return area2(); } }",
        ),
        ("c/other.pep", "import \"module\";\nextend Counter { area2(): int { return 100; } }"),
        ("main.pep", "import c;\ntest(): int { var k = c.Counter(); return k.f(); }"),
    ];
    assert_eq!(run("unaliased_capture", &files), 7);
}

#[test]
fn generic_calls_and_prelude_names_are_not_captured_by_hidden_methods() {
    // `hash<int>(x)` and `twice<int>(x)` are never bound to a method, even
    // though a private extension in another file adds `hash` and `twice`.
    let files = [
        ("util.pep", "export twice<T>(x: T): int { return 2; }"),
        (
            "point.pep",
            "import \"util\";\nexport struct Point { var x: int; key(): int { return (hash<int>(x) == hash<int>(x) ? 1 : 0) + twice<int>(x); } }",
        ),
        ("ext.pep", "import \"point\";\nextend Point { hash(): ulong { return 1; } twice(): int { return 100; } }"),
        ("main.pep", "import \"point\";\nimport \"ext\";\ntest(): int { var p = Point(); return p.key(); }"),
    ];
    assert_eq!(run("generic_not_captured", &files), 3);
}

#[test]
fn a_split_c_style_declaration_is_still_exported() {
    let files = [
        ("lib.pep", "export struct P { var x: int; }\nexport P\nmake() { var p = P(); p.x = 7; return p; }"),
        ("main.pep", "import \"lib\";\ntest(): int { return make().x; }"),
    ];
    assert_eq!(run("split_c_style", &files), 7);
}

#[test]
fn a_file_outside_any_module_imports_only_its_folder() {
    let files = [
        ("common.pep", "export seven(): int { return 7; }"),
        ("app/lib.pep", "import \"../common\";\nexport f(): int { return seven(); }"),
        ("main.pep", "import \"app/lib\";\ntest(): int { return f(); }"),
    ];
    let err = error("outside_folder", &files);
    assert!(err.contains("\"../common.pep\" is outside this file's folder"), "{}", err);
}

#[test]
fn values_do_not_hide_imports_in_types_or_generic_calls() {
    let files = [
        (
            "g/module.pep",
            "export pick<T>(x: T): T { return x; }\nexport struct Vec { var n: int; }",
        ),
        (
            "main.pep",
            "import [pick as choose, Vec as V] from g;\nimport g;\n\
             struct S { var v: int; choose(): int { return 1; } pick(): int { return 2; }\n\
                 f(): int { return choose<int>(3) + g.pick<int>(4); } }\n\
             h(V: int, w: V): int { var choose = 2; return choose<int>(5) + choose + V + w.n; }\n\
             test(): int { var s = S(); var w = V(); w.n = 10; return s.f() + h(100, w); }",
        ),
    ];
    // 3 + 4 + (5 + 2 + 100 + 10)
    assert_eq!(run("types_not_hidden", &files), 124);
}

#[test]
fn an_override_exported_under_an_alias_exports_the_generic() {
    let files = [
        ("g/module.pep", "export pick<T>(x: T): T { return x; }"),
        ("b.pep", "import [pick as choose] from g;\nexport choose<int>(x: int): int { return x + 100; }"),
        ("main.pep", "import \"b\";\nimport [pick] from g;\ntest(): int { return pick<int>(3); }"),
    ];
    assert_eq!(run("override_export_alias", &files), 103);
}

#[test]
fn a_chain_of_exported_overrides_settles() {
    let files = [
        ("c.pep", "export pick<T>(x: T): int { return 1; }"),
        ("b.pep", "import [pick as p1] from \"c\";\nexport p1<int>(x: int): int { return 2; }"),
        ("a.pep", "import [pick as p2] from \"b\";\nexport p2<String>(x: String): int { return 3; }"),
        ("d.pep", "import [pick as p3] from \"a\";\nexport p3<ulong>(x: ulong): int { return 4; }"),
        ("main.pep", "import [pick] from \"d\";\nimport \"b\";\nimport \"a\";\ntest(): int { return pick<int>(0); }"),
    ];
    assert_eq!(run("override_chain", &files), 2);
}

#[test]
fn a_module_folder_may_be_imported_with_the_extension_spelled() {
    let files = [
        ("./geo/module.pep", "export f(): int { return 5; }"),
        ("main.pep", "import \"geo.pep\" as g;\ntest(): int { return g.f(); }"),
    ];
    assert_eq!(run("folder_with_extension", &files), 5);
}

#[test]
fn errors_name_a_module_folder_as_a_folder() {
    let files = [
        ("./vec/module.pep", "export struct Vec3 { var x: int; }"),
        ("main.pep", "import [Vec2] from \"vec\";\ntest(): int { return 0; }"),
    ];
    let err = error("folder_named", &files);
    assert!(err.contains("'Vec2' is not exported by the module folder \"vec\""), "{}", err);
}

#[test]
fn constructors_and_destructors_are_linked_and_checked_whatever_their_attributes() {
    // Platform selection keeps a constructor or destructor whatever its
    // `[Target]`, so its imports are rewritten and its references checked.
    let never = "[Target(OS(Windows) && OS(Linux))]";
    let main = format!("import geo;\nstruct S {{ var v: int; {never} construct() {{ v = geo.seven(); }} }}\ntest(): int {{ var s = S(); return s.v; }}");
    let files = [("geo/module.pep", "export seven(): int { return 7; }"), ("main.pep", main.as_str())];
    compile("ctor_target_linked", &files).expect("links");

    let main = format!("import \"lib\";\nstruct S {{ var v: int; {never} construct() {{ v = secret(); }} }}\ntest(): int {{ return 0; }}");
    let files = [("lib.pep", "secret(): int { return 9; }\nexport f(): int { return 0; }"), ("main.pep", main.as_str())];
    let err = error("ctor_target_checked", &files);
    assert!(err.contains("'secret' is private to"), "{}", err);
}

#[test]
fn an_override_of_a_prelude_alias_is_exported_under_the_generic() {
    let files = [
        ("alt/module.pep", "export pick<T>(x: T): int { return 1; }\nexport pick as choose;"),
        ("lib.pep", "export choose<int>(x: int): int { return 7; }"),
        ("main.pep", "import \"lib\";\ntest(): int { return pick<int>(3); }"),
    ];
    assert_eq!(run_with("prelude_alias_override", &files, &["--import", "alt"]), 7);
}

#[test]
fn a_file_named_module_is_described_as_a_file() {
    let files = [
        ("./geo/module.pep", "import \"impl\";\nexport f(): int { return 1; }"),
        ("./geo/impl.pep", "import [nope] from \"module.pep\";\nexport g(): int { return 0; }"),
        ("./mymodule/module.pep", "export h(): int { return 2; }"),
        ("main.pep", "import \"geo\";\nimport [nope2] from \"mymodule\";\ntest(): int { return 0; }"),
    ];
    let err = error("module_named_file", &files);
    assert!(err.contains("'nope' is not exported by \"module.pep\""), "{}", err);
    assert!(err.contains("'nope2' is not exported by the module folder \"mymodule\""), "{}", err);
}

#[test]
fn an_override_of_the_files_own_generic_keeps_its_name() {
    // A prelude alias named `pick` does not rename lib's own `pick<int>`.
    let files = [
        ("alt/module.pep", "export foo<T>(x: T): int { return 1; }\nexport foo as pick;"),
        ("lib.pep", "export pick<T>(x: T): int { return 2; }\nexport pick<int>(x: int): int { return 3; }"),
        ("main.pep", "import [pick] from \"lib\";\ntest(): int { return pick<int>(3); }"),
    ];
    assert_eq!(run_with("own_generic_override", &files, &["--import", "alt"]), 3);
}

#[test]
fn a_forced_import_replaces_a_runtime_export() {
    let files = [
        ("quiet/module.pep", "export assert(condition: bool, msg: __ptr<char>): void { }"),
        ("main.pep", "test(): int { assert(false, \"x\"); return 7; }"),
    ];
    assert_eq!(run_with("forced_replaces_runtime", &files, &["--import", "quiet"]), 7);
}

#[test]
fn a_forced_import_replaces_only_the_overloads_it_declares() {
    // The replacement takes the runtime's `assert(bool, String)` member; a
    // `String` message calls it, while the runtime's `__ptr<char>` member
    // (which a literal message would pick) stays in the set.
    let files = [
        ("quiet/module.pep", "export assert(condition: bool, message: String): void { }"),
        ("main.pep", "test(): int { var m = String(\"x\"); assert(false, m); return 7; }"),
    ];
    assert_eq!(run_with("forced_string_assert", &files, &["--import", "quiet"]), 7);
}

#[test]
fn a_forced_file_import_may_spell_the_extension() {
    let files = [("main.pep", "test(): int { return val(); }")];
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = write_tree("forced_with_extension", &files);
    std::fs::write(dir.join("deps").join("util.pep"), "export val(): int { return 4; }").unwrap();
    let main_path = dir.join("main.pep");
    let deps = dir.join("deps");
    let options = pepper_driver::Options::parse_from([
        "pepper",
        main_path.to_str().unwrap(),
        "-I",
        deps.to_str().unwrap(),
        "--import",
        "util.pep",
    ]);
    pepper_driver::compiler::compile(&options, "main").expect("`--import util.pep` resolves util.pep");
}

#[test]
fn a_value_does_not_hide_an_unimported_type() {
    let files = [
        ("lib.pep", "export struct Point { var x: int; }\nexport make(): Point { return Point(); }"),
        ("main.pep", "import [make] from \"lib\";\nf(Point: int): int { var p: Point = make(); return p.x + Point; }\ntest(): int { return f(1); }"),
    ];
    let err = error("value_hides_type", &files);
    assert!(err.contains("'Point' is exported by") && err.contains("which this file does not import"), "{}", err);
}

#[test]
fn a_forced_modules_other_files_share_its_exemptions() {
    let files = [
        ("quiet/module.pep", "import \"impl\";\nexport assert;"),
        ("quiet/impl.pep", "export assert(condition: bool, msg: __ptr<char>): void { }"),
        ("main.pep", "test(): int { assert(false, \"x\"); return 7; }"),
    ];
    assert_eq!(run_with("forced_module_files", &files, &["--import", "quiet"]), 7);
}

#[test]
fn a_forced_modules_other_files_stay_private() {
    // Only module.pep's exports are visible everywhere; impl.pep's own
    // exports are not, though they may still replace runtime exports.
    let files = [
        ("counter/module.pep", "import \"impl\";\nexport step as increment_size;"),
        ("counter/impl.pep", "export step(): int { return 2; }\nexport secret(): int { return 9; }"),
        ("main.pep", "test(): int { return increment_size() + secret(); }"),
    ];
    let err = match compile_with("forced_parts_private", &files, &["--import", "counter"]) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e,
    };
    assert!(err.contains("'secret' is exported by") && err.contains("which this file does not import"), "{}", err);
}

#[test]
fn an_unresolved_forced_import_names_what_was_searched() {
    let err = match compile_with("forced_missing_ext", &[("main.pep", "test(): int { return 0; }")], &["--import", "nosuch.pep"]) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e,
    };
    assert!(err.contains("cannot find module 'nosuch' (no nosuch/module.pep) or file nosuch.pep in"), "{}", err);
}

#[test]
fn a_forced_alias_may_not_replace_a_runtime_export() {
    // The runtime's own files would keep calling their `assert`, so only a
    // declaration under the name itself may replace it.
    let files = [
        ("quiet/module.pep", "quiet_assert(condition: bool, msg: __ptr<char>): void { }\nexport quiet_assert as assert;"),
        ("main.pep", "test(): int { assert(false, \"x\"); return 7; }"),
    ];
    let err = match compile_with("forced_alias_replaces", &files, &["--import", "quiet"]) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e,
    };
    assert!(err.contains("a forced import cannot replace 'assert' with an alias"), "{}", err);
}

#[test]
fn a_keyword_prefixed_module_qualifies_local_and_field_types() {
    let files = [
        ("ordered/module.pep", "export struct Socket { var fd: int; }"),
        ("externals/module.pep", "export struct Pipe { var fd: int; }"),
        (
            "main.pep",
            "import ordered;\nimport externals;\nstruct H { externals.Pipe p; }\n\
             test(): int { ordered.Socket s = ordered.Socket(); s.fd = 4; var h = H(); h.p = externals.Pipe(); h.p.fd = 3; return s.fd + h.p.fd; }",
        ),
    ];
    assert_eq!(run("keyword_prefixed_modules", &files), 7);
}

#[test]
fn a_module_nested_in_a_forced_module_has_its_own_exports() {
    let files = [
        ("alt/module.pep", "import \"sub\" as s;\nexport f(): int { return s.g(); }"),
        ("alt/sub/module.pep", "export g(): int { return 1; }\nexport assert(condition: bool, msg: __ptr<char>): void { }"),
        ("main.pep", "test(): int { return f(); }"),
    ];
    // `sub` is a module of its own, not part of the forced one, so its
    // `assert` is its own and replaces nothing.
    assert_eq!(run_with("forced_nested_module", &files, &["--import", "alt"]), 1);
}

#[test]
fn a_file_may_call_its_own_concrete_generic() {
    assert_eq!(run("own_concrete_generic", &[("main.pep", "foo<int>(x: int): int { return x + 1; }\ntest(): int { return foo<int>(4); }")]), 5);
}

#[test]
fn concrete_overloads_in_two_files_are_each_their_own() {
    let files = [
        ("lib.pep", "conv<long>(x: long): long { return x + 100; }\nexport usel(): long { return conv<long>(1); }"),
        ("main.pep", "import \"lib\";\nconv<int>(x: int): int { return x + 1; }\ntest(): int { return conv<int>(3) + (usel() as int); }"),
    ];
    assert_eq!(run("two_file_overloads", &files), 105);
}

#[test]
fn an_own_concrete_generic_beside_a_plain_function_elsewhere() {
    // lib's plain `conv` is no generic base, so main's `conv<int>` stays its
    // own; the runtime's private `hex` does not block a user's `hex<int>`.
    let files = [
        ("lib.pep", "conv(x: ulong): int { return 100; }\nexport seven(): int { return conv(1 as ulong) - 93; }"),
        ("main.pep", "import \"lib\";\nconv<int>(x: int): int { return x + 1; }\ntest(): int { return conv<int>(6) + seven(); }"),
    ];
    assert_eq!(run("own_concrete_beside_plain", &files), 14);
    // The runtime's private, non-generic `hex` is no generic base either.
    compile("own_hex", &[("main.pep", "hex<int>(x: int): int { return x + 1; }\ntest(): int { return hex<int>(6); }")])
        .expect("passes linking and visibility");
}

#[test]
fn an_uncalled_override_of_a_private_generic_is_blocked() {
    // main never calls `conv<int>`, but declaring it would still replace
    // the instantiation lib's `seven` uses (8 instead of 7).
    let files = [
        ("lib.pep", "conv<T>(x: T): int { return 0; }\nexport seven(): int { return conv<int>(7) + 7; }"),
        ("main.pep", "import [seven] from \"lib\";\nconv<int>(x: int): int { return 1; }\ntest(): int { return seven(); }"),
    ];
    let err = error("uncalled_private_override", &files);
    assert!(err.contains("'conv' is private to") && err.contains("lib.pep"), "{}", err);
    assert_eq!(err.matches("error:").count(), 1, "{}", err);
}

#[test]
fn a_blocked_own_override_names_the_other_file() {
    let files = [
        ("lib.pep", "conv<T>(x: T): T { return x; }\nexport seven(): int { return conv<int>(7); }"),
        ("main.pep", "import \"lib\";\nconv<int>(x: int): int { return x + 1; }\ntest(): int { return conv<int>(6) + seven(); }"),
    ];
    let err = error("blocked_override_names_other", &files);
    assert!(err.contains("'conv' is private to") && err.contains("lib.pep"), "{}", err);
    assert!(!err.contains("is private to C:") || !err.contains("main.pep; declare"), "{}", err);
}

#[test]
fn private_names_are_per_file() {
    // Each file's private function, struct (with a method), and module
    // variable are its own, whatever other files declare.
    let files = [
        (
            "lib.pep",
            "helper(): int { return 1; }\nstruct Cell { var v: int; int get() { return v + base; } }\nconst base = 10;\n\
             export from_lib(): int { var c = Cell(); c.v = helper(); return c.get(); }",
        ),
        (
            "main.pep",
            "import \"lib\";\nhelper(): int { return 2; }\nstruct Cell { var v: int; int get() { return v * base; } }\nconst base = 100;\n\
             test(): int { var c = Cell(); c.v = helper(); return c.get() + from_lib(); }",
        ),
    ];
    // main: 2 * 100; lib: 1 + 10.
    assert_eq!(run("private_names_per_file", &files), 211);
}

#[test]
fn private_names_of_same_named_files_in_different_modules_are_distinct() {
    // `a/util.pep` and `b/util.pep` share a file name; their namespaces are
    // the module-qualified paths `a/util` and `b/util`.
    let files = [
        ("a/module.pep", "import \"util\";\nexport a_value(): int { return from_a_util(); }"),
        ("a/util.pep", "helper(): int { return 1; }\nexport from_a_util(): int { return helper(); }"),
        ("b/module.pep", "import \"util\";\nexport b_value(): int { return from_b_util(); }"),
        ("b/util.pep", "helper(): int { return 2; }\nexport from_b_util(): int { return helper(); }"),
        ("main.pep", "import a;\nimport b;\ntest(): int { return a.a_value() * 10 + b.b_value(); }"),
    ];
    assert_eq!(run("same_named_files", &files), 12);
}

#[test]
fn a_private_name_may_repeat_an_export_of_another_file() {
    // main's private `twice` shadows nothing and is shadowed by nothing: lib
    // keeps calling its own exported `twice`.
    let files = [
        ("lib.pep", "export twice(x: int): int { return x * 2; }\nexport four(): int { return twice(2); }"),
        ("main.pep", "import [four] from \"lib\";\ntwice(x: int): int { return x + x + 1; }\ntest(): int { return twice(3) * 10 + four(); }"),
    ];
    assert_eq!(run("private_repeats_export", &files), 74);
}

#[test]
fn a_reexported_private_declaration_is_reached_under_its_file() {
    // `export secret as shown` publishes lib's private `secret`; main's own
    // private `secret` stays distinct.
    let files = [
        ("lib.pep", "secret(): int { return 5; }\nexport secret as shown;"),
        ("main.pep", "import \"lib\";\nsecret(): int { return 7; }\ntest(): int { return shown() * 10 + secret(); }"),
    ];
    assert_eq!(run("reexported_private", &files), 57);
}

#[test]
fn a_struct_override_beside_its_private_struct_is_an_override() {
    // lib's `Point` is mangled; `describe<Point>` must still name it, or
    // it would read as a second generic and `describe<Point>(...)` would
    // call `describe<T>`.
    let lib = "struct Point { var x: int; }\ndescribe<T>(v: T): int { return 1; }\n\
               describe<Point>(p: Point): int { return 2; }\n\
               export run(): int { return describe<int>(5) * 10 + describe<Point>(Point()); }";
    let files = [("lib.pep", lib), ("main.pep", "import \"lib\";\ntest(): int { return run(); }")];
    assert_eq!(run("struct_override_private", &files), 12);
}

#[test]
fn private_declarations_are_local_to_the_object() {
    // A mangled name is never a global symbol: nothing else can name it,
    // and ELF linkers would read `helper@lib` as a symbol version.
    let files = [
        ("lib.pep", "helper(): int { return 1; }\nconst count = 2;\nexport api(): int { return helper() + count; }"),
        ("main.pep", "import \"lib\";\ntest(): int { return api(); }"),
    ];
    let mut module = compile("private_linkage", &files).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.generate(&mut module).expect("generate");
    let internal = inkwell::module::Linkage::Internal;
    assert_eq!(generator.module.get_function("helper@lib").expect("helper").get_linkage(), internal);
    assert_eq!(generator.module.get_global("count@lib").expect("count").get_linkage(), internal);
    // So is an export of a file other than the root's: importers name it
    // by its mangled name, inside this one object.
    assert_eq!(generator.module.get_function("api@lib").expect("api").get_linkage(), internal);
}

#[test]
fn an_exported_generic_keeps_its_name_beside_a_private_struct_override() {
    // `describe<Point>` after the exported `describe<T>` shares its name:
    // the generic stays exported, and the override stays an override.
    let lib = "struct Point { var x: int; }\nexport describe<T>(v: T): int { return 1; }\n\
               describe<Point>(p: Point): int { return 2; }\n\
               export run(): int { return describe<Point>(Point()); }";
    let files = [("lib.pep", lib), ("main.pep", "import \"lib\";\ntest(): int { return describe<int>(3) * 10 + run(); }")];
    assert_eq!(run("exported_generic_private_override", &files), 12);
}

#[test]
fn a_constructor_error_quotes_a_private_struct_as_written() {
    let files = [
        ("lib.pep", "struct Point { var x: int; construct(this.y = 0) {} }\nexport make(): int { var p = Point(); return p.x; }"),
        ("main.pep", "import \"lib\";\ntest(): int { return make(); }"),
    ];
    let err = error("ctor_quotes_private", &files);
    assert!(err.contains("constructor parameter 'this.y' has no matching field in 'Point'"), "{}", err);
}

#[test]
fn private_generics_with_private_overrides_stay_per_file() {
    // Each lib's private `describe<int>` overrides its own private
    // `describe<T>`; neither makes the name public.
    let a = "describe<T>(v: T): int { return 1; }\ndescribe<int>(v: int): int { return 2; }\n\
             export from_a(): int { return describe<int>(0) * 10 + describe<bool>(true); }";
    let b = "describe<T>(v: T): int { return 3; }\ndescribe<int>(v: int): int { return 4; }\n\
             export from_b(): int { return describe<int>(0) * 10 + describe<bool>(true); }";
    let main = "import \"a\";\nimport \"b\";\ntest(): int { return from_a() * 100 + from_b(); }";
    assert_eq!(run("private_overrides_per_file", &[("a.pep", a), ("b.pep", b), ("main.pep", main)]), 2143);
}

/// A struct in one file and an exported extension of it in another.
const EXTENDED: &[(&str, &str)] = &[
    ("types.pep", "export struct S { var x: int; }"),
    ("ext.pep", "import \"types\";\nexport extend S { double(): int { return x * 2; } }"),
];

#[test]
fn an_exported_extension_is_usable_where_its_file_is_imported() {
    let main = "import \"types\";\nimport \"ext\";\ntest(): int { var s = S(); s.x = 4; return s.double(); }";
    let files = [EXTENDED, &[("main.pep", main)]].concat();
    assert_eq!(run("extension_imported", &files), 8);
}

#[test]
fn an_exported_extension_needs_an_import() {
    // ext.pep is in the program, but only through other.pep's import.
    let main = "import \"types\";\nimport \"other\";\ntest(): int { var s = S(); s.x = 4; return s.double() + other(); }";
    let other = "import \"ext\";\nexport other(): int { return 0; }";
    let files = [EXTENDED, &[("other.pep", other), ("main.pep", main)]].concat();
    let err = error("extension_not_imported", &files);
    assert!(err.contains("'double' is declared in an extension in") && err.contains("which this file does not import"), "{}", err);
}

#[test]
fn an_extension_in_another_module_names_the_module_to_import() {
    // main.pep reaches `geo.Pt` only through `other`; `import "geo/ext"`
    // would be rejected (a file of another module), so the error names the
    // module.
    let files = [
        ("geo/module.pep", "import \"ext\";\nexport struct Pt { var x: int; }\nexport origin(): Pt { return Pt(); }"),
        ("geo/ext.pep", "import \"module\";\nexport extend Pt { triple(): int { return x * 3; } }"),
        ("other/module.pep", "import geo;\nexport mk(): geo.Pt { return geo.origin(); }"),
        ("main.pep", "import other;\ntest(): int { return other.mk().triple(); }"),
    ];
    let err = error("extension_module_named", &files);
    assert!(err.contains("which this file does not import; import its module 'geo'"), "{}", err);
}

#[test]
fn a_module_import_reaches_the_extensions_of_its_files() {
    // `import geo` makes the exported extensions of every file of geo
    // usable, as `import "geo/ext"` could not (it is another module's file).
    let files = [
        ("geo/module.pep", "import \"ext\";\nexport struct Pt { var x: int; }"),
        ("geo/ext.pep", "import \"module\";\nexport extend Pt { triple(): int { return x * 3; } }"),
        ("main.pep", "import geo;\ntest(): int { var p = geo.Pt(); p.x = 2; return p.triple(); }"),
    ];
    assert_eq!(run("module_extensions", &files), 6);
}

#[test]
fn an_extension_a_file_cannot_see_may_not_capture_its_calls() {
    // b.pep's extension adds `helper` and `print` to S, but a.pep does not
    // import b.pep: in S's own method, `print(1)` would silently call the
    // method instead of the runtime's `print`.
    let a = "export struct S { var x: int; total(): int { return helper(); } show() { print(1); } }\n\
             export helper(): int { return 1; }";
    let b = "import \"a\";\nexport extend S { helper(): int { return 100; } print(v: int) { } }\nexport touch(): int { return 0; }";
    let main = "import \"a\";\nimport \"b\";\ntest(): int { var s = S(); return s.total() + touch(); }";
    let err = error("hidden_extension_capture", &[("a.pep", a), ("b.pep", b), ("main.pep", main)]);
    // a.pep's own `helper` is mangled apart from the method; the runtime's
    // `print` keeps its name, so the method would capture it.
    assert!(!err.contains("'helper' is declared in an extension in"), "{}", err);
    assert!(err.contains("'print' is declared in an extension in") && err.contains("b.pep"), "{}", err);
}

#[test]
fn only_a_call_can_be_captured_by_an_invisible_extension() {
    // Sema binds a bare call to a method, but a bare value to the field or
    // top-level declaration: a function reference and a global are fine.
    let a = "export struct S { var x: int; total(): int { var f = helper; return f() + count; } }\n\
             export helper(): int { return 1; }\nexport const count = 7;";
    let b = "import \"a\";\nexport extend S { helper(): int { return 100; } count(): int { return 100; } }\nexport touch(): int { return 0; }";
    let main = "import \"a\";\nimport \"b\";\ntest(): int { var s = S(); return s.total() + touch(); }";
    assert_eq!(run("invisible_extension_values", &[("a.pep", a), ("b.pep", b), ("main.pep", main)]), 8);
}

#[test]
fn a_dropped_extension_method_captures_nothing() {
    // The extension's `helper` is not compiled on this platform.
    let dropped = if cfg!(windows) { "[Target(!OS(Windows))]" } else { "[Target(OS(Windows))]" };
    let a = "export struct S { var x: int; total(): int { return helper(); } }\nexport helper(): int { return 1; }";
    let b = format!("import \"a\";\nexport extend S {{ {} helper(): int {{ return 100; }} }}\nexport touch(): int {{ return 0; }}", dropped);
    let main = "import \"a\";\nimport \"b\";\ntest(): int { var s = S(); return s.total() + touch(); }";
    assert_eq!(run("dropped_extension_method", &[("a.pep", a), ("b.pep", &b), ("main.pep", main)]), 1);
}

#[test]
fn an_invisible_extension_does_not_capture_an_exported_function_in_a_trait_default() {
    // S conforms to T in a.pep; b.pep, which a.pep does not import, adds
    // `helper` to S, which T's default `total` would call instead.
    let a = "export trait T { area(): int; total(): int { return helper(); } }\nexport struct S { var x: int; }\n\
             export extend S with T { area(): int { return 0; } }\nexport helper(): int { return 1; }";
    let b = "import \"a\";\nexport extend S { helper(): int { return 100; } }\nexport touch(): int { return 0; }";
    let main = "import \"a\";\nimport \"b\";\ntest(): int { var s = S(); return s.total() + touch(); }";
    // `helper` is a.pep's export, mangled apart from b.pep's method.
    assert_eq!(run("trait_default_capture", &[("a.pep", a), ("b.pep", b), ("main.pep", main)]), 1);
}

#[test]
fn a_trait_default_may_call_the_traits_own_methods() {
    // `area` in T's default is a method of T, whichever file adopts it.
    let a = "export trait T { area(): int; total(): int { return area() + 1; } }";
    let b = "import \"a\";\nexport struct S { var x: int; }\nexport extend S with T { area(): int { return 41; } }";
    let main = "import \"a\";\nimport \"b\";\ntest(): int { var s = S(); return s.total(); }";
    assert_eq!(run("trait_default_own_methods", &[("a.pep", a), ("b.pep", b), ("main.pep", main)]), 42);
}

#[test]
fn an_invisible_extension_through_an_alias_does_not_capture_an_exported_function() {
    // b.pep extends S as `C`; a.pep does not import b.pep.
    let a = "export struct S { var x: int; total(): int { return helper(); } }\nexport helper(): int { return 1; }";
    let b = "import \"a\";\ntype C = S;\nexport extend C { helper(): int { return 100; } }\nexport touch(): int { return 0; }";
    let main = "import \"a\";\nimport \"b\";\ntest(): int { var s = S(); return s.total() + touch(); }";
    assert_eq!(run("alias_extension_capture", &[("a.pep", a), ("b.pep", b), ("main.pep", main)]), 1);
}

#[test]
fn an_invisible_extension_through_a_generic_alias_does_not_capture_an_exported_function() {
    let a = "export struct Box<T> { var v: T; total(): int { return helper(); } }\nexport helper(): int { return 1; }";
    let b = "import \"a\";\ntype B = Box<int>;\nexport extend B { helper(): int { return 100; } }\nexport touch(): int { return 0; }";
    let main = "import \"a\";\nimport \"b\";\ntest(): int { var x = Box<int>(); return x.total() + touch(); }";
    assert_eq!(run("generic_alias_capture", &[("a.pep", a), ("b.pep", b), ("main.pep", main)]), 1);
}

#[test]
fn an_extension_through_an_alias_does_not_capture_a_renamed_import() {
    // In S's method, `hh` is h's `helper`; b.pep's extension (written as
    // `extend C`, C = S, and visible to a.pep) adds a `helper` method.
    let files = [
        ("h.pep", "export helper(): int { return 1; }"),
        ("a.pep", "import [helper as hh] from \"h\";\nimport \"b\";\nexport struct S { var x: int; total(): int { return hh(); } }"),
        ("b.pep", "import \"a\";\ntype C = S;\nexport extend C { helper(): int { return 100; } }"),
        ("main.pep", "import \"a\";\ntest(): int { var s = S(); return s.total(); }"),
    ];
    assert_eq!(run("alias_capture_renamed_import", &files), 1);
}

#[test]
fn an_extension_does_not_capture_a_renamed_import_in_a_trait_default() {
    let files = [
        ("h.pep", "export helper(): int { return 1; }"),
        ("a.pep", "import [helper as hh] from \"h\";\nimport \"b\";\nexport trait T { total(): int { return hh(); } }\n\
                   export struct S { var x: int; }\nexport extend S with T { }"),
        ("b.pep", "import \"a\";\nexport extend S { helper(): int { return 100; } }"),
        ("main.pep", "import \"a\";\ntest(): int { var s = S(); return s.total(); }"),
    ];
    assert_eq!(run("trait_default_capture_renamed", &files), 1);
}

#[test]
fn a_dropped_trait_method_does_not_hide_a_function() {
    // On this platform `area` is not a method of T, so `area()` in the
    // default is the private function.
    let dropped = if cfg!(windows) { "[Target(!OS(Windows))]" } else { "[Target(OS(Windows))]" };
    let a = format!(
        "area(): int {{ return 41; }}\nexport trait T {{ {} area(): int; total(): int {{ return area() + 1; }} }}\n\
         export struct S {{ var x: int; }}\nexport extend S with T {{ }}",
        dropped
    );
    let main = "import \"a\";\ntest(): int { var s = S(); return s.total(); }";
    assert_eq!(run("dropped_trait_method", &[("a.pep", &a), ("main.pep", main)]), 42);
}

#[test]
fn a_method_a_visible_trait_declares_needs_no_import_of_its_extension() {
    // main.pep sees Shape, which declares `area`; the extension that gives
    // S its `area` is in ext.pep, reached only through other.pep.
    let files = [
        ("shape.pep", "export trait Shape { area(): int; }"),
        ("types.pep", "export struct S { var x: int; }"),
        ("ext.pep", "import \"shape\";\nimport \"types\";\nexport extend S with Shape { area(): int { return 7; } }"),
        ("other.pep", "import \"ext\";\nexport other(): int { return 0; }"),
        ("main.pep", "import \"shape\";\nimport \"types\";\nimport \"other\";\ntest(): int { var s = S(); return s.area() + other(); }"),
    ];
    assert_eq!(run("visible_trait_method", &files), 7);
}

#[test]
fn a_generic_or_trait_receiver_is_checked_where_it_is_instantiated() {
    // lib.pep's `measure<X>` and T's default call `area` on receivers whose
    // type lib.pep cannot know; main.pep, which instantiates them, imports
    // the extension.
    let files = [
        ("lib.pep", "export measure<X>(x: X): int { return x.area(); }\nexport trait T { twice(): int { return this.area() * 2; } }"),
        ("types.pep", "export struct S { var x: int; }"),
        ("ext.pep", "import \"types\";\nimport \"lib\";\nexport extend S with T { area(): int { return 5; } }"),
        ("main.pep", "import \"lib\";\nimport \"types\";\nimport \"ext\";\ntest(): int { var s = S(); return measure<S>(s) + s.twice(); }"),
    ];
    assert_eq!(run("generic_receiver", &files), 15);
}

#[test]
fn a_local_shadowing_a_generic_parameter_is_checked() {
    // `x` is a local S here, not the generic parameter.
    let files = [
        ("types.pep", "export struct S { var x: int; }"),
        ("ext.pep", "import \"types\";\nexport extend S { area(): int { return 5; } }"),
        ("other.pep", "import \"ext\";\nexport other(): int { return 0; }"),
        ("main.pep", "import \"types\";\nimport \"other\";\nf<X>(x: X): int { var x = S(); return x.area(); }\n\
                      test(): int { return f<int>(1) + other(); }"),
    ];
    let err = error("local_shadows_generic", &files);
    assert!(err.contains("'area' is declared in an extension in"), "{}", err);
}

#[test]
fn a_call_through_a_visible_trait_needs_no_conformance_in_view() {
    // shape.pep hides Sq and its conformance; main.pep calls `area`
    // through a Shape value, directly or through a re-exporting file.
    let shape = "export trait Shape { area(): int; }\nstruct Sq { var x: int; }\n\
                 extend Sq with Shape { area(): int { return 9; } }\nexport make(): Shape { return Sq(); }";
    let files = [
        ("shape.pep", shape),
        ("main.pep", "import \"shape\";\ntest(): int { var s: Shape = make(); var f = s.area; return s.area() + f(); }"),
    ];
    assert_eq!(run("trait_value_private_conformance", &files), 18);
    let files = [
        ("shape.pep", shape),
        ("factory.pep", "import \"shape\";\nexport Shape;\nexport make;"),
        ("main.pep", "import \"factory\";\ntest(): int { var s: Shape = make(); return s.area(); }"),
    ];
    assert_eq!(run("trait_value_reexported_trait", &files), 9);
}

#[test]
fn values_typed_by_a_generic_parameter_are_checked_where_instantiated() {
    // Locals and closure parameters of type X, declared or inferred.
    let files = [
        ("lib.pep", "export f<X>(x: X): int { var y: X = x; var z = y; var g = (w: X): int => w.double(); return y.double() + z.double() + g(x); }"),
        ("types.pep", "export struct S { var x: int; }"),
        ("ext.pep", "import \"types\";\nexport extend S { double(): int { return 2; } }"),
        ("main.pep", "import \"lib\";\nimport \"types\";\nimport \"ext\";\ntest(): int { return f<S>(S()); }"),
    ];
    assert_eq!(run("generic_locals", &files), 6);
}

#[test]
fn chained_and_struct_generic_receivers_are_checked_where_instantiated() {
    let files = [
        ("lib.pep", "export measure<X>(x: X): int { return x.me().area(); }\n\
                     export struct Box<T> { var v: int; apply(t: T): int { return t.area(); } }"),
        ("types.pep", "export struct S { var x: int; me(): S { return this; } }"),
        ("ext.pep", "import \"types\";\nexport extend S { area(): int { return 5; } }"),
        ("main.pep", "import \"lib\";\nimport \"types\";\nimport \"ext\";\n\
                      test(): int { var s = S(); var b = Box<S>(); return measure<S>(s) + b.apply(s); }"),
    ];
    assert_eq!(run("chained_generic_receivers", &files), 10);
}

/// S, and an exported extension of it that files reach only by importing
/// ext.pep.
const HIDDEN: &[(&str, &str)] = &[
    ("types.pep", "export struct S { var x: int; }"),
    ("ext.pep", "import \"types\";\nexport extend S { hidden(): int { return 2; } }"),
];

#[test]
fn a_generic_binding_ends_with_its_scope() {
    // The inner `s` (or `x`) is generic, but it is out of scope, or
    // shadowed, where `hidden` is called on a plain S.
    for body in [
        "{ var s = x; } var s = S(); return s.hidden();",
        "{ var x: X = x; } var x = S(); return x.hidden();",
        "{ var s = x; } var a = Array<S>(); a.append(S()); var n = 0; for (var s in a) { n = n + s.hidden(); } return n;",
    ] {
        let lib = format!("import \"types\";\nexport f<X>(x: X): int {{ {} }}", body);
        let files = [HIDDEN, &[("lib.pep", lib.as_str()), ("main.pep", "import \"lib\";\nimport \"ext\";\ntest(): int { return f<int>(1); }")]].concat();
        let err = error("generic_binding_scope", &files);
        assert!(err.contains("'hidden' is declared in an extension in"), "{}\n{}", body, err);
    }
}

#[test]
fn generic_bindings_through_shadowing_and_loops() {
    // Each receiver is a value of type X, checked where f<S> is used.
    let lib = "export f<X>(x: X): int { var y = x; { var y = y; return y.hidden(); } }";
    let files = [HIDDEN, &[("lib.pep", lib), ("main.pep", "import \"lib\";\nimport \"types\";\nimport \"ext\";\ntest(): int { return f<S>(S()); }")]].concat();
    assert_eq!(run("generic_bindings_shadow", &files), 2);
    // A loop binding typed X (compiled only: an `X[]` parameter does not
    // generate code yet).
    let lib = "export g<X>(a: X[]): int { var n = 0; for (X s in a) { n = n + s.hidden(); } return n; }";
    let files = [HIDDEN, &[("lib.pep", lib), ("main.pep", "import \"lib\";\ntest(): int { return 0; }")]].concat();
    compile("generic_bindings_loop", &files).expect("a loop binding typed X is checked where g is used");
}

#[test]
fn a_trait_reached_through_a_reexport_is_visible_unspelled() {
    let files = [
        ("shape.pep", "export trait Shape { area(): int; }\nstruct Sq { var x: int; }\n\
                       extend Sq with Shape { area(): int { return 9; } }\nexport make(): Shape { return Sq(); }"),
        ("factory.pep", "import \"shape\";\nexport Shape;\nexport make;"),
        ("main.pep", "import \"factory\";\ntest(): int { var s = make(); return s.area() + make().area(); }"),
    ];
    assert_eq!(run("trait_reexport_unspelled", &files), 18);
}

#[test]
fn loop_and_with_bindings_from_generic_values_are_checked_where_instantiated() {
    let lib = "export f<X>(x: X): int { var n = 0; for (var e in x) { n = n + e.hidden(); } return n; }\n\
               export g<X>(x: X): int { with (var e = x) { return e.hidden(); } return 0; }";
    let files = [HIDDEN, &[("lib.pep", lib), ("main.pep", "import \"lib\";\ntest(): int { return 0; }")]].concat();
    compile("generic_loop_with_bindings", &files).expect("bindings from a generic value are checked where f and g are used");
}

#[test]
fn this_in_a_default_and_generic_fields_are_checked_where_instantiated() {
    let lib = "export trait Tr { area(): int; twice(): int { var me = this; return me.hidden(); } }\n\
               export struct Box<T> { var v: T; get(): int { return v.hidden() + this.v.hidden(); } }";
    let files = [HIDDEN, &[("lib.pep", lib), ("main.pep", "import \"lib\";\nimport \"types\";\nimport \"ext\";\n\
                  extend S with Tr { area(): int { return 0; } }\n\
                  test(): int { var s = S(); var b = Box<S>(); b.v = s; return s.twice() + b.get(); }")]].concat();
    assert_eq!(run("this_and_generic_fields", &files), 6);
}

#[test]
fn values_whose_type_contains_a_type_parameter_are_checked_where_instantiated() {
    for lib in [
        "export f<X>(a: Array<X>): int { var n = 0; for (var s in a) { n = n + s.hidden(); } return n; }",
        "export f<X>(a: Array<X>): int { return a[0].hidden(); }",
        "export f<X>(a: Array<X>): int { var y = a[0]; return y.hidden(); }",
        "export struct Box<T> { var items: Array<T>; first(): int { return this.items[0].hidden(); } }",
    ] {
        let files = [HIDDEN, &[("lib.pep", lib), ("main.pep", "import \"lib\";\ntest(): int { return 0; }")]].concat();
        compile("generic_containers", &files).unwrap_or_else(|e| panic!("{}\n{}", lib, e));
    }
}

#[test]
fn a_struct_override_of_an_imported_generic_is_honored() {
    // main.pep's `describe<Point>` overrides lib.pep's exported
    // `describe<T>` for its own (private) Point.
    let files = [
        ("lib.pep", "export describe<T>(v: T): int { return 1; }"),
        ("main.pep", "import \"lib\";\nstruct Point { var x: int; }\ndescribe<Point>(p: Point): int { return 2; }\n\
                      test(): int { return describe<int>(1) * 10 + describe<Point>(Point()); }"),
    ];
    assert_eq!(run("struct_override_imported", &files), 12);
}

#[test]
fn a_struct_override_applies_where_the_generic_is_instantiated() {
    // lib.pep's generic code calls `describe<T>`; with T = Point@main, it
    // reaches main.pep's override, as it would for `describe<int>`.
    let files = [
        ("lib.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("./geo/module.pep", "export struct Point { var x: int; }"),
        ("main.pep", "import \"lib\";\nimport \"geo\" as g;\nstruct Point { var y: int; }\n\
                      describe<Point>(p: Point): int { return 20; }\n\
                      test(): int { return twice<Point>(Point()) + twice<g.Point>(g.Point()); }"),
    ];
    // main's Point: 20 * 2; geo's Point has no override: 1 * 2.
    assert_eq!(run("struct_override_instantiated", &files), 42);
}

#[test]
fn a_struct_override_in_a_non_root_file_is_honored() {
    // lib.pep's Point is mangled; its override of the runtime's `hash<T>`
    // names it, and calls to `hash<Point>` reach it.
    let lib = "export struct Point { var x: int; }\nhash<Point>(Point p): u64 { return p.x as u64; }\n\
               export same_bucket(): int { var a = Point(); a.x = 5; return (hash<Point>(a) == 5 as u64) ? 1 : 0; }";
    let files = [("lib.pep", lib), ("main.pep", "import \"lib\";\ntest(): int { return same_bucket(); }")];
    assert_eq!(run("struct_override_nonroot", &files), 1);
}

#[test]
fn another_files_private_struct_named_like_a_type_parameter_changes_nothing() {
    // other.pep's private `T` is mangled apart: `describe<T>` stays the base.
    let files = [
        ("lib.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("other.pep", "struct T { var x: int; }\nexport other(): int { return 0; }"),
        ("main.pep", "import \"lib\";\nimport \"other\";\nstruct Point { var x: int; }\n\
                      describe<Point>(p: Point): int { return 20; }\ntest(): int { return twice<Point>(Point()) + other(); }"),
    ];
    assert_eq!(run("private_struct_t_elsewhere", &files), 40);
}

#[test]
fn another_files_private_generic_is_no_base_for_a_struct_override() {
    // lib.pep's `describe<T>` is private, so main.pep's `describe<Point>`
    // is main.pep's own generic, not an override of lib.pep's.
    let files = [
        ("lib.pep", "describe<T>(v: T): int { return 1; }\nexport one(): int { return describe<int>(0); }"),
        ("main.pep", "import \"lib\";\nstruct Point { var x: int; }\ndescribe<Point>(p: Point): int { return 2; }\n\
                      test(): int { return describe<Point>(Point()) * 10 + one(); }"),
    ];
    assert_eq!(run("struct_override_private_base", &files), 21);
}

#[test]
fn an_override_must_name_a_struct_its_file_can_see() {
    // lib.pep has no Point of its own or imported; main's private Point is
    // not lib's to override for.
    let files = [
        ("lib.pep", "export describe<T>(v: T): int { return 1; }\ndescribe<Point>(p: Point): int { return 2; }\nexport one(): int { return 0; }"),
        ("main.pep", "import \"lib\";\nstruct Point { var x: int; }\ntest(): int { return describe<Point>(Point()) + one(); }"),
    ];
    let err = error("override_unknown_struct", &files);
    assert!(err.contains("redefinition of generic 'describe'"), "{}", err);
}

#[test]
fn a_struct_override_may_name_an_aliased_import() {
    let files = [
        ("lib.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("geo.pep", "export struct Point { var x: int; }"),
        ("main.pep", "import \"lib\";\nimport [Point as P] from \"geo\";\ndescribe<P>(p: P): int { return 20; }\n\
                      test(): int { return twice<P>(P()); }"),
    ];
    assert_eq!(run("override_aliased_struct", &files), 40);
}

#[test]
fn a_struct_override_may_spell_the_generic_by_an_alias() {
    let lib = "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }";
    let files = [
        ("lib.pep", lib),
        ("main.pep", "import [describe as dd, twice] from \"lib\";\nstruct Point { var x: int; }\n\
                      dd<Point>(p: Point): int { return 20; }\ntest(): int { return twice<Point>(Point()); }"),
    ];
    assert_eq!(run("override_generic_import_alias", &files), 40);
    let files = [
        ("./m/module.pep", "import \"impl\";\nexport describe as d;\nexport twice;"),
        ("./m/impl.pep", lib),
        ("main.pep", "import [d, twice] from \"m\";\nstruct Point { var x: int; }\n\
                      d<Point>(p: Point): int { return 20; }\ntest(): int { return twice<Point>(Point()); }"),
    ];
    assert_eq!(run("override_generic_reexport_alias", &files), 40);
}

#[test]
fn an_exported_struct_named_like_a_type_parameter_changes_nothing() {
    // lib.pep does not import other.pep, so its `T` is a type parameter.
    let files = [
        ("lib.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("other.pep", "export struct T { var x: int; }"),
        ("main.pep", "import \"lib\";\nimport \"other\";\nstruct Point { var x: int; }\n\
                      describe<Point>(p: Point): int { return 20; }\ntest(): int { var t = T(); return twice<Point>(Point()); }"),
    ];
    assert_eq!(run("exported_struct_t_elsewhere", &files), 40);
}

#[test]
fn only_generics_a_file_can_see_are_bases_for_its_overrides() {
    // other.pep's private `describe<U>` is not main.pep's to override:
    // main.pep's `describe<T>` (T an imported struct) is its own generic.
    let files = [
        ("types.pep", "export struct T { var x: int; }"),
        ("other.pep", "describe<U>(v: U): int { return 1; }\nexport other(): int { return describe<int>(0); }"),
        ("mid.pep", "import \"other\";\nexport mid(): int { return other(); }"),
        ("main.pep", "import \"types\";\nimport \"mid\";\ndescribe<T>(v: T): int { return 7; }\ntest(): int { return describe<int>(0) + mid(); }"),
    ];
    assert_eq!(run("invisible_base", &files), 8);
}

#[test]
fn a_module_import_sees_only_the_modules_exports_as_types() {
    // m's impl.pep exports `T` to its module, but m does not export it:
    // main.pep's `describe<T>` is a generic.
    let files = [
        ("m/module.pep", "import \"impl\";\nexport helper(): int { return 1; }"),
        ("m/impl.pep", "export struct T { var x: int; }"),
        ("main.pep", "import m;\ndescribe<T>(v: T): int { return 3; }\ntest(): int { return describe<int>(0) + m.helper(); }"),
    ];
    assert_eq!(run("module_exports_types", &files), 4);
}

#[test]
fn a_struct_reexported_under_another_name_can_be_overridden_for() {
    let files = [
        ("lib.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("./m/module.pep", "import \"impl\";\nexport Point as Pt;"),
        ("./m/impl.pep", "export struct Point { var x: int; }"),
        ("main.pep", "import \"lib\";\nimport \"m\";\ndescribe<Pt>(p: Pt): int { return 20; }\ntest(): int { return twice<Pt>(Pt()); }"),
    ];
    assert_eq!(run("reexported_struct_override", &files), 40);
}

#[test]
fn a_generic_reexported_through_a_qualifier_can_be_overridden() {
    let files = [
        ("geo/module.pep", "import \"impl\" as i;\nexport i.describe;\nexport i.twice;"),
        ("geo/impl.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("main.pep", "import [describe, twice] from geo;\nstruct Point { var x: int; }\n\
                      describe<Point>(p: Point): int { return 20; }\ntest(): int { return twice<Point>(Point()); }"),
    ];
    assert_eq!(run("override_qualified_reexport", &files), 40);
}

#[test]
fn a_forced_modules_internal_types_are_not_types_everywhere() {
    // fm's impl.pep exports `T` to its module only: main.pep's `wrap<T>`
    // is a generic.
    let files = [
        ("fm/module.pep", "import \"impl\";\nexport wrap;"),
        ("fm/impl.pep", "export struct T { var x: int; }\nexport wrap<U>(v: U): int { return 1; }"),
        ("main.pep", "wrap<T>(v: T): int { return 7; }\ntest(): int { return wrap<int>(0); }"),
    ];
    assert_eq!(run_with("forced_module_internal_types", &files, &["--import", "fm"]), 7);
}

#[test]
fn a_trait_is_not_an_override_argument() {
    let files = [
        ("base.pep", "export describe<T>(v: T): int { return 1; }"),
        ("main.pep", "import \"base\";\ntrait Shape { area(): int; }\ndescribe<Shape>(s: Shape): int { return 2; }\ntest(): int { return 0; }"),
    ];
    let err = error("trait_override_argument", &files);
    assert!(err.contains("'Shape' is not a struct; an override's type argument must name a struct"), "{}", err);
}

#[test]
fn a_closure_in_an_override_captures_nothing_of_its_type_arguments() {
    let files = [
        ("lib.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("main.pep", "import \"lib\";\nstruct Point { var x: int; }\n\
                      describe<Point>(p: Point): int { var f = (q: Point): int => q.x * 10; return f(p); }\n\
                      test(): int { var p = Point(); p.x = 2; return twice<Point>(p); }"),
    ];
    assert_eq!(run("closure_in_override", &files), 40);
}

#[test]
fn another_files_private_generic_of_the_same_name_does_not_block_an_override() {
    // lib.pep's private `describe<T>` is mangled apart; main.pep's override
    // binds base.pep's exported one.
    let files = [
        ("base.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("lib.pep", "describe<T>(v: T): int { return 5; }\nexport five(): int { return describe<int>(0); }"),
        ("main.pep", "import \"base\";\nimport \"lib\";\nstruct Point { var x: int; }\n\
                      describe<Point>(p: Point): int { return 20; }\ndescribe<int>(v: int): int { return 30; }\n\
                      test(): int { return twice<Point>(Point()) + describe<int>(0) + five(); }"),
    ];
    assert_eq!(run("private_same_name_generic", &files), 75);
}

#[test]
fn an_unrelated_exported_base_does_not_unlock_a_private_override() {
    // c.pep overrides b.pep's private `describe<T>`; a.pep's exported one
    // is not c.pep's to bind, since c.pep does not import a.pep.
    let files = [
        ("a.pep", "export describe<T>(v: T): int { return 1; }"),
        ("b.pep", "describe<T>(v: T): int { return 10; }\nexport twice_b<T>(v: T): int { return describe<T>(v) * 2; }"),
        ("c.pep", "import \"b\";\ndescribe<int>(v: int): int { return 30; }\nexport c_val(): int { return twice_b<int>(0); }"),
        ("main.pep", "import \"a\";\nimport \"c\";\ntest(): int { return c_val(); }"),
    ];
    let err = error("unrelated_exported_base", &files);
    assert!(err.contains("'describe' is private to") && err.contains("b.pep"), "{}", err);
}

#[test]
fn a_type_parameter_named_like_a_trait_is_still_a_base() {
    // lib.pep's `describe<Shape>` is a generic whose parameter is named
    // Shape, as before traits were types; main.pep overrides it for Point.
    let files = [
        ("lib.pep", "export trait Shape { area(): int; }\nexport describe<Shape>(v: Shape): int { return 1; }\n\
                     export twice<U>(v: U): int { return describe<U>(v) * 2; }"),
        ("main.pep", "import \"lib\";\nstruct Point { var x: int; }\ndescribe<Point>(p: Point): int { return 20; }\n\
                      test(): int { return twice<Point>(Point()); }"),
    ];
    assert_eq!(run("trait_named_type_parameter_base", &files), 40);
}

#[test]
fn a_forced_modules_generics_are_bases_everywhere() {
    // lib's `describe<T>` lives in impl.pep, reached through module.pep;
    // b.pep's private generic of that name is not main.pep's to override.
    let files = [
        ("lib/module.pep", "import \"impl\";\nexport describe;\nexport twice;"),
        ("lib/impl.pep", "export describe<T>(v: T): int { return 1; }\nexport twice<U>(v: U): int { return describe<U>(v) * 2; }"),
        ("b.pep", "describe<T>(v: T): int { return 5; }\nexport five(): int { return describe<int>(0); }"),
        ("main.pep", "import \"b\";\nstruct Point { var x: int; }\ndescribe<Point>(p: Point): int { return 20; }\n\
                      test(): int { return twice<Point>(Point()) + five(); }"),
    ];
    assert_eq!(run_with("forced_module_base", &files, &["--import", "lib"]), 45);
}

#[test]
fn a_forced_modules_trait_named_type_parameter_is_a_base() {
    let files = [
        ("lib/module.pep", "export trait Shape { area(): int; }\nexport describe<Shape>(v: Shape): int { return 1; }\n\
                            export twice<U>(v: U): int { return describe<U>(v) * 2; }"),
        ("main.pep", "struct Point { var x: int; }\ndescribe<Point>(p: Point): int { return 20; }\n\
                      test(): int { return twice<Point>(Point()); }"),
    ];
    assert_eq!(run_with("forced_trait_named_base", &files, &["--import", "lib"]), 40);
}

#[test]
fn an_overrides_struct_argument_is_a_known_type() {
    // In `describe<S>`, `p` is an S, not a value of generic type: its
    // `hidden` needs ext.pep imported.
    let lib = "import \"types\";\nexport describe<T>(v: T): int { return 1; }\ndescribe<S>(p: S): int { return p.hidden(); }\nexport one(): int { return 0; }";
    let files = [HIDDEN, &[("lib.pep", lib), ("main.pep", "import \"lib\";\nimport \"ext\";\ntest(): int { return one(); }")]].concat();
    let err = error("override_argument_known_type", &files);
    assert!(err.contains("'hidden' is declared in an extension in"), "{}", err);
}

#[test]
fn a_files_own_function_hides_the_imported_generic_it_would_override() {
    // main.pep's own `describe` (of another arity, or not generic) hides
    // lib.pep's: `describe<Point>` is a second declaration of that name.
    let lib = "export describe<T>(v: T): int { return 1; }\nexport twice<T>(v: T): int { return describe<T>(v) * 2; }";
    for own in ["describe<A, B>(a: A, b: B): int { return 7; }", "describe(a: int): int { return 7; }"] {
        let main = format!(
            "import \"lib\";\nstruct Point {{ var x: int; }}\n{}\ndescribe<Point>(p: Point): int {{ return 20; }}\ntest(): int {{ return twice<Point>(Point()); }}",
            own
        );
        let err = error("own_function_hides_generic", &[("lib.pep", lib), ("main.pep", &main)]);
        assert!(err.contains("redefinition of generic 'describe'"), "{}\n{}", own, err);
    }
}

/// A module whose `module.pep` only re-exports its files.
const SHAPES: &[(&str, &str)] = &[
    ("shapes/module.pep", "export * from \"rect\";\nexport [perimeter as outline, Side] from \"measure\";\n"),
    (
        "shapes/rect.pep",
        "export struct Rect { var w: int; var h: int; }\nexport area(r: Rect): int { return r.w * r.h + helper(); }\nhelper(): int { return 0; }\n",
    ),
    (
        "shapes/measure.pep",
        "import \"rect\";\nexport perimeter(r: Rect): int { return 2 * (r.w + r.h); }\nexport struct Side { var n: int; }\nexport hidden(): int { return 7; }\n",
    ),
];

fn with_shapes<'a>(main: &'a str) -> Vec<(&'a str, &'a str)> {
    let mut files: Vec<(&str, &str)> = SHAPES.to_vec();
    files.push(("main.pep", main));
    files
}

#[test]
fn export_star_from_a_file_re_exports_all_its_exports() {
    let main = r#"
import shapes;
test(): int {
    var r = shapes.Rect();
    r.w = 3;
    r.h = 4;
    return shapes.area(r);
}
"#;
    assert_eq!(run("export_star_file", &with_shapes(main)), 12);
}

#[test]
fn export_list_from_a_file_re_exports_the_listed_names() {
    let main = r#"
import [Rect, outline, Side] from shapes;
test(): int {
    var r = Rect();
    r.w = 3;
    r.h = 4;
    var s = Side();
    s.n = 1;
    return outline(r) + s.n;
}
"#;
    assert_eq!(run("export_list_file", &with_shapes(main)), 15);
}

#[test]
fn export_list_publishes_only_the_listed_names_under_their_new_names() {
    let err = error("export_list_unlisted", &with_shapes("import shapes;\ntest(): int { return shapes.hidden(); }"));
    assert!(err.contains("'hidden' is not exported by 'shapes'"), "{}", err);
    let err = error(
        "export_list_renamed",
        &with_shapes("import shapes;\ntest(): int { var r = shapes.Rect(); return shapes.perimeter(r); }"),
    );
    assert!(err.contains("'perimeter' is not exported by 'shapes'"), "{}", err);
}

#[test]
fn export_star_does_not_publish_private_names() {
    let err = error("export_star_private", &with_shapes("import shapes;\ntest(): int { return shapes.helper(); }"));
    assert!(err.contains("'helper' is not exported by 'shapes'"), "{}", err);
}

#[test]
fn export_star_from_a_module_makes_a_facade() {
    let mut files = with_shapes(
        r#"
import kit;
test(): int {
    var r = kit.Rect();
    r.w = 2;
    r.h = 5;
    return kit.area(r) + kit.twice(1);
}
"#,
    );
    files.push(("kit/module.pep", "export * from shapes;\nexport * from \"extra\";\n"));
    files.push(("kit/extra.pep", "export twice(x: int): int { return x * 2; }\n"));
    assert_eq!(run("export_star_module", &files), 12);
}

#[test]
fn export_from_binds_no_name_in_its_own_file() {
    let files = [
        ("lib/module.pep", "export * from \"impl\";\nexport g(): int { return f(); }\n"),
        ("lib/impl.pep", "export f(): int { return 1; }\n"),
        ("main.pep", "import lib;\ntest(): int { return lib.g(); }"),
    ];
    let err = error("export_from_binds_nothing", &files);
    assert!(err.contains("'f'"), "{}", err);
}

#[test]
fn export_from_and_import_of_the_same_file_work_together() {
    let files = [
        ("lib/module.pep", "import \"impl\";\nexport * from \"impl\";\nexport g(): int { return f() + 1; }\n"),
        ("lib/impl.pep", "export f(): int { return 1; }\n"),
        ("main.pep", "import lib;\ntest(): int { return lib.f() * 10 + lib.g(); }"),
    ];
    assert_eq!(run("export_from_and_import", &files), 12);
}

#[test]
fn export_star_chains_through_files() {
    let files = [
        ("lib/module.pep", "export * from \"a\";\n"),
        ("lib/a.pep", "export * from \"b\";\n"),
        ("lib/b.pep", "export f(): int { return 5; }\n"),
        ("main.pep", "import [f] from lib;\ntest(): int { return f(); }"),
    ];
    assert_eq!(run("export_star_chain", &files), 5);
}

#[test]
fn a_file_import_sees_what_the_file_re_exports() {
    let files = [
        ("./pkg/module.pep", "export * from \"inner\";\n"),
        ("./pkg/inner.pep", "export f(): int { return 4; }\n"),
        ("main.pep", "import \"pkg\";\ntest(): int { return f(); }"),
    ];
    assert_eq!(run("export_star_local_folder", &files), 4);
}

#[test]
fn export_star_collisions_are_reported_at_the_later_export() {
    let files = [
        ("lib/module.pep", "export * from \"a\";\nexport * from \"b\";\n"),
        // Top-level names are unique program-wide, so two exports collide
        // only through a renaming re-export.
        ("lib/a.pep", "export area(): int { return 1; }\n"),
        ("lib/b.pep", "export size(): int { return 2; }\nexport size as area;\n"),
        ("main.pep", "import lib;\ntest(): int { return lib.area(); }"),
    ];
    let err = error("export_star_collision", &files);
    assert!(err.contains("module.pep:2:1: error: 'area' is exported twice by module 'lib'"), "{}", err);
    assert!(err.contains("module.pep:1:1: note: also exported here"), "{}", err);
}

#[test]
fn export_star_colliding_with_an_own_export_is_reported() {
    let files = [
        ("lib/module.pep", "export * from \"a\";\nexport area(): int { return 2; }\n"),
        ("lib/a.pep", "export size(): int { return 1; }\nexport size as area;\n"),
        ("main.pep", "import lib;\ntest(): int { return lib.area(); }"),
    ];
    let err = error("export_star_own_collision", &files);
    assert!(err.contains("module.pep:1:1: error: 'area' is exported twice by module 'lib'"), "{}", err);
    assert!(err.contains("module.pep:2:8: note: also exported here"), "{}", err);
}

#[test]
fn export_star_of_one_declaration_twice_is_no_collision() {
    let files = [
        ("lib/module.pep", "export * from \"a\";\nexport * from \"b\";\n"),
        ("lib/a.pep", "export f(): int { return 3; }\n"),
        ("lib/b.pep", "export * from \"a\";\n"),
        ("main.pep", "import lib;\ntest(): int { return lib.f(); }"),
    ];
    assert_eq!(run("export_star_same_declaration", &files), 3);
}

#[test]
fn export_list_of_a_missing_name_is_reported() {
    let files = [
        ("lib/module.pep", "export [nope] from \"a\";\n"),
        ("lib/a.pep", "export f(): int { return 1; }\n"),
        ("main.pep", "import lib;\ntest(): int { return 0; }"),
    ];
    let err = error("export_list_missing", &files);
    assert!(err.contains("'nope' is not exported by \"a.pep\""), "{}", err);
}

#[test]
fn export_from_an_unknown_file_is_reported_at_the_source() {
    let files = [("lib/module.pep", "export * from \"missing\";\n"), ("main.pep", "import lib;\ntest(): int { return 0; }")];
    let err = error("export_from_missing", &files);
    assert!(err.contains("cannot find \"missing.pep\""), "{}", err);
}

#[test]
fn export_from_takes_platform_attributes() {
    let files = [
        (
            "lib/module.pep",
            "[Target(OS(Linux))]\nexport * from \"linux\";\n[Target(OS(Windows))]\nexport * from \"windows\";\n[Target(OS(MacOS))]\nexport * from \"mac\";\n",
        ),
        ("lib/linux.pep", "export os_id(): int { return 1; }\n"),
        ("lib/windows.pep", "export os_id(): int { return 2; }\n"),
        ("lib/mac.pep", "export os_id(): int { return 3; }\n"),
        ("main.pep", "import lib;\ntest(): int { return lib.os_id(); }"),
    ];
    let expected = if cfg!(target_os = "linux") {
        1
    } else if cfg!(target_os = "windows") {
        2
    } else {
        3
    };
    assert_eq!(run("export_from_platform", &files), expected);
}

#[test]
fn export_from_must_come_before_declarations() {
    let files = [
        ("lib/module.pep", "export f(): int { return 1; }\nexport * from \"a\";\n"),
        ("lib/a.pep", "export g(): int { return 1; }\n"),
        ("main.pep", "import lib;\ntest(): int { return 0; }"),
    ];
    let err = error("export_from_order", &files);
    assert!(err.contains("imports must come before all declarations"), "{}", err);
}
