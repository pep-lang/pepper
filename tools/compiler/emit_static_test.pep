# `--emit-static` (`driver/emit_static.pep`): the program's source with each
# `static` block replaced by what it emits, which must build into the same
# program.

import compiler.driver;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import [TempFolder] from testing;

const _CONCRETE = "struct Point {\n    var x: int;\n    var y: int;\n}\n\nsum(p: Point): int {\n    var total = 0;\n    static (total, p) {\n        var n = 0;\n        while (n < 3) {\n            total += n * 10;\n            n += 1;\n        }\n        for (var field in reflect.properties<Point>()) {\n            if (field.index == 0) {\n                continue;\n            }\n            {\n                var doubled = field.get(p) * 2;\n                if (doubled > 4) {\n                    total += doubled;\n                } else {\n                    total -= 1;\n                }\n            }\n            reflect.print(field.name);\n        }\n        if (reflect.is_struct<Point>()) {\n            total += $\"{reflect.name<Point>()}!\".length;\n        } else {\n            total = 0;\n        }\n    }\n    return total;\n}\n\nmain(): int {\n    var p = Point();\n    p.x = 1;\n    p.y = 5;\n    print(sum(p));\n    return 0;\n}\n";

const _GENERIC = "struct Point {\n    var x: int;\n    var y: int;\n}\n\nstruct Size {\n    var width: int;\n}\n\nnames<T>(value: T): String {\n    var out = \"\";\n    static (out, value) {\n        for (var field in reflect.properties<T>()) {\n            var copy: field.Type = field.get(value);\n            out = out + $\"{field.name}={copy} \";\n        }\n    }\n    return out;\n}\n\nstruct Box<T> {\n    var value: T;\n\n    count(): int {\n        var n = 0;\n        static (n) {\n            for (var field in reflect.properties<T>()) {\n                n += 1;\n            }\n        }\n        return n;\n    }\n}\n\nmain(): int {\n    var p = Point();\n    p.x = 1;\n    var s = Size();\n    s.width = 7;\n    print(names(p) + names(s));\n    var b = Box<Point>();\n    print(b.count());\n    return 0;\n}\n";

const _CASES = "enum Shape {\n    Circle(radius: int),\n    Rect(width: int, height: int),\n}\n\nenum Color {\n    Red,\n    Green,\n}\n\n[Attribute]\nstruct Step {}\n\n[Step]\nfirst(): int {\n    return 1;\n}\n\nstruct Counter {\n    var hits: int;\n}\n\ntotal(shape: Shape, color: Color, counter: Counter): int {\n    var sum = 0;\n    static (sum, shape, color, counter) {\n        for (var case in reflect.cases<Shape>()) {\n            if (case.matches(shape)) {\n                for (var item in case.values) {\n                    sum += item.get(shape) * (item.index + 1);\n                }\n            }\n        }\n        for (var case in reflect.cases<Color>()) {\n            if (case.matches(color)) {\n                sum += case.value * 100;\n            }\n        }\n        for (var step in reflect.functions_with<Step>()) {\n            sum += step.call();\n        }\n        for (var field in reflect.properties<Counter>()) {\n            field.set(counter, sum);\n        }\n    }\n    return sum;\n}\n\nmain(): int {\n    var counter = Counter();\n    print(total(Shape.Rect(3, 4), Color.Green, counter));\n    print(counter.hits);\n    return 0;\n}\n";

# Writes `text` to `path`, making its folder.
_write(path: Path, text: String) {
    Directory.create_all(path.parent().value());
    File.write_text(path, text);
}

# The program whose entry is `main`, loaded with the runtime.
_load(main: Path): link.Program {
    var program = link.load_program(main, link.Setup());
    if (program.is_err()) {
        print(program.error());
    }
    expect_true(program.is_ok());
    return program.value();
}

# `--emit-static` (`--emit-static=keep` with `keep`) of the program whose
# entry is `main`, into `out`.
_emit(main: Path, out: Path, keep: bool): Result<void, String> {
    var setup = link.Setup();
    var program = link.load_program(main, setup);
    if (program.is_err()) {
        return Result<void, String>.err(program.error());
    }
    return driver.emit_static(program.value(), main, out, keep);
}

# `main` built into `dir` as `name` and run: its output, then its exit
# status.
_build_and_run(main: Path, dir: Path, name: String): String {
    var output = dir.join(Path(name));
    var options = driver.BuildOptions(output, dir.join(Path($"{name}.build")));
    options.in_process = true;
    var built = driver.build(_load(main), options);
    if (built.is_err()) {
        return $"build failed: {built.error()}";
    }
    var command = process.Command(output.to_string());
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var ran = command.run();
    if (ran.is_err()) {
        return "cannot run";
    }
    # Windows writes a line ending as `\r\n`.
    var stdout = ran.value().stdout.replace("\r\n", "\n");
    return $"{stdout}\nexit: {ran.value().status.code().value_or(-1)}";
}

# `_emit` that must succeed, returning the copy of `name`.
_emitted(main: Path, out: Path, keep: bool, name: String): String {
    var made = _emit(main, out, keep);
    if (made.is_err()) {
        print(made.error());
    }
    expect_true(made.is_ok());
    var text = File.read_to_string(out.join(Path(name)));
    expect_true(text.is_ok());
    return text.ok_or("");
}

# `text` with each run of whitespace as one space, so a line the emitted
# file's formatting wraps still matches its one-line form.
_spaced(text: String): String {
    var spaced = text.replace("\n", " ");
    while (spaced.contains("  ")) {
        spaced = spaced.replace("  ", " ");
    }
    return spaced;
}

# Prints `text` when it lacks `expected`, which it must hold (whitespace
# aside).
_expect_contains(text: String, expected: String) {
    bool found = _spaced(text).contains(_spaced(expected));
    if (!found) {
        print($"missing:\n{expected}\nin:\n{text}");
    }
    expect_true(found);
}

[Test]
expands_for_if_while_nested_blocks_and_captures() {
    var folder = TempFolder("emit_concrete");
    var main = folder.path.join(Path("main.pep"));
    _write(main, _CONCRETE);
    var out = folder.path.join(Path("out"));
    var emitted = _emitted(main, out, false, "main.pep");
    # Each `while` iteration and `for` pass is a block; the pass `continue`
    # skipped and the compile-time steps are gone; the `if` kept one branch.
    _expect_contains(
        emitted,
        "sum(p: Point): int {\n    var total = 0;\n    # static (total, p) expanded from main.pep:8:5\n    {\n        {\n            total += 0;\n        }\n        {\n            total += 10;\n        }\n        {\n            total += 20;\n        }\n        {\n            {\n                var doubled = p.y * 2;\n                if (doubled > 4) {\n                    total += doubled;\n                } else {\n                    total -= 1;\n                }\n            }\n        }\n        {\n            total += 6;\n        }\n    }\n    # end static\n    return total;\n}\n"
    );
    # Everything else is unchanged.
    expect_true(emitted.starts_with(_CONCRETE.substr_bytes(0, _CONCRETE.find("sum(") as ulong)));
    var tail = _CONCRETE.find("main(): int") as ulong;
    expect_true(emitted.ends_with(_CONCRETE.substr_bytes(tail, _CONCRETE.size - tail)));
    expect_equal(
        _build_and_run(out.join(Path("main.pep")), folder.path, "emitted"),
        _build_and_run(main, folder.path, "original")
    );
}

[Test]
keep_writes_the_block_as_comments_above_its_expansion() {
    var folder = TempFolder("emit_keep");
    var main = folder.path.join(Path("main.pep"));
    _write(main, _CONCRETE);
    var emitted = _emitted(main, folder.path.join(Path("out")), true, "main.pep");
    _expect_contains(emitted, "    # static (total, p) {\n    #     var n = 0;\n    #     while (n < 3) {\n");
    _expect_contains(emitted, "    #     }\n    # }\n    # static (total, p) expanded from main.pep:8:5\n    {\n");
}

[Test]
generic_functions_get_a_specialized_copy_per_use() {
    var folder = TempFolder("emit_generic");
    var main = folder.path.join(Path("main.pep"));
    _write(main, _GENERIC);
    var out = folder.path.join(Path("out"));
    var emitted = _emitted(main, out, false, "main.pep");
    # The generic function stays, followed by one override per type.
    _expect_contains(
        emitted,
        "\n# 'names' specialized for T = Point, with its static blocks expanded\nnames<Point>(value: Point): String {\n    var out = \"\";\n    # static (out, value) expanded from main.pep:12:5 for T = Point\n    {\n        {\n            var copy: int = value.x;\n            out = out + $\"x={copy} \";\n        }\n        {\n            var copy: int = value.y;\n            out = out + $\"y={copy} \";\n        }\n    }\n    # end static\n    return out;\n}\n"
    );
    _expect_contains(emitted, "names<Size>(value: Size): String {");
    _expect_contains(emitted, "names<T>(value: T): String {\n    var out = \"\";\n    static (out, value) {");
    # A generic method keeps its block, with each expansion as comments.
    _expect_contains(
        emitted,
        "        # static (n) at main.pep:26:9 expands in each specialization:\n        # for T = Point\n        # {\n        #     {\n        #         n += 1;\n"
    );
    _expect_contains(emitted, "        # end static\n        static (n) {\n");
    expect_equal(
        _build_and_run(out.join(Path("main.pep")), folder.path, "emitted"),
        _build_and_run(main, folder.path, "original")
    );
}

[Test]
cases_functions_and_set_round_trip() {
    var folder = TempFolder("emit_cases");
    var main = folder.path.join(Path("main.pep"));
    _write(main, _CASES);
    var out = folder.path.join(Path("out"));
    var emitted = _emitted(main, out, false, "main.pep");
    for (var expected in [
        "if (shape is Shape.Rect) {",
        "sum += match (shape) { Shape.Rect(_, _pep_value) => _pep_value, else => __default<int>() } * (2);",
        "if (color == Color.Green) {",
        "sum += first();",
        "counter.hits = sum;"
    ]) {
        _expect_contains(emitted, expected);
    }
    expect_equal(
        _build_and_run(out.join(Path("main.pep")), folder.path, "emitted"),
        _build_and_run(main, folder.path, "original")
    );
}

[Test]
files_without_blocks_are_copied_and_originals_are_kept() {
    var folder = TempFolder("emit_files");
    var helper = "# Unchanged.\nexport twice(n: int): int {\n    return n * 2;\n}\n";
    var source = "import \"helpers/math\" as math;\n\nmain(): int {\n    var n = 0;\n    static (n) {\n        n = 21;\n    }\n    print(math.twice(n));\n    return 0;\n}\n";
    var main = folder.path.join(Path("main.pep"));
    _write(main, source);
    _write(folder.path.join(Path("helpers")).join(Path("math.pep")), helper);
    var out = folder.path.join(Path("expanded"));
    var emitted = _emitted(main, out, false, "main.pep");
    expect_equal(File.read_to_string(out.join(Path("helpers")).join(Path("math.pep"))).value(), helper);
    expect_equal(File.read_to_string(main).value(), source);
    _expect_contains(emitted, "    {\n        n = 21;\n    }\n    # end static\n");
    expect_equal(_build_and_run(out.join(Path("main.pep")), folder.path, "emitted"), "42\n\nexit: 0");
    # Never over the originals.
    var over = _emit(main, folder.path, false);
    expect_true(over.is_err() and over.error().contains("would overwrite"));
}

[Test]
an_error_in_a_block_stops_it_as_it_stops_a_build() {
    var folder = TempFolder("emit_errors");
    var main = folder.path.join(Path("bad.pep"));
    _write(main, "main(): int {\n    static {\n        reflect.error(\"not ready\");\n    }\n    return 0;\n}\n");
    var out = folder.path.join(Path("bad"));
    var made = _emit(main, out, false);
    expect_true(made.is_err() and made.error().contains("bad.pep:3:17: error: not ready"));
    expect_false(out.exists());
}

# Emits and builds every `reflection-*` docs example whose index in the
# listing is `part` modulo `parts`, and requires the expanded copy to print
# what the original prints. Split in parts, since each example builds twice
# and a slow runner would pass the test timeout with all of them in one.
_reflection_examples_round_trip(part: ulong, parts: ulong) {
    var examples = Path("../docs/examples");
    var programs = Array<Path>();
    for (var entry in Directory.open(examples).value().entries().value()) {
        if (!entry.name.starts_with("reflection-")) {
            continue;
        }
        programs.append(
            entry.is_directory ?
                examples.join(Path(entry.name)).join(Path("main.pep")) :
                examples.join(Path(entry.name))
        );
    }
    expect_true(programs.count >= 8);
    for (var index in 0..programs.count) {
        if (index % parts != part) {
            continue;
        }
        var main = programs[index];
        var folder = TempFolder("emit_examples");
        var out = folder.path.join(Path("out"));
        var made = _emit(main, out, false);
        if (made.is_err()) {
            print($"{main}: {made.error()}");
        }
        expect_true(made.is_ok());
        var emitted = out.join(Path(main.file_name().value()));
        var text = File.read_to_string(emitted).ok_or("");
        expect_false(text.contains("static (") and !text.contains("expanded from"));
        var original = _build_and_run(main, folder.path, "original");
        var copy = _build_and_run(emitted, folder.path, "emitted");
        if (original != copy) {
            print($"{main}: the expanded copy prints\n{copy}\ninstead of\n{original}");
        }
        expect_equal(copy, original);
    }
}

[Test]
reflection_examples_round_trip_part_1() {
    _reflection_examples_round_trip(0, 3);
}

[Test]
reflection_examples_round_trip_part_2() {
    _reflection_examples_round_trip(1, 3);
}

[Test]
reflection_examples_round_trip_part_3() {
    _reflection_examples_round_trip(2, 3);
}
