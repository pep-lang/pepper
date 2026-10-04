# The compiler's sema builder in Pepper makes the same model of a linked
# program as the Rust builder: the JSON of the model before any pass, from
# `compiler.sema` here and from `pep-build --emit-model`, match byte for
# byte, and a program the builder rejects gets the same error.

import io;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import compiler.sema;
import [TempFolder] from testing;

# The programs are split in parts, each a test of its own, to keep each
# within the time a test may take.
[Test]
builds_the_test_programs_part_1() {
    builds_programs(0);
}

[Test]
builds_the_test_programs_part_2() {
    builds_programs(1);
}

[Test]
builds_the_test_programs_part_3() {
    builds_programs(2);
}

[Test]
builds_the_test_programs_part_4() {
    builds_programs(3);
}

[Test]
builds_the_test_programs_part_5() {
    builds_programs(4);
}

[Test]
builds_the_test_programs_part_6() {
    builds_programs(5);
}

[Test]
builds_the_test_programs_part_7() {
    builds_programs(6);
}

[Test]
builds_the_test_programs_part_8() {
    builds_programs(7);
}

const PARTS = 8;

# Builds every `PARTS`th program of the corpus and the documentation's
# programs of several files, from the `part`th, with both builders.
builds_programs(part: ulong) {
    var compiler = process.find_companion("pep-build");
    expect_true(compiler.is_value(), "pep-build is beside pep-test or on the PATH");
    if (!compiler.is_value()) {
        return;
    }
    var programs = Array<Path>();
    # The corpus: one `test.pep` per folder.
    var listing = Directory.open(Path("../tests"));
    expect_true(listing.is_ok(), "the corpus is found from tools/");
    var names = Array<String>();
    for (var entry in listing.value().entries().value()) {
        if (entry.is_directory) {
            names.append(entry.name);
        }
    }
    names.sort((a, b) => a.compare(b));
    for (var name in names) {
        var program = Path("../tests").join(name).join("test.pep");
        if (program.is_file()) {
            programs.append(program);
        }
    }
    # The documentation's programs of several files and modules.
    for (var name in [
        "modules-files",
        "modules-folders",
        "modules-reexports",
        "overloading-modules",
        "visibility-modules",
        "visibility-namespaces"
    ]) {
        programs.append(Path("../docs/examples").join(name).join("main.pep"));
    }
    expect_true(programs.count > 40, "the corpus has its programs");
    ulong mismatches = 0;
    ulong i = part;
    while (i < programs.count) {
        if (!same_model(compiler.value(), programs[i], Array<String>(), true)) {
            mismatches += 1;
        }
        i += PARTS;
    }
    expect_equal(mismatches, 0 as ulong);
}

# Programs without the runtime that exercise the builder's lowering of
# `for`, `with`, `match`, `is`, `?`, destructuring, ranges, collection
# literals, properties and `static` blocks.
[Test]
lowers_statements_as_the_rust_builder_does() {
    var compiler = process.find_companion("pep-build");
    if (!compiler.is_value()) {
        return;
    }
    var folder = TempFolder("sema_lowering");
    expect_equal(write_and_compare(compiler.value(), folder, lowering_programs()), 0 as ulong);
}

# Programs the builder rejects: each error, its place and its message match
# the Rust builder's.
[Test]
reports_builder_errors_as_the_rust_builder_does() {
    var compiler = process.find_companion("pep-build");
    if (!compiler.is_value()) {
        return;
    }
    var folder = TempFolder("sema_errors");
    expect_equal(write_and_compare(compiler.value(), folder, error_programs()), 0 as ulong);
}

# Writes each program to a `main.pep` of its own in `folder`, compares the
# two builders' models of it, without the runtime, and returns how many
# differ.
write_and_compare(compiler: Path, folder: TempFolder, programs: String[]): ulong {
    ulong mismatches = 0;
    ulong t = 0;
    while (t < programs.count) {
        var root = folder.path.join($"program{t}");
        Directory.create_all(root);
        var path = root.join("main.pep");
        File.write_text(path, programs[t]);
        if (!same_model(compiler, path, ["--no-runtime"], false)) {
            mismatches += 1;
        }
        t += 1;
    }
    return mismatches;
}

# Whether the two builders agree on the program rooted at `root`: the same
# model, or the same error. A program the Rust compiler cannot load or
# link is skipped.
same_model(compiler: Path, root: Path, arguments: String[], runtime: bool): bool {
    var command = process.Command(compiler.to_string()).argument("--emit-model");
    for (var argument in arguments) {
        command.argument(argument);
    }
    var output = command.argument(root.to_string()).stdout(process.Stream.Pipe).stderr(process.Stream.Pipe).run();
    if (output.is_err()) {
        return true;
    }
    var setup = link.Setup();
    setup.runtime = runtime;
    var program = link.load_program(root, setup);
    if (program.is_err()) {
        return true;
    }
    var built = sema.merge(program.value());
    if (!output.value().status.success()) {
        var expected = trimmed(output.value().stderr);
        if (!built.is_err()) {
            print($"{root}: the Rust builder rejects it, but not this one: {expected}");
            return false;
        }
        if (built.error() != expected) {
            print($"{root}: the error differs from the Rust builder's:\n{built.error()}\nnot\n{expected}");
            return false;
        }
        return true;
    }
    if (built.is_err()) {
        print($"{root}: the Rust builder builds it, but: {built.error()}");
        return false;
    }
    var expected = trimmed(output.value().stdout);
    var actual = sema.model_json(built.value());
    if (actual != expected) {
        print(
            $"{root}: the model differs from the Rust builder's at byte {first_difference(actual, expected)} of its JSON"
        );
        return false;
    }
    return true;
}

trimmed(text: String): String {
    if (text.ends_with("\n")) {
        return text.substr_bytes(0, text.size - 1);
    }
    return text;
}

first_difference(a: String, b: String): ulong {
    ulong i = 0;
    while (i < a.size and i < b.size and a.byte_at(i) == b.byte_at(i)) {
        i += 1;
    }
    return i;
}

# The programs `lowers_statements_as_the_rust_builder_does` builds.
lowering_programs(): String[] {
    return [
        # Ranges, tuple and collection literals, `for`, `match` with guards
        # and alternatives, `is`, destructuring, `with` and interpolation.
        "struct P { var x: int = 1; var y: int = 2; }\nenum Shape { Circle(r: int), Square(side: int), Empty }\nmain(): int {\n    var total = 0;\n    for (var i in 0..10) { total += i; }\n    for (var (a, b) in [(1, 2), (3, 4)]) { total += a + b; }\n    var m = [\"a\": 1, \"b\": 2];\n    var s = Shape.Circle(3);\n    match (s) {\n        Circle(r) => { total += r; }\n        Square(side) if side > 2 => { total += side; }\n        else => {}\n    }\n    if (s is Circle(r)) { total += r; }\n    var (x, y) = (1, 2);\n    var t = match (total) { 0 => 1, 1, 2 => 2, else => 3 };\n    with (var p = P()) { total += p.x; }\n    var text = $\"{total} and {x}\";\n    return total + y + t;\n}\n",
        # Properties, `?`, a long collection literal, `while` and `?:`.
        "struct Box {\n    var value: int = 0;\n    var doubled: int { get { return value * 2; } set { value = field; } }\n}\nf(): Result<int, String> { var v = g()?; return Result<int, String>.Ok(v + 1); }\ng(): Result<int, String> { return Result<int, String>.Ok(1); }\nmain(): int {\n    var b = Box();\n    b.doubled = 3;\n    var list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];\n    while (b.value < 10) { b.value += 1; if (b.value == 5) { break; } }\n    var c = b.value > 2 ? 1 : 0;\n    return c;\n}\n"
    ];
}

# The programs `reports_builder_errors_as_the_rust_builder_does` builds,
# each with the error the Rust builder reports.
error_programs(): String[] {
    return [
        # a closure in a guard cannot use 'r', bound by the arm's patterns
        "enum Shape { Circle(r: int), Point }\ntest(): int {\n    return match (Shape.Point) {\n        Circle(r) if (() => r)() > 1 => 1,\n        else => 2,\n    };\n}\n",
        # a destructuring assignment cannot have labels: list the places alone
        "main(): int {\n    var a = 1;\n    var b = 2;\n    (x: a, y: b) = (b, a);\n    return 0;\n}\n",
        # a module-scope 'static' block has no runtime values to capture
        "var n = 0;\n\nstatic (n) {\n}\n\ntest(): int {\n    return 0;\n}\n",
        # an extension cannot add storage: property 'y' must be computed, with accessor bodies that do not use 'field'
        "struct A {\n    var x: int;\n}\nextend A {\n    var y: int { get; }\n}\nmain(): int {\n    return 0;\n}\n",
        # 'Implicit' applies only to constructors
        "[Implicit]\nstruct A {}\ntest(): int { return 0; }\n",
        # '?' can be used only in a statement of a function body
        "struct Other {\n    construct() {}\n}\nparse(): Result<int> {\n    return Result<int>.ok(1);\n}\nmaybe(): int? {\n    return Optional<int>.Value(1);\n}\nvar g = parse()?;\ntest(): int {\n    return 0;\n}\n",
        # 'Deprecated' cannot be applied to an extension; deprecate its methods instead
        "struct S { int x; }\n[Deprecated(\"old\")]\nextend S { m() {} }\nmain(): int { return 0; }\n",
        # '?' cannot follow a call in the same statement
        "parse(): Result<int> {\n    return Result<int>.ok(1);\n}\nf(): Result<int> {\n    return Result<int>.ok(parse().value() + parse()?);\n}\nmain(): int {\n    return 0;\n}\n",
        # '[Shared]' does not apply to value struct 'S': it is thread-safe when its fields are
        "[Value]\n[Shared]\nstruct S {\n    const x: int;\n}\n\nmain(): int {\n    return 0;\n}\n",
        # empty array literal has no element type; declare the variable's type or write 'Array<T>()'
        "main(): int {\n    var a = [];\n    return 0;\n}\n",
        # empty map literal has no key or value type; declare the variable's type or write 'HashMap<K, V>()'
        "main(): int {\n    var m = [:];\n    return 0;\n}\n",
        # 'm' has no body; only a trait method or a '[__BuiltIn]' declaration may end with ';'
        "struct S {\n    var x: int;\n    m(): int;\n}\n\nmain(): int {\n    return 0;\n}\n",
        # '__refcount' is a reserved (synthesized) member and cannot be accessed from source code
        "struct P { var x: int; }\nmain(): int {\n    var p = P();\n    return p.__refcount;\n}\n",
        # 't' is bound at a different element than in the arm's first pattern: bind it at the same element in each
        "\nenum Doc {\n    Text(text: String),\n    Line,\n    Pair(left: Doc, right: Doc),\n}\ntest(): int { return match (Doc.Line) { Pair(Text(t), _), Pair(_, Text(t)) => 1, else => 0 }; }",
        # 'name' is built into every enum and cannot be redeclared
        "enum E { A\n    name(): String { return \"\"; }\n}\ntest(): int { return 0; }",
        # missing label for element 1 of a labeled tuple: label every element or none
        "f(): (line: int, int) {\n    return (1, 2);\n}\n",
        # 'unsafe_cast' needs the type to cast to: 'unsafe_cast<T>(value)'
        "main(): int {\n    var x = unsafe_cast(3);\n    return 0;\n}\n",
        # only one constructor of 'Meters' may be 'Implicit'
        "\nstruct Meters {\n    int value;\n    [Implicit]\n    construct(v: int) { value = v; }\n    [Implicit]\n    construct(v: double) { value = 0; }\n}\ntest(): int { return 0; }\n",
        # only one of '[Likely]' or '[Unlikely]' can mark an 'if'
        "main(): int {\n    var n = 1;\n    [Likely]\n    [Unlikely]\n    if (n > 0) {\n        return 1;\n    }\n    return 0;\n}\n",
        # positional argument cannot follow a named argument
        "f(a: int, b: int): int { return a + b; }\nmain(): int {\n    return f(a = 1, 2);\n}\n",
        # '?' requires the enclosing function to return a Result or an Optional
        "struct Other {\n    construct() {}\n}\nparse(): Result<int> {\n    return Result<int>.ok(1);\n}\nmaybe(): int? {\n    return Optional<int>.Value(1);\n}\nf(): void {\n    parse()?;\n}\ntest(): int {\n    return 0;\n}\n",
        # 'unsafe_cast' takes 1 type argument, have 2
        "main(): int {\n    var x = unsafe_cast<int, int>(3);\n    return 0;\n}\n",
        # 'Likely' takes no arguments
        "main(): int {\n    var n = 1;\n    match (n) {\n        [Likely(2)]\n        1 => { return 1; }\n        else => { return 0; }\n    }\n}\n"
    ];
}
