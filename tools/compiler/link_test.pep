# The compiler's linker in Pepper loads and links programs as the Rust
# compiler does: the JSON of every file after linking, with the linking
# errors, from `compiler.link` here and from `pep-build --emit-linked`,
# match byte for byte.

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
        ]
    ];
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
        if (!same_program(compiler.value(), root.join("main.pep"), ["-I", root.join("deps").to_string()])) {
            mismatches += 1;
        }
        t += 1;
    }
    expect_equal(mismatches, 0 as ulong);
}

# Whether the two linkers agree on the program rooted at `root`, reporting
# where they do not. A program the Rust compiler cannot load is skipped.
same_program(compiler: Path, root: Path, arguments: String[]): bool {
    var command = process.Command(compiler.to_string()).argument("--emit-linked");
    var setup = link.Setup();
    ulong i = 0;
    while (i < arguments.count) {
        command.argument(arguments[i]);
        if (arguments[i] == "-I") {
            setup.import_dirs.append(Path(arguments[i + 1]));
        }
        i += 1;
    }
    var output = command.argument(root.to_string()).stdout(process.Stream.Pipe).stderr(process.Stream.Pipe).run();
    if (output.is_err() or !output.value().status.success()) {
        return true;
    }
    var expected = output.value().stdout.trim_end();
    var program = link.load_program(root, setup);
    if (program.is_err()) {
        print($"{root}: the Rust compiler links it, but: {program.error()}");
        return false;
    }
    var actual = program.value().to_json().to_string();
    if (actual != expected) {
        print(
            $"{root}: the linked program differs from the Rust compiler's at byte {first_difference(actual, expected)} of its JSON"
        );
        return false;
    }
    return true;
}

first_difference(a: String, b: String): ulong {
    ulong i = 0;
    while (i < a.size and i < b.size and a.byte_at(i) == b.byte_at(i)) {
        i += 1;
    }
    return i;
}
