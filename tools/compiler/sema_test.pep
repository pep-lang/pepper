# The compiler's sema builder builds every program of the corpus, and of
# the curated programs below, builds or rejects each as its first line
# says (`expected_outcomes`).

import io;
import [Directory, File, Path] from io;
import compiler.link;
import compiler.sema;
import [TempFolder] from testing;
import [check_programs, headline] from "expected_outcomes";

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
# programs of several files, from the `part`th, which it must build.
builds_programs(part: ulong) {
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
    ulong rejected = 0;
    ulong i = part;
    while (i < programs.count) {
        var ended = outcome(programs[i], true);
        if (ended != "accepted") {
            print($"{programs[i]}: {ended}");
            rejected += 1;
        }
        i += PARTS;
    }
    expect_equal(rejected, 0 as ulong);
}

# Programs without the runtime that exercise the builder's lowering of
# `for`, `with`, `match`, `is`, `?`, destructuring, ranges, collection
# literals, properties and `static` blocks.
[Test]
lowers_statements() {
    var folder = TempFolder("sema_lowering");
    expect_equal(check_expected(folder, lowering_programs()), 0 as ulong);
}

# Programs the builder rejects: each error, its place and its message are
# the expected ones.
[Test]
reports_builder_errors() {
    var folder = TempFolder("sema_errors");
    expect_equal(check_expected(folder, error_programs()), 0 as ulong);
}

# A model value's fingerprint is the same for an equal value (a copy) and
# differs once the value changes: the implicit-types pass relies on it to
# find the code another pass changed.
[Test]
fingerprints_tell_changed_code_apart() {
    var folder = TempFolder("sema_fingerprints");
    var path = folder.path.join("main.pep");
    File.write_text(
        path, "twice(x: int): int {\n    var y = x + x;\n    return y;\n}\nmain(): int {\n    return twice(2) - 4;\n}\n"
    );
    var setup = link.Setup();
    setup.runtime = false;
    var program = link.load_program(path, setup);
    expect_true(program.is_ok());
    var built = sema.merge(program.value());
    expect_true(built.is_ok());
    var function = built.value().functions[0];
    var copy = function.copy();
    expect_equal(_print(copy), _print(function));
    copy.name = "thrice";
    expect_true(_print(copy) != _print(function));
    copy = function.copy();
    copy.body.value().items.pop();
    expect_true(_print(copy) != _print(function));
}

# A checked module saved as a record reads back the same: the model's JSON
# (keys sorted, since a map's order is not kept) before and after the round
# trip match, for a module the passes left and
# for one only merged, on the runtime.
[Test]
records_read_back_what_they_wrote() {
    var folder = TempFolder("sema_records");
    var path = folder.path.join("main.pep");
    File.write_text(
        path,
        "struct Point {\n    var x: int;\n    var y: int;\n    construct(x: int, y: int) {\n        this.x = x;\n        this.y = y;\n    }\n}\n"
            + "main(): int {\n    var points = [Point(1, 2), Point(3, 4)];\n    var names = HashMap<String, double>();\n"
            + "    names[\"pi\"] = 3.14;\n    print($\"{points.count} {names[\"pi\"]}\");\n    return 0;\n}\n"
    );
    var program = link.load_program(path, link.Setup());
    expect_true(program.is_ok());
    var built = sema.merge(program.value());
    expect_true(built.is_ok());
    expect_equal(_round_trip(built.value()), sema.model_json(built.value()));
    var module = built.value();
    var state = sema.PassState(program.value().target);
    expect_true(sema.run_steps_with(module, state, 0xffffffffffffffff).is_ok());
    expect_equal(_round_trip(module), sema.model_json(module));
    # A record that is cut short says so rather than reading garbage.
    var out = sema.RecordOut();
    sema.write_module(out, module);
    var bytes = out.finish();
    var cut = Array<u8>();
    for (var i in 0..bytes.count / 2) {
        cut.append(bytes[i]);
    }
    var input = sema.RecordIn(cut);
    sema.read_module(input);
    expect_false(input.done());
}

# `module` written to a record and read back, as JSON.
_round_trip(module: sema.Module): String {
    var out = sema.RecordOut();
    sema.write_module(out, module);
    var input = sema.RecordIn(out.finish());
    var read = sema.read_module(input);
    expect_equal(input.error, "");
    expect_true(input.done());
    return sema.model_json(read);
}

_print(function: sema.FunctionDef): ulong {
    var into = sema.Fingerprint();
    function.fingerprint(into);
    return into.value;
}

# `check_programs` with the builder, without the runtime.
check_expected(folder: TempFolder, programs: String[]): ulong {
    return check_programs(folder, programs, (path: Path): String => outcome(path, false));
}

# How building the program rooted at `root` ends: `accepted`, or the first
# line of the error that loading or the builder reports.
outcome(root: Path, runtime: bool): String {
    var setup = link.Setup();
    setup.runtime = runtime;
    var program = link.load_program(root, setup);
    if (program.is_err()) {
        return headline(program.error(), root);
    }
    var built = sema.merge(program.value());
    if (built.is_err()) {
        return headline(built.error(), root);
    }
    return "accepted";
}

# The programs `lowers_statements` builds.
lowering_programs(): String[] {
    return [
        # Ranges, tuple and collection literals, `for`, `match` with guards
        # and alternatives, `is`, destructuring, `with` and interpolation.
        "# expect: accepted\nstruct P { var x: int = 1; var y: int = 2; }\nenum Shape { Circle(r: int), Square(side: int), Empty }\nmain(): int {\n    var total = 0;\n    for (var i in 0..10) { total += i; }\n    for (var (a, b) in [(1, 2), (3, 4)]) { total += a + b; }\n    var m = [\"a\": 1, \"b\": 2];\n    var s = Shape.Circle(3);\n    match (s) {\n        Circle(r) => { total += r; }\n        Square(side) if side > 2 => { total += side; }\n        else => {}\n    }\n    if (s is Circle(r)) { total += r; }\n    var (x, y) = (1, 2);\n    var t = match (total) { 0 => 1, 1, 2 => 2, else => 3 };\n    with (var p = P()) { total += p.x; }\n    var text = $\"{total} and {x}\";\n    return total + y + t;\n}\n",
        # Properties, `?`, a long collection literal, `while` and `?:`.
        "# expect: accepted\nstruct Box {\n    var value: int = 0;\n    var doubled: int { get { return value * 2; } set { value = field; } }\n}\nf(): Result<int, String> { var v = g()?; return Result<int, String>.Ok(v + 1); }\ng(): Result<int, String> { return Result<int, String>.Ok(1); }\nmain(): int {\n    var b = Box();\n    b.doubled = 3;\n    var list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];\n    while (b.value < 10) { b.value += 1; if (b.value == 5) { break; } }\n    var c = b.value > 2 ? 1 : 0;\n    return c;\n}\n"
    ];
}

# The programs `reports_builder_errors` builds.
error_programs(): String[] {
    return [
        # a closure in a guard cannot use 'r', bound by the arm's patterns
        "# expect: main.pep:5:29: error: a closure in a guard cannot use 'r', bound by the arm's patterns\nenum Shape { Circle(r: int), Point }\ntest(): int {\n    return match (Shape.Point) {\n        Circle(r) if (() => r)() > 1 => 1,\n        else => 2,\n    };\n}\n",
        # a destructuring assignment cannot have labels: list the places alone
        "# expect: main.pep:5:6: error: a destructuring assignment cannot have labels: list the places alone\nmain(): int {\n    var a = 1;\n    var b = 2;\n    (x: a, y: b) = (b, a);\n    return 0;\n}\n",
        # a module-scope 'static' block has no runtime values to capture
        "# expect: main.pep:4:9: error: a module-scope 'static' block has no runtime values to capture\nvar n = 0;\n\nstatic (n) {\n}\n\ntest(): int {\n    return 0;\n}\n",
        # an extension cannot add storage: property 'y' must be computed, with accessor bodies that do not use 'field'
        "# expect: main.pep:6:9: error: an extension cannot add storage: property 'y' must be computed, with accessor bodies that do not use 'field'\nstruct A {\n    var x: int;\n}\nextend A {\n    var y: int { get; }\n}\nmain(): int {\n    return 0;\n}\n",
        # 'Implicit' applies only to constructors
        "# expect: main.pep:2:1: error: 'Implicit' applies only to constructors\n[Implicit]\nstruct A {}\ntest(): int { return 0; }\n",
        # '?' can be used only in a statement of a function body
        "# expect: main.pep:11:16: error: '?' can be used only in a statement of a function body\nstruct Other {\n    construct() {}\n}\nparse(): Result<int> {\n    return Result<int>.ok(1);\n}\nmaybe(): int? {\n    return Optional<int>.Value(1);\n}\nvar g = parse()?;\ntest(): int {\n    return 0;\n}\n",
        # 'Deprecated' cannot be applied to an extension; deprecate its methods instead
        "# expect: main.pep:3:1: error: 'Deprecated' cannot be applied to an extension; deprecate its methods instead\nstruct S { int x; }\n[Deprecated(\"old\")]\nextend S { m() {} }\nmain(): int { return 0; }\n",
        # '?' cannot follow a call in the same statement
        "# expect: main.pep:6:52: error: '?' cannot follow a call in the same statement\nparse(): Result<int> {\n    return Result<int>.ok(1);\n}\nf(): Result<int> {\n    return Result<int>.ok(parse().value() + parse()?);\n}\nmain(): int {\n    return 0;\n}\n",
        # '[Shared]' does not apply to value struct 'S': it is thread-safe when its fields are
        "# expect: main.pep:3:1: error: '[Shared]' does not apply to value struct 'S': it is thread-safe when its fields are\n[Value]\n[Shared]\nstruct S {\n    const x: int;\n}\n\nmain(): int {\n    return 0;\n}\n",
        # empty array literal has no element type; declare the variable's type or write 'Array<T>()'
        "# expect: main.pep:3:13: error: empty array literal has no element type; declare the variable's type or write 'Array<T>()'\nmain(): int {\n    var a = [];\n    return 0;\n}\n",
        # empty map literal has no key or value type; declare the variable's type or write 'HashMap<K, V>()'
        "# expect: main.pep:3:13: error: empty map literal has no key or value type; declare the variable's type or write 'HashMap<K, V>()'\nmain(): int {\n    var m = [:];\n    return 0;\n}\n",
        # 'm' has no body; only a trait method or a '[__BuiltIn]' declaration may end with ';'
        "# expect: main.pep:4:5: error: 'm' has no body; only a trait method or a '[__BuiltIn]' declaration may end with ';'\nstruct S {\n    var x: int;\n    m(): int;\n}\n\nmain(): int {\n    return 0;\n}\n",
        # '__refcount' is a reserved (synthesized) member and cannot be accessed from source code
        "# expect: main.pep:5:14: error: '__refcount' is a reserved (synthesized) member and cannot be accessed from source code\nstruct P { var x: int; }\nmain(): int {\n    var p = P();\n    return p.__refcount;\n}\n",
        # 't' is bound at a different element than in the arm's first pattern: bind it at the same element in each
        "# expect: main.pep:8:72: error: 't' is bound at a different element than in the arm's first pattern: bind it at the same element in each\n\nenum Doc {\n    Text(text: String),\n    Line,\n    Pair(left: Doc, right: Doc),\n}\ntest(): int { return match (Doc.Line) { Pair(Text(t), _), Pair(_, Text(t)) => 1, else => 0 }; }",
        # 'name' is built into every enum and cannot be redeclared
        "# expect: main.pep:3:5: error: 'name' is built into every enum and cannot be redeclared\nenum E { A\n    name(): String { return \"\"; }\n}\ntest(): int { return 0; }",
        # missing label for element 1 of a labeled tuple: label every element or none
        "# expect: main.pep:2:18: error: missing label for element 1 of a labeled tuple: label every element or none\nf(): (line: int, int) {\n    return (1, 2);\n}\n",
        # 'unsafe_cast' needs the type to cast to: 'unsafe_cast<T>(value)'
        "# expect: main.pep:3:13: error: 'unsafe_cast' needs the type to cast to: 'unsafe_cast<T>(value)'\nmain(): int {\n    var x = unsafe_cast(3);\n    return 0;\n}\n",
        # only one constructor of 'Meters' may be 'Implicit'
        "# expect: main.pep:7:5: error: only one constructor of 'Meters' may be 'Implicit'\n\nstruct Meters {\n    int value;\n    [Implicit]\n    construct(v: int) { value = v; }\n    [Implicit]\n    construct(v: double) { value = 0; }\n}\ntest(): int { return 0; }\n",
        # only one of '[Likely]' or '[Unlikely]' can mark an 'if'
        "# expect: main.pep:5:5: error: only one of '[Likely]' or '[Unlikely]' can mark an 'if'\nmain(): int {\n    var n = 1;\n    [Likely]\n    [Unlikely]\n    if (n > 0) {\n        return 1;\n    }\n    return 0;\n}\n",
        # positional argument cannot follow a named argument
        "# expect: main.pep:4:21: error: positional argument cannot follow a named argument\nf(a: int, b: int): int { return a + b; }\nmain(): int {\n    return f(a = 1, 2);\n}\n",
        # '?' requires the enclosing function to return a Result or an Optional
        "# expect: main.pep:12:12: error: '?' requires the enclosing function to return a Result or an Optional\nstruct Other {\n    construct() {}\n}\nparse(): Result<int> {\n    return Result<int>.ok(1);\n}\nmaybe(): int? {\n    return Optional<int>.Value(1);\n}\nf(): void {\n    parse()?;\n}\ntest(): int {\n    return 0;\n}\n",
        # 'unsafe_cast' takes 1 type argument, have 2
        "# expect: main.pep:3:13: error: 'unsafe_cast' takes 1 type argument, have 2\nmain(): int {\n    var x = unsafe_cast<int, int>(3);\n    return 0;\n}\n",
        # 'Likely' takes no arguments
        "# expect: main.pep:5:9: error: 'Likely' takes no arguments\nmain(): int {\n    var n = 1;\n    match (n) {\n        [Likely(2)]\n        1 => { return 1; }\n        else => { return 0; }\n    }\n}\n"
    ];
}
