# The compiler's sema passes in Pepper change the model as the Rust passes
# do: after the steps ported so far (`sema.PORTED_STEPS`), the model's JSON
# from `compiler.sema` here and from `pep-build --emit-model
# --emit-model-step N` match byte for byte, and a program a step rejects
# gets the same error.

import [render_all] from compiler.diagnostic;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import compiler.sema;
import [TempFolder] from testing;

# The programs are split in parts, each a test of its own, to keep each
# within the time a test may take.
[Test]
runs_the_passes_over_the_test_programs_part_1() {
    runs_passes(0);
}

[Test]
runs_the_passes_over_the_test_programs_part_2() {
    runs_passes(1);
}

[Test]
runs_the_passes_over_the_test_programs_part_3() {
    runs_passes(2);
}

[Test]
runs_the_passes_over_the_test_programs_part_4() {
    runs_passes(3);
}

[Test]
runs_the_passes_over_the_test_programs_part_5() {
    runs_passes(4);
}

[Test]
runs_the_passes_over_the_test_programs_part_6() {
    runs_passes(5);
}

[Test]
runs_the_passes_over_the_test_programs_part_7() {
    runs_passes(6);
}

[Test]
runs_the_passes_over_the_test_programs_part_8() {
    runs_passes(7);
}

const PARTS = 8;

# Runs the passes over every `PARTS`th program of the corpus and the
# documentation's programs of several files, from the `part`th, with both
# compilers.
runs_passes(part: ulong) {
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
        if (!same_passes(compiler.value(), programs[i], Array<String>(), true)) {
            mismatches += 1;
        }
        i += PARTS;
    }
    expect_equal(mismatches, 0 as ulong);
}

# Programs without the runtime whose platform attributes a pass rejects:
# each error, its place and its message match the Rust compiler's.
[Test]
reports_pass_errors_as_the_rust_passes_do() {
    var compiler = process.find_companion("pep-build");
    if (!compiler.is_value()) {
        return;
    }
    var folder = TempFolder("passes_errors");
    expect_equal(write_and_compare(compiler.value(), folder, error_programs()), 0 as ulong);
}

# Programs the platform filters, the closures lifting and the struct
# synthesis change, without the runtime.
[Test]
rewrites_programs_as_the_rust_passes_do() {
    var compiler = process.find_companion("pep-build");
    if (!compiler.is_value()) {
        return;
    }
    var folder = TempFolder("passes_programs");
    expect_equal(write_and_compare(compiler.value(), folder, rewritten_programs()), 0 as ulong);
}

# Writes each program to a `main.pep` of its own in `folder`, compares the
# two compilers' passes over it, without the runtime, and returns how many
# differ.
write_and_compare(compiler: Path, folder: TempFolder, programs: String[]): ulong {
    ulong mismatches = 0;
    ulong t = 0;
    while (t < programs.count) {
        var root = folder.path.join($"program{t}");
        Directory.create_all(root);
        var path = root.join("main.pep");
        File.write_text(path, programs[t]);
        if (!same_passes(compiler, path, ["--no-runtime"], false)) {
            mismatches += 1;
        }
        t += 1;
    }
    return mismatches;
}

# Whether the two compilers' passes agree on the program rooted at `root`
# after the ported steps, and if not, reports the first step where they
# part.
same_passes(compiler: Path, root: Path, arguments: String[], runtime: bool): bool {
    var steps = sema.PORTED_STEPS;
    var first = compare_step(compiler, root, arguments, runtime, steps);
    if (!first.is_value()) {
        return true;
    }
    # Find the first step that differs.
    ulong step = 1;
    while (step < steps) {
        var differs = compare_step(compiler, root, arguments, runtime, step);
        if (differs.is_value()) {
            print($"{root}: step {step}: {differs.value()}");
            return false;
        }
        step += 1;
    }
    print($"{root}: step {steps}: {first.value()}");
    return false;
}

# How the two compilers' models of the program rooted at `root` differ
# after `steps` steps, or none when they match.
compare_step(compiler: Path, root: Path, arguments: String[], runtime: bool, steps: ulong): String? {
    var command = process
        .Command(compiler.to_string())
        .argument("--emit-model")
        .argument("--emit-model-step")
        .argument($"{steps}");
    for (var argument in arguments) {
        command.argument(argument);
    }
    var output = command.argument(root.to_string()).stdout(process.Stream.Pipe).stderr(process.Stream.Pipe).run();
    if (output.is_err()) {
        return Optional<String>.Empty;
    }
    var setup = link.Setup();
    setup.runtime = runtime;
    # A program the Rust compiler builds must load here too; one it
    # rejects before the passes is sema_test's to compare.
    var accepted = output.value().status.success();
    var program = link.load_program(root, setup);
    if (program.is_err()) {
        return accepted ?
            Optional<String>.Value("the Rust compiler loads it, but not this one") :
            Optional<String>.Empty;
    }
    var built = sema.merge(program.value());
    if (built.is_err()) {
        return accepted ?
            Optional<String>.Value("the Rust compiler merges it, but not this one") :
            Optional<String>.Empty;
    }
    var module = built.value();
    var ran = sema.run_steps(module, program.value().target, steps);
    if (!output.value().status.success()) {
        var expected = trimmed(output.value().stderr);
        if (!ran.is_err()) {
            return Optional<String>.Value($"the Rust passes reject it, but not these: {expected}");
        }
        var actual = render_all([ran.error()], program.value().sources());
        if (actual != expected) {
            return Optional<String>.Value($"the error differs from the Rust passes':\n{actual}\nnot\n{expected}");
        }
        return Optional<String>.Empty;
    }
    if (ran.is_err()) {
        return Optional<String>.Value(
            $"the Rust passes accept it, but: {render_all([ran.error()], program.value().sources())}"
        );
    }
    var expected = trimmed(output.value().stdout);
    var actual = sema.model_json(module);
    if (actual != expected) {
        return Optional<String>.Value(
            $"the model differs from the Rust passes' at byte {first_difference(actual, expected)} of its JSON: {excerpt(actual, first_difference(actual, expected))} not {excerpt(expected, first_difference(actual, expected))}"
        );
    }
    return Optional<String>.Empty;
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

# Up to 120 bytes of `text` around `at`.
excerpt(text: String, at: ulong): String {
    var start = at > 60 ? at - 60 : 0;
    var end = at + 60 < text.size ? at + 60 : text.size;
    return text.substr_bytes(start, end - start);
}

# Programs a pass rejects.
error_programs(): String[] {
    return [
        # A misspelled OS, in code that would be dropped anyway.
        "[Target(OS(Windoze))]\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        # A build option comparison with no literal.
        "[Target(BuildOption(A) == BuildOption(B))]\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        # A malformed predicate inside a dropped block.
        "main(): int {\n    [Target(OS(Windows))] {\n        [Target(Arch(z80))] {\n            return 1;\n        }\n    }\n    return 0;\n}\n",
        # A test that takes a parameter, and one that returns a value.
        "[Test]\nt(x: int) {}\nmain(): int { return 0; }\n",
        "[Test]\nt(): int { return 1; }\nmain(): int { return 0; }\n",
        "[ShouldPanic]\nt() {}\nmain(): int { return 0; }\n",
        "struct S {\n    [Test]\n    t() {}\n}\nmain(): int { return 0; }\n",
        # A captured local that is assigned.
        "main(): int {\n    var n = 1;\n    var f = () => n + 1;\n    n = 2;\n    return f();\n}\n",
        # `this` in a closure of a static method.
        "struct S {\n    var x: int;\n    static make(): () => int {\n        return () => x;\n    }\n}\nmain(): int { return 0; }\n",
        # A closure capturing `this` stored in a field of `this`.
        "struct S {\n    var x: int;\n    var f: () => int;\n    set() {\n        f = () => x;\n    }\n}\nmain(): int { return 0; }\n",
        # Misplaced and contradictory `[Equatable]`.
        "[Equatable]\nenum E { A, B }\nmain(): int { return 0; }\n",
        "struct S {\n    [Equatable(exclude = true)]\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "[Equatable(include = true)]\nstruct S {\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "[Equatable]\nstruct S {\n    [Equatable(include = true, exclude = false)]\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "[Equatable]\nstruct S {\n    [Equatable(include = 1)]\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "[Equatable]\n[Value]\nstruct S {\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "[Equatable]\nstruct S {\n    var x: int;\n    ==(other: S): bool { return true; }\n}\nmain(): int { return 0; }\n",
        # Type aliases: a cycle, too many arguments, a missing one.
        "type A = B;\ntype B = Box<A>;\nstruct Box<T> { var v: T; }\nmain(): int { return 0; }\n",
        "type P<T> = Box<T>;\nstruct Box<T> { var v: T; }\nf(p: P<int, int>) {}\nmain(): int { return 0; }\n",
        "type P<T, U> = Box<T>;\nstruct Box<T> { var v: T; }\nf(p: P<int>) {}\nmain(): int { return 0; }\n",
        # A constructor parameter that names no field.
        "struct S {\n    var x: int;\n    construct(this.y = 0) {}\n}\nmain(): int { return 0; }\n"
    ];
}

# Programs the steps ported so far rewrite.
rewritten_programs(): String[] {
    return [
        # Declarations, members, enum cases and blocks for one platform.
        "[Target(OS(Windows))]\nf(): int { return 1; }\n[Target(!OS(Windows))]\nf(): int { return 2; }\nstruct S {\n    var x: int;\n    [Target(OS(Linux))]\n    linux(): int { return 1; }\n    [Target(OS(Mac))]\n    mac(): int { return 2; }\n}\nenum E {\n    A,\n    [Target(OS(Windows))]\n    B,\n    C,\n}\nmain(): int {\n    var n = 0;\n    [Target(OS(Linux))] {\n        n = 1;\n    }\n    if (n == 0) {\n        [Target(OS(Windows))] {\n            n = 2;\n        }\n    } else {\n        [Target(Arch(x64))] {\n            n = 3;\n        }\n    }\n    while (n > 10) {\n        [Target(Arch(aarch64))] {\n            n = 4;\n        }\n    }\n    return f() + n;\n}\n",
        # A test, kept only in a test build.
        "[Test]\nchecks() {}\nmain(): int { return 0; }\n",
        # Closures: captures, nesting, `this`, bare members, statics, a
        # parameter default, a field default and a global.
        "var g: () => int = () => 1;\nstruct S {\n    var x: int;\n    var h: () => int = () => 2;\n    get(): int { return x; }\n    static twice(n: int): int { return n * 2; }\n    run(k: int): int {\n        var a = 3;\n        var f = (b: int) => {\n            var inner = () => a + b + k + x + get() + twice(a);\n            return inner();\n        };\n        var m = get;\n        return f(1) + this.x;\n    }\n}\nf(g: () => int = () => 5): int { return g(); }\nmain(): int {\n    var s = S();\n    return s.run(1) + f() + g();\n}\n",
        # Closures in a generic struct, an extension, a trait's default
        # method and a deprecated function.
        "struct Box<T> {\n    var v: T;\n    map(): () => T { return () => v; }\n}\nextend Box<U> {\n    other(): () => U { return () => this.v; }\n}\ntrait Shape {\n    area(): int;\n    twice(): () => int { return () => area() * 2; }\n}\n[Deprecated(\"old\")]\nold(): () => int { return () => 1; }\nmain(): int { return 0; }\n",
        # `[Equatable]`: all fields, one field, an excluded one, none.
        "[Equatable]\nstruct P {\n    var x: int;\n    var y: int;\n}\n[Equatable]\nstruct Q {\n    var x: int;\n    [Equatable(exclude = true)]\n    var cache: int;\n}\n[Equatable]\nstruct R {\n    [Equatable(false)]\n    var x: int;\n}\nmain(): int { return 0; }\n",
        # Type aliases: generic with a default, nested, a static receiver,
        # an explicit generic argument and a value that shares a name.
        "struct Box<T> {\n    var v: T;\n    static make(v: T): Box<T> { var b = Box<T>(); b.v = v; return b; }\n}\ntype Id = int;\ntype B<T = Id> = Box<T>;\ntype BB<T> = B<B<T>>;\nvar g: B = Box<int>();\ng2<T>(x: T): T { return x; }\nf(b: BB<long>, n: Id): B<Id> {\n    var c = B.make(n);\n    var d = g2<B<Id>>(c);\n    var size = sizeof<B<Id>>();\n    return d;\n}\nmain(): int { return 0; }\n",
        # Struct synthesis: counted, shared, value and generic structs,
        # field parameters, enum and float fields, and a reference enum.
        "enum Color { Red = 1, Green = 2 }\n[Shared]\nstruct Counter { var n: int; }\n[Value]\nstruct V {\n    var x: int;\n    construct(this.x = 0) {}\n}\nstruct Box<T> {\n    var v: T;\n    var w: Box<T>;\n    var p: __ptr<int>;\n}\nstruct S {\n    var c: Color;\n    var f: double;\n    var v: V;\n    var t: (int, bool);\n    var s: S;\n    var k: int = 7;\n    construct(this.k = 1, extra: int = 2) {\n        c = Color.Green;\n    }\n    construct() {}\n    destruct {}\n}\nenum Shape {\n    Dot,\n    Circle(r: double),\n}\nmain(): int { return 0; }\n"
    ];
}
