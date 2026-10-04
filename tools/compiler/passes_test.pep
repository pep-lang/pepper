# The compiler's sema passes in Pepper change the model as the Rust passes
# do: after the steps ported so far (through the specialization loop), the model's JSON
# from `compiler.sema` here and from `pep-build --emit-model
# --emit-model-step N` match byte for byte, and a program a step rejects
# gets the same error.

import [Diagnostic, render_all] from compiler.diagnostic;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import compiler.sema;
import [TempFolder] from testing;

# The programs are split in parts, each a test of its own, to keep each
# within the time a test may take. The programs that use much of the
# runtime take the longest, so each is a test of its own.
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

[Test]
runs_the_passes_over_the_test_programs_part_9() {
    runs_passes(8);
}

[Test]
runs_the_passes_over_the_test_programs_part_10() {
    runs_passes(9);
}

[Test]
runs_the_passes_over_the_test_programs_part_11() {
    runs_passes(10);
}

[Test]
runs_the_passes_over_the_test_programs_part_12() {
    runs_passes(11);
}

[Test]
runs_the_passes_over_the_atomics_test() {
    runs_passes_over(Path("../tests/Atomic.Basic").join("test.pep"));
}

[Test]
runs_the_passes_over_the_generic_shared_constraints_test() {
    runs_passes_over(Path("../tests/Generic.SharedConstraint").join("test.pep"));
}

[Test]
runs_the_passes_over_the_globals_test() {
    runs_passes_over(Path("../tests/Globals.Basic").join("test.pep"));
}

[Test]
runs_the_passes_over_the_io_test() {
    runs_passes_over(Path("../tests/Io.Basic").join("test.pep"));
}

[Test]
runs_the_passes_over_the_threads_copy_example() {
    runs_passes_over(Path("../docs/examples").join("threads-copy.pep"));
}

[Test]
runs_the_passes_over_the_threads_lock_body_example() {
    runs_passes_over(Path("../docs/examples").join("threads-lock-body.pep"));
}

const PARTS = 12;

# The corpus's programs with tests of their own.
slow_programs(): String[] {
    return ["Atomic.Basic", "Generic.SharedConstraint", "Globals.Basic", "Io.Basic"];
}

# Runs the passes over `program` with both compilers.
runs_passes_over(program: Path) {
    var compiler = process.find_companion("pep-build");
    expect_true(compiler.is_value(), "pep-build is beside pep-test or on the PATH");
    if (!compiler.is_value()) {
        return;
    }
    expect_true(program.is_file(), "the program is found from tools/");
    expect_true(same_passes(compiler.value(), program, Array<String>(), true), "the passes agree");
}

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
        if (program.is_file() and !slow_programs().contains(name)) {
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
    # The documentation's programs with `static` blocks and attributes, and
    # with copies.
    for (var name in [
        "build-options.pep",
        "debugging-static.pep",
        "reflection-attributes.pep",
        "reflection-functions.pep",
        "structs-static.pep",
        "reflection-module/main.pep",
        # Copies (`threads-copy.pep` and the census of a locked value in
        # `threads-lock-body.pep` have tests of their own).
        "memory-copy-traits.pep",
        "memory-copyable.pep"
    ]) {
        programs.append(Path("../docs/examples").join(name));
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
# part. The specialization loop runs as many steps as the program needs, so
# the Rust passes are compared after as many as these ran.
same_passes(compiler: Path, root: Path, arguments: String[], runtime: bool): bool {
    var (first, steps) = compare_step(compiler, root, arguments, runtime, ALL_STEPS);
    if (!first.is_value()) {
        return true;
    }
    # Find the first step that differs.
    ulong step = 1;
    while (step < steps) {
        var (differs, _) = compare_step(compiler, root, arguments, runtime, step);
        if (differs.is_value()) {
            print($"{root}: step {step}: {differs.value()}");
            return false;
        }
        step += 1;
    }
    print($"{root}: step {steps}: {first.value()}");
    return false;
}

# More steps than any program runs: all those ported.
const ALL_STEPS: ulong = 1000000;

# How the two compilers' models of the program rooted at `root` differ
# after `limit` steps of these passes (as many as ran, when fewer), or none
# when they match; and how many steps that was.
compare_step(compiler: Path, root: Path, arguments: String[], runtime: bool, limit: ulong): (String?, ulong) {
    var none = Optional<String>.Empty;
    var setup = link.Setup();
    setup.runtime = runtime;
    var program = link.load_program(root, setup);
    var built = program.is_ok() ?
        Optional<Result<sema.Module, String>>.Value(sema.merge(program.value())) :
        Optional<Result<sema.Module, String>>.Empty;
    var ran = Optional<Result<ulong, Diagnostic>>.Empty;
    if (built.is_value() and built.value().is_ok()) {
        ran = Optional<Result<ulong, Diagnostic>>.Value(
            sema.run_steps(built.value().value(), program.value().target, limit, program.value().sources())
        );
    }
    var steps = limit;
    if (ran.is_value() and ran.value().is_ok()) {
        steps = ran.value().value();
    }
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
        return (none, steps);
    }
    # A program the Rust compiler builds must load here too; one it
    # rejects before the passes is sema_test's to compare.
    var accepted = output.value().status.success();
    if (program.is_err()) {
        return (accepted ? Optional<String>.Value("the Rust compiler loads it, but not this one") : none, steps);
    }
    if (built.value().is_err()) {
        return (accepted ? Optional<String>.Value("the Rust compiler merges it, but not this one") : none, steps);
    }
    var module = built.value().value();
    var result = ran.value();
    if (!accepted) {
        var expected = trimmed(output.value().stderr);
        if (!result.is_err()) {
            return (Optional<String>.Value($"the Rust passes reject it, but not these: {expected}"), steps);
        }
        var actual = render_all([result.error()], program.value().sources());
        if (actual != expected) {
            return (
                Optional<String>.Value($"the error differs from the Rust passes':\n{actual}\nnot\n{expected}"), steps
            );
        }
        return (none, steps);
    }
    if (result.is_err()) {
        return (
            Optional<String>.Value(
                $"the Rust passes accept it, but: {render_all([result.error()], program.value().sources())}"
            ),
            steps
        );
    }
    var expected = trimmed(output.value().stdout);
    var actual = sema.model_json(module);
    if (actual != expected) {
        var at = first_difference(actual, expected);
        return (
            Optional<String>.Value(
                $"the model differs from the Rust passes' at byte {at} of its JSON: {excerpt(actual, at)} not {excerpt(expected, at)}"
            ),
            steps
        );
    }
    return (none, steps);
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
        "struct S {\n    var x: int;\n    construct(this.y = 0) {}\n}\nmain(): int { return 0; }\n",
        # Attributes an `[Attribute]` struct cannot take, and one that
        # cannot be an attribute.
        "enum K { A }\n[Attribute]\nstruct T { var k: K; }\n[T(K.B)]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "[Attribute]\nstruct A {\n    var x: int;\n    construct(x: int) { this.x = x; }\n}\n[A()]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "[Attribute]\nstruct A { var x: int[]; }\nmain(): int { return 0; }\n",
        "[Attribute]\nstruct A { var x: int; }\n[A(1, 2)]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "[Attribute]\nstruct A { var x: int; }\n[A(y = 1)]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "[Attribute]\nstruct A { var x: int; }\n[A(f())]\nstruct P { var y: int; }\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        "[Attribute]\nstruct A { var x: int; }\n[A(1, x = 2)]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "[Attribute]\nstruct A { var x: int; }\n[A(\"s\")]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "[Attribute]\nstruct A { var x: int; }\nstruct P { var y: int; }\nmain(): int {\n    static {\n        reflect.print(reflect.attribute<P, A>());\n    }\n    return 0;\n}\n",
        "[Nope]\nstruct P { var x: int; }\nmain(): int { return 0; }\n",
        # Static blocks: what a block cannot evaluate, `reflect` misused,
        # `reflect.error` and `reflect.assert`, and a module-scope block.
        "main(): int {\n    static {\n        reflect.print(reflect.name<int, int>());\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        reflect.assert(1 == 2, \"nope\");\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        reflect = 3;\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        reflect.print(reflect.build_option(\"NOPE\"));\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        reflect.print(reflect.has_build_option(\"1x\"));\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        foo();\n    }\n    return 0;\n}\nfoo() {}\n",
        "struct P { var x: int; }\nmain(): int {\n    static {\n        reflect.cases<P>();\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        if (3) {\n        }\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        var x = 1 / 0;\n    }\n    return 0;\n}\n",
        "struct P { var y: int; }\nmain(): int {\n    var n = 0;\n    static (n) {\n        n = reflect.properties<P>();\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        for (var c in reflect.cases<K>()) {\n            reflect.error($\"bad {c.name}\");\n        }\n    }\n    return 0;\n}\nenum K { A, B }\n",
        "main(): int {\n    static {\n        reflect.print(reflect.cases<K>()[5]);\n    }\n    return 0;\n}\nenum K { A }\n",
        "struct P { var x: int; }\nmain(): int {\n    static {\n        for (var f in reflect.properties<P>()) {\n            reflect.print(f.nope);\n        }\n    }\n    return 0;\n}\n",
        "static {\n    reflect.error(\"module\");\n    const X = 1;\n}\nmain(): int { return 0; }\n",
        "main(): int {\n    static {\n        for (var x in 3) {\n        }\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        reflect.properties<Nope>();\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        var x = 9223372036854775807 + 1;\n    }\n    return 0;\n}\n",
        "enum K { A }\nmain(): int {\n    static {\n        reflect.properties<K>();\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        reflect.nope<int>();\n    }\n    return 0;\n}\n",
        "main(): int {\n    var n = 1;\n    static {\n        reflect.print(n);\n    }\n    return 0;\n}\n",
        "enum S { C(r: int) }\nmain(): int {\n    var s = S.C(1);\n    static (s) {\n        for (var k in reflect.cases<S>()) {\n            for (var v in k.values) {\n                v.set(s, 2);\n            }\n        }\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        reflect.print(reflect.properties<int>);\n    }\n    return 0;\n}\n",
        "main(): int {\n    static {\n        while (true) {\n        }\n    }\n    return 0;\n}\n",
        # Enum cases and value types' methods; `main`'s parameters; names
        # declared twice and const bindings assigned; `[Alias]` and
        # `[Rename]`; `[Link]`.
        "struct S {\n    [Alias(\"a\", \"b\")]\n    m(x: int) {}\n}\nmain(): int { return 0; }\n",
        "[Alias(\"a\", \"y\")]\nf(x: int) {}\nmain(): int { return 0; }\n",
        "[Alias(\"a\")]\nf(x: int) {}\nmain(): int { return 0; }\n",
        "[Alias(\"x\", \"x\")]\nf(x: int) {}\nmain(): int { return 0; }\n",
        "struct S {\n    const x: int = 1;\n    set() {\n        this.x = 2;\n    }\n}\nmain(): int { return 0; }\n",
        "struct S {\n    const x: int = 1;\n    set() {\n        x = 2;\n    }\n}\nmain(): int { return 0; }\n",
        "const G = 1;\nmain(): int {\n    G += 2;\n    return G;\n}\n",
        "main(): int {\n    const x = 1;\n    x++;\n    return x;\n}\n",
        "main(): int {\n    const x = 1;\n    x = 2;\n    return x;\n}\n",
        "enum Color { Red, Green }\nmain(): int {\n    var c = 1 as Color;\n    return 0;\n}\n",
        "enum Color { Red, Green }\nmain(): int {\n    var c = Color.from_value;\n    return 0;\n}\n",
        "enum Color { Red, Green }\nmain(): int {\n    var c = Color.Blue;\n    return 0;\n}\n",
        "enum Color { Red, Green }\nmain(): int {\n    var c = Color.nope();\n    return 0;\n}\n",
        "enum Color {\n    Red,\n    Green,\n    twice(): int { return 2; }\n}\nmain(): int {\n    return Color.twice();\n}\n",
        "enum Color { Red, Green }\nextend Color {\n    f(): int { return 1; }\n}\nmain(): int { return 0; }\n",
        "[Link(path = \"\")]\nextern int f();\nmain(): int { return 0; }\n",
        "[Link]\nextern int f();\nmain(): int { return 0; }\n",
        "[Link(nope = \"n\")]\nextern int f();\nmain(): int { return 0; }\n",
        "[Link(\"m\", lib = \"n\")]\nextern int f();\nmain(): int { return 0; }\n",
        "[LinkName(\"g\")]\nextern int f();\nmain(): int { return 0; }\n",
        "[Link(\"m\", \"n\")]\nextern int f();\nmain(): int { return 0; }\n",
        "[Link(lib = 1)]\nextern int f();\nmain(): int { return 0; }\n",
        "[Link(name = \"a\")]\n[Link(name = \"b\")]\nextern int f();\nmain(): int { return 0; }\n",
        "main(args: String[]): int { return 0; }\n",
        "main(a: int): int { return 0; }\n",
        "main(a: String[], b: int): int { return 0; }\n",
        "extend int {\n    *(other: double): int { return 1; }\n}\nmain(): int { return 0; }\n",
        "extend int {\n    +(a: int, b: int): int { return a; }\n}\nmain(): int { return 0; }\n",
        "main(): int {\n    var x = 1;\n    var x = 2;\n    return x;\n}\n",
        "enum Doc {\n    Line,\n    Text(text: int),\n}\nmain(): int {\n    var d = Doc();\n    return 0;\n}\n",
        "enum Doc {\n    Line,\n    Text(text: int, more: int),\n}\nmain(): int {\n    var d = Doc.Text;\n    return 0;\n}\n",
        "enum Doc {\n    Line,\n    Text(text: int),\n}\nmain(): int {\n    var d = Doc.Nope;\n    return 0;\n}\n",
        "[Rename(\"old\", \"x\")]\n[Alias(\"old\", \"x\")]\nf(x: int) {}\nmain(): int { return 0; }\n",
        "trait Twice {\n    twice(): int;\n}\nextend int with Twice {\n}\nmain(): int { return 0; }\n",
        "main(): int { return 0; }\nmain(): int { return 1; }\n",
        # A misnamed argument, with and without a likely meaning.
        "f(alpha: int, beta: int = 2) {}\nmain(): int {\n    f(1, betta = 3);\n    return 0;\n}\n",
        "f(alpha: int, beta: int = 2) {}\nmain(): int {\n    f(1, zzz = 3);\n    return 0;\n}\n",
        # Too many arguments, one given twice, and one missing.
        "f(a: int, b: int = 2) {}\nmain(): int {\n    f(1, 2, 3, b = 4);\n    return 0;\n}\n",
        "f(a: int, b: int = 2) {}\nmain(): int {\n    f(1, a = 2);\n    return 0;\n}\n",
        "f(a: int, b: int = 2) {}\nmain(): int {\n    f(b = 1);\n    return 0;\n}\n",
        # Overloads none of which fit, and ones that bind differently.
        "f(a: int) {}\nf(b: String) {}\nmain(): int {\n    f(c = 1);\n    return 0;\n}\n",
        "f(a: int, b: int) {}\nf(b: double, a: double) {}\nmain(): int {\n    f(b = 1, a = 2);\n    return 0;\n}\n",
        # A named argument to an extern, and to a method called bare.
        "extern int e(int x);\nmain(): int {\n    return e(x = 1);\n}\n",
        "struct S {\n    m(first: int) {}\n    run() { m(frist = 1); }\n}\nmain(): int { return 0; }\n",
        "struct Box<T> {\n    var v: T;\n    construct(value: T) { v = value; }\n}\nmain(): int {\n    var b = Box<int>(valu = 1);\n    return 0;\n}\n",
        "f(a: int) {}\nvar g = f(b = 1);\nmain(): int { return 0; }\n",
        # Overloads that clash: free functions, externs, constructors,
        # methods, a trait's methods, and concrete overrides.
        "f(x: int) {}\nf(y: i32) {}\nmain(): int { return 0; }\n",
        "f(x: int): int { return 0; }\nf(x: int): bool { return true; }\nmain(): int { return 0; }\n",
        "f<T>(x: T) {}\nf<U>(y: U) {}\nmain(): int { return 0; }\n",
        "extern int puts(__ptr<char> s);\nputs(x: int): int { return x; }\nmain(): int { return 0; }\n",
        "puts(x: int): int { return x; }\nextern int puts(__ptr<char> s);\nmain(): int { return 0; }\n",
        "extern int puts(__ptr<char> s);\nextern long puts(__ptr<char> s);\nmain(): int { return 0; }\n",
        "struct P {\n    var x: int;\n    construct(a: int) {}\n    construct(b: i32) {}\n}\nmain(): int { return 0; }\n",
        "struct P {\n    get(): int { return 0; }\n    static get(i: int): int { return i; }\n}\nmain(): int { return 0; }\n",
        "struct P {\n    get(i: int): int { return 0; }\n    get(j: int): int { return j; }\n}\nmain(): int { return 0; }\n",
        "trait R {\n    read(): int;\n    read(): long;\n}\nmain(): int { return 0; }\n",
        "hash<T>(value: T): ulong { return 0; }\nhash<T>(value: T, seed: ulong): ulong { return seed; }\nhash<int>(value: int, a: int, b: int): ulong { return 1; }\nmain(): int { return 0; }\n",
        "f<T>(a: T, b: int) {}\nf<T>(a: int, b: T) {}\nf<int>(a: int, b: int) {}\nmain(): int { return 0; }\n",
        # `?` on what is neither a Result nor an Optional, and in a function
        # returning another kind.
        "f(): int { return 1; }\ng(): int {\n    var x = f()?;\n    return x;\n}\nmain(): int { return g(); }\n",
        "struct Optional<T> {}\nf(): Optional<int> { return Optional<int>(); }\ng(): int {\n    var x = f()?;\n    return 0;\n}\nmain(): int { return g(); }\n",
        # A trait member an extension leaves out, and one it declares with
        # another type.
        "trait Shape {\n    area(): int;\n}\nstruct Box {}\nextend Box with Shape;\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n}\nstruct Box {}\nextend Box with Shape {\n    area(): long { return 1; }\n}\nmain(): int { return 0; }\n",
        "trait Sized {\n    var size: int { get; }\n}\nstruct Box {\n    var other: int;\n}\nextend Box with Sized;\nmain(): int { return 0; }\n",
        # A value `print` cannot convert.
        "print<T>(value: T) {}\nstruct S {}\nmain(): int {\n    print(S());\n    return 0;\n}\n",
        # Constraints that name no trait, a trait named `Shared`, and type
        # arguments that do not conform (a number, a type parameter, a
        # struct).
        "struct S {}\nf<T: S>(x: T) {}\nmain(): int { return 0; }\n",
        "trait Shared {}\nmain(): int { return 0; }\n",
        "trait Named {\n    name(): int;\n}\nstruct Box<T: Named> {}\nmain(): int {\n    var b = Box<int>();\n    return 0;\n}\n",
        "trait Named {\n    name(): int;\n}\nstruct Box<T: Named> {}\nf<U>(b: Box<U>) {}\nmain(): int { return 0; }\n",
        "trait Named {\n    name(): int;\n}\nstruct S {}\nstruct Box<T: Named> {}\nmain(): int {\n    var b = Box<S>();\n    return 0;\n}\n",
        # Constrained generic code uses only what its constraints offer.
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.perimeter(); }\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.radius; }\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nmake<T: Shape>(item: T): T { return T(); }\nmain(): int { return 0; }\n",
        "trait Named {\n    name(): String;\n}\ntrait Titled {\n    name(): String;\n}\nlabel<T: Named & Titled>(item: T): String { return item.name(); }\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.scale(1, 2); }\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.scale(\"twice\"); }\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nstruct Circle {\n}\nkeep<T: Shape>(item: T): int {\n    var shape: Shape = item;\n    var circle: Circle = item;\n    return 0;\n}\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nsmaller<T: Shape>(a: T, b: T): bool { return a < b; }\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nstruct Gallery<T: Shape> {\n    var items = Array<T>();\n    first(): int { return items[0].depth(); }\n}\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nmake<T: Shape>(): T { return T.unit(); }\nmain(): int { return 0; }\n",
        "trait Addable {\n    +(other: this): this;\n}\ngrow<T: Addable>(a: T, b: T): T {\n    var total = a;\n    total += b;\n    return total;\n}\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n}\nflip<T: Shape>(a: T): T { return -a; }\nmain(): int { return 0; }\n",
        "trait Shape {\n    area(): int;\n}\npick<T: Shape>(a: T): int { return a[0]; }\nmain(): int { return 0; }\n",
        # Range bounds must be integers.
        "_range<T>(a: T, b: T, inclusive: bool): int { return 0; }\nmain(): int {\n    var r = 1.5..3.0;\n    return 0;\n}\n",
        "_range<T>(a: T, b: T, inclusive: bool): int { return 0; }\nmain(): int {\n    var r = \"a\"..>\"z\";\n    return 0;\n}\n",
        # A generic method's constraints, at its specialization.
        "trait Named {\n    name(): int;\n}\nstruct Box {\n    get<T: Named>(x: T): int { return 0; }\n}\nmain(): int {\n    var b = Box();\n    return b.get<int>(1);\n}\n",
        "struct Box {\n    get<T>(x: T): T { return x; }\n}\nmain(): int {\n    var b = Box();\n    var f = b.get<int>;\n    return b.get<int>(1) + f(2) + b.missing<int>(3);\n}\n",
        # A specialization's `static` block emits a lowered string.
        "pick<T>(x: T): T {\n    var s = x;\n    static (s) {\n        var t = \"ab\";\n        s = t;\n    }\n    return s;\n}\nmain(): int {\n    var p = pick<int>(1);\n    return 0;\n}\n",
        # Intrinsics: function pointers, `__ptr<T>`, typed intrinsics and SIMD arity.
        "f(): int { return 1; }\nmain(): int {\n    var p = __function_pointer(f);\n    var q = __function_pointer(g);\n    return 0;\n}\n",
        "main(): int {\n    var x: __ptr<int> = null;\n    var y = __address<int>(x);\n    var b = __is_pod<__ptr<char>>();\n    var v = __simd_add<int>(1);\n    return 0;\n}\n",
        "struct S {\n    static h(): int { return 2; }\n    m(): int {\n        var p = __function_pointer(h);\n        var q = __function_pointer(1, 2);\n        return 0;\n    }\n}\nmain(): int { return 0; }\n",
        "main(): int {\n    var x: __ptr<int> = null;\n    var y = __address<int>(x);\n    var b = __is_pod<__ptr<char>>();\n    return 0;\n}\n",
        # Bare names in methods: an undeclared one, in a concrete struct, a
        # specialization and a trait's default method.
        "struct S {\n    var n: int;\n    get(): int { return zork; }\n}\nmain(): int { return 0; }\n",
        "struct B<T> {\n    var v: T;\n    get(): int { return zork + 1; }\n}\nmain(): int { var b = B<int>(); return 0; }\n",
        "trait Counted {\n    count(): int { return n; }\n}\nstruct S {\n    var n: int;\n}\nextend S with Counted;\nmain(): int { return 0; }\n",
        # Copies that cannot be made: a destructor (through a field), a raw
        # pointer field, `[NotCopyable]` and a plain function value.
        "struct R {\n    var n: int;\n    destruct { n = 0; }\n}\nstruct H {\n    var r: R;\n}\ncopy<T>(value: T): T { return value; }\nmain(): int {\n    var h = H();\n    var c = copy(h);\n    return 0;\n}\n",
        "struct P {\n    var p: __ptr<char>;\n}\ncopy<T>(value: T): T { return value; }\nmain(): int {\n    var c = copy(P());\n    return 0;\n}\n",
        "[Attribute]\nstruct NotCopyable {\n    var reason: String;\n}\nstruct String {\n    var data: __ptr<char>;\n    construct(raw: __ptr<char>, size: long, length: long) {}\n}\n[NotCopyable(\"it owns a handle\")]\nstruct F {\n    var n: int;\n}\nstruct W {\n    var f: F;\n    var g: (int) => int;\n}\ncopy<T>(value: T): T { return value; }\nmain(): int {\n    var c = copy(W());\n    return 0;\n}\n",
        "struct W {\n    var g: (int) => int;\n}\ncopy<T>(value: T): T { return value; }\nmain(): int {\n    var c = copy(W());\n    return 0;\n}\n"
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
        "enum Color { Red = 1, Green = 2 }\n[Shared]\nstruct Counter { var n: int; }\n[Value]\nstruct V {\n    var x: int;\n    construct(this.x = 0) {}\n}\nstruct Box<T> {\n    var v: T;\n    var w: Box<T>;\n    var p: __ptr<int>;\n}\nstruct S {\n    var c: Color;\n    var f: double;\n    var v: V;\n    var t: (int, bool);\n    var s: S;\n    var k: int = 7;\n    construct(this.k = 1, extra: int = 2) {\n        c = Color.Green;\n    }\n    construct() {}\n    destruct {}\n}\nenum Shape {\n    Dot,\n    Circle(r: double),\n}\nmain(): int { return 0; }\n",
        # Static blocks over properties, fields, value and reference enum
        # cases, attribute values, functions with an attribute, loops and
        # compile-time arithmetic, emitted branches, methods and
        # constructors, and module-scope constants.
        "enum Kind { Flag, Value }\n\n[Attribute]\nstruct Opt {\n    const long_name: String;\n    const short_name: String;\n    const kind: Kind;\n    const count: int = 1;\n    const ratio: double;\n\n    construct(long_name: String, short_name: String = \"\", kind: Kind = Kind.Value) {\n        this.long_name = long_name;\n        this.short_name = short_name;\n        this.kind = kind;\n    }\n}\n\n[Attribute]\nstruct Tag {\n    var text: String;\n    var weight: int;\n}\n\nstruct Args {\n    [Opt(\"verbose\", \"v\", kind = Kind.Flag)]\n    var verbose: bool;\n    [Opt(\"out\" + \"put\")]\n    [Tag(\"t\", -3)]\n    var output: String;\n    var plain: int;\n}\n\nmain(): int {\n    var a = Args();\n    static (a) {\n        for (var f in reflect.properties<Args>()) {\n            if (f.has_attribute<Opt>()) {\n                var o = f.attribute<Opt>();\n                reflect.print(o);\n                reflect.print($\"{o.long_name}/{o.short_name}/{o.kind}/{o.count}/{o.ratio}\");\n            }\n            if (f.has_attribute<Tag>()) {\n                reflect.print(f.attribute<Tag>().weight);\n            }\n        }\n        reflect.print(reflect.has_attribute<Args, Opt>());\n    }\n    return 0;\n}\n",
        "enum Color { Red, Green = 5, Blue }\n\nmain(): int {\n    var c = Color.Green;\n    static (c) {\n        for (var k in reflect.cases<Color>()) {\n            if (k.matches(c)) {\n                reflect.print($\"{k.name} {k.value} {k.index} {k.is_last}\");\n            }\n            var v = k.get();\n        }\n    }\n    return 0;\n}\n",
        "[Attribute]\nstruct A {\n    var x: int;\n    construct(x: int) { this.x = x; reflect.print(\"hi\"); }\n}\nmain(): int { return 0; }\n",
        "struct P { var x: int; var y: int; }\n\nmain(): int {\n    var p = P();\n    var n = 0;\n    static (p, n) {\n        for (var f in reflect.properties<P>()) {\n            if (f.get(p) == 0) {\n                n += 1;\n            } else {\n                n -= 1;\n            }\n        }\n    }\n    return n;\n}\n",
        "struct Point {\n    var x: int;\n    var _y: int;\n}\n\nmain(): int {\n    var p = Point();\n    static (p) {\n        for (var f in reflect.fields<Point>()) {\n            reflect.print(f.name);\n        }\n    }\n    return 0;\n}\n",
        "[Attribute]\nstruct Command {\n    var name: String;\n}\n\n[Command(\"b\")]\nrun_b(): int { return 2; }\n\n[Command(\"a\")]\nrun_a(): int { return 1; }\n\nmain(): int {\n    var total = 0;\n    static (total) {\n        for (var f in reflect.functions_with<Command>()) {\n            reflect.print($\"{f.name} {f.attribute<Command>().name}\");\n            total += f.call();\n        }\n    }\n    return total;\n}\n",
        "main(): int {\n    var out = 0;\n    static (out) {\n        var i = 0;\n        var s = \"\";\n        while (i < 5) {\n            i += 1;\n            if (i == 2) {\n                continue;\n            }\n            if (i == 4) {\n                break;\n            }\n            s = s + $\"{i}\";\n            out += i;\n        }\n        var list = reflect.cases<K>();\n        reflect.print(list.count);\n        reflect.print(list[1]);\n        reflect.print(s.length);\n        reflect.print(1.5 * 2);\n        reflect.print(7 / 2);\n        reflect.print(7 % 3);\n        reflect.print(-7.5 % 2);\n        reflect.print(\"a\" < \"b\");\n        reflect.print(1 < 2.5);\n        reflect.print(10.0 / 4);\n        reflect.print(1e21);\n        reflect.print(0.1 + 0.2);\n        reflect.print(s.starts_with(\"1\"));\n        reflect.print(true and false or !false);\n        reflect.print(i == 4 ? \"four\" : \"other\");\n        reflect.assert(i == 4, \"i is four\");\n        reflect.print(reflect.name<Array<int>>());\n        reflect.print(reflect.is_struct<K>());\n        reflect.print(reflect.is_enum<K>());\n        reflect.print(reflect.is_reference<String>());\n        reflect.print(reflect.is_same<int, i32>());\n        reflect.print(reflect.is_same<__ptr<int>, i32*>());\n        reflect.print(reflect.has_build_option(\"X\"));\n        reflect.print(reflect.build_option(\"X\", \"dflt\"));\n        reflect.print(\"q\\\"uote\\n\");\n    }\n    return out;\n}\n\nenum K { A, B }\n",
        "struct P {\n    var x: int;\n    var y: int;\n\n    sum(): int {\n        var total = 0;\n        static (total) {\n            for (var f in reflect.properties<P>()) {\n                total += f.get(this);\n            }\n        }\n        return total;\n    }\n\n    construct() {\n        static {\n            reflect.print(\"ctor\");\n        }\n    }\n}\n\nmain(): int {\n    return P().sum();\n}\n",
        "enum Level { Low, High }\n\nstatic {\n    var n = 0;\n    for (var c in reflect.cases<Level>()) {\n        n += c.value + 1;\n    }\n    const COUNT = n;\n    const NAME = \"lvl\" + $\"{n}\";\n    const RATE = 2.5;\n    const ON = n > 1;\n    const TOP = Level.High;\n}\n\nmain(): int {\n    return COUNT;\n}\n",
        "struct Point {\n    var x: int;\n    var y: double;\n    const name: String = \"p\";\n    var _hidden: int;\n    var label: String { get { return name; } }\n}\n\nmain(): int {\n    var p = Point();\n    var total = 0;\n    static (p, total) {\n        for (var field in reflect.properties<Point>()) {\n            reflect.print($\"{field.name} {field.index} {field.is_last} {field.type_name} {field.is_const} {field.is_property}\");\n            if (reflect.is_same<field.Type, int>()) {\n                total += field.get(p);\n                field.set(p, 3);\n            }\n        }\n    }\n    return total;\n}\n",
        "enum Shape {\n    Circle(radius: double),\n    Rect(w: int, h: int),\n    Empty,\n}\n\nmain(): int {\n    var s = Shape.Circle(1.5);\n    var n = 0;\n    static (s, n) {\n        for (var k in reflect.cases<Shape>()) {\n            if (k.matches(s)) {\n                n += 1;\n            }\n            for (var v in k.values) {\n                reflect.print($\"{v.name} {v.type_name}\");\n            }\n        }\n    }\n    return n;\n}\n",
        # Enum cases, built-in and static methods, value type extensions
        # and their trait defaults; `main(args)`; shadowing and const
        # fields set in a constructor; `[Alias]`, `[Rename]` and `[Link]`.
        "[Alias(\"w\", \"width\")]\n[Rename(\"old\", \"height\")]\nf(width: int, height: int) {}\nstruct S {\n    var x: int;\n    [Alias(\"ex\", \"x\")]\n    construct(this.x = 0) {}\n}\nmain(): int { return 0; }\n",
        "const G = 1;\nstruct S {\n    const x: int;\n    construct() { x = 1; this.x = 2; }\n}\nmain(): int {\n    var x = 1;\n    {\n        var x = 2;\n    }\n    var y = x;\n    y += 1;\n    return y;\n}\n",
        "enum Color: u8 { Red = 2, Green, Blue = 0 }\nenum Doc {\n    Line,\n    Text(text: int),\n    static make(): Doc { return Doc.Line; }\n}\nextend int {\n    doubled(): int { return this * 2; }\n    static zero(): int { return 0; }\n}\ntrait Twice {\n    twice(): int;\n    thrice(): int { return twice() + 1; }\n}\nextend int with Twice {\n    twice(): int { return this * 2; }\n}\nenum Level {\n    Low,\n    High,\n    up(): Level { return next(); }\n    next(): Level { return Level.High; }\n    static first(): Level { return Level.Low; }\n}\nvar g: Color;\nstruct S {\n    var c: Color = Color.Green;\n    f(c: Color = Color.Blue): Color { return c; }\n}\nf(c: Color = Color.Red): Color { return c; }\nmain(): int {\n    Color c;\n    var d = Doc.Line;\n    var l = Level.first();\n    var v = Color.from_value(1);\n    var z = int.zero();\n    if (c == Color.Red) {\n        Level k;\n    }\n    return 0;\n}\n",
        "[Link(\"m\", path = \"/usr/lib\")]\n[Link(name = \"cos\")]\nextern double my_cos(double x);\nmain(): int { return 0; }\n",
        "_pep_arguments(): String[] { return Array<String>(); }\nmain(args: String[]): int { return args.count as int; }\n",
        "_pep_arguments(): String[] { return Array<String>(); }\nmain(args: String[]) {}\n",
        # Named arguments: skipped defaults, reordering that evaluates first, constructors, a bare method, a former name, overloads, generics and a global.
        "f(a: int, b: int = 2, c: int = 3): int { return a + b + c; }\ng(): int { return 1; }\nstruct P {\n    var x: int;\n    var y: int;\n    construct(x: int = 0, y: int = 0) { this.x = x; this.y = y; }\n    m(first: int, second: int = 1): int { return first + second; }\n    call(): int { return m(second = 2, first = 1); }\n    other(): P { return this; }\n}\n[Rename(\"old\", \"b\")]\nh(a: int, b: int) {}\nk(a: int, b: int) {}\nk(a: double, b: double) {}\nid<T>(value: T, times: int = 1, scale: T = value): T { return value; }\nvar global = f(c = 1, a = 2);\nmain(): int {\n    var n = f(1, c = 4);\n    n += f(c = g(), a = n);\n    n += f(c = -1, a = 5);\n    var p = P(y = 2);\n    var q = P(y = g(), x = -1);\n    var r = p.other().m(second = 1, first = n);\n    h(1, old = 2);\n    k(b = 1, a = 2);\n    var i = id(scale = 2, value = 3);\n    var j = id<long>(value = 1);\n    return n + p.call() + i;\n}\n",
        "struct Box<T> {\n    var v: T;\n    construct(value: T, extra: int = 0) { v = value; }\n}\nmain(): int {\n    var f = (a: int) => a;\n    var x = f(1);\n    var b = Box<int>(extra = 2, value = x);\n    return 0;\n}\n",
        # Function, tuple and weak reference types; negated literals;
        # overload sets of functions, methods and constructors, and
        # concrete overrides.
        "struct Node {\n    var next: __weak<Node>;\n}\n[Shared]\nstruct Hub { var n: int; }\ntrait Shape {\n    area(): int;\n}\nstruct Box<T> { var w: __weak<T>; }\nf(t: (int, bool), g: shared (int) => int, h: (int) => (int) => bool): (bool, double) {\n    var w: __weak<Hub>;\n    var s: __weak<Shape>;\n    var p: __ptr<__tuple<int, long>>;\n    var k = (a: int) => a + 1;\n    return (true, 1.0);\n}\nvar global: ((int, int)) => void;\nmain(): int { return 0; }\n",
        "var g = -5;\nf(x: int = -1): double { return -2.5 + -x; }\nstruct S {\n    var v: int;\n    construct() { v = -3; }\n    get(): long { return -9223372036854775807 - 1; }\n    destruct { var d = -0.0; }\n}\nmain(): int { return -(-1); }\n",
        "scale(x: int): int { return x * 2; }\nscale(x: double): double { return x * 2.0; }\nscale<T>(x: T, times: int): T { return x; }\nhash<T>(value: T): ulong { return 0; }\nhash<T>(value: T, seed: ulong): ulong { return seed; }\nhash<int>(value: int): ulong { return 1; }\ndescribe<T>(value: T): int { return 0; }\ndescribe<String>(value: String): int { return 1; }\nstruct P {\n    var x: int;\n    construct() {}\n    construct(x: int) { this.x = x; }\n    get(): int { return x; }\n    get(i: int): int { return i; }\n    static make(): P { return P(); }\n}\ntrait Reader {\n    read(): int;\n    read(count: int): int;\n}\nextern int puts(__ptr<char> s);\nextern int puts(__ptr<char> s);\nmain(): int { return scale(1); }\n",
        # String literals in bodies, globals, `String` defaults, trait
        # defaults, generic methods and extensions.
        "struct String {\n    var data: __ptr<char>;\n    construct(raw: __ptr<char>, size: long, length: long) {}\n}\nvar greeting = \"héllo\";\nf(name: String = \"wörld\", raw: __ptr<char> = \"c\"): String { return \"a\" + \"\"; }\ntrait Named {\n    name(): String { return \"named\"; }\n}\nstruct Box<T> {\n    var v: T;\n    add<U>(u: U): String { return \"add\"; }\n    construct(label: String = \"box\") {}\n}\nextend int {\n    text(): String { return \"int\"; }\n}\nmain(): int {\n    var s = \"日本\";\n    return 0;\n}\n",
        # Generic uses: fields, methods, locals in nested blocks, an
        # extension of the base, globals, calls and a function value.
        "struct Box<T> {\n    var v: T;\n    var others: Box<Box<T>>;\n    var ints: Box<int>;\n    get(b: Box<long>): Box<short> { var local: Box<bool>; return Box<short>(); }\n    construct() { var c: Box<char>; }\n}\nstruct Pair<A, B> { var a: A; var b: B; }\nextend Box<T> {\n    wrap(): Box<T> { return Box<T>(); }\n    twice(): Box<double> { return Box<double>(); }\n}\nlarger<T>(a: T, b: T): T { return a; }\nmake<U>(u: U): Box<U> { var p: Pair<U, int>; return Box<U>(); }\nvar global: Pair<int, bool> = Pair<int, bool>();\nvar picked = larger<long>(1, 2);\nmain(): int {\n    var x = larger<int>(1, 2);\n    var f = larger<double>;\n    if (x > 0) {\n        Pair<String, int> p;\n    } else {\n        while (x < 0) {\n            Box<uint> q;\n        }\n    }\n    var m = make<byte>(1);\n    return x;\n}\n",
        # Operators on structs and enums: overloads, indexes, unary operators
        # and truth tests.
        "struct V {\n    var x: int;\n    construct(x: int) { this.x = x; }\n    +(other: V): V { return V(x + other.x); }\n    +(other: int): V { return V(x + other); }\n    ==(other: V): bool { return x == other.x; }\n    -(): V { return V(0 - x); }\n    !!(): bool { return x != 0; }\n    +=(other: int) { x = x + other; }\n}\nstruct Grid {\n    var cells: __ptr<int>;\n    var values: V;\n    __index_get(i: int): int { return cells[i]; }\n    __index_set(i: int, value: int) { cells[i] = value; }\n    total(): int { return this[0] + values.x; }\n}\nenum Level {\n    Low,\n    High,\n    <(other: Level): bool { return false; }\n    __index_get(i: int): int { return i; }\n}\nvar origin = V(1) + V(2);\nmain(): int {\n    var a = V(1);\n    var b = a + V(2) + 3;\n    var c = -a;\n    a += 4;\n    if (a) { b = c; }\n    var t = !a;\n    var u = a and b;\n    var ne = a != b;\n    var g = Grid();\n    g[1] = 2;\n    g[1] += 3;\n    g[2] *= g[1];\n    var p: __ptr<int> = null;\n    var q = p[3];\n    var l = Level.Low < Level.High;\n    var w = Level.Low[2];\n    return g[0];\n}\n"
    ];
}
