# The build cache of the compiler in Pepper (`driver/cache.pep`): a
# module's files are one unit, a build keeps each unit's object, the next
# build reuses those whose inputs did not change, and an unchanged program
# is not built again.

import compiler.driver;
import [Directory, File, Path] from io;
import compiler.link;
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
