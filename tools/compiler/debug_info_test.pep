# Debug info (`-g`, `codegen/debug.pep`): compile units, subprograms,
# line locations, variables and types in the IR; a program built with it
# carries DWARF that gdb reads, optimized too; the build cache keeps `-g`
# objects apart; and `static` blocks step pass by pass, as written or
# (`--debug-static=expanded`) in an expanded copy of the file. The intent
# of the Rust compiler's `debug_info_tests.rs`.

import compiler.codegen;
import compiler.driver;
import [Directory, File, Path] from io;
import compiler.link;
import os;
import process;
import compiler.sema;
import [TempFolder] from testing;
import [Utf8] from text;

const _PROGRAM = "struct Point {\n    var x: int = 0;\n    var y: int = 0;\n}\n\ntotal(p: Point): int {\n    return p.x + p.y;\n}\n\nmain(): int {\n    var points = Array<Point>();\n    var p = Point();\n    p.x = 1;\n    p.y = 2;\n    points.append(p);\n    var first = points[0];\n    return total(first) - LIMIT;\n}\n\nconst LIMIT: int = 3;\n";

const _TYPES = "enum Suit: u8 {\n    Clubs,\n    Hearts = 5,\n}\n\ntrait Shape {\n    area(): int;\n}\n\nstruct Square {\n    var side: int = 2;\n}\n\nextend Square with Shape {\n    area(): int { return side * side; }\n}\n\nstruct Node {\n    Node next;\n    (int, Node) pair;\n}\n\nstruct Leaf {\n    var up: Leaf?;\n}\n\nmain(): int {\n    var leaf = Optional<Leaf>.Empty;\n    var found = Optional<int>.Value(7);\n    var suit = Suit.Hearts;\n    var pair = (3, Square());\n    Shape shape = Square();\n    var node = Node();\n    var counts = Array<long>();\n    return shape.area() - 4 + (suit as int) - 5 + pair.0 - 3 + (counts.count as int);\n}\n";

# A `static` block whose compile-time `for`, `while` and `if` each unroll
# into passes. 1 + 2 + 3, plus 0 + 1, times 2: `total` returns 14.
const _STATIC = "struct Point {\n    var x: int = 1;\n    var y: int = 2;\n    var z: int = 3;\n}\n\ntotal(p: Point): int {\n    var sum = 0;\n    static (sum, p) {\n        for (var field in reflect.properties<Point>()) {\n            sum = sum + field.get(p);\n        }\n        var n = 0;\n        while (n < 2) {\n            sum = sum + n;\n            n += 1;\n        }\n        if (reflect.is_struct<Point>()) {\n            sum = sum * 2;\n        }\n    }\n    return sum;\n}\n\nmain(): int {\n    return total(Point()) - 14;\n}\n";

# `source` (a program of one file, with the runtime) loaded from `folder`.
_load(folder: Path, source: String): link.Program {
    var file = folder.join(Path("main.pep"));
    File.write_text(file, source);
    var program = link.load_program(file, link.Setup());
    if (program.is_err()) {
        print(program.error());
    }
    expect_true(program.is_ok());
    return program.value();
}

# The LLVM IR of `source`, unoptimized, with debug info when `debug`.
_ir(source: String, debug: bool): String {
    var folder = TempFolder("debug_ir");
    var program = _load(folder.path, source);
    var module = sema.merge(program);
    expect_true(module.is_ok());
    var state = sema.run_passes(module.value(), program.target, program.sources());
    expect_true(state.is_ok());
    var namespaces = Array<String>();
    for (var f in program.files) {
        namespaces.append(f.namespace);
    }
    var ir = codegen.generate_ir(
        module.value(),
        state.value(),
        namespaces,
        "main",
        Optional<codegen.Cpu>.Empty,
        debug,
        0,
        false,
        codegen.RuntimeChecks.all(),
        debug ? driver.gdb_printers(program) : ""
    );
    if (ir.is_err()) {
        print(ir.error().message);
    }
    expect_true(ir.is_ok());
    return ir.value();
}

# A binary file's bytes as text, each invalid sequence as U+FFFD, to search
# for the names it holds.
_binary_text(file: Path): String {
    return Utf8.decode_lossy(File.read_bytes(file).value());
}

# The text of where `program`'s debug info lives: the program itself, a
# `.pdb` beside it on Windows (CodeView) and its `.dSYM` on macOS.
_debug_info_text(program: Path): String {
    var text = _binary_text(program);
    var folder = program.parent().value();
    for (var entry in Directory.open(folder).value().entries().value()) {
        if (entry.name.ends_with(".pdb")) {
            text = text + _binary_text(entry.path);
        }
    }
    var dwarf = Path(program.to_string() + ".dSYM").join(Path("Contents")).join(Path("Resources")).join(Path("DWARF"));
    if (dwarf.is_directory()) {
        for (var entry in Directory.open(dwarf).value().entries().value()) {
            text = text + _binary_text(entry.path);
        }
    }
    return text;
}

# The first line of `text` holding every one of `needles`; empty for none.
_line(text: String, needles: String[]): String {
    for (var line in text.split("\n")) {
        bool all = true;
        for (var needle in needles) {
            all = all and line.contains(needle);
        }
        if (all) {
            return line;
        }
    }
    return "";
}

# How many lines of `text` hold every one of `needles`.
_count(text: String, needles: String[]): ulong {
    ulong count = 0;
    for (var line in text.split("\n")) {
        bool all = true;
        for (var needle in needles) {
            all = all and line.contains(needle);
        }
        if (all) {
            count += 1;
        }
    }
    return count;
}

# The metadata id a line of IR defines (`!12` for `!12 = ...`).
_id(line: String): String {
    var parts = line.split_once(" = ");
    return parts.is_value() ? parts.value().0 : "";
}

# Builds `source` from `folder` into `folder/main` with debug info and no
# cache, at `opt_level`, with `--debug-static=expanded` when `expanded`.
_build(folder: Path, source: String, opt_level: uint, expanded: bool): Path {
    var program = _load(folder, source);
    var output = folder.join(Path("main"));
    var options = driver.BuildOptions(output, folder.join(Path("build")));
    options.in_process = true;
    options.debug = true;
    options.opt_level = opt_level;
    options.debug_static_expanded = expanded;
    options.entry = Optional<Path>.Value(folder.join(Path("main.pep")));
    var built = driver.build(program, options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    return output;
}

# Runs `program`, which must succeed.
_run(program: Path) {
    var ran = process.Command(program.to_string()).spawn();
    expect_true(ran.is_ok());
    expect_true(ran.value().wait().value().success());
}

# gdb's output for `script` on `program`; none where gdb is missing, or
# cannot run the program (a host that forbids tracing never reaches the
# breakpoint, whose report starts with `stop`).
_gdb(program: Path, script: String, stop: String): String? {
    if (link.Target().os != "linux" or !process.find_executable("gdb").is_value()) {
        return Optional<String>.Empty;
    }
    var commands = program.parent().value().join(Path("gdb.cmd"));
    File.write_text(commands, script);
    var command = process.Command("gdb");
    command
        .argument("-nx")
        .argument("-batch")
        .argument("-x")
        .argument(commands.to_string())
        .argument(program.to_string());
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var ran = command.run();
    if (ran.is_err() or !ran.value().stdout.contains(stop)) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(ran.value().stdout);
}

# The source lines gdb stopped on, in order, and what it printed (`$1 = 4`
# as `4`).
_stops(text: String): String[] {
    var out = Array<String>();
    for (var line in text.split("\n")) {
        var tab = line.split_once("\t");
        if (tab.is_value() and uint.parse(tab.value().0).is_value()) {
            out.append(tab.value().0);
        } else if (line.starts_with("$")) {
            var space = line.rfind(" ");
            out.append(line.substr_bytes(space as ulong + 1, line.size - space as ulong - 1));
        }
    }
    return out;
}

# The line of `text` that is `statement`, indented, from 1; 0 for none.
_line_number(text: String, statement: String): ulong {
    var lines = text.split("\n");
    for (var i in 0..lines.count) {
        if (lines[i].trim() == statement) {
            return i + 1;
        }
    }
    return 0;
}

[Test]
g_emits_subprograms_line_locations_variables_and_types() {
    var ir = _ir(_PROGRAM, true);
    expect_true(ir.contains("!\"Debug Info Version\""));
    expect_true(ir.contains("distinct !DICompileUnit("));
    # `total` is declared on line 6, and its body is on line 7 (at its
    # expression's operator, where pepc places a binary expression).
    var total = _line(ir, ["!DISubprogram(name: \"total\""]);
    expect_true(total.contains("line: 6,") and total.contains("DISPFlagDefinition"));
    expect_true(ir.contains($"!DILocation(line: 7, column: 16, scope: {_id(total)})"));
    # A synthesized method is artificial, and declared at its struct.
    var acquire = _line(ir, ["!DISubprogram(name: \"Point.__acquire\""]);
    expect_true(acquire.contains("line: 1,") and acquire.contains("DIFlagArtificial"));
    # Parameters, locals, and `this` (the runtime declares variables of the
    # same names on other lines).
    expect_false(_line(ir, ["!DILocalVariable(name: \"p\", arg: 1,", "line: 6,"]).is_empty);
    expect_false(_line(ir, ["!DILocalVariable(name: \"first\", scope:", "line: 16,"]).is_empty);
    expect_true(_line(ir, ["!DILocalVariable(name: \"this\", arg: 1,"]).contains("DIFlagObjectPointer"));
    # A struct reference is a pointer to the struct, whose members include
    # the reference counts.
    var point = _line(ir, ["!DICompositeType(tag: DW_TAG_structure_type, name: \"Point\""]);
    expect_true(point.contains("line: 1,") and point.contains("size: 128,"));
    expect_true(_line(ir, ["!DIDerivedType(tag: DW_TAG_member, name: \"y\""]).contains("offset: 96"));
    expect_false(_line(ir, ["!DIDerivedType(tag: DW_TAG_member, name: \"__refcount\""]).is_empty);
    # Module-scope variables, and base types under their Pepper names.
    expect_true(_line(ir, ["!DIGlobalVariable(name: \"LIMIT\""]).contains("line: 20,"));
    expect_true(ir.contains("!DIBasicType(name: \"int\", size: 32, encoding: DW_ATE_signed)"));
    # On Linux the program carries gdb's pretty-printers for the runtime's
    # types.
    expect_equal(ir.contains("section \".debug_gdb_scripts\""), link.Target().os == "linux");

    var plain = _ir(_PROGRAM, false);
    expect_false(plain.contains("!dbg"));
    expect_false(plain.contains("DICompileUnit"));
}

[Test]
g_describes_enums_tuples_traits_and_generics() {
    var ir = _ir(_TYPES, true);
    # A plain enum is an enumeration of its cases over its representation.
    expect_false(_line(ir, ["!DICompositeType(tag: DW_TAG_enumeration_type, name: \"Suit\""]).is_empty);
    expect_true(ir.contains("!DIEnumerator(name: \"Hearts\", value: 5, isUnsigned: true)"));
    # A tuple has a member per element, named by position.
    expect_false(_line(ir, ["!DICompositeType(tag: DW_TAG_structure_type, name: \"(int, Node)\""]).is_empty);
    expect_false(_line(ir, ["!DIDerivedType(tag: DW_TAG_member, name: \"1\""]).is_empty);
    # A trait value is its object and vtable.
    expect_false(_line(ir, ["!DICompositeType(tag: DW_TAG_structure_type, name: \"Shape\""]).is_empty);
    expect_false(_line(ir, ["!DIDerivedType(tag: DW_TAG_member, name: \"vtable\""]).is_empty);
    # A generic instantiation has its own type, named as written.
    expect_false(_line(ir, ["!DICompositeType(tag: DW_TAG_structure_type, name: \"Array<long>\""]).is_empty);
    expect_false(_line(ir, ["!DICompositeType(tag: DW_TAG_structure_type, name: \"Node\""]).is_empty);
    # A value enum is held inline: its structure, not a pointer to it, with
    # its payload as a member a debugger expression can name.
    expect_false(_line(ir, ["!DICompositeType(tag: DW_TAG_structure_type, name: \"Optional<int>\""]).is_empty);
    expect_true(_line(ir, ["!DIDerivedType(tag: DW_TAG_pointer_type, name: \"Optional<"]).is_empty);
    expect_false(_line(ir, ["!DIDerivedType(tag: DW_TAG_member, name: \"Value__value\""]).is_empty);
    for (var name in ["leaf", "found", "suit", "pair", "shape", "node", "counts"]) {
        expect_false(_line(ir, [$"!DILocalVariable(name: \"{name}\""]).is_empty);
    }
}

[Test]
a_closure_is_named_for_where_it_is_written() {
    var ir = _ir(
        "apply(f: (int) => int, x: int): int {\n    return f(x);\n}\n\nmain(): int {\n    var k = 2;\n    return apply((x: int) => x * k, 3) - 6;\n}\n",
        true
    );
    expect_true(ir.contains("!DISubprogram(name: \"closure at main.pep:7\""));
}

[Test]
g_gives_each_static_pass_a_stop_and_its_compile_time_variables() {
    var ir = _ir(_STATIC, true);
    # The `nop`s' lines: three passes of the `for` (line 10), two of the
    # `while` (14), and the `if` (18).
    var lines = Array<String>();
    for (var line in ir.split("\n")) {
        if (line.contains("call void asm sideeffect \"nop\"")) {
            var id = line.substr_bytes(
                line.rfind("!dbg ") as ulong + 5, line.size - line.rfind("!dbg ") as ulong - 5
            ).trim();
            var location = _line(ir, [$"{id} = !DILocation("]);
            lines.append(location.split("line: ")[1].split(",")[0]);
        }
    }
    expect_equal(", ".join(lines), "10, 10, 10, 14, 14, 18");
    # `field` once per pass, as a `reflect.Member`, and `n` in each `while`
    # pass and in the `if`.
    expect_equal(_count(ir, ["!DILocalVariable(name: \"field\",", "line: 10,"]), 3 as ulong);
    expect_equal(
        _count(ir, ["!DILocalVariable(name: \"n\",", "line: 14,"])
            + _count(ir, ["!DILocalVariable(name: \"n\",", "line: 18,"]),
        3 as ulong
    );
    expect_true(ir.contains("!DICompositeType(tag: DW_TAG_structure_type, name: \"reflect.Member\""));
    expect_true(ir.contains("c\"y\\00\""));
    # Code without `-g` has no stops.
    expect_false(_ir(_STATIC, false).contains("asm sideeffect \"nop\""));
}

[Test]
g_builds_a_program_whose_dwarf_gdb_reads() {
    var folder = TempFolder("debug_build");
    var program = _build(folder.path, _PROGRAM, 0, false);
    _run(program);
    if (link.Target().os == "linux") {
        # The section names are in the ELF's section name table.
        var bytes = _binary_text(program);
        expect_true(bytes.contains(".debug_info"));
        expect_true(bytes.contains(".debug_line"));
    }
    var text = _gdb(
        program, "break main.pep:7\nrun\nprint p.x\nprint p.y\nup\nprint first.y\ninfo locals\n", "Breakpoint 1, total"
    );
    if (text.is_value()) {
        # `up` shows the call on line 17.
        expect_equal(", ".join(_stops(text.value())), "7, 1, 2, 17, 2");
        expect_true(text.value().contains("points = "));
    }
}

[Test]
g_builds_an_optimized_program_that_runs() {
    var folder = TempFolder("debug_optimized");
    _run(_build(folder.path, _STATIC, 2, false));
}

[Test]
the_build_cache_keeps_g_objects_apart() {
    var folder = TempFolder("debug_cache");
    var program = _load(folder.path, _PROGRAM);
    var output = folder.path.join(Path("main"));
    var options = driver.BuildOptions(output, folder.path.join(Path("build")));
    options.in_process = true;
    options.cache = Optional<driver.Cache>.Value(driver.Cache(folder.path.join(Path("cache"))));
    var plain = driver.build(program, options);
    expect_true(plain.is_ok());
    # The same program with `-g` is another build: none of its objects is
    # the plain build's.
    options.debug = true;
    var debug = driver.build(_load(folder.path, _PROGRAM), options);
    expect_true(debug.is_ok());
    expect_false(debug.value().unchanged);
    expect_true(debug.value().hits.is_empty);
    _run(output);
    var again = driver.build(_load(folder.path, _PROGRAM), options);
    expect_true(again.value().unchanged);
}

[Test]
gdb_steps_through_static_passes() {
    var folder = TempFolder("debug_static");
    var program = _build(folder.path, _STATIC, 0, false);
    _run(program);
    var text = _gdb(
        program,
        "break total\nrun\nnext\nnext\nnext\nprint field.name\nnext\nnext\nprint field.name\n" + "next\n".repeat(10),
        "Breakpoint 1, total"
    );
    if (text.is_value()) {
        expect_equal(
            ", ".join(_stops(text.value())), "7, 8, 10, 11, \"x\", 10, 11, \"y\", 10, 11, 14, 15, 14, 15, 18, 19, 22"
        );
    }
}

[Test]
debug_static_expanded_writes_and_steps_through_the_expanded_source() {
    var folder = TempFolder("debug_expanded");
    var program = _build(folder.path, _STATIC, 0, true);
    _run(program);
    var expanded = File.read_to_string(folder.path.join(Path("main.static.pep")));
    expect_true(expanded.is_ok());
    var text = expanded.value();
    expect_true(text.contains("# static (sum, p) expanded from main.pep:9:5"));
    # The debug info names the copy.
    expect_true(_debug_info_text(program).contains("main.static.pep"));
    var y = _line_number(text, "sum = sum + p.y;");
    var z = _line_number(text, "sum = sum + p.z;");
    var zero = _line_number(text, "sum = sum + 0;");
    expect_true(y > 0 and z > 0 and zero > 0);
    var gdb = _gdb(
        program, $"break main.static.pep:{y}\nrun\nprint field.name\nnext\nnext\nnext\nnext\n", "Breakpoint 1, total"
    );
    if (gdb.is_value()) {
        # After the `y` pass: the `z` pass's `{`, its statement, then the
        # `while`'s first pass.
        expect_equal(", ".join(_stops(gdb.value())), $"{y}, \"y\", {z - 1}, {z}, {zero - 1}, {zero}");
    }
}

[Test]
debug_static_takes_source_or_expanded_with_g() {
    var compiler = process.find_companion("pep-build");
    if (!compiler.is_value()) {
        return;
    }
    var folder = TempFolder("debug_static_option");
    var file = folder.path.join(Path("main.pep"));
    File.write_text(file, _STATIC);
    for (var view in ["--debug-static=source", "--debug-static=expanded"]) {
        var command = process.Command(compiler.value().to_string());
        command.argument(file.to_string()).argument("-g").argument(view);
        command.argument("-o").argument(folder.path.join(Path("main")).to_string());
        command.argument("--build").argument(folder.path.join(Path("build")).to_string());
        command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
        var ran = command.run();
        expect_true(ran.is_ok() and ran.value().status.success());
        _run(folder.path.join(Path("main")));
    }
    expect_true(folder.path.join(Path("main.static.pep")).is_file());
    # It needs `-g`, and one of the two views.
    for (var arguments in [["--debug-static=source"], ["-g", "--debug-static=inline"]]) {
        var command = process.Command(compiler.value().to_string());
        command.argument(file.to_string());
        for (var argument in arguments) {
            command.argument(argument);
        }
        command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
        var ran = command.run();
        expect_true(ran.is_ok());
        expect_equal(ran.value().status.code().value(), 2);
    }
}
