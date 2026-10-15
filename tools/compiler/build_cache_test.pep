# The build cache of the compiler in Pepper (`driver/cache.pep`): a
# module's files are one unit, a build keeps each unit's object, the next
# build reuses those whose inputs did not change (other units' files by
# their interfaces), and an unchanged program is not built again.

import compiler.driver;
import compiler.incremental;
import [Directory, File, Path] from io;
import compiler.link;
import os;
import process;
import [TempFolder] from testing;

# A program of two files and a module of two files, built with no runtime.
_write_program(root: Path) {
    Directory.create_all(root.join(Path("geo")));
    File.write_text(
        root.join(Path("main.pep")),
        "import \"a\";\nimport \"b\";\nimport geo;\nmain(): int {\n    return a_value() + b_value() + geo.area(2, 3) - 9;\n}\n"
    );
    File.write_text(root.join(Path("a.pep")), "export a_value(): int {\n    return 1;\n}\n");
    File.write_text(root.join(Path("b.pep")), "export b_value(): int {\n    return 2;\n}\n");
    File.write_text(
        root.join(Path("geo")).join(Path("module.pep")),
        "import \"math\";\nexport area(w: int, h: int): int {\n    return _times(w, h);\n}\n_unit(): int {\n    return 1;\n}\n"
    );
    # Seen by `module.pep` with no import, as a file of the same module.
    File.write_text(
        root.join(Path("geo")).join(Path("math.pep")), "_times(a: int, b: int): int {\n    return a * b;\n}\n"
    );
}

_load(root: Path): link.Program {
    var setup = link.Setup();
    setup.runtime = false;
    setup.import_dirs.append(root);
    var program = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    return program.value();
}

# Builds the program in `root` with the cache in it, and runs it.
_build(root: Path, debug: bool = false): driver.Built {
    var output = root.join(Path("main"));
    var options = driver.BuildOptions(output, root.join(Path("build")));
    options.debug = debug;
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
    options.in_process = true;
    var built = driver.build(_load(root), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    var ran = process.Command(output.to_string()).spawn();
    expect_true(ran.is_ok());
    expect_true(ran.value().wait().value().success());
    return built.value();
}

# The name of the unit holding the file whose name ends with `file`.
_unit_of(program: link.Program, file: String): String {
    for (var unit in link.translation_units(program)) {
        for (var i in unit.files) {
            if (program.files[i].name.ends_with(file)) {
                return unit.name;
            }
        }
    }
    return "";
}

[Test]
gives_each_file_a_unit_of_its_own() {
    var folder = TempFolder("units");
    _write_program(folder.path);
    var program = _load(folder.path);
    var geo = _unit_of(program, "module.pep");
    expect_false(geo.is_empty);
    expect_true(_unit_of(program, "math.pep") != geo);
    expect_true(_unit_of(program, "a.pep") != _unit_of(program, "b.pep"));
    expect_true(_unit_of(program, "a.pep") != geo);
}

[Test]
reuses_the_objects_of_unchanged_units() {
    var folder = TempFolder("build_cache");
    var root = folder.path;
    _write_program(root);
    var program = _load(root);
    var a = _unit_of(program, "a.pep");
    var b = _unit_of(program, "b.pep");
    var geo = _unit_of(program, "module.pep");

    var first = _build(root);
    expect_false(first.unchanged);
    expect_true(first.hits.is_empty);
    expect_true(first.misses.contains(a) and first.misses.contains(b) and first.misses.contains(geo));

    var again = _build(root);
    expect_true(again.unchanged);

    File.write_text(root.join(Path("b.pep")), "export b_value(): int {\n    return 1 + 1;\n}\n");
    var edited = _build(root);
    expect_false(edited.unchanged);
    expect_true(edited.misses.contains(b));
    expect_true(edited.hits.contains(a) and edited.hits.contains(geo));

    # A body edit to a file of the module: `module.pep`, which imports it,
    # keeps its object.
    var math = _unit_of(program, "math.pep");
    File.write_text(
        root.join(Path("geo")).join(Path("math.pep")), "_times(a: int, b: int): int {\n    return b * a;\n}\n"
    );
    var module = _build(root);
    expect_true(module.misses.contains(math));
    expect_true(module.hits.contains(geo) and module.hits.contains(a) and module.hits.contains(b));
}

[Test]
rebuilds_only_the_unit_whose_body_changed() {
    var folder = TempFolder("early_cutoff");
    var root = folder.path;
    _write_program(root);
    # Code of its own beside the entry point, so `main.pep`'s unit has an
    # object to reuse.
    File.write_text(
        root.join(Path("main.pep")),
        "import \"a\";\nimport \"b\";\nimport geo;\n_total(): int {\n    return a_value() + b_value() + geo.area(2, 3);\n}\nmain(): int {\n    return _total() - 9;\n}\n"
    );
    var program = _load(root);
    var main = _unit_of(program, "main.pep");
    var b = _unit_of(program, "b.pep");
    _build(root);

    # A body edit leaves `b.pep`'s interface alone: `main.pep`, which
    # imports it, is still a hit.
    File.write_text(root.join(Path("b.pep")), "export b_value(): int {\n    return 3 - 1;\n}\n");
    var body = _build(root);
    expect_true(body.misses.contains(b));
    expect_true(body.hits.contains(main));

    # A signature edit changes it: `main.pep` is checked and built again.
    File.write_text(root.join(Path("b.pep")), "export b_value(x: int = 2): int {\n    return x;\n}\n");
    var signature = _build(root);
    expect_true(signature.misses.contains(b) and signature.misses.contains(main));
}

# How many records the cache holds of the compilation unit named `unit`
# (after its first file): one for each key it was stored under.
_records_of(root: Path, unit: String): ulong {
    return _count_records(root.join(Path("cache")), "", unit.replace(":", "_").replace("#", "_"));
}

_count_records(dir: Path, name: String, folder: String): ulong {
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return 0;
    }
    ulong count = 0;
    for (var entry in listing.value().entries().value()) {
        if (entry.is_directory) {
            count += _count_records(entry.path, entry.name, folder);
        } else if (entry.name.ends_with(".rec") and folder.ends_with(name) and !name.is_empty) {
            count += 1;
        }
    }
    return count;
}

# A compilation unit is keyed on the compilation units it reads: an interface
# edit to `a.pep` keeps the record of `b.pep`'s compilation unit, which does not
# read it, and an edit to `b.pep` that of `a.pep`'s.
[Test]
keeps_the_compilation_units_an_edit_does_not_reach() {
    var folder = TempFolder("unit_keys");
    var root = folder.path;
    _write_program(root);
    var program = _load(root);
    var a = _unit_of(program, "a.pep");
    var b = _unit_of(program, "b.pep");
    _build(root);
    expect_true(_records_of(root, a) == 1 and _records_of(root, b) == 1);

    File.write_text(root.join(Path("a.pep")), "export a_value(x: int = 1): int {\n    return x;\n}\n");
    _build(root);
    expect_true(_records_of(root, a) == 2);
    expect_true(_records_of(root, b) == 1);

    File.write_text(root.join(Path("b.pep")), "export b_value(x: int = 2): int {\n    return x;\n}\n");
    _build(root);
    expect_true(_records_of(root, a) == 2);
    expect_true(_records_of(root, b) == 2);
}

# An edit to one file of a module rebuilds that file's object alone while
# its interface stays; an edit to its interface rebuilds the files that
# import it too.
[Test]
rebuilds_only_the_objects_an_edit_reaches() {
    var folder = TempFolder("file_objects");
    var root = folder.path;
    _write_program(root);
    var program = _load(root);
    var geo = _unit_of(program, "module.pep");
    var math = _unit_of(program, "math.pep");
    var first = _build(root);
    expect_true(first.misses.contains(geo) and first.misses.contains(math));

    File.write_text(
        root.join(Path("geo")).join(Path("math.pep")), "_times(a: int, b: int): int {\n    return b * a;\n}\n"
    );
    var edited = _build(root);
    expect_true(edited.misses.contains(math));
    expect_true(edited.hits.contains(geo));

    File.write_text(
        root.join(Path("geo")).join(Path("math.pep")),
        "_times(a: int, b: int, c: int = 1): int {\n    return b * a * c;\n}\n"
    );
    var changed = _build(root);
    expect_true(changed.misses.contains(math) and changed.misses.contains(geo));
}

# Writes a program whose `b.pep` calls `a.pep`'s `a_count`, which
# returns `a_body`.
_write_callee(root: Path, a_body: String) {
    File.write_text(
        root.join(Path("a.pep")),
        "export trait Measure {\n    measure(): int;\n}\nexport a_count(items: Measure[], extra: int = 0): int {\n    var total = extra;\n    for (var m in items) {\n        total += m.measure();\n    }\n    return total + "
            + a_body
            + ";\n}\n"
    );
    # `b.pep` implements `Measure`, so the confinement summary `a.pep`'s
    # compilation unit recorded for `a_count`, whose trait calls now reach
    # `_Three` too, is made again from its body: a call under a lock needs it.
    File.write_text(
        root.join(Path("b.pep")),
        "import async;\nimport \"a\";\n[Shared]\nstruct _Count {\n    const value: async.Atomic<long>;\n    construct() {\n        this.value = async.Atomic<long>(0);\n    }\n}\nstruct _Three {\n    var n: int;\n    construct() {\n        this.n = 3;\n    }\n}\nextend _Three with Measure {\n    measure(): int {\n        return n;\n    }\n}\nexport b_value(): int {\n    var counter = async.Mutex<_Count>(_Count());\n    var items = Array<Measure>();\n    items.append(_Three());\n    var n = 0;\n    with (var c = counter.lock()) {\n        n = a_count(items);\n    }\n    return n;\n}\n"
    );
    File.write_text(
        root.join(Path("main.pep")),
        "import \"a\";\nimport \"b\";\nmain(): int {\n    return b_value() - a_count(Array<Measure>(), 3);\n}\n"
    );
}

# A body a compilation unit decodes from a record below it is not a change of
# that compilation unit's: its record keeps no copy of the body, which an edit
# to the body below would leave stale (`PEPC_VERIFY_CUTOFF` finds the copy).
[Test]
keeps_no_copy_of_the_bodies_it_decodes() {
    var folder = TempFolder("decoded_bodies");
    var root = folder.path;
    _write_callee(root, "0");
    var build = () => {
        var setup = link.Setup();
        setup.import_dirs.append(root);
        setup.defer_bodies = true;
        var output = root.join(Path("main"));
        var options = driver.BuildOptions(output, root.join(Path("build")));
        options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
        options.in_process = true;
        options.verify_cutoff = true;
        var program = link.load_program(root.join(Path("main.pep")), setup);
        expect_true(program.is_ok());
        var built = driver.build(program.value(), options);
        if (built.is_err()) {
            print(built.error());
        }
        expect_true(built.is_ok());
        var ran = process.Command(output.to_string()).spawn();
        expect_true(ran.is_ok() and ran.value().wait().value().success());
    };
    build();
    _write_callee(root, "1 - 1");
    build();
}

# A summary a compilation unit settles for a function below it blames a
# place in that function counted from the function's start: an edit that
# only moves the function keeps the record, and the place it points at
# (`PEPC_VERIFY_CUTOFF` finds a stale one).
[Test]
keeps_a_settled_summary_right_when_its_function_moves() {
    var folder = TempFolder("moved_blame");
    var root = folder.path;
    var callee = "export trait Measure {\n    measure(): int;\n}\nexport a_first(items: Measure[], extra: int = 0): Measure {\n    var total = extra;\n    for (var m in items) {\n        total += m.measure();\n    }\n    return items[0];\n}\n";
    File.write_text(root.join(Path("a.pep")), callee);
    File.write_text(
        root.join(Path("b.pep")),
        "import async;\nimport \"a\";\n[Shared]\nstruct _Count {\n    const value: async.Atomic<long>;\n    construct() {\n        this.value = async.Atomic<long>(0);\n    }\n}\nstruct _Three {\n    var n: int;\n    construct() {\n        this.n = 3;\n    }\n}\nextend _Three with Measure {\n    measure(): int {\n        return n;\n    }\n}\nexport b_value(): int {\n    var counter = async.Mutex<_Count>(_Count());\n    var items = Array<Measure>();\n    items.append(_Three());\n    var n = 0;\n    with (var c = counter.lock()) {\n        n = a_first(items).measure();\n    }\n    return n;\n}\n"
    );
    File.write_text(
        root.join(Path("main.pep")), "import \"a\";\nimport \"b\";\nmain(): int {\n    return b_value() - 3;\n}\n"
    );
    var build = () => {
        var setup = link.Setup();
        setup.import_dirs.append(root);
        var output = root.join(Path("main"));
        var options = driver.BuildOptions(output, root.join(Path("build")));
        options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
        options.in_process = true;
        options.verify_cutoff = true;
        var program = link.load_program(root.join(Path("main.pep")), setup);
        expect_true(program.is_ok());
        var built = driver.build(program.value(), options);
        if (built.is_err()) {
            print(built.error());
        }
        expect_true(built.is_ok());
    };
    build();
    File.write_text(root.join(Path("a.pep")), "# moved\n" + callee);
    build();
}

[Test]
keeps_the_objects_another_build_stored_first() {
    var folder = TempFolder("store_twice");
    var root = folder.path;
    var cache = incremental.Cache(root.join(Path("cache")));
    var first = root.join(Path("first"));
    Directory.create_all(first);
    File.write_text(first.join(Path("0.o")), "first");
    var stored = cache.store(first, "unit", "key");
    expect_true(stored.is_ok());

    # A build that made the same key at the same time finds it stored: the
    # objects a build may be linking stay, and its own copy goes.
    var second = root.join(Path("second"));
    Directory.create_all(second);
    File.write_text(second.join(Path("0.o")), "second");
    var again = cache.store(second, "unit", "key");
    expect_true(again.is_ok());
    expect_equal(again.value().to_string(), stored.value().to_string());
    expect_equal(File.read_to_string(stored.value().join(Path("0.o"))).value(), "first");
    expect_false(second.metadata().is_ok());
}

# A key reused by a build counts as the unit's newest, and no key stored
# or reused lately is pruned, so a build linking it at the same time finds
# its objects.
[Test]
prunes_neither_reused_nor_recent_keys() {
    var folder = TempFolder("prune");
    var root = folder.path;
    var cache = incremental.Cache(root.join(Path("cache")));
    var hour: long = 3600000000000;
    var now = os.SystemTime.now().unix_nanoseconds();
    for (var i in 0..8) {
        var built = root.join(Path($"built{i}"));
        Directory.create_all(built);
        File.write_text(built.join(Path("0.o")), $"{i}");
        var stored = cache.store(built, "unit", $"key{i}");
        expect_true(stored.is_ok());
        # Stored hours ago, oldest first.
        stored.value().set_modified(now - (10 - (i as long)) * hour);
    }
    cache.used(cache.objects("unit", "key0"));

    var newest = root.join(Path("built8"));
    Directory.create_all(newest);
    File.write_text(newest.join(Path("0.o")), "8");
    expect_true(cache.store(newest, "unit", "key8").is_ok());
    expect_true(cache.objects("unit", "key0").exists());
    expect_false(cache.objects("unit", "key1").exists());
    expect_true(cache.objects("unit", "key2").exists());
    # The pruned key left by a rename, and nothing of it stays behind; a
    # build reusing it finds it gone, and compiles it.
    expect_false(cache.used(cache.objects("unit", "key1")));
    expect_equal(
        Directory.open(cache.objects("unit", "key0").parent().value()).value().entries().value().count, 8 as ulong
    );

    # Within the grace period nothing goes, however many keys there are.
    var recent = root.join(Path("built9"));
    Directory.create_all(recent);
    File.write_text(recent.join(Path("0.o")), "9");
    for (var i in 2..8) {
        cache.objects("unit", $"key{i}").set_modified(now - 60000000000);
    }
    expect_true(cache.store(recent, "unit", "key9").is_ok());
    for (var i in [0, 2, 3, 4, 5, 6, 7, 8, 9]) {
        expect_true(cache.objects("unit", $"key{i}").exists());
    }
}

# Pruning a unit's keys leaves the units named below it alone: unit
# `process` (`process.pep`) beside units `process/test/...` (the files of
# `process/test/`) once removed their folders whole, objects a build was
# about to link among them (#851).
[Test]
prunes_no_other_units_keys() {
    var folder = TempFolder("prune_nested");
    var root = folder.path;
    var cache = incremental.Cache(root.join(Path("cache")));
    var hours_ago = os.SystemTime.now().unix_nanoseconds() - 10 * 3600000000000;
    var below = root.join(Path("below"));
    Directory.create_all(below);
    File.write_text(below.join(Path("0.o")), "below");
    var kept = cache.store(below, "process/test/fork_test#0", "key");
    expect_true(kept.is_ok());
    for (var i in 0..9) {
        var built = root.join(Path($"built{i}"));
        Directory.create_all(built);
        File.write_text(built.join(Path("0.o")), $"{i}");
        var stored = cache.store(built, "process", $"key{i}");
        expect_true(stored.is_ok());
        # Oldest first, a second apart (NTFS keeps 100 ns), and the other
        # unit's folders older still.
        stored.value().set_modified(hours_ago + (i as long) * 1000000000);
        var up = kept.value();
        while (up.to_string() != cache.dir.to_string()) {
            up.set_modified(hours_ago - 1000000000);
            up = up.parent().value();
        }
    }
    var newest = root.join(Path("newest"));
    Directory.create_all(newest);
    File.write_text(newest.join(Path("0.o")), "newest");
    expect_true(cache.store(newest, "process", "key9").is_ok());
    expect_false(cache.objects("process", "key0").exists());
    expect_true(kept.value().join(Path("0.o")).is_file());
}

# A build with debug info whose every unit is a hit still defines `main`,
# which only the entry part, compiled every build, holds (#827); and the
# hits' parts count as just reused, so a build storing newer keys of them
# does not prune them while this one links them.
[Test]
builds_with_debug_info_from_every_unit_in_the_cache() {
    var folder = TempFolder("debug_hits");
    var root = folder.path;
    _write_program(root);
    # Code of its own beside `main`, so `main.pep`'s unit has an object
    # to reuse.
    File.write_text(
        root.join(Path("main.pep")),
        "import \"a\";\nimport \"b\";\nimport geo;\n_total(): int {\n    return a_value() + b_value() + geo.area(2, 3);\n}\nmain(): int {\n    return _total() - 9;\n}\n"
    );
    var first = _build(root, true);
    expect_true(first.hits.is_empty);

    var parts = Array<Path>();
    var units = root.join(Path("cache")).join(Path("v2")).join(Path("units"));
    var hours_ago = os.SystemTime.now().unix_nanoseconds() - 10 * 3600000000000;
    for (var entry in Directory.open(units).value().entries().value()) {
        if (!entry.name.contains("#")) {
            continue;
        }
        for (var key in Directory.open(units.join(Path(entry.name))).value().entries().value()) {
            var part = units.join(Path(entry.name)).join(Path(key.name));
            part.set_modified(hours_ago);
            parts.append(part);
        }
    }
    expect_false(parts.is_empty);

    # The output gone, so the program is built again, all from the cache.
    File.remove(root.join(Path("main")));
    var again = _build(root, true);
    expect_false(again.unchanged);
    expect_true(again.misses.is_empty);
    expect_false(again.hits.is_empty);
    for (var part in parts) {
        expect_true(part.metadata().value().modified > hours_ago);
    }
}

[Test]
builds_without_a_cache() {
    var folder = TempFolder("no_cache");
    var root = folder.path;
    _write_program(root);
    var output = root.join(Path("main"));
    var options = driver.BuildOptions(output, root.join(Path("build")));
    options.in_process = true;
    var built = driver.build(_load(root), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    expect_false(built.value().unchanged);
    expect_true(built.value().hits.is_empty and built.value().misses.is_empty);
    expect_false(root.join(Path("cache")).exists());
    var ran = process.Command(output.to_string()).spawn();
    expect_true(ran.is_ok() and ran.value().wait().value().success());
}

# Each part names a string literal's object by its text: an object kept in
# the cache still finds its own literals after an edit adds literals to
# another unit.
[Test]
keeps_string_literals_apart_across_units() {
    var folder = TempFolder("cached_strings");
    var root = folder.path;
    File.write_text(root.join(Path("a.pep")), "export a_text(): String {\n    return \"alpha\" + \"beta\";\n}\n");
    File.write_text(
        root.join(Path("main.pep")), "import \"a\";\nmain(): int {\n    return a_text() == \"alphabeta\" ? 0 : 1;\n}\n"
    );
    var setup = link.Setup();
    setup.import_dirs.append(root);
    var build = () => {
        var output = root.join(Path("main"));
        var options = driver.BuildOptions(output, root.join(Path("build")));
        options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
        options.in_process = true;
        var program = link.load_program(root.join(Path("main.pep")), setup);
        expect_true(program.is_ok());
        var built = driver.build(program.value(), options);
        if (built.is_err()) {
            print(built.error());
        }
        expect_true(built.is_ok());
        var ran = process.Command(output.to_string()).spawn();
        expect_true(ran.is_ok() and ran.value().wait().value().success());
    };
    build();
    File.write_text(
        root.join(Path("main.pep")),
        "import \"a\";\nmain(): int {\n    var first = \"one\" + \"two\" + \"three\";\n    return a_text() == \"alphabeta\" and first == \"onetwothree\" ? 0 : 1;\n}\n"
    );
    build();
}

# Writes a program whose `a.pep` returns `a_body`, and whose `main.pep`
# differs with `version`.
_write_deferred(root: Path, a_body: String, version: int) {
    File.write_text(
        root.join(Path("b.pep")),
        "[Deprecated(\"use b_new\")]\nexport b_old(): int {\n    return 2;\n}\nexport b_new(): int {\n    return 2;\n}\n"
    );
    File.write_text(
        root.join(Path("a.pep")), "import \"b\";\nexport a_value(): int {\n    return " + a_body + ";\n}\n"
    );
    File.write_text(
        root.join(Path("main.pep")),
        "import \"a\";\nmain(): int {\n    return a_value() - 2 + " + $"{version} - {version}" + ";\n}\n"
    );
}

# Builds the program in `root`, its bodies linked as needed, runs it, and
# returns whether the build linked `a.pep`'s bodies.
_build_deferred(root: Path): bool {
    var setup = link.Setup();
    setup.import_dirs.append(root);
    setup.defer_bodies = true;
    var output = root.join(Path("main"));
    var options = driver.BuildOptions(output, root.join(Path("build")));
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
    options.in_process = true;
    var program = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    var built = driver.build(program.value(), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    var ran = process.Command(output.to_string()).spawn();
    expect_true(ran.is_ok() and ran.value().wait().value().success());
    for (var i in 0..program.value().files.count) {
        if (program.value().files[i].name.ends_with("a.pep")) {
            return program.value().has_bodies(i);
        }
    }
    return true;
}

# A build loaded with `defer_bodies` links and checks the bodies of the files it
# checks, not those of the compilation units it loads from the cache, even when
# a file of the compilation unit warned: its record keeps the warnings, which a
# build that loads it prints again.
[Test]
links_only_the_bodies_of_the_compilation_units_it_checks() {
    var folder = TempFolder("deferred_bodies");
    var root = folder.path;
    _write_deferred(root, "b_new()", 1);
    expect_true(_build_deferred(root));
    _write_deferred(root, "b_new()", 2);
    expect_false(_build_deferred(root));
    # `a.pep` warns: its compilation unit's record keeps the warning, which the
    # next build prints again without checking the compilation unit.
    _write_deferred(root, "b_old()", 3);
    expect_true(_build_deferred(root));
    _write_deferred(root, "b_old()", 4);
    expect_false(_build_deferred(root));
}

# Writes a program whose `a.pep` starts with `top`, whose `a_value`
# returns `value` of its argument, through a closure, and whose
# `_Counter.next` returns `next`.
_write_rechecked(root: Path, top: String, value: String, next: String = "n + 1") {
    File.write_text(
        root.join(Path("a.pep")),
        top
            + "export a_value(n: int): int {\n    var add = (x: int) => "
            + value
            + ";\n    return add(n);\n}\nexport a_fail(n: int): int {\n    if (n > 0) {\n        panic(\"stop\");\n    }\n    return n;\n}\n"
            + "struct _Counter {\n    var n: int;\n    construct(n: int) {\n        this.n = n;\n    }\n    next(): int {\n        return "
            + next
            + ";\n    }\n}\nexport a_count(): int {\n    return _Counter(0).next();\n}\n"
    );
    File.write_text(
        root.join(Path("main.pep")),
        "import \"a\";\nmain(args: String[]): int {\n    if (args.count > 1) {\n        return a_fail(1);\n    }\n    return a_value(0) == 1 and a_count() == 1 ? 0 : 1;\n}\n"
    );
}

# Builds the program in `root`, runs it, and returns the build and what the
# program, failing on purpose, writes on standard error.
_build_rechecked(root: Path): (driver.Built, String) {
    var setup = link.Setup();
    setup.import_dirs.append(root);
    var output = root.join(Path("main"));
    var options = driver.BuildOptions(output, root.join(Path("build")));
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
    options.in_process = true;
    var program = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    var built = driver.build(program.value(), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    var ran = process.Command(output.to_string()).run();
    expect_true(ran.is_ok() and ran.value().status.success());
    var failed = process.Command(output.to_string()).argument("fail").run();
    expect_true(failed.is_ok() and !failed.value().status.success());
    return (built.value(), failed.value().stderr);
}

# An edit of only bodies (or comments) checks again just the bodies changed,
# from the compilation unit's record before the edit, with its locations
# moved to where they are now; any other edit checks the compilation unit
# from its files.
[Test]
checks_again_only_the_bodies_an_edit_changed() {
    var folder = TempFolder("rechecked");
    var root = folder.path;
    _write_rechecked(root, "", "x + 1");
    var (first, _) = _build_rechecked(root);
    expect_true(first.rechecked.is_empty);

    # The closure's body changed.
    _write_rechecked(root, "", "x * 2 + 1");
    var program = _load(root);
    var a = _unit_of(program, "a.pep");
    var (body, failed) = _build_rechecked(root);
    expect_true(body.rechecked.count == 1 and body.rechecked.contains(a));
    expect_true(failed.contains("a.pep:7"));

    # A comment moves `a_fail`'s `panic` a line down.
    _write_rechecked(root, "# A comment.\n", "x * 2 + 1");
    var (comment, moved) = _build_rechecked(root);
    expect_true(comment.rechecked.contains(a));
    expect_true(moved.contains("a.pep:8"));

    # A method's body changed: its struct stays checked.
    _write_rechecked(root, "# A comment.\n", "x * 2 + 1", "1 + n");
    var (method, _) = _build_rechecked(root);
    expect_true(method.rechecked.contains(a));

    # A new function is checked with the rest from the files.
    _write_rechecked(root, "_unused(): int {\n    return 0;\n}\n", "x * 2 + 1");
    var (declared, _) = _build_rechecked(root);
    expect_true(declared.misses.contains(a));
    expect_true(declared.rechecked.is_empty);
}

# Writes a program whose `a.pep` starts with `top` and declares struct
# `Thing` with `methods` before `size`, and whose `b.pep` calls `Thing.size` and a generic method, which
# its record adds a specialization of to `Thing`.
_write_methods(root: Path, methods: String, top: String = "") {
    File.write_text(
        root.join(Path("a.pep")),
        top
            + "export struct Thing {\n    var n: int;\n    construct(n: int) {\n        this.n = n;\n    }\n    pick<T>(x: T): T {\n        return x;\n    }\n"
            + methods
            + "    size(): int {\n        return n;\n    }\n}\n"
    );
    File.write_text(
        root.join(Path("b.pep")),
        "import \"a\";\nexport b_value(): int {\n    var t = Thing(2);\n    return t.size() + 1 + t.pick<int>(1);\n}\n"
    );
    File.write_text(root.join(Path("main.pep")), "import \"b\";\nmain(): int {\n    return b_value() - 4;\n}\n");
}

# Builds the program in `root`, checking every record early cutoff loads
# again, and runs it.
_build_methods(root: Path) {
    var setup = link.Setup();
    setup.import_dirs.append(root);
    var output = root.join(Path("main"));
    var options = driver.BuildOptions(output, root.join(Path("build")));
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
    options.in_process = true;
    options.verify_cutoff = true;
    var program = link.load_program(root.join(Path("main.pep")), setup);
    expect_true(program.is_ok());
    var built = driver.build(program.value(), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    var ran = process.Command(output.to_string()).run();
    expect_true(ran.is_ok() and ran.value().status.success());
}

# Adding or changing a method a reader does not call keeps the reader's
# record, even one that adds to the struct; changing one it calls does not.
[Test]
keeps_the_readers_of_a_struct_a_method_edit_does_not_reach() {
    var folder = TempFolder("method_keys");
    var root = folder.path;
    _write_methods(root, "");
    _build_methods(root);
    var program = _load(root);
    var b = _unit_of(program, "b.pep");
    expect_true(_records_of(root, b) == 1);
    _write_methods(root, "    thing_doubled(): int {\n        return n * 2;\n    }\n");
    _build_methods(root);
    expect_true(_records_of(root, b) == 1);
    _write_methods(root, "    thing_doubled(): long {\n        return n as long;\n    }\n");
    _build_methods(root);
    expect_true(_records_of(root, b) == 1);
    _write_methods(
        root,
        "    thing_doubled(): long {\n        return n as long;\n    }\n    size(x: int): int {\n        return x;\n    }\n"
    );
    _build_methods(root);
    expect_true(_records_of(root, b) == 2);
}

# An edit that moves what a reader's record copies from a file, and keeps
# the reader's key, leaves the copies where the code is now: `b.pep`'s
# specialization of `Thing.pick` (`PEPC_VERIFY_CUTOFF` finds a stale one).
[Test]
keeps_the_places_of_what_a_reader_copies_when_an_edit_moves_them() {
    var folder = TempFolder("moved_copies");
    var root = folder.path;
    _write_methods(root, "");
    _build_methods(root);
    var program = _load(root);
    var b = _unit_of(program, "b.pep");
    _write_methods(root, "", "export unrelated_thing(): int {\n    return 3;\n}\n");
    _build_methods(root);
    expect_true(_records_of(root, b) == 1);
}
