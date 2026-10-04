# The compiler's linker in Pepper loads, links and checks programs as the
# Rust compiler does: the JSON of every file after linking, with the
# linking errors, from `compiler.link` here and from `pep-build
# --emit-linked`, match byte for byte, and so do the errors and warnings of
# the checks after linking and `pep-build --emit-checked`.

import io;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import [TempFolder] from testing;

# The programs are split in parts, each a test of its own, to keep each
# within the time a test may take.
[Test]
links_the_test_programs_part_1() {
    links_programs(0);
}

[Test]
links_the_test_programs_part_2() {
    links_programs(1);
}

[Test]
links_the_test_programs_part_3() {
    links_programs(2);
}

[Test]
links_the_test_programs_part_4() {
    links_programs(3);
}

[Test]
links_the_test_programs_part_5() {
    links_programs(4);
}

[Test]
links_the_test_programs_part_6() {
    links_programs(5);
}

const PARTS = 6;

# Links every `PARTS`th program of the corpus and the documentation's
# programs of several files, from the `part`th, with both linkers.
links_programs(part: ulong) {
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
        "modules-same-name",
        "overloading-imports",
        "overloading-modules",
        "overloading-visibility",
        "visibility-namespaces"
    ]) {
        programs.append(Path("../docs/examples").join(name).join("main.pep"));
    }
    expect_true(programs.count > 40, "the corpus has its programs");
    ulong mismatches = 0;
    ulong i = part;
    while (i < programs.count) {
        if (!same_program(compiler.value(), programs[i], Array<String>())) {
            mismatches += 1;
        }
        i += PARTS;
    }
    expect_equal(mismatches, 0 as ulong);
}

# Programs whose imports are wrong: each error, its place and its message
# match the Rust compiler's.
[Test]
reports_linking_errors_as_the_rust_compiler_does() {
    var compiler = process.find_companion("pep-build");
    if (!compiler.is_value()) {
        return;
    }
    var folder = TempFolder("link_errors");
    var trees = [
        # An unknown module and an unknown file.
        [
            "main.pep",
            "import nowhere;\nimport \"missing\";\nmain(): int { return 0; }\n"
        ],
        # A private symbol, a name two imports give different meanings,
        # and a qualifier that names no import.
        [
            "main.pep",
            "import [hidden] from geo;\nimport \"a\";\nimport \"b\";\nmain(): int { var t = Thing(); var p: q.Point; return 0; }\n",
            "deps/geo/module.pep",
            "hidden(): int { return 1; }\nexport shown(): int { return 2; }\n",
            "a.pep",
            "export struct Thing {}\n",
            "b.pep",
            "export struct Thing { var x: int; }\n"
        ],
        # A re-export of an unknown name, a name exported twice, and an
        # import that repeats a declaration.
        [
            "main.pep",
            "import geo;\nimport [Shape] from geo;\nstruct Shape {}\nmain(): int { return geo.area(); }\n",
            "deps/geo/module.pep",
            "import \"shapes\";\nexport struct Shape {}\nexport nothing as something;\nexport area as Shape;\nexport area;\n",
            "deps/geo/shapes.pep",
            "export area(): int { return 3; }\n"
        ],
        # Overrides whose type arguments are not structs, and a generic
        # defined twice.
        [
            "main.pep",
            "import [pick, Shape] from lib;\npick<Shape>(s: Shape): int { return 1; }\npick<Unknown>(u: Unknown): int { return 2; }\nsame<T>(t: T): int { return 0; }\nsame<U>(u: U): int { return 1; }\nmain(): int { return 0; }\n",
            "deps/lib/module.pep",
            "export pick<T>(value: T): int { return 0; }\nexport trait Shape { area(): int; }\n"
        ],
        # `private` names of one module: the same names in two files, and
        # uses from another file of the module and from outside it.
        [
            "main.pep",
            "import [use] from shop;\nmain(): int { return use() + helper(); }\n",
            "deps/shop/module.pep",
            "export * from \"a\";\nexport * from \"b\";\n",
            "deps/shop/a.pep",
            "private helper(): int { return 1; }\nprivate struct Shelf {}\nprivate extend Shelf { shelf_area(): int { return 0; } }\n",
            "deps/shop/b.pep",
            "private struct Shelf {}\nexport use(): int { var s = Shelf(); return helper() + s.shelf_area(); }\n"
        ]
    ];
    expect_equal(write_and_compare(compiler.value(), folder, trees), 0 as ulong);
}

# Programs the checks after linking report on: each error and warning, its
# place, its notes and its fix match the Rust compiler's.
[Test]
reports_check_errors_and_warnings_as_the_rust_compiler_does() {
    var compiler = process.find_companion("pep-build");
    if (!compiler.is_value()) {
        return;
    }
    var folder = TempFolder("check_errors");
    var trees = [
        # Deprecated functions, structs, constructors, constants and aliases,
        # used and declared; no warning inside a deprecated declaration.
        [
            "main.pep",
            "[Deprecated(\"use 'twice' instead\", \"twice\")]\ndup(x: int): int { return x * 2; }\ntwice(x: int): int { return x * 2; }\n[Deprecated(\"use 'Point' instead\")]\nstruct OldPoint { var x: int; }\n[Deprecated(\"\")]\nconst limit = 3;\nstruct Box {\n    var value: int;\n    [Deprecated(\"use 'make_box' instead\")]\n    construct(v: int) { value = v; }\n}\n[Deprecated(\"old\")]\ntype Alias = int;\n[Deprecated(\"old\")]\ntrait Shape { area(): int; }\n[Deprecated(\"old\")]\nhelper(): int { return limit + dup(1); }\nmain(): int {\n    var p: OldPoint = OldPoint();\n    var b = Box(limit);\n    var a: Alias = dup(21);\n    var f = () => dup(2);\n    return p.x + b.value + a + f();\n}\n"
        ],
        # A deprecated export used through a qualifier and an import list.
        [
            "main.pep",
            "import \"lib\" as l;\nimport [stale] from \"lib\";\nmain(): int {\n    return l.stale() + stale();\n}\n",
            "lib.pep",
            "[Deprecated(\"use 'fresh' instead\", \"fresh\")]\nexport stale(): int { return 1; }\nexport fresh(): int { return 1; }\n"
        ],
        # A `new` constructor, and comparisons with undefined build options.
        [
            "main.pep",
            "struct S {\n    var x: int;\n    new(v: int) { x = v; }\n}\n[Target(BuildOption(FAST) == 1)]\nfast(): int { return 1; }\n[Target(BuildOption(FAST) == 1 or BuildOption(\"SLOW\") >= 2)]\nslow(): int { return 2; }\nmain(): int { var s = S(1); return s.x; }\n"
        ],
        # `[__BuiltIn]` outside the runtime.
        [
            "main.pep",
            "[__BuiltIn(thing)]\nstruct Thing {}\n[__BuiltIn]\nother(): int { return 0; }\nmain(): int { return 0; }\n"
        ],
        # Extension methods out of reach, and types of a module not imported.
        [
            "main.pep",
            "import geo;\nimport \"local\";\nextend Shape { more(): int { return hidden() + shown(); } }\nmain(): int {\n    var s = Shape();\n    var t: Box<int> = Box<int>();\n    return s.shown() + s.hidden() + s.across() + t.get();\n}\n",
            "deps/geo/module.pep",
            "export struct Shape { var n: int; }\nextend Shape { hidden(): int { return 1; } }\nexport extend Shape { shown(): int { return 2; } }\nexport struct Box<T> { var v: T; get(): int { return v.size(); } }\n",
            "deps/other/module.pep",
            "import geo;\nexport extend geo.Shape { across(): int { return 3; } }\n",
            "local.pep",
            "import geo;\nimport other;\nexport probe(): int { return 0; }\n"
        ],
        # Types and variables declared twice, and overrides in two files.
        [
            "main.pep",
            "import \"a\";\nimport \"b\";\nstruct P {}\nstruct P {}\nvar q = 1;\nvar q = 2;\nmain(): int { return 0; }\n",
            "a.pep",
            "export helper(): int { return 1; }\nexport hash<T>(v: T): ulong { return 0; }\nhash<int>(v: int): ulong { return 1; }\n",
            "b.pep",
            "export helper(): int { return 2; }\nhash<int>(v: int): ulong { return 2; }\n"
        ],
        # Members of private extensions, through a trait default and generic
        # receivers, and private functions.
        [
            "main.pep",
            "import \"lib\";\ntrait Named { name(): int; describe(): int { return name() + extra(); } }\nstruct G<T> { var v: T; f(): int { return v.secret() + this.v.secret(); } }\ng<T>(x: T): int { var y = x; return y.secret() + x.secret(); }\nmain(): int { var l = Lib(); return l.secret() + private_fn() + PUBLIC; }\n",
            "lib.pep",
            "export struct Lib { var n: int; }\nextend Lib { secret(): int { return 1; } extra(): int { return 2; } }\nextend Lib with Named { name(): int { return 3; } }\nprivate_fn(): int { return 4; }\nexport const PUBLIC = 5;\n"
        ],
        # Tabs and characters outside ASCII before the reported name.
        [
            "main.pep",
            "import \"lib\";\nmain(): int {\n\tvar s = \"été\t!\"; return hidden() + s.size;\n}\n",
            "lib.pep",
            "hidden(): int { return 1; }\n"
        ],
        # Lines that end in CRLF.
        [
            "main.pep",
            "import \"lib\";\nmain(): int {\n\tvar x = Lib();\r\n\treturn hidden(x) + Lib.make().n;\r\n}\r\n",
            "lib.pep",
            "export struct Lib { var n: int; static make(): Lib { return Lib(); } }\nhidden(l: Lib): int { return l.n; }\n"
        ]
    ];
    expect_equal(write_and_compare(compiler.value(), folder, trees), 0 as ulong);
}

# Writes each tree of files (name, text, name, text, ...) to a folder of
# its own in `folder`, compares the program rooted at its `main.pep`, with
# its `deps` folder searched for modules, and returns how many differ.
write_and_compare(compiler: Path, folder: TempFolder, trees: String[][]): ulong {
    ulong mismatches = 0;
    ulong t = 0;
    while (t < trees.count) {
        var root = folder.path.join($"tree{t}");
        var files = trees[t];
        ulong i = 0;
        while (i + 1 < files.count) {
            var path = root.join(files[i]);
            Directory.create_all(path.parent().value());
            File.write_text(path, files[i + 1]);
            i += 2;
        }
        Directory.create_all(root.join("deps"));
        if (!same_program(compiler, root.join("main.pep"), ["-I", root.join("deps").to_string()])) {
            mismatches += 1;
        }
        t += 1;
    }
    return mismatches;
}

# Whether the two linkers agree on the program rooted at `root`, and the
# two compilers' checks after linking, reporting where they do not. A
# program the Rust compiler cannot load is skipped.
same_program(compiler: Path, root: Path, arguments: String[]): bool {
    var expected = rust_output(compiler, "--emit-linked", root, arguments);
    if (!expected.is_value()) {
        return true;
    }
    var setup = link.Setup();
    ulong i = 0;
    while (i < arguments.count) {
        if (arguments[i] == "-I") {
            setup.import_dirs.append(Path(arguments[i + 1]));
        }
        i += 1;
    }
    var program = link.load_program(root, setup);
    if (program.is_err()) {
        print($"{root}: the Rust compiler links it, but: {program.error()}");
        return false;
    }
    var actual = program.value().to_json().to_string();
    if (actual != expected.value()) {
        var at = first_difference(actual, expected.value());
        print(
            $"{root}: the linked program differs from the Rust compiler's at byte {at} of its JSON: {excerpt(actual, at)} not {excerpt(expected.value(), at)}"
        );
        return false;
    }
    var checked = rust_output(compiler, "--emit-checked", root, arguments);
    var report = program.value().check_report();
    if (checked.is_value() and report != checked.value()) {
        print(
            $"{root}: the checks report differs from the Rust compiler's at byte {first_difference(report, checked.value())}"
        );
        print(report);
        return false;
    }
    return true;
}

# What `pep-build` prints with `option` for the program rooted at `root`,
# without the final newline; none when it fails.
rust_output(compiler: Path, option: String, root: Path, arguments: String[]): String? {
    var command = process.Command(compiler.to_string()).argument(option);
    for (var argument in arguments) {
        command.argument(argument);
    }
    var output = command.argument(root.to_string()).stdout(process.Stream.Pipe).stderr(process.Stream.Pipe).run();
    if (output.is_err() or !output.value().status.success()) {
        return Optional<String>.Empty;
    }
    var text = output.value().stdout;
    if (text.ends_with("\n")) {
        text = text.substr_bytes(0, text.size - 1);
    }
    return Optional<String>.Value(text);
}

# Up to 200 bytes of `text` around `at`.
excerpt(text: String, at: ulong): String {
    var start = at > 100 ? at - 100 : 0;
    var end = at + 100 < text.size ? at + 100 : text.size;
    return text.substr_bytes(start, end - start);
}

first_difference(a: String, b: String): ulong {
    ulong i = 0;
    while (i < a.size and i < b.size and a.byte_at(i) == b.byte_at(i)) {
        i += 1;
    }
    return i;
}
