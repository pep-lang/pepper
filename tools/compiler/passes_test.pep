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
    # The documentation's programs with `static` blocks and attributes.
    for (var name in [
        "build-options.pep",
        "debugging-static.pep",
        "reflection-attributes.pep",
        "reflection-functions.pep",
        "structs-static.pep",
        "reflection-module/main.pep"
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
        "main(): int {\n    static {\n        while (true) {\n        }\n    }\n    return 0;\n}\n"
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
        "enum Shape {\n    Circle(radius: double),\n    Rect(w: int, h: int),\n    Empty,\n}\n\nmain(): int {\n    var s = Shape.Circle(1.5);\n    var n = 0;\n    static (s, n) {\n        for (var k in reflect.cases<Shape>()) {\n            if (k.matches(s)) {\n                n += 1;\n            }\n            for (var v in k.values) {\n                reflect.print($\"{v.name} {v.type_name}\");\n            }\n        }\n    }\n    return n;\n}\n"
    ];
}
