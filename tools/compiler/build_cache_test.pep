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
    return _count_records(root.join(Path("cache")), "", unit.replace("/", ".").replace(":", "_"));
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
        return built.value();
    };
    var first = build();
    expect_true(first.hits.is_empty);
    _write_callee(root, "1 - 1");
    # Only `a.pep`'s unit changed: the others' objects are reused.
    var second = build();
    expect_false(second.hits.is_empty);
    expect_false(second.misses.is_empty);
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
        var ran = process.Command(output.to_string()).spawn();
        expect_true(ran.is_ok() and ran.value().wait().value().success());
        return built.value();
    };
    var first = build();
    expect_true(first.hits.is_empty);
    File.write_text(root.join(Path("a.pep")), "# moved\n" + callee);
    # Only `a.pep` moved: the others' objects are reused.
    var second = build();
    expect_false(second.hits.is_empty);
    expect_false(second.misses.is_empty);
}

[Test]
moves_objects_by_copying_where_a_rename_cannot() {
    var folder = TempFolder("store_across_drives");
    var root = folder.path;
    var built = root.join(Path("built"));
    Directory.create_all(built.join(Path("nested")));
    File.write_text(built.join(Path("0.o")), "object");
    File.write_text(built.join(Path("nested")).join(Path("1.o")), "nested");
    var target = root.join(Path("cache")).join(Path("key"));
    Directory.create_all(target.parent().value());

    expect_true(incremental._move_across_drives(built, target).is_ok());
    expect_equal(File.read_to_string(target.join(Path("0.o"))).value(), "object");
    expect_equal(File.read_to_string(target.join(Path("nested")).join(Path("1.o"))).value(), "nested");
    expect_false(built.metadata().is_ok());
    # Only the key's folder is left beside it: no staging copy.
    expect_equal(Directory.open(target.parent().value()).value().entries().value().count, 1 as ulong);

    # Another build's copy of the key in place first stays, and so does
    # `built`, for `store` to drop (#227).
    Directory.create_all(built);
    File.write_text(built.join(Path("0.o")), "second");
    expect_false(incremental._move_across_drives(built, target).is_ok());
    expect_equal(File.read_to_string(target.join(Path("0.o"))).value(), "object");
    expect_true(built.metadata().is_ok());
    expect_equal(Directory.open(target.parent().value()).value().entries().value().count, 1 as ulong);
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

# A folder of a compilation unit's objects, as a build compiled them.
_unit_built(root: Path, name: String): Path {
    var built = root.join(Path(name));
    Directory.create_all(built);
    File.write_text(built.join(Path("0.o")), name);
    return built;
}

# Builds sharing one cache that compile one compilation unit under one key
# on objects below that differ each store it, whichever stores first, even
# at the same moment: all a build that stores second sees is the key's
# folder there, so this stores one after another (pep-lang/pepper#152).
[Test]
stores_a_unit_another_build_stored_first_on_other_objects_below() {
    var folder = TempFolder("store_unit_twice");
    var root = folder.path;
    var cache = incremental.Cache(root.join(Path("cache")));
    var below_f = [incremental.Defines("f\n")];
    var below_g = [incremental.Defines("g\n")];
    var first = cache.store_unit(_unit_built(root, "first"), "+unit", "key", "f\n", below_f, "0.o");
    expect_equal(first.value(), "key");

    # Needing `g`, which the first's objects below lack: its own objects go
    # under the other key, and the first's stay.
    var second = cache.store_unit(_unit_built(root, "second"), "+unit", "key", "g\n", below_g, "0.o");
    expect_true(second.is_ok());
    expect_true(second.value() != "key");
    expect_equal(File.read_to_string(cache.objects("+unit", second.value()).join(Path("0.o"))).value(), "second");
    expect_equal(File.read_to_string(cache.objects("+unit", "key").join(Path("0.o"))).value(), "first");

    # On objects below the first's link with, it links those, and so with
    # the second's; its own go.
    var both = [incremental.Defines("f\ng\n")];
    var third = _unit_built(root, "third");
    expect_equal(cache.store_unit(third, "+unit", "key", "f\n", both, "0.o").value(), "key");
    expect_false(third.metadata().is_ok());
    var fourth = _unit_built(root, "fourth");
    expect_equal(cache.store_unit(fourth, "+unit", "key", "g\n", below_g, "0.o").value(), second.value());
    expect_false(fourth.metadata().is_ok());
}

# A build links the objects of a compilation unit it found in the cache
# from there, and never links without them: a key's folder gone by then
# (another build pruning the unit moves it aside, and back when it was
# reused meanwhile) is an error, not a link short of the unit's symbols
# (pep-lang/pepper#24).
[Test]
links_a_reused_units_objects_or_fails() {
    var folder = TempFolder("reused_objects");
    var root = folder.path;
    var cache = incremental.Cache(root.join(Path("cache")));
    var built = root.join(Path("built"));
    Directory.create_all(built);
    File.write_text(built.join(Path("0.o")), "part 0");
    File.write_text(built.join(Path("1.o")), "part 1");
    expect_true(cache.store(built, "+unit", "key").is_ok());

    var found = cache.reused_objects("+unit", "key", "o");
    expect_true(found.is_ok());
    expect_equal(found.value().count, 2 as ulong);
    expect_equal(found.value()[1].file_name().value(), "1.o");

    var gone = cache.reused_objects("+unit", "other", "o");
    expect_true(gone.is_err());
    expect_true(gone.error().starts_with("the build cache no longer holds the objects of '+unit'"));
}

# A key a build decided to reuse that a build pruning its unit has moved
# aside, to move it back since it was reused (`_prune`), is found once it
# is back, not taken for gone (pep-lang/pepper#172): the look that misses
# it here puts it back, as the prune would between two looks.
[Test]
finds_a_reused_key_a_prune_moves_aside_and_back() {
    var folder = TempFolder("look_again");
    var root = folder.path;
    var cache = incremental.Cache(root.join(Path("cache")));
    var below = [incremental.Defines("f\n")];
    expect_equal(cache.store_unit(_unit_built(root, "built"), "+unit", "key", "f\n", below, "0.o").value(), "key");
    var kept = cache.objects("+unit", "key");
    var aside = kept.parent().value().join(Path(".removing.1.0"));
    expect_true(File.rename(kept, aside).is_ok());

    var looks = Array<int>();
    var found = cache.look_again(() => {
        looks.append(0);
        var key = cache.unit_objects("+unit", "key", below, "0.o");
        if (!key.is_value()) {
            File.rename(aside, kept);
        }
        return key;
    });
    expect_equal(found.value(), "key");
    expect_equal(looks.count, 2 as ulong);
    expect_equal(cache.reused_objects("+unit", "key", "o").value().count, 1 as ulong);

    # A key gone for good is not found, after about a second of looks.
    expect_false(cache.look_again(() => cache.unit_objects("+unit", "other", below, "0.o")).is_value());
}

# The objects a build links are hard links to the cache's, so a build
# pruning the unit that moves the key's folder aside and removes it after
# this build's last look (`_prune`) leaves the link its objects
# (pep-lang/pepper#178). Objects outside the cache are linked as they are.
[Test]
pins_a_reused_keys_objects_for_the_link() {
    var folder = TempFolder("pin");
    var root = folder.path;
    var cache = incremental.Cache(root.join(Path("cache")));
    var below = [incremental.Defines("f\n")];
    expect_equal(cache.store_unit(_unit_built(root, "built"), "+unit", "key", "f\n", below, "0.o").value(), "key");
    var kept = cache.reused_objects("+unit", "key", "o").value();
    var own = root.join(Path("own.o"));
    File.write_text(own, "own");
    var objects = kept.copy();
    objects.append(own);
    var pinned = cache.pin(objects, root.join(Path("pinned"))).value();
    expect_equal(pinned.count, objects.count);
    expect_equal(pinned[pinned.count - 1].to_string(), own.to_string());

    var key = cache.objects("+unit", "key");
    var aside = key.parent().value().join(Path(".removing.1.0"));
    expect_true(File.rename(key, aside).is_ok());
    expect_true(Directory.remove_all(aside).is_ok());
    for (var i in 0..kept.count) {
        expect_false(kept[i].is_file());
        expect_true(pinned[i].is_file());
    }

    # An object gone for good fails the build, after about a second of looks.
    expect_true(cache.pin(kept, root.join(Path("again"))).is_err());
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
# about to link among them.
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

# The most characters a path in the cache adds to the cache's own.
const _LONGEST_CACHE_PATH: ulong = 72;

# Every path in `dir`, folders and files.
_paths_in(dir: Path, out: Path[]) {
    for (var entry in Directory.open(dir).value().entries().value()) {
        out.append(entry.path);
        if (entry.is_directory) {
            _paths_in(entry.path, out);
        }
    }
}

# No path in the cache adds more than `_LONGEST_CACHE_PATH` characters to
# the cache's folder, however long a unit's name: the cache sits in
# the project's folder, and Windows tools fail on a path over 260
# characters.
[Test]
keeps_every_path_in_the_cache_short() {
    var folder = TempFolder("short_paths");
    var root = folder.path;
    _write_program(root);
    _build(root);
    var cache = incremental.Cache(root.join(Path("cache")));
    var paths = Array<Path>();
    _paths_in(root.join(Path("cache")), paths);
    expect_false(paths.is_empty);
    # The longest each kind of path can be: a long name, a whole key, and
    # the longest file beside a key's objects or a record.
    var name = "a_package/with_a_namespace/as_long_as/any_project_has";
    var key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    paths.append(cache.part($"+{name}", 999, key).join(Path("interfaces")));
    paths.append(cache.objects(name, key).parent().value().join(Path($".removing.{process.id()}.999")));
    var unit = incremental.CompilationUnit(name);
    unit.key = key;
    paths.append(Path($"{incremental.record_path(cache, unit)}.fields.{process.id()}"));
    var base = root.join(Path("cache")).to_string().size;
    for (var path in paths) {
        if (path.to_string().size - base > _LONGEST_CACHE_PATH) {
            print($"too long: {path}");
        }
        expect_true(path.to_string().size - base <= _LONGEST_CACHE_PATH);
    }
    # Two long names that start alike keep folders of their own.
    var first = cache.objects($"{name}/one", key).to_string();
    expect_true(first != cache.objects($"{name}/two", key).to_string());
}

# A build with debug info whose every unit is a hit still defines `main`,
# which only the entry part, compiled every build, holds; and the
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
    var units = incremental.Cache(root.join(Path("cache"))).dir.join(Path("u"));
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
    var first = _build_with_runtime(root, "main.pep");
    expect_true(first.hits.is_empty);
    File.write_text(
        root.join(Path("main.pep")),
        "import \"a\";\nmain(): int {\n    var first = \"one\" + \"two\" + \"three\";\n    return a_text() == \"alphabeta\" and first == \"onetwothree\" ? 0 : 1;\n}\n"
    );
    # `a.pep`'s object comes from the cache, with its own literals.
    var second = _build_with_runtime(root, "main.pep");
    expect_false(second.hits.is_empty);
}

# Builds the program whose entry is `entry` in `root`, with the runtime and
# the cache in `root`, and runs it.
_build_with_runtime(root: Path, entry: String): driver.Built {
    var setup = link.Setup();
    setup.import_dirs.append(root);
    var output = root.join(Path("main"));
    var options = driver.BuildOptions(output, root.join(Path("build")));
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
    options.in_process = true;
    var program = link.load_program(root.join(Path(entry)), setup);
    expect_true(program.is_ok());
    var built = driver.build(program.value(), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    var ran = process.Command(output.to_string()).spawn();
    expect_true(ran.is_ok() and ran.value().wait().value().success());
    return built.value();
}

# Writes `source.pep`, whose structs hold a `Source` trait value and whose
# `call` releases a `() => int`; `archive.pep`, a conformer of `Source` that
# holds one, in a file `source.pep` does not see, as `archive.TarReader` is
# to `compress.DecompressReader`; `chain.pep`, a closure chain; and three
# programs: `with.pep` and `with_too.pep`, which make `Archive` and the
# chain's closures part of `source.pep`'s cycles, and `without.pep`, which
# has neither.
_write_steering(root: Path) {
    File.write_text(
        root.join(Path("source.pep")),
        "export trait Source {\n    next(): int;\n}\n"
            + "export struct Wrap {\n    var inner: Source;\n"
            + "    construct(inner: Source) {\n        this.inner = inner;\n    }\n}\n"
            + "extend Wrap with Source {\n    next(): int {\n        return inner.next() + 1;\n    }\n}\n"
            + "export struct Zero {\n    construct() {}\n}\n"
            + "extend Zero with Source {\n    next(): int {\n        return 0;\n    }\n}\n"
            + "export wrap_twice(): int {\n    Source s = Wrap(Wrap(Zero()));\n    return s.next();\n}\n"
            + "export call(f: () => int): int {\n    return f();\n}\n"
    );
    File.write_text(
        root.join(Path("archive.pep")),
        "import \"source\";\nexport struct Archive {\n    var source: Source;\n    var buffer: int[] = Array<int>();\n"
            + "    construct(source: Source) {\n        this.source = source;\n    }\n}\n"
            + "extend Archive with Source {\n    next(): int {\n        buffer.append(1);\n"
            + "        return source.next();\n    }\n}\n"
    );
    # Closures capturing the one before, so `() => int` is in a cycle.
    File.write_text(
        root.join(Path("chain.pep")),
        "import \"source\";\nexport chain(): int {\n"
            + "    var f: () => int = () => 1;\n    for (var i in 0..3) {\n        var g = f;\n        f = () => g() + 1;\n    }\n"
            + "    return call(f);\n}\n"
    );
    var imports = "import \"archive\";\nimport \"chain\";\nimport \"source\";\n";
    File.write_text(
        root.join(Path("with.pep")),
        imports
            + "main(): int {\n    Source s = Archive(Wrap(Archive(Zero())));\n"
            + "    return s.next() + chain() + wrap_twice() - 7;\n}\n"
    );
    File.write_text(
        root.join(Path("with_too.pep")),
        imports
            + "main(): int {\n    Source s = Archive(Zero());\n    return s.next() + chain() + wrap_twice() - 6;\n}\n"
    );
    File.write_text(
        root.join(Path("without.pep")),
        "import \"source\";\nmain(): int {\n    return wrap_twice() + call(() => 1) - 3;\n}\n"
    );
}

# The name of the unit of `source.pep` in the program `entry` in `root`.
_source_unit(root: Path, entry: String): String {
    var setup = link.Setup();
    setup.import_dirs.append(root);
    var program = link.load_program(root.join(Path(entry)), setup);
    expect_true(program.is_ok());
    return _unit_of(program.value(), "source.pep");
}

# A file's last releases steer into the conformers of a trait it holds and
# the closures of a function type it releases, which are the program's, so
# the cache keeps its object apart for each set of those it steers into
# (`Keys.steering`): a program without them never links an object that
# names them, a program with more compiles the file again, and each
# program gets its own back (#170).
[Test]
links_an_object_built_in_a_program_with_more_conformers() {
    var folder = TempFolder("steering");
    var root = folder.path;
    _write_steering(root);
    var source = _source_unit(root, "with.pep");
    _build_with_runtime(root, "with.pep");
    var without = _build_with_runtime(root, "without.pep");
    expect_true(without.misses.contains(source));
    var back = _build_with_runtime(root, "with.pep");
    expect_true(back.hits.contains(source));

    # Built first without them, the object steers into fewer than a program
    # with them gives: that program compiles the file again.
    var other = TempFolder("steering_fewer");
    _write_steering(other.path);
    _build_with_runtime(other.path, "without.pep");
    var more = _build_with_runtime(other.path, "with.pep");
    expect_true(more.misses.contains(source));
}

# A program whose cycles steer a file into the same structs as the program
# that stored its object reuses that object.
[Test]
reuses_an_object_built_in_a_program_with_the_same_conformers() {
    var folder = TempFolder("steering_same");
    var root = folder.path;
    _write_steering(root);
    _build_with_runtime(root, "with.pep");
    var again = _build_with_runtime(root, "with_too.pep");
    expect_true(again.hits.contains(_source_unit(root, "with_too.pep")));
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
    panic("a.pep is not among the program's files");
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
# returns `value` of its argument, through a closure, followed by
# `functions`, whose `_Counter.next` returns `next`, followed by `methods`,
# and whose `a_count` returns `count`, followed by `bottom`.
_write_rechecked(
    root: Path,
    top: String,
    value: String,
    next: String = "n + 1",
    methods: String = "",
    count: String = "_Counter(0).next()",
    functions: String = "",
    bottom: String = ""
) {
    File.write_text(
        root.join(Path("a.pep")),
        top
            + "export a_value(n: int): int {\n    var add = (x: int) => "
            + value
            + ";\n    return add(n);\n}\n"
            + functions
            + "export a_fail(n: int): int {\n    if (n > 0) {\n        panic(\"stop\");\n    }\n    return n;\n}\n"
            + "struct _Counter {\n    var n: int;\n    construct(n: int) {\n        this.n = n;\n    }\n    next(): int {\n        return "
            + next
            + ";\n    }\n"
            + methods
            + "}\nexport a_count(): int {\n    return "
            + count
            + ";\n}\n"
            + bottom
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

# A method body checked again is filtered for the target like the rest: a
# block for another platform, which names nothing that exists, goes before
# the passes check the body, though its struct was checked before.
[Test]
filters_the_platform_blocks_of_a_body_checked_again() {
    var folder = TempFolder("rechecked-platform");
    var root = folder.path;
    var shifted = (
        sum: String
    ) => "    shifted(): int {\n        [Target(OS(Wasi))] {\n            return nope;\n        }\n        return "
        + sum
        + ";\n    }\n";
    var count = "_Counter(0).next() + _Counter(0).shifted()";
    _write_rechecked(root, "", "x + 1", "n + 1", shifted("n + 0"), count);
    _build_rechecked(root);
    var a = _unit_of(_load(root), "a.pep");
    _write_rechecked(root, "", "x + 1", "n + 1", shifted("0 + n"), count);
    var (method, _) = _build_rechecked(root);
    expect_true(method.rechecked.contains(a));
}

# An edit that adds a struct, a function or a method no code named before checks
# again only it and the bodies that changed; one named before checks the
# compilation unit from its files.
[Test]
checks_again_only_the_declarations_an_edit_adds() {
    var folder = TempFolder("added");
    var root = folder.path;
    _write_rechecked(root, "", "x + 1");
    _build_rechecked(root);
    var a = _unit_of(_load(root), "a.pep");

    # A method, which a changed body calls.
    var twice = "    twice(): int {\n        return n * 2;\n    }\n";
    _write_rechecked(root, "", "x + 1", "n + 1", twice, "_Counter(0).next() + _Counter(0).twice()");
    var (method, _) = _build_rechecked(root);
    expect_true(method.rechecked.contains(a));

    # A function after another, whose `panic` moves two lines down.
    var zero = "_zero(): int {\n    return 0;\n}\n";
    _write_rechecked(root, "", "x + 1 + _zero()", "n + 1", twice, "_Counter(0).next() + _Counter(0).twice()", zero);
    var (function, failed) = _build_rechecked(root);
    expect_true(function.rechecked.contains(a));
    expect_true(failed.contains("a.pep:10"));

    # A struct after another, which a changed body uses.
    var pair = "struct _Pair {\n    var x: int;\n}\n";
    _write_rechecked(
        root, "", "x + 1 + _zero()", "n + 1", twice, "_Counter(0).next() + _Counter(0).twice() + _Pair().x", zero, pair
    );
    var (structure, _) = _build_rechecked(root);
    expect_true(structure.rechecked.contains(a));

    # A field, which a changed body reads: its struct is checked again whole.
    var extra = "    var extra: int = 1;\n";
    _write_rechecked(
        root,
        "",
        "x + 1 + _zero()",
        "n + 1",
        twice + extra,
        "_Counter(0).next() + _Counter(0).twice() + _Counter(0).extra - 1 + _Pair().x",
        zero,
        pair
    );
    var (field, _) = _build_rechecked(root);
    expect_true(field.rechecked.contains(a));

    # A method named as the closure's variable was.
    var add = "    add(): int {\n        return 0;\n    }\n";
    _write_rechecked(
        root, "", "x + 1 + _zero()", "n + 1", twice + add, "_Counter(0).next() + _Counter(0).twice()", zero
    );
    var (named, _) = _build_rechecked(root);
    expect_true(named.misses.contains(a));
    expect_true(named.rechecked.is_empty);
}

# A field added to a struct that code the edit keeps copies: the struct's
# `__copy()` is made again, and copies the new field.
[Test]
copies_the_field_an_edit_adds() {
    var folder = TempFolder("added-field");
    var root = folder.path;
    var box = (field: String) => "struct _Box {\n    var n: int;\n"
        + field
        + "    construct(n: int) {\n        this.n = n;\n    }\n}\n";
    var copied = "_copied(): _Box {\n    return copy(_Box(1));\n}\n";
    _write_rechecked(root, "", "x + 1", "n + 1", "", "_Counter(0).next() + _copied().n - 1", box("") + copied);
    _build_rechecked(root);
    var a = _unit_of(_load(root), "a.pep");

    _write_rechecked(
        root,
        "",
        "x + 1",
        "n + 1",
        "",
        "_Counter(0).next() + _copied().n - 1 + _copied().extra - 2",
        box("    var extra: int = 2;\n") + copied
    );
    var (field, _) = _build_rechecked(root);
    expect_true(field.rechecked.contains(a));
}

# Writes `tab.pep`, whose struct `Table` stores `stored` from its
# constructor, and `main.pep`, whose `main` returns 0 when a `Table(3)`
# holds `count`.
_write_constructed(root: Path, stored: String, count: int) {
    File.write_text(
        root.join(Path("tab.pep")),
        "export struct Table {\n    var count: ulong;\n    construct(count: ulong) {\n        this.count = "
            + stored
            + ";\n    }\n}\n"
    );
    File.write_text(
        root.join(Path("main.pep")),
        $"import \"tab\";\nmain(): int {{\n    return Table(3).count == {count} ? 0 : 1;\n}}\n"
    );
}

# A constructor's changed body is checked again with its whole struct, which
# `synthesize` completes (#270).
[Test]
checks_again_the_struct_of_a_changed_constructor() {
    var folder = TempFolder("constructor");
    var root = folder.path;
    _write_constructed(root, "count", 3);
    _build_with_runtime(root, "main.pep");
    _write_constructed(root, "count + 1", 4);
    var built = _build_with_runtime(root, "main.pep");
    expect_true(built.rechecked.contains(_unit_of(_load(root), "tab.pep")));
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

# A trait's default method is compiled into the struct that adopts it, in
# that struct's compilation unit: an edit to its body there builds the
# adopter again (#46), which runs the new body.
[Test]
rebuilds_the_adopters_of_a_changed_default_method() {
    var folder = TempFolder("default_method");
    var root = folder.path;
    var write = (added: int) => {
        File.write_text(
            root.join(Path("a.pep")),
            $"export trait Sized {{\n    n(): int;\n    total(): int {{\n        return n() + {added};\n    }}\n}}\n"
        );
        File.write_text(
            root.join(Path("b.pep")),
            "import \"a\";\nstruct _Three {\n    n(): int {\n        return 3;\n    }\n}\nextend _Three with Sized;\nexport b_value(): int {\n    return _Three().total();\n}\n"
        );
        File.write_text(
            root.join(Path("main.pep")), $"import \"b\";\nmain(): int {{\n    return b_value() - {3 + added};\n}}\n"
        );
    };
    write(1);
    _build_methods(root);
    write(2);
    _build_methods(root);
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

# Adding a field a reader does not name keeps the reader's record; one that
# copies the struct, which copies every field, is checked again
# (`fields_still_match`).
[Test]
keeps_the_readers_of_a_struct_a_field_edit_does_not_reach() {
    var folder = TempFolder("field_keys");
    var root = folder.path;
    _write_fields(root, "");
    _build_methods(root);
    var program = _load(root);
    var b = _unit_of(program, "b.pep");
    var c = _unit_of(program, "c.pep");
    expect_true(_records_of(root, b) == 1);
    expect_true(_records_of(root, c) == 1);
    var kept = _kept_fields(root.join(Path("cache")), c);
    expect_true(kept.contains("Thing "));
    _write_fields(root, "    var m: int = 3;\n");
    _build_methods(root);
    expect_true(_records_of(root, b) == 1);
    # Its key is the same; its record is checked again, on the new fields.
    expect_true(_records_of(root, c) == 1);
    expect_true(_kept_fields(root.join(Path("cache")), c) != kept);
}

# The struct lines kept beside the records of `unit` under `dir`, the cache.
_kept_fields(dir: Path, unit: String): String {
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return "";
    }
    var out = StringBuilder();
    for (var entry in listing.value().entries().value()) {
        if (entry.is_directory) {
            out.append(_kept_fields(entry.path, unit));
        } else if (entry.name.ends_with(".rec.fields") and dir.to_string().ends_with(unit)) {
            out.append(File.read_to_string(entry.path).value());
        }
    }
    return out.to_string();
}

# A struct `Thing` with `fields` after its first, which `b.pep` reads a field
# of and `c.pep` copies.
_write_fields(root: Path, fields: String) {
    File.write_text(
        root.join(Path("a.pep")),
        "export struct Thing {\n    var n: int;\n" + fields + "    construct(n: int) {\n        this.n = n;\n    }\n}\n"
    );
    File.write_text(root.join(Path("b.pep")), "import \"a\";\nexport b_value(): int {\n    return Thing(2).n;\n}\n");
    File.write_text(
        root.join(Path("c.pep")),
        "import \"a\";\nexport c_value(): int {\n    var t = Thing(1);\n    return copy(t).n;\n}\n"
    );
    File.write_text(
        root.join(Path("main.pep")),
        "import \"b\";\nimport \"c\";\nmain(): int {\n    return b_value() + c_value() - 3;\n}\n"
    );
}
