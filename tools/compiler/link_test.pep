# The compiler's linker loads and links every program of the corpus
# without an error, and reports on each of the curated programs below the
# errors and warnings its first lines expect (`expected_outcomes`).

import io;
import [Directory, File, Path] from io;
import compiler.link;
import [TempFolder] from testing;
import [check_trees, headline, headlines] from "expected_outcomes";

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
# programs of several files, from the `part`th, which must load and link
# without an error.
links_programs(part: ulong) {
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
    ulong failed = 0;
    ulong i = part;
    while (i < programs.count) {
        var program = link.load_program(programs[i], link.Setup());
        var errors = program.is_ok() ? program.value().check() : Optional<String>.Value(program.error());
        if (errors.is_value()) {
            print($"{programs[i]}: {errors.value()}");
            failed += 1;
        }
        i += PARTS;
    }
    expect_equal(failed, 0 as ulong);
}

# Programs whose imports are wrong: each error, its place and its message
# are the expected ones.
[Test]
reports_linking_errors() {
    var folder = TempFolder("link_errors");
    var trees = [
        # An unknown module and an unknown file.
        [
            "main.pep",
            "# expect: main.pep:3:8: error: cannot find module 'nowhere': no nowhere/module.pep in deps, runtime\n# expect: main.pep:4:8: error: cannot find \"missing.pep\" or the module folder \"missing\" next to this file\nimport nowhere;\nimport \"missing\";\nmain(): int { return 0; }\n"
        ],
        # A private symbol, a name two imports give different meanings,
        # and a qualifier that names no import.
        [
            "main.pep",
            "# expect: main.pep:4:9: error: 'hidden' is not exported by module 'geo'\n# expect: main.pep:7:23: error: 'Thing' is ambiguous: more than one import provides it\n# expect: main.pep:7:39: error: 'q' is not an imported module\nimport [hidden] from geo;\nimport \"a\";\nimport \"b\";\nmain(): int { var t = Thing(); var p: q.Point; return 0; }\n",
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
            "# expect: main.pep:5:9: error: 'Shape' is imported but also declared in this file\n# expect: deps/geo/module.pep:3:8: error: cannot export 'nothing': no such symbol in this file or its imports\n# expect: deps/geo/module.pep:4:1: error: 'Shape' is exported twice, as 'Shape' and 'area'\nimport geo;\nimport [Shape] from geo;\nstruct Shape {}\nmain(): int { return geo.area(); }\n",
            "deps/geo/module.pep",
            "import \"shapes\";\nexport struct Shape {}\nexport nothing as something;\nexport area as Shape;\nexport area;\n",
            "deps/geo/shapes.pep",
            "export area(): int { return 3; }\n"
        ],
        # Overrides whose type arguments are not structs, and a generic
        # defined twice.
        [
            "main.pep",
            "# expect: main.pep:4:6: error: 'Shape' is not a struct; an override's type argument must name a struct\n# expect: main.pep:7:1: error: redefinition of generic 'same'; to override it for a type, each type argument must name a struct this file can see\nimport [pick, Shape] from lib;\npick<Shape>(s: Shape): int { return 1; }\npick<Unknown>(u: Unknown): int { return 2; }\nsame<T>(t: T): int { return 0; }\nsame<U>(u: U): int { return 1; }\nmain(): int { return 0; }\n",
            "deps/lib/module.pep",
            "export pick<T>(value: T): int { return 0; }\nexport trait Shape { area(): int; }\n"
        ],
        # `private` names of one module: the same names in two files, and
        # uses from another file of the module and from outside it.
        [
            "main.pep",
            "# expect: main.pep:8:30: error: 'helper' is internal to module 'shop'; export it from the module to use it here\n# expect: deps/shop/a.pep:1:9: note: declared here\n# expect: deps/shop/b.pep:2:45: error: 'helper' is private to deps/shop/a.pep; remove 'private' to use it from the other files of its module\n# expect: deps/shop/a.pep:1:9: note: declared here\n# expect: deps/shop/b.pep:2:58: error: 'shelf_area' is declared in a private extension in deps/shop/a.pep; remove 'private' to use it from the other files of its module\n# expect: deps/shop/a.pep:3:24: note: declared here\nimport [use] from shop;\nmain(): int { return use() + helper(); }\n",
            "deps/shop/module.pep",
            "export * from \"a\";\nexport * from \"b\";\n",
            "deps/shop/a.pep",
            "private helper(): int { return 1; }\nprivate struct Shelf {}\nprivate extend Shelf { shelf_area(): int { return 0; } }\n",
            "deps/shop/b.pep",
            "private struct Shelf {}\nexport use(): int { var s = Shelf(); return helper() + s.shelf_area(); }\n"
        ],
        # A file of a module that uses another file's function, struct and
        # extension method without importing that file.
        [
            "main.pep",
            "# expect: deps/shop/b.pep:1:29: error: 'Shelf' is declared in deps/shop/a.pep, another file of this module, which this file does not import; add an import for it\n# expect: deps/shop/b.pep:1:45: error: 'helper' is declared in deps/shop/a.pep, another file of this module, which this file does not import; add an import for it\nimport [use] from shop;\nmain(): int { return use(); }\n",
            "deps/shop/module.pep",
            "import \"a\";\nexport * from \"b\";\n",
            "deps/shop/a.pep",
            "helper(): int { return 1; }\nstruct Shelf { var n: int = 0; }\nextend Shelf { shelf_size(): int { return n; } }\n",
            "deps/shop/b.pep",
            "export use(): int { var s = Shelf(); return helper() + s.shelf_size(); }\n"
        ],
        # The same with an extension's method: the struct's file is
        # imported, the file of the extension is not.
        [
            "main.pep",
            "# expect: deps/shop/b.pep:2:33: error: 'shelf_room' is declared in an extension in deps/shop/a.pep, which this file does not import; add an import for it\n# expect: deps/shop/a.pep:2:16: note: declared here\nimport [use] from shop;\nmain(): int { return use(); }\n",
            "deps/shop/module.pep",
            "import \"a\";\nexport * from \"b\";\n",
            "deps/shop/c.pep",
            "struct Shelf { var n: int = 0; }\n",
            "deps/shop/a.pep",
            "import \"c\";\nextend Shelf { shelf_room(): int { return n; } }\n",
            "deps/shop/b.pep",
            "import \"c\";\ncount(s: Shelf): int { return s.shelf_room(); }\nexport use(): int { return count(Shelf()); }\n"
        ]
    ];
    expect_equal(check_trees(folder, trees, outcome), 0 as ulong);
}

# Programs the checks after linking report on: each error, warning and
# note, and its place, are the expected ones.
[Test]
reports_check_errors_and_warnings() {
    var folder = TempFolder("check_errors");
    var trees = [
        # Deprecated functions, structs, constructors, constants and aliases,
        # used and declared; no warning inside a deprecated declaration.
        [
            "main.pep",
            "# expect: main.pep:34:12: warning: 'OldPoint' is deprecated: use 'Point' instead [deprecated]\n# expect: main.pep:19:8: note: 'OldPoint' declared here\n# expect: main.pep:34:23: warning: 'OldPoint' is deprecated: use 'Point' instead [deprecated]\n# expect: main.pep:19:8: note: 'OldPoint' declared here\n# expect: main.pep:35:13: warning: 'Box' is deprecated: use 'make_box' instead [deprecated]\n# expect: main.pep:25:5: note: 'Box' declared here\n# expect: main.pep:35:17: warning: 'limit' is deprecated [deprecated]\n# expect: main.pep:21:7: note: 'limit' declared here\n# expect: main.pep:36:12: warning: 'Alias' is deprecated: old [deprecated]\n# expect: main.pep:28:6: note: 'Alias' declared here\n# expect: main.pep:36:20: warning: 'dup' is deprecated: use 'twice' instead [deprecated]\n# expect: main.pep:16:1: note: 'dup' declared here\n# expect: main.pep:37:19: warning: 'dup' is deprecated: use 'twice' instead [deprecated]\n# expect: main.pep:16:1: note: 'dup' declared here\n[Deprecated(\"use 'twice' instead\", \"twice\")]\ndup(x: int): int { return x * 2; }\ntwice(x: int): int { return x * 2; }\n[Deprecated(\"use 'Point' instead\")]\nstruct OldPoint { var x: int; }\n[Deprecated(\"\")]\nconst limit = 3;\nstruct Box {\n    var value: int;\n    [Deprecated(\"use 'make_box' instead\")]\n    construct(v: int) { value = v; }\n}\n[Deprecated(\"old\")]\ntype Alias = int;\n[Deprecated(\"old\")]\ntrait Shape { area(): int; }\n[Deprecated(\"old\")]\nhelper(): int { return limit + dup(1); }\nmain(): int {\n    var p: OldPoint = OldPoint();\n    var b = Box(limit);\n    var a: Alias = dup(21);\n    var f = () => dup(2);\n    return p.x + b.value + a + f();\n}\n"
        ],
        # A deprecated export used through a qualifier and an import list.
        [
            "main.pep",
            "# expect: main.pep:10:14: warning: 'stale' is deprecated: use 'fresh' instead [deprecated]\n# expect: lib.pep:2:8: note: 'stale' declared here\n# expect: main.pep:10:24: warning: 'stale' is deprecated: use 'fresh' instead [deprecated]\n# expect: lib.pep:2:8: note: 'stale' declared here\n# expect: main.pep:8:9: warning: 'stale' is deprecated: use 'fresh' instead [deprecated]\n# expect: lib.pep:2:8: note: 'stale' declared here\nimport \"lib\" as l;\nimport [stale] from \"lib\";\nmain(): int {\n    return l.stale() + stale();\n}\n",
            "lib.pep",
            "[Deprecated(\"use 'fresh' instead\", \"fresh\")]\nexport stale(): int { return 1; }\nexport fresh(): int { return 1; }\n"
        ],
        # A `new` constructor, and comparisons with undefined build options.
        [
            "main.pep",
            "# expect: main.pep:7:5: warning: `new` is deprecated; constructors are spelled `construct`, matching `destruct` [deprecated]\n# expect: main.pep:9:9: warning: build option 'FAST' is not defined; the comparison is false\n# expect: main.pep:11:9: warning: build option 'FAST' is not defined; the comparison is false\n# expect: main.pep:11:35: warning: build option 'SLOW' is not defined; the comparison is false\nstruct S {\n    var x: int;\n    new(v: int) { x = v; }\n}\n[Target(BuildOption(FAST) == 1)]\nfast(): int { return 1; }\n[Target(BuildOption(FAST) == 1 or BuildOption(\"SLOW\") >= 2)]\nslow(): int { return 2; }\nmain(): int { var s = S(1); return s.x; }\n"
        ],
        # `[__BuiltIn]` outside the runtime.
        [
            "main.pep",
            "# expect: main.pep:3:2: error: '__BuiltIn' declares a compiler built-in and is allowed only in the runtime\n# expect: main.pep:5:2: error: '__BuiltIn' declares a compiler built-in and is allowed only in the runtime\n[__BuiltIn(thing)]\nstruct Thing {}\n[__BuiltIn]\nother(): int { return 0; }\nmain(): int { return 0; }\n"
        ],
        # Extension methods out of reach, and types of a module not imported.
        [
            "main.pep",
            "# expect: main.pep:17:8: error: 'Shape' is exported by deps/geo/module.pep, which this file does not import; add an import for it\n# expect: deps/geo/module.pep:1:15: note: declared here\n# expect: main.pep:17:37: error: 'hidden' is declared in an extension internal to module 'geo'; export the extension to use it here\n# expect: deps/geo/module.pep:2:16: note: declared here\n# expect: main.pep:19:13: error: 'Shape' is exported by deps/geo/module.pep, which this file does not import; add an import for it\n# expect: deps/geo/module.pep:1:15: note: declared here\n# expect: main.pep:20:12: error: 'Box' is exported by deps/geo/module.pep, which this file does not import; add an import for it\n# expect: deps/geo/module.pep:4:15: note: declared here\n# expect: main.pep:20:23: error: 'Box' is exported by deps/geo/module.pep, which this file does not import; add an import for it\n# expect: deps/geo/module.pep:4:15: note: declared here\n# expect: main.pep:21:26: error: 'hidden' is declared in an extension internal to module 'geo'; export the extension to use it here\n# expect: deps/geo/module.pep:2:16: note: declared here\n# expect: main.pep:21:39: error: 'across' is declared in an extension in deps/other/module.pep, which this file does not import; import its module 'other'\n# expect: deps/other/module.pep:2:27: note: declared here\nimport geo;\nimport \"local\";\nextend Shape { more(): int { return hidden() + shown(); } }\nmain(): int {\n    var s = Shape();\n    var t: Box<int> = Box<int>();\n    return s.shown() + s.hidden() + s.across() + t.get();\n}\n",
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
            "# expect: main.pep:8:8: error: redefinition of 'P'\n# expect: main.pep:7:8: note: previous definition is here\n# expect: main.pep:10:5: error: redefinition of 'q'\n# expect: main.pep:9:5: note: previous definition is here\nimport \"a\";\nimport \"b\";\nstruct P {}\nstruct P {}\nvar q = 1;\nvar q = 2;\nmain(): int { return 0; }\n",
            "a.pep",
            "import keys;\nexport helper(): int { return 1; }\n",
            "b.pep",
            "export helper(): int { return 2; }\n",
            "deps/keys/module.pep",
            "export struct Key { var n: int; }\nhash<Key>(v: Key): ulong { return 1; }\n",
            "deps/keys/more.pep",
            "hash<Key>(v: Key): ulong { return 2; }\n"
        ],
        # Members of private extensions, through a trait default and generic
        # receivers, and private functions.
        [
            "main.pep",
            "# expect: main.pep:10:62: error: 'extra' is declared in a private extension in lib.pep; declare the extension with 'export' to use it from another file\n# expect: lib.pep:2:42: note: declared here\n# expect: main.pep:13:39: error: 'secret' is declared in a private extension in lib.pep; declare the extension with 'export' to use it from another file\n# expect: lib.pep:2:14: note: declared here\n# expect: main.pep:13:50: error: 'private_fn' is private to lib.pep; declare it with 'export' to use it from another file\n# expect: lib.pep:4:1: note: declared here\n# expect: lib.pep:3:17: error: 'Named' is private to main.pep; declare it with 'export' to use it from another file\n# expect: main.pep:10:7: note: declared here\nimport \"lib\";\ntrait Named { name(): int; describe(): int { return name() + extra(); } }\nstruct G<T> { var v: T; f(): int { return v.secret() + this.v.secret(); } }\ng<T>(x: T): int { var y = x; return y.secret() + x.secret(); }\nmain(): int { var l = Lib(); return l.secret() + private_fn() + PUBLIC; }\n",
            "lib.pep",
            "export struct Lib { var n: int; }\nextend Lib { secret(): int { return 1; } extra(): int { return 2; } }\nextend Lib with Named { name(): int { return 3; } }\nprivate_fn(): int { return 4; }\nexport const PUBLIC = 5;\n"
        ],
        # Declarations named like built-in types (#719).
        [
            "main.pep",
            "# expect: main.pep:5:7: error: 'double' is the name of a built-in type; choose another name\n# expect: main.pep:6:8: error: 'short' is the name of a built-in type; choose another name\n# expect: lib.pep:1:8: error: 'float' is the name of a built-in type; choose another name\nimport \"lib\";\nconst double = (x: int): int => x * 2;\nstruct short {}\nmain(): int { return 0; }\n",
            "lib.pep",
            "export float(): int { return 1; }\n"
        ],
        # Tabs and characters outside ASCII before the reported name.
        [
            "main.pep",
            "# expect: main.pep:5:26: error: 'hidden' is private to lib.pep; declare it with 'export' to use it from another file\n# expect: lib.pep:1:1: note: declared here\nimport \"lib\";\nmain(): int {\n\tvar s = \"été\t!\"; return hidden() + s.size;\n}\n",
            "lib.pep",
            "hidden(): int { return 1; }\n"
        ],
        # Lines that end in CRLF.
        [
            "main.pep",
            "# expect: main.pep:6:9: error: 'hidden' is private to lib.pep; declare it with 'export' to use it from another file\n# expect: lib.pep:2:1: note: declared here\nimport \"lib\";\nmain(): int {\n\tvar x = Lib();\r\n\treturn hidden(x) + Lib.make().n;\r\n}\r\n",
            "lib.pep",
            "export struct Lib { var n: int; static make(): Lib { return Lib(); } }\nhidden(l: Lib): int { return l.n; }\n"
        ]
    ];
    expect_equal(check_trees(folder, trees, outcome), 0 as ulong);
}

# How loading, linking and the checks after linking end on the program
# rooted at `root`, with its `deps` folder searched for modules.
outcome(root: Path): String {
    var setup = link.Setup();
    setup.import_dirs.append(root.parent().value().join("deps"));
    var program = link.load_program(root, setup);
    if (program.is_err()) {
        return headline(program.error(), root);
    }
    return headlines(program.value().check_report(), root);
}

[Test]
symbols_get_their_linker_spelling() {
    expect_equal(link.symbol_name("main"), "main");
    expect_equal(link.symbol_name("Point.length"), "Point.length");
    expect_equal(link.symbol_name("Array<int>.count"), "_PArray_3cint_3e.count");
    expect_equal(link.symbol_name("helper@io/file"), "_Phelper_40io_2ffile");
    expect_equal(link.symbol_name("a_b@x"), "_Pa__b_40x");
    expect_equal(link.symbol_name("_Pfoo"), "_P__Pfoo");
    expect_equal(link.symbol_name("exit"), "_Pexit");
    expect_equal(link.symbol_name("_pep_malloc"), "_P__pep__malloc");
    expect_not_equal(link.symbol_name("a_40"), link.symbol_name("a@"));
}

# The orphan rule, which only this compiler checks: an override goes in
# the file or module that declares the generic or one of its type
# arguments.
[Test]
overrides_go_beside_their_generic_or_type() {
    var folder = TempFolder("orphan");
    var files = [
        "main.pep",
        "import \"lib\";\nimport [Spot] from geo;\nstruct Mine { var n: int; }\nhash<Mine>(v: Mine): ulong { return 1; }\ndescribe<Mine>(v: Mine): int { return 2; }\nhash<bool>(v: bool): ulong { return 3; }\ndescribe<Spot>(v: Spot): int { return 4; }\nmain(): int { return 0; }\n",
        "lib.pep",
        "export describe<T>(v: T): int { return 0; }\ndescribe<int>(v: int): int { return 5; }\n",
        "deps/geo/module.pep",
        "import \"hashing\";\nexport struct Spot { var n: int; }\n",
        "deps/geo/hashing.pep",
        "hash<Spot>(v: Spot): ulong { return 6; }\n"
    ];
    ulong at = 0;
    while (at + 1 < files.count) {
        var path = folder.path.join(files[at]);
        Directory.create_all(path.parent().value());
        File.write_text(path, files[at + 1]);
        at += 2;
    }
    var setup = link.Setup();
    setup.import_dirs.append(folder.path.join("deps"));
    var program = link.load_program(folder.path.join("main.pep"), setup);
    expect_true(program.is_ok(), "the program loads");
    if (program.is_err()) {
        return;
    }
    var messages = Array<String>();
    for (var e in program.value().errors) {
        messages.append(e.message);
    }
    var expected = [
        "cannot override 'hash' for 'bool' here: an override must be in the file or module that declares 'hash' or one of its type arguments",
        "cannot override 'describe' for 'Spot' here: an override must be in the file or module that declares 'describe' or one of its type arguments"
    ];
    expect_equal(messages.count, expected.count);
    for (var i in 0..messages.count) {
        if (i < expected.count) {
            expect_equal(messages[i], expected[i]);
        }
    }
}
