# The build cache of the compiler in Pepper (`driver/cache.pep`): a
# module's files are one unit, a build keeps each unit's object, the next
# build reuses those whose inputs did not change (other units' files by
# their interfaces), and an unchanged program is not built again.

import compiler.driver;
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
_build(root: Path): driver.Built {
    var output = root.join(Path("main"));
    var options = driver.BuildOptions(output, root.join(Path("build")));
    options.cache = Optional<driver.Cache>.Value(driver.Cache(root.join(Path("cache"))));
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
    for (var unit in link.units(program)) {
        for (var i in unit.files) {
            if (program.files[i].name.ends_with(file)) {
                return unit.name;
            }
        }
    }
    return "";
}

[Test]
puts_a_modules_files_in_one_unit() {
    var folder = TempFolder("units");
    _write_program(folder.path);
    var program = _load(folder.path);
    var geo = _unit_of(program, "module.pep");
    expect_false(geo.is_empty);
    expect_equal(_unit_of(program, "math.pep"), geo);
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

    # An edit to a file the module's other files see without an import.
    File.write_text(
        root.join(Path("geo")).join(Path("math.pep")), "_times(a: int, b: int): int {\n    return b * a;\n}\n"
    );
    var module = _build(root);
    expect_true(module.misses.contains(geo));
    expect_true(module.hits.contains(a) and module.hits.contains(b));
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

[Test]
keeps_the_objects_another_build_stored_first() {
    var folder = TempFolder("store_twice");
    var root = folder.path;
    var cache = driver.Cache(root.join(Path("cache")));
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
    var cache = driver.Cache(root.join(Path("cache")));
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
        options.cache = Optional<driver.Cache>.Value(driver.Cache(root.join(Path("cache"))));
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
