# The compiler's linker loads and links every program of the corpus
# without an error, and reports on each of the curated programs below the
# errors and warnings its first lines expect (`expected_outcomes`).

import compiler.ast;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import compiler.parse;
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
        "overloading-runtime",
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
            "# expect: main.pep:3:8: error: cannot find module 'nowhere': no nowhere/module.pep in deps, runtime\n# expect: main.pep:4:8: error: cannot find 'missing.pep' or the module folder 'missing' next to this file\nimport nowhere;\nimport \"missing\";\nmain(): int { return 0; }\n"
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
        ],
        # A match on a trait value names a struct of another file of the
        # module, which this file does not import.
        [
            "main.pep",
            "# expect: deps/shop/b.pep:2:41: error: 'Circle' is declared in deps/shop/c.pep, another file of this module, which this file does not import; add an import for it\nimport [use] from shop;\nmain(): int { return 0; }\n",
            "deps/shop/module.pep",
            "import \"c\";\nexport * from \"b\";\n",
            "deps/shop/a.pep",
            "export trait Shape { area(): int; }\n",
            "deps/shop/c.pep",
            "import \"a\";\nexport struct Circle { var r: int = 0; }\nextend Circle with Shape { area(): int { return r; } }\n",
            "deps/shop/b.pep",
            "import \"a\";\nexport use(s: Shape): int { match (s) { Circle(c) => { return c.r; } else => { return 0; } } }\n"
        ],
        # An enum's case shares its name with a struct two imports provide.
        [
            "main.pep",
            "# expect: accepted\nimport \"a\";\nimport \"b\";\nenum Shape { Circle(radius: int), Dot }\nmain(): int { match (Shape.Dot) { Circle(radius) => { return radius; } Dot => { return 0; } } }\n",
            "a.pep",
            "export struct Circle {}\n",
            "b.pep",
            "export struct Circle {}\n"
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
        # A comparison of two undefined build options warns at each (#374).
        [
            "main.pep",
            "# expect: main.pep:3:9: warning: build option 'FAST' is not defined; the comparison is false\n# expect: main.pep:3:29: warning: build option 'SLOW' is not defined; the comparison is false\n[Target(BuildOption(FAST) < BuildOption(\"SLOW\"))]\nboth(): int { return 3; }\nmain(): int { return 0; }\n"
        ],
        # Arithmetic on an undefined build option warns at it (#375).
        [
            "main.pep",
            "# expect: main.pep:2:13: warning: build option 'LEVEL' is not defined; the comparison is false\n[Target(2 * BuildOption(LEVEL) % 3 == 0)]\nthird(): int { return 3; }\nmain(): int { return 0; }\n"
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
        # An extern and a function of one name in two files of a module,
        # the extern's file first in path order, as process's `fork`.
        [
            "main.pep",
            "# expect: accepted\nimport sys;\nmain(): int { return sys.go(); }\n",
            "deps/sys/a_sys.pep",
            "extern int go();\n",
            "deps/sys/module.pep",
            "import \"a_sys\";\nexport go(): int { return 1; }\n"
        ],
        # Members of private extensions, through a trait default and generic
        # receivers, and private functions.
        [
            "main.pep",
            "# expect: main.pep:10:62: error: 'extra' is declared in a private extension in lib.pep; declare the extension with 'export' to use it from another file\n# expect: lib.pep:2:42: note: declared here\n# expect: main.pep:13:39: error: 'secret' is declared in a private extension in lib.pep; declare the extension with 'export' to use it from another file\n# expect: lib.pep:2:14: note: declared here\n# expect: main.pep:13:50: error: 'private_fn' is private to lib.pep; declare it with 'export' to use it from another file\n# expect: lib.pep:4:1: note: declared here\n# expect: lib.pep:3:17: error: 'Named' is private to main.pep; declare it with 'export' to use it from another file\n# expect: main.pep:10:7: note: declared here\nimport \"lib\";\ntrait Named { name(): int; describe(): int { return name() + extra(); } }\nstruct G<T> { var v: T; f(): int { return v.secret() + this.v.secret(); } }\ng<T>(x: T): int { var y = x; return y.secret() + x.secret(); }\nmain(): int { var l = Lib(); return l.secret() + private_fn() + PUBLIC; }\n",
            "lib.pep",
            "export struct Lib { var n: int; }\nextend Lib { secret(): int { return 1; } extra(): int { return 2; } }\nextend Lib with Named { name(): int { return 3; } }\nprivate_fn(): int { return 4; }\nexport const PUBLIC = 5;\n"
        ],
        # Declarations named like built-in types.
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
        ],
        # A package with a build script, found on the import path, whose
        # `generated` module no build makes (#413).
        [
            "main.pep",
            "# expect: deps/gen/module.pep:1:8: error: 'gen' generates module 'generated' with its build script, which runs only for the project and its dependencies; add 'gen' to '[dependencies]' instead of finding it on the import path\nimport gen;\nmain(): int {\n    return gen.answer();\n}\n",
            "deps/gen/pep.toml",
            "[package]\nname = \"gen\"\nversion = \"0.1.0\"\n",
            "deps/gen/build.pep",
            "main(): int {\n    return 0;\n}\n",
            "deps/gen/module.pep",
            "import generated;\nexport answer(): int {\n    return generated.answer();\n}\n"
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

# The `[Target]` attribute of `f` in `[Target(condition)] f() {}`.
_target_attribute(condition: String): ast.Attribute {
    return parse.parse("[Target(" + condition + ")]\nf() {}\n").value().build_option_tests[0];
}

# A `[Target]` compares two build options (#374): as integers when both
# values are, else as numbers when both are, else as text, which `<` and
# the other orderings refuse; and it is false when either is not defined.
[Test]
compares_two_build_options() {
    var target = link.Target();
    target.build_options["TWO"] = "2";
    target.build_options["TEN"] = "10";
    target.build_options["HEX"] = "0xa";
    target.build_options["HALF"] = "2.5";
    target.build_options["WORD"] = "high";
    target.build_options["SAME"] = "high";
    # The first is 2 < 10, though "2" > "10" as text.
    for (var (
        condition,
        kept
    ) in [
        ("BuildOption(TWO) < BuildOption(TEN)", true),
        ("BuildOption(TEN) == BuildOption(HEX)", true),
        ("BuildOption(HALF) > BuildOption(TWO)", true),
        ("BuildOption(TWO) >= BuildOption(HALF)", false),
        ("BuildOption(WORD) == BuildOption(SAME)", true),
        ("BuildOption(WORD) != BuildOption(TWO)", true),
        ("BuildOption(WORD) == BuildOption(TWO)", false),
        ("BuildOption(TWO) == BuildOption(UNSET)", false),
        ("BuildOption(UNSET) != BuildOption(TWO)", false),
        ("BuildOption(UNSET) == BuildOption(\"UNSET\")", false),
        ("BuildOption(UNSET) < BuildOption(WORD)", false)
    ]) {
        var attribute = _target_attribute(condition);
        expect_false(target.check(attribute).is_value());
        expect_equal(target.keep([attribute]).value(), kept);
    }
    # At the operator, naming the value that is not a number.
    for (var (
        condition,
        message
    ) in [
        (
            "BuildOption(WORD) < BuildOption(TWO)",
            "build option 'WORD' is 'high', which is not a number; '<' compares two build options only as numbers"
        ),
        (
            "BuildOption(HALF) >= BuildOption(SAME)",
            "build option 'SAME' is 'high', which is not a number; '>=' compares two build options only as numbers"
        )
    ]) {
        var error = target.check(_target_attribute(condition));
        expect_equal(error.value().0, message);
        expect_equal(error.value().1.start, 26 as ulong);
    }
}

# A `[Target]` computes with build options (#375): `+ - * / %` on options
# and numbers, as `long`s when every value is an integer, else as
# `double`s; false when an option in it is not defined.
[Test]
computes_with_build_options() {
    var target = link.Target();
    target.build_options["TWO"] = "2";
    target.build_options["TEN"] = "10";
    target.build_options["HEX"] = "0xa";
    target.build_options["HALF"] = "2.5";
    target.build_options["WORD"] = "high";
    target.build_options["BIG"] = "9223372036854775807";
    for (var (
        condition,
        kept
    ) in [
        ("BuildOption(TEN) % 2 == 0", true),
        ("BuildOption(TWO) + 1 > 2", true),
        ("BuildOption(TWO) + 1 > 3", false),
        ("BuildOption(TWO) + BuildOption(TEN) * 2 == 22", true),
        ("(BuildOption(TWO) + BuildOption(TEN)) * 2 == 24", true),
        ("2 * BuildOption(HEX) == 20", true),
        ("1 + 2 > BuildOption(TWO)", true),
        ("BuildOption(TEN) / 4 == 2", true),
        ("BuildOption(TEN) / 4.0 == 2.5", true),
        ("BuildOption(HALF) * 2 == 5", true),
        ("-7 % BuildOption(TWO) == -1", true),
        ("BuildOption(TWO) - 3 < -0.5", true),
        ("BuildOption(BIG) / -1 == -9223372036854775807", true),
        ("BuildOption(HALF) / 0 > 1", true),
        ("BuildOption(UNSET) + 1 > 0", false),
        ("BuildOption(UNSET) + 1 != 0", false),
        ("BuildOption(UNSET) / 0 == 1", false)
    ]) {
        var attribute = _target_attribute(condition);
        expect_false(target.check(attribute).is_value());
        expect_equal(target.keep([attribute]).value(), kept);
    }
    # At the operator, or at an operand that is not a number.
    for (var (
        condition,
        message,
        start
    ) in [
        (
            "BuildOption(WORD) % 2 == 0",
            "build option 'WORD' is 'high', which is not a number; '%' takes only numbers",
            26 as ulong
        ),
        (
            "BuildOption(TWO) + 1 == BuildOption(WORD)",
            "build option 'WORD' is 'high', which is not a number; '==' compares arithmetic only with numbers",
            29 as ulong
        ),
        ("BuildOption(TWO) / 0 == 1", "division by zero in a 'Target' condition", 25 as ulong),
        ("BuildOption(TWO) % (BuildOption(TWO) - 2) == 1", "remainder by zero in a 'Target' condition", 25 as ulong),
        (
            "BuildOption(BIG) * 2 > 0",
            "integer overflow: '9223372036854775807 * 2' does not fit in a 'long'",
            25 as ulong
        ),
        ("BuildOption(TWO) + \"x\" > 1", "'+' in a 'Target' takes only build options and numbers", 27 as ulong),
        (
            "BuildOption(TWO) + 1 == true",
            "'==' in a 'Target' compares arithmetic only with build options and numbers",
            32 as ulong
        ),
        (
            "BuildOption(TWO) + 1",
            "'+' in a 'Target' must be part of a comparison, such as 'BuildOption(A) + 2 == 0'",
            25 as ulong
        )
    ]) {
        var error = target.check(_target_attribute(condition));
        expect_equal(error.value().0, message);
        expect_equal(error.value().1.start, start);
    }
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
