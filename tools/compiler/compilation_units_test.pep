# Programs that once built one way and not the other: in compilation units
# (each file, or each import cycle of files, checked on its own, as a build
# with the cache checks it) or whole (with no cache). Each is built both ways
# and must run.

import compiler.driver;
import compiler.incremental;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import [TempFolder] from testing;

# Writes `files` (a path relative to the folder, then its text) into a new
# folder, builds its `main.pep` both ways and runs what each built.
_builds_and_runs(name: String, files: Array<(String, String)>) {
    var folder = TempFolder(name);
    var root = folder.path;
    for (var (path, text) in files) {
        var file = root.join(Path(path));
        Directory.create_all(file.parent().value());
        File.write_text(file, text);
    }
    for (var cached in [true, false]) {
        var setup = link.Setup();
        setup.import_dirs.append(root);
        var program = link.load_program(root.join(Path("main.pep")), setup);
        expect_true(program.is_ok());
        var output = root.join(Path(cached ? "units" : "whole"));
        var options = driver.BuildOptions(output, root.join(Path("build")));
        if (cached) {
            options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
        }
        options.in_process = true;
        var built = driver.build(program.value(), options);
        if (built.is_err()) {
            print($"{name} ({cached ? "units" : "whole"}): {built.error()}");
        }
        expect_true(built.is_ok());
        var ran = process.Command(output.to_string()).spawn();
        expect_true(ran.is_ok() and ran.value().wait().value().success());
    }
}

# A function of a compilation unit below held in a local and called through it:
# the compilation unit's bodies are set aside while the passes run, and the
# function was taken for a declaration with no body, not a value.
[Test]
calls_a_function_of_a_unit_below_through_a_local() {
    _builds_and_runs(
        "units_function_value",
        [
            ("util.pep", "export twice(x: int): int {\n    return x * 2;\n}\n"),
            ("main.pep", "import \"util\" as u;\nmain(): int {\n    var f = u.twice;\n    return f(4) - 8;\n}\n")
        ]
    );
}

# A generic struct with a generic method keeps its methods' bodies when
# the whole program is checked: a call in one given back late to a
# generic overload was bound without its specializations, to the plain
# overload beside it.
[Test]
binds_a_generic_overload_beside_a_plain_one() {
    _builds_and_runs(
        "generic_overload",
        [
            (
                "main.pep",
                "struct Describer<U> {\n    describe(value: bool): int {\n        return 1;\n    }\n    describe<T>(value: Array<T>): int {\n        return 2;\n    }\n    all(u: U): int {\n        return describe([u]);\n    }\n}\nmain(): int {\n    return Describer<int>().all(3) - 2;\n}\n"
            )
        ]
    );
}

# A closure in a generic method of a compilation unit below, specialized in this
# compilation unit, capturing a local whose type is inferred: the compilation
# unit walked only the structs it declared or extended, not the checked struct
# it added the specialization to, so the capture's type was never inferred.
[Test]
captures_an_inferred_local_in_a_method_specialized_above() {
    _builds_and_runs(
        "units_closure_capture",
        [
            (
                "lib/holder.pep",
                "struct _Item {\n    var n: int;\n    construct(n: int) {\n        this.n = n;\n    }\n}\nexport struct Holder {\n    var binders: Array<() => int> = Array<() => int>();\n    add<T>(value: T) {\n        var declared = Array<_Item>();\n        declared.append(_Item(1));\n        binders.append(() => declared.count as int);\n    }\n    run(): int {\n        var total = 0;\n        for (var b in binders) {\n            total += b();\n        }\n        return total;\n    }\n}\n"
            ),
            ("lib/module.pep", "export [Holder] from \"holder\";\n"),
            (
                "main.pep",
                "import [Holder] from lib;\nstruct Options {\n    var a: int = 0;\n}\nmain(): int {\n    var h = Holder();\n    h.add<Options>(Options());\n    return h.run() - 1;\n}\n"
            )
        ]
    );
}

# Two compilation units that read a third and not each other, each specializing
# a generic method of its struct the same way (here and in the runtime's
# `Copies`, which copying the array argument uses): merged, the program had
# both, "redefinition of '_address<Array<i32>>'".
[Test]
keeps_once_a_method_two_units_specialized() {
    _builds_and_runs(
        "units_twice_specialized",
        [
            ("lib/holder.pep", "export struct Holder {\n    get<T>(value: T): int {\n        return 1;\n    }\n}\n"),
            ("lib/module.pep", "export [Holder] from \"holder\";\n"),
            (
                "a.pep",
                "import [Holder] from lib;\nexport a_value(): int {\n    return Holder().get<Array<int>>([1]);\n}\n"
            ),
            (
                "b.pep",
                "import [Holder] from lib;\nexport b_value(): int {\n    return Holder().get<Array<int>>([2]);\n}\n"
            ),
            ("main.pep", "import \"a\";\nimport \"b\";\nmain(): int {\n    return a_value() + b_value() - 2;\n}\n")
        ]
    );
}

# The same with a method the passes synthesize for a use: two compilation units
# that copy a struct of a third each gave it a `__copy`.
[Test]
keeps_once_a_copy_method_two_units_made() {
    _builds_and_runs(
        "units_twice_copied",
        [
            (
                "lib/item.pep",
                "export struct Item {\n    var n: int;\n    var names: String[] = Array<String>();\n    construct(n: int) {\n        this.n = n;\n    }\n}\n"
            ),
            ("lib/module.pep", "export [Item] from \"item\";\n"),
            (
                "a.pep",
                "import [Item] from lib;\nexport a_value(): int {\n    var c = copy(Item(1));\n    return c.n;\n}\n"
            ),
            (
                "b.pep",
                "import [Item] from lib;\nexport b_value(): int {\n    var c = copy(Item(1));\n    return c.n;\n}\n"
            ),
            ("main.pep", "import \"a\";\nimport \"b\";\nmain(): int {\n    return a_value() + b_value() - 2;\n}\n")
        ]
    );
}

# Builds `main.pep` in `root`, which imports from `imports`, with the
# cache in `cache`, and runs it.
_build_with(root: Path, imports: Path, cache: Path) {
    var setup = link.Setup();
    setup.import_dirs.append(imports);
    var program = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    var output = root.join(Path("main"));
    var options = driver.BuildOptions(output, root.join(Path("build")));
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(cache));
    options.in_process = true;
    var built = driver.build(program.value(), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    var ran = process.Command(output.to_string()).spawn();
    expect_true(ran.is_ok() and ran.value().wait().value().success());
}

# A member the passes synthesize for a use (`__copy`) of a struct of a
# compilation unit below is defined wherever it is used, not in the struct's
# file's object: that object, cached by a program that never copied the struct,
# does not have it, and the program that copies it then did not link ("undefined
# reference to Item@lib/item.____copy").
[Test]
links_a_copy_method_the_cached_object_of_its_struct_lacks() {
    var folder = TempFolder("synthesized_member");
    var root = folder.path;
    var lib = root.join(Path("lib"));
    Directory.create_all(lib);
    File.write_text(
        lib.join(Path("item.pep")),
        "export struct Item {\n    var n: int;\n    var names: String[] = Array<String>();\n    construct(n: int) {\n        this.n = n;\n    }\n}\n"
    );
    File.write_text(lib.join(Path("module.pep")), "export [Item] from \"item\";\n");
    for (var (name, use) in [("plain", "Item(1).n"), ("copies", "copy(Item(1)).n")]) {
        var program = root.join(Path(name));
        Directory.create_all(program);
        File.write_text(
            program.join(Path("main.pep")), "import [Item] from lib;\nmain(): int {\n    return " + use + " - 1;\n}\n"
        );
        _build_with(program, root, root.join(Path("cache")));
    }
}

# Loads the program of `main.pep` and `lib/helpers.pep` (as `helpers`) with
# no runtime.
_load_two(name: String, main: String, helpers: String): (TempFolder, link.Program) {
    var folder = TempFolder(name);
    var root = folder.path;
    Directory.create_all(root.join(Path("lib")));
    File.write_text(root.join(Path("main.pep")), main);
    File.write_text(root.join(Path("lib")).join(Path("helpers.pep")), helpers);
    var setup = link.Setup();
    setup.runtime = false;
    setup.import_dirs.append(root);
    var program = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    return (folder, program.value());
}

_file_ending(program: link.Program, name: String): link.ProgramFile {
    for (var file in program.files) {
        if (file.name.ends_with(name)) {
            return file;
        }
    }
    expect_true(false);
    return program.files[0];
}

# What a file shows other units' code: a declaration's names outside the
# bodies of functions that are not generic, only to code that names it, its
# own name and its methods' left out.
[Test]
shows_the_names_outside_plain_bodies() {
    var (
        folder,
        program
    ) = _load_two(
        "file_names",
        "import \"lib/helpers\";\nmain(): int {\n    return shown_twice<int>(1) - 2;\n}\n",
        "_plain(): int {\n    return 2;\n}\n_in_generic(): int {\n    return 2;\n}\n_in_default(): int {\n    return 1;\n}\nexport shown_twice<T>(x: int = _in_default()): int {\n    return x * _in_generic();\n}\nexport hidden_twice(x: int): int {\n    return x * _plain();\n}\nstruct _Leaf {\n    var next: _Leaf?;\n}\nstruct _Tree {\n    var leaf: _Leaf;\n    size(): int {\n        return _plain();\n    }\n}\n"
    );
    var (all, shown, shown_by) = incremental.file_names(_file_ending(program, "helpers.pep"));
    for (var name in ["_plain", "_in_generic", "_in_default", "shown_twice", "hidden_twice", "_Leaf", "_Tree"]) {
        expect_true(all.contains(name));
        expect_false(shown.contains(name));
    }
    expect_true(shown_by["shown_twice"].contains("_in_generic") and shown_by["shown_twice"].contains("_in_default"));
    expect_false(shown_by["hidden_twice"].contains("_plain"));
    expect_true(shown_by["_Tree"].contains("_Leaf"));
    expect_false(shown_by["_Tree"].contains("_plain") or shown_by["_Tree"].contains("size"));
    expect_false(shown_by.contains("_Leaf") and shown_by["_Leaf"].contains("_Leaf"));
    expect_true(folder.path.is_dir());
}

# A compilation unit's key takes the entries of a function or struct that is
# not generic from another unit's own interface only when its code can name
# it, itself or through a declaration it names.
[Test]
keys_a_unit_on_the_functions_it_can_name() {
    var (
        folder,
        program
    ) = _load_two(
        "hidden_keys",
        "import \"lib/helpers\";\nmain(): int {\n    return twice(1) - 2;\n}\n",
        "export twice(x: int): int {\n    return x * _Box().x;\n}\nexport boxed(): _Box {\n    return _Box();\n}\nstruct _Box {\n    var x: int;\n}\n"
    );
    var units = incremental.compilation_units(program, "base");
    expect_true(units.count == 2);
    # `boxed` shows `_Box`, but `main` does not name `boxed`.
    var boxes = ["public\n_Box 1\ntwice 1", ""];
    var boxed = incremental.compilation_unit_key(units, 1, boxes);
    boxes[0] = "public\n_Box 2\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, boxes) == boxed);
    units[1].mentions.insert("boxed");
    units[1].reach = Optional<HashSet<String>>.Empty;
    expect_true(incremental.compilation_unit_key(units, 1, boxes) != boxed);
    units[1].mentions.remove("boxed");
    units[1].reach = Optional<HashSet<String>>.Empty;
    var owns = ["public\n_unnamed 1\ntwice 1", ""];
    var key = incremental.compilation_unit_key(units, 1, owns);
    owns[0] = "public\n_unnamed 2\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) == key);
    owns[0] = "public\n_unnamed 2\ntwice 2";
    expect_true(incremental.compilation_unit_key(units, 1, owns) != key);
    owns[0] = "other\n_unnamed 1\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) != key);
    # A method's line, when the reader names its struct: taken when it
    # names the method too, or may call it without naming it.
    units[1].mentions.insert("_Box");
    units[1].reach = Optional<HashSet<String>>.Empty;
    owns[0] = "public\n_Box\tlength 1\n_Box\t== 1\ntwice 1";
    key = incremental.compilation_unit_key(units, 1, owns);
    owns[0] = "public\n_Box\tlength 2\n_Box\t== 1\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) == key);
    owns[0] = "public\n_Box\tlength 2\n_Box\t== 2\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) != key);
    units[1].mentions.insert("length");
    units[1].reach = Optional<HashSet<String>>.Empty;
    key = incremental.compilation_unit_key(units, 1, owns);
    owns[0] = "public\n_Box\tlength 3\n_Box\t== 2\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) != key);
    # A field's line: taken only when the reader names the field.
    owns[0] = "public\n_Box\tlength 3\n_Box\t== 2\n_Box\t.y 1\ntwice 1";
    key = incremental.compilation_unit_key(units, 1, owns);
    owns[0] = "public\n_Box\tlength 3\n_Box\t== 2\n_Box\t.y 2\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) == key);
    units[1].mentions.insert("y");
    units[1].reach = Optional<HashSet<String>>.Empty;
    key = incremental.compilation_unit_key(units, 1, owns);
    owns[0] = "public\n_Box\tlength 3\n_Box\t== 2\n_Box\t.y 3\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) != key);
    units[1].mentions.remove("y");
    units[1].reach = Optional<HashSet<String>>.Empty;
    units[1].mentions.remove("_Box");
    units[1].reach = Optional<HashSet<String>>.Empty;
    key = incremental.compilation_unit_key(units, 1, owns);
    owns[0] = "public\n_Box\tlength 4\n_Box\t== 3\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) == key);
    units[1].mentions.remove("length");
    units[1].reach = Optional<HashSet<String>>.Empty;
    # The compiler's own code calls the runtime's functions by name.
    owns[0] = "public\n_unnamed 1\ntwice 1";
    units[0].name = "runtime";
    key = incremental.compilation_unit_key(units, 1, owns);
    owns[0] = "public\n_unnamed 2\ntwice 1";
    expect_true(incremental.compilation_unit_key(units, 1, owns) != key);
    expect_true(folder.path.is_dir());
}

# The link reads the objects from a response file, which keeps a path's
# spaces and backslashes (#887): on Windows a backslash is a separator, and
# a path with one overflowed the command line.
[Test]
links_objects_under_a_path_with_spaces_and_backslashes() {
    expect_true(driver.response_file([Path("a b\\c.o")]) == "\"a b\\\\c.o\"\n");
    var folder = TempFolder("spaced_link");
    var root = folder.path.join(Path("a b\\c"));
    Directory.create_all(root);
    File.write_text(root.join(Path("main.pep")), "main(): int {\n    return 0;\n}\n");
    _build_with(root, root, root.join(Path("cache d")));
}
