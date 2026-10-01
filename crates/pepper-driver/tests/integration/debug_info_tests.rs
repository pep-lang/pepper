//! Debug info (`-g`): compile units, subprograms and line tables in the IR
//! and objects, inlined-at chains once optimized, and the build cache
//! keeping `-g` objects apart (see INTERNALS.md §4.4).

use clap::Parser;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

const PROGRAM: &str = "struct Point {
    var x: int = 0;
    var y: int = 0;
}

total(p: Point): int {
    return p.x + p.y;
}

main(): int {
    var points = Array<Point>();
    var p = Point();
    p.x = 1;
    p.y = 2;
    points.append(p);
    var first = points[0];
    return total(first) - LIMIT;
}

const LIMIT: int = 3;
";

/// A fresh directory holding `main.pep` (`PROGRAM`).
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_debug_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("main.pep"), PROGRAM).unwrap();
    dir
}

/// Run the compiler on `dir/main.pep` with `extra` options, building in
/// `dir/build` with no cache.
fn compile(dir: &Path, extra: &[&str]) {
    // Runtime discovery searches from the working directory.
    std::env::set_current_dir(repo_root()).unwrap();
    let mut args = vec![
        "pepper".to_string(),
        dir.join("main.pep").to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
        "--no-cache".to_string(),
    ];
    args.extend(extra.iter().map(|a| a.to_string()));
    pepper_driver::run(pepper_driver::Options::parse_from(args)).expect("compile");
}

/// The whole program's IR with `extra` options.
fn ir(name: &str, extra: &[&str]) -> String {
    let dir = scratch(name);
    let mut args = vec!["--emit-llvm"];
    args.extend(extra);
    compile(&dir, &args);
    let ir = std::fs::read_to_string(dir.join("build").join("main.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    ir
}

#[test]
fn g_emits_subprograms_and_line_locations() {
    let ir = ir("lines", &["-g"]);
    assert!(ir.contains("!\"Debug Info Version\""), "no debug info version flag");
    assert!(ir.contains("distinct !DICompileUnit("), "no compile unit");
    // `total` is declared on line 6, and its body is on line 7.
    let total = ir
        .lines()
        .find(|l| l.contains("!DISubprogram(name: \"total\""))
        .unwrap_or_else(|| panic!("no subprogram for 'total'"));
    assert!(total.contains("line: 6,") && total.contains("DISPFlagDefinition"), "{total}");
    let id = total.split(" = ").next().unwrap();
    assert!(ir.contains(&format!("!DILocation(line: 7, column: 12, scope: {id})")), "no location for 'p.x' in 'total'");
    // A synthesized method is artificial, and declared at its struct.
    let acquire = ir
        .lines()
        .find(|l| l.contains("!DISubprogram(name: \"Point.__acquire\""))
        .unwrap_or_else(|| panic!("no subprogram for 'Point.__acquire'"));
    assert!(acquire.contains("line: 1,") && acquire.contains("DIFlagArtificial"), "{acquire}");
}

#[test]
fn g_describes_variables_and_struct_types() {
    let ir = ir("variables", &["-g"]);
    // The runtime declares variables of the same names elsewhere.
    let line = |needle: &str| ir.lines().find(|l| l.contains(needle)).unwrap_or_else(|| panic!("no '{needle}' in the IR")).to_string();
    let has = |needle: &str, also: &str| ir.lines().any(|l| l.contains(needle) && l.contains(also));
    // Parameters, locals, and `this`.
    assert!(has("!DILocalVariable(name: \"p\", arg: 1,", "line: 6,"));
    assert!(has("!DILocalVariable(name: \"first\", scope:", "line: 16,"));
    assert!(line("!DILocalVariable(name: \"this\", arg: 1,").contains("DIFlagObjectPointer"));
    // A struct reference is a pointer to the struct, whose members include
    // the reference counts.
    let point = line("!DICompositeType(tag: DW_TAG_structure_type, name: \"Point\"");
    assert!(point.contains("line: 1,") && point.contains("size: 128,"), "{point}");
    assert!(line("!DIDerivedType(tag: DW_TAG_member, name: \"y\"").contains("offset: 96"));
    line("!DIDerivedType(tag: DW_TAG_member, name: \"__refcount\"");
    // Module-scope variables, and base types under their Pepper names.
    assert!(line("!DIGlobalVariable(name: \"LIMIT\"").contains("line: 20,"));
    line("!DIBasicType(name: \"int\", size: 32, encoding: DW_ATE_signed)");
}

/// On Linux the program carries gdb's pretty-printers for the runtime's
/// types, which gdb loads with it.
#[test]
fn g_embeds_gdb_printers_on_linux() {
    let ir = ir("printers", &["-g"]);
    let embedded = ir.contains("section \".debug_gdb_scripts\"");
    assert_eq!(embedded, cfg!(target_os = "linux"), "a .debug_gdb_scripts section only on Linux");
}

#[test]
fn without_g_there_is_no_debug_info() {
    let ir = ir("none", &[]);
    assert!(!ir.contains("!dbg"), "debug locations without -g");
    assert!(!ir.contains("DICompileUnit"), "a compile unit without -g");
}

#[test]
fn optimized_code_keeps_inlined_at_chains() {
    let ir = ir("inlined", &["-g", "-O2"]);
    assert!(ir.contains("isOptimized: true"), "the compile unit is not marked optimized");
    assert!(ir.contains("inlinedAt: "), "inlining at -O2 left no inlined-at locations");
}

#[test]
fn g_links_an_executable_that_runs() {
    let dir = scratch("link");
    let exe = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    compile(&dir, &["-g", "-o", exe.to_str().unwrap()]);
    if cfg!(windows) {
        // The runtime's visualizers are in it.
        let pdb = std::fs::read(dir.join("main.pdb")).expect("no .pdb beside the executable");
        assert!(pdb.windows(13).any(|w| w == b"pepper.natvis"), "the .pdb has no pepper.natvis");
    }
    let status = std::process::Command::new(&exe).status().unwrap();
    assert!(status.success(), "{status}");
    let _ = std::fs::remove_dir_all(&dir);
}

const TYPES: &str = "enum Suit: u8 {
    Clubs,
    Hearts = 5,
}

trait Shape {
    area(): int;
}

struct Square {
    var side: int = 2;
}

extend Square with Shape {
    area(): int { return side * side; }
}

struct Node {
    Node next;
    (int, Node) pair;
}

main(): int {
    var suit = Suit.Hearts;
    var pair = (3, Square());
    Shape shape = Square();
    var node = Node();
    var counts = Array<long>();
    return shape.area() - 4 + (suit as int) - 5 + pair.0 - 3 + (counts.count() as int);
}
";

#[test]
fn g_describes_enums_tuples_traits_and_generics() {
    let dir = scratch("types");
    std::fs::write(dir.join("main.pep"), TYPES).unwrap();
    compile(&dir, &["-g", "--emit-llvm"]);
    let ir = std::fs::read_to_string(dir.join("build").join("main.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let has = |needle: &str| ir.lines().any(|l| l.contains(needle));
    // A plain enum is an enumeration of its cases over its representation.
    assert!(has("!DICompositeType(tag: DW_TAG_enumeration_type, name: \"Suit\""), "no enumeration for 'Suit'");
    assert!(has("!DIEnumerator(name: \"Hearts\", value: 5, isUnsigned: true)"), "no enumerator 'Hearts'");
    // A tuple has a member per element, named by position.
    assert!(has("!DICompositeType(tag: DW_TAG_structure_type, name: \"(int, Node)\""), "no structure for the tuple");
    assert!(has("!DIDerivedType(tag: DW_TAG_member, name: \"1\""), "no member '1'");
    // A trait value is its object and vtable.
    assert!(has("!DICompositeType(tag: DW_TAG_structure_type, name: \"Shape\""), "no structure for 'Shape'");
    assert!(has("!DIDerivedType(tag: DW_TAG_member, name: \"vtable\""), "no member 'vtable'");
    // A generic instantiation has its own type, named as written.
    assert!(has("!DICompositeType(tag: DW_TAG_structure_type, name: \"Array<long>\""), "no structure for 'Array<long>'");
    // A struct that leads back to itself, through a field and a tuple.
    assert!(has("!DICompositeType(tag: DW_TAG_structure_type, name: \"Node\""), "no structure for 'Node'");
    for name in ["suit", "pair", "shape", "node", "counts"] {
        assert!(has(&format!("!DILocalVariable(name: \"{name}\"")), "no variable '{name}'");
    }
}

/// The JIT runs a module with debug info, and on Linux registers its code
/// with the GDB JIT interface (`__jit_debug_descriptor`), which gdb and lldb
/// read: MCJIT registers every object it loads.
#[test]
fn jit_code_with_debug_info_runs_and_is_registered() {
    std::env::set_current_dir(repo_root()).unwrap();
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", "test(): int {\n    var p = 41;\n    return p + 1;\n}\n").expect("compile");
    let context = inkwell::context::Context::create();
    let mut generator = pepper_codegen::CodeGenerator::new(&context, "test");
    generator.debug_info = true;
    let engine = generator.jit_engine(&mut module).expect("jit");
    assert_eq!(pepper_codegen::CodeGenerator::jit_call_i32(&engine, "test"), Ok(42));
    #[cfg(target_os = "linux")]
    {
        // LLVM's GDB JIT interface: `{ version, action, relevant entry,
        // first entry }`, linked into this process with LLVM.
        unsafe extern "C" {
            static __jit_debug_descriptor: [usize; 3];
        }
        let first_entry = unsafe { std::ptr::addr_of!(__jit_debug_descriptor).read_volatile()[2] };
        assert_ne!(first_entry, 0, "the JIT registered no code with the GDB JIT interface");
    }
}
