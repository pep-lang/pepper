//! Debug info (`-g`): compile units, subprograms and line tables in the IR
//! and objects, inlined-at chains once optimized, and the build cache
//! keeping `-g` objects apart (see INTERNALS.md §4.4).

use clap::Parser;
use std::path::{Path, PathBuf};

use crate::support::repo_root;

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

/// `PROGRAM`'s IR with `-g`, compiled once for the tests that read it.
fn g_ir() -> &'static str {
    static IR: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    IR.get_or_init(|| ir("g", &["-g"]))
}

#[test]
fn g_emits_subprograms_and_line_locations() {
    let ir = g_ir();
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
fn frame_pointers_are_kept_only_when_asked() {
    let kept = ir("frame_pointers", &["-O2", "--frame-pointers"]);
    assert!(kept.contains("\"frame-pointer\"=\"all\""), "no frame-pointer attribute with --frame-pointers");
    let plain = ir("no_frame_pointers", &["-O2"]);
    assert!(!plain.contains("\"frame-pointer\"=\"all\""), "a frame-pointer attribute without --frame-pointers");
}

#[test]
fn a_closure_is_named_for_where_it_is_written() {
    let dir = scratch("closure");
    std::fs::write(
        dir.join("main.pep"),
        "apply(f: (int) => int, x: int): int {\n    return f(x);\n}\n\nmain(): int {\n    var k = 2;\n    return apply((x: int) => x * k, 3) - 6;\n}\n",
    )
    .unwrap();
    compile(&dir, &["--emit-llvm", "-g"]);
    let ir = std::fs::read_to_string(dir.join("build").join("main.ll")).unwrap();
    assert!(ir.contains("!DISubprogram(name: \"closure at main.pep:7\""), "no subprogram named for the closure");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn g_describes_variables_and_struct_types() {
    let ir = g_ir();
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
    let ir = g_ir();
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

struct Leaf {
    var up: Leaf?;
}

main(): int {
    var leaf = Optional<Leaf>.Empty;
    var found = Optional<int>.Value(7);
    var suit = Suit.Hearts;
    var pair = (3, Square());
    Shape shape = Square();
    var node = Node();
    var counts = Array<long>();
    return shape.area() - 4 + (suit as int) - 5 + pair.0 - 3 + (counts.count as int);
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
    // A value enum is held inline: its structure, not a pointer to it,
    // with its payload as a member a debugger expression can name.
    assert!(has("!DICompositeType(tag: DW_TAG_structure_type, name: \"Optional<int>\""), "no structure for 'Optional<int>'");
    assert!(!has("!DIDerivedType(tag: DW_TAG_pointer_type, name: \"Optional<"), "an optional is described as a pointer");
    assert!(has("!DIDerivedType(tag: DW_TAG_member, name: \"Value__value\""), "no member 'Value__value'");
    for name in ["leaf", "found", "suit", "pair", "shape", "node", "counts"] {
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

/// A `static` block whose compile-time `for`, `while` and `if` each unroll
/// into passes (#521). 1 + 2 + 3, plus 0 + 1, times 2: `total` returns 14.
const STATIC: &str = "struct Point {
    var x: int = 1;
    var y: int = 2;
    var z: int = 3;
}

total(p: Point): int {
    var sum = 0;
    static (sum, p) {
        for (var field in reflect.properties<Point>()) {
            sum = sum + field.get(p);
        }
        var n = 0;
        while (n < 2) {
            sum = sum + n;
            n += 1;
        }
        if (reflect.is_struct<Point>()) {
            sum = sum * 2;
        }
    }
    return sum;
}

main(): int {
    return total(Point()) - 14;
}
";

/// `STATIC` compiled with `extra` options in a fresh directory, which is
/// returned.
fn compile_static(name: &str, extra: &[&str]) -> PathBuf {
    let dir = scratch(name);
    std::fs::write(dir.join("main.pep"), STATIC).unwrap();
    compile(&dir, extra);
    dir
}

/// Each pass of a compile-time loop, and the branch a compile-time `if`
/// keeps, starts with a `nop` on the header's line under `-g -O0`, so a
/// debugger stops there once per pass; its compile-time variables are
/// declared in the pass's scope.
#[test]
fn g_gives_each_static_pass_a_stop_and_its_compile_time_variables() {
    let dir = compile_static("static", &["--emit-llvm", "-g"]);
    let ir = std::fs::read_to_string(dir.join("build").join("main.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    // The `nop`s' lines: three passes of the `for` (line 10), two of the
    // `while` (14), and the `if` (18).
    let lines: Vec<u32> = ir
        .lines()
        .filter(|l| l.contains("call void asm sideeffect \"nop\""))
        .map(|l| {
            let id = l.rsplit("!dbg ").next().unwrap().trim();
            let location = ir.lines().find(|d| d.starts_with(&format!("{id} = !DILocation("))).unwrap();
            location.split("line: ").nth(1).unwrap().split(',').next().unwrap().parse().unwrap()
        })
        .collect();
    assert_eq!(lines, [10, 10, 10, 14, 14, 18], "the nops' lines");
    // `field` once per pass, as a `reflect.Member`, and `n` in each
    // `while` pass and in the `if` (the runtime has variables of these
    // names too, on other lines).
    let declared = |name: &str, line: u32| {
        ir.lines().filter(|l| l.contains(&format!("!DILocalVariable(name: \"{name}\",")) && l.contains(&format!("line: {line},"))).count()
    };
    assert_eq!(declared("field", 10), 3);
    assert_eq!(declared("n", 14) + declared("n", 18), 3);
    assert!(ir.contains("!DICompositeType(tag: DW_TAG_structure_type, name: \"reflect.Member\""), "no 'reflect.Member' type");
    assert!(ir.contains("c\"y\\00\""), "no constant for the member name 'y'");

    // Optimized code has no stops, and code without `-g` nothing at all.
    for (name, extra) in [("static_o2", &["--emit-llvm", "-g", "-O2"][..]), ("static_no_g", &["--emit-llvm"][..])] {
        let dir = compile_static(name, extra);
        let ir = std::fs::read_to_string(dir.join("build").join("main.ll")).unwrap();
        let _ = std::fs::remove_dir_all(&dir);
        assert!(!ir.contains("asm sideeffect \"nop\""), "a nop with {extra:?}");
    }
}

/// gdb steps through the passes of `STATIC`'s `static` block one by one,
/// alternating between each loop's header and body as in a runtime loop,
/// and prints the compile-time loop variable. Skipped where gdb is not
/// installed or cannot run the program.
#[test]
fn gdb_steps_through_static_passes() {
    if !cfg!(target_os = "linux") || std::process::Command::new("gdb").arg("--version").output().is_err() {
        return;
    }
    let dir = scratch("static_gdb");
    std::fs::write(dir.join("main.pep"), STATIC).unwrap();
    let exe = dir.join("main");
    compile(&dir, &["-g", "-o", exe.to_str().unwrap()]);
    let mut script = String::from("break total\nrun\nnext\nnext\nnext\nprint field.name\nnext\nnext\nprint field.name\n");
    script.push_str(&"next\n".repeat(10));
    std::fs::write(dir.join("gdb.cmd"), script).unwrap();
    let output = std::process::Command::new("gdb").arg("-nx").arg("-batch").arg("-x").arg(dir.join("gdb.cmd")).arg(&exe).output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let text = String::from_utf8_lossy(&output.stdout);
    // A host that forbids tracing (some containers) never reaches the
    // breakpoint.
    if !text.contains("Breakpoint 1, total") {
        return;
    }
    // The source lines gdb stopped on, and what it printed.
    let stops: Vec<&str> = text
        .lines()
        .filter_map(|l| match l.split_once('\t') {
            Some((line, _)) if line.parse::<u32>().is_ok() => Some(line),
            _ => l.starts_with('$').then(|| l.rsplit(' ').next().unwrap()),
        })
        .collect();
    assert_eq!(
        stops,
        ["7", "8", "10", "11", "\"x\"", "10", "11", "\"y\"", "10", "11", "14", "15", "14", "15", "18", "19", "22"],
        "{text}"
    );
}

/// With `--debug-static=expanded`, `-g` writes `main.static.pep` beside the
/// output, `STATIC` with its block expanded, and the debug info places the
/// expansion's statements in it, each pass's `{` as its header (#521).
#[test]
fn debug_static_expanded_writes_and_points_at_the_expanded_source() {
    let dir = scratch("static_expanded");
    std::fs::write(dir.join("main.pep"), STATIC).unwrap();
    let exe = dir.join("main");
    compile(&dir, &["-g", "--debug-static=expanded", "--emit-llvm", "-o", exe.to_str().unwrap()]);
    let expanded = std::fs::read_to_string(dir.join("main.static.pep")).expect("no main.static.pep beside the output");
    let ir = std::fs::read_to_string(dir.join("build").join("main.ll")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let line_of = |text: &str| expanded.lines().position(|l| l.trim() == text).unwrap_or_else(|| panic!("no '{text}' in:\n{expanded}")) as u32 + 1;
    assert!(expanded.contains("# static (sum, p) expanded from main.pep:9:5"), "{expanded}");
    let file = ir.lines().find(|l| l.contains("!DIFile(filename:") && l.contains("main.static.pep")).expect("no DIFile for main.static.pep");
    let file = file.split(" = ").next().unwrap();
    // Each pass's statement, on its line of the expanded file, in a scope
    // in that file.
    let scopes: Vec<&str> = ir.lines().filter(|l| l.contains(&format!("file: {file},"))).map(|l| l.split(" = ").next().unwrap()).collect();
    for text in ["sum = sum + p.x;", "sum = sum + p.y;", "sum = sum + p.z;", "sum = sum + 1;", "sum = sum * 2;"] {
        let line = line_of(text);
        assert!(
            ir.lines().any(|l| l.contains(&format!("!DILocation(line: {line},")) && scopes.iter().any(|s| l.contains(&format!("scope: {s})")) || l.contains(&format!("scope: {s},")))),
            "no location on line {line} ('{text}') of main.static.pep"
        );
    }
}

/// gdb stops on a breakpoint set on a line of the expanded file, in the
/// pass that line belongs to, and steps through the expansion's lines in
/// order. Skipped where gdb is not installed or cannot run the program.
#[test]
fn gdb_steps_through_the_expanded_source() {
    if !cfg!(target_os = "linux") || std::process::Command::new("gdb").arg("--version").output().is_err() {
        return;
    }
    let dir = scratch("static_expanded_gdb");
    std::fs::write(dir.join("main.pep"), STATIC).unwrap();
    let exe = dir.join("main");
    compile(&dir, &["-g", "--debug-static=expanded", "-o", exe.to_str().unwrap()]);
    let expanded = std::fs::read_to_string(dir.join("main.static.pep")).unwrap();
    let line_of = |text: &str| expanded.lines().position(|l| l.trim() == text).unwrap() + 1;
    let y = line_of("sum = sum + p.y;");
    let script = format!("break main.static.pep:{y}\nrun\nprint field.name\nnext\nnext\nnext\nnext\n");
    std::fs::write(dir.join("gdb.cmd"), script).unwrap();
    let output = std::process::Command::new("gdb").arg("-nx").arg("-batch").arg("-x").arg(dir.join("gdb.cmd")).arg(&exe).output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let text = String::from_utf8_lossy(&output.stdout);
    if !text.contains("Breakpoint 1, total") {
        return;
    }
    assert!(text.contains(&format!("main.static.pep:{y}")), "{text}");
    assert!(text.contains("$1 = ") && text.contains("\"y\""), "{text}");
    // After the `y` pass: the `z` pass's `{`, its statement, then the
    // `while`'s first pass.
    let stops: Vec<usize> = text.lines().filter_map(|l| l.split_once('\t')?.0.parse().ok()).collect();
    let z = line_of("sum = sum + p.z;");
    let zero = line_of("sum = sum + 0;");
    assert_eq!(stops, [y, z - 1, z, zero - 1, zero], "{text}");
}
