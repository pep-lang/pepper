# A Pepper library linked into a Pepper program (`--lib pepper`, #220), as
# `pep-build` builds both: the program supplies the one runtime, runs the
# library's initializers before its own, releases the library's
# thread-locals when a thread ends, and refuses a library whose stamp does
# not fit it.

import compiler.driver;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import [TempFolder] from testing;
import [expect_contains, expect_exit, run, tool, write_file] from tool_testing;
import toolchain;

# A library that imports a runtime module (`json`) the program does not,
# sets a global by a call, and holds a thread-local whose release counts.
const _GEO = "import async;\nimport json;\n\nconst released = async.Atomic<int>(0);\n\n[Shared]\nstruct Badge {\n    const number: int;\n\n    construct(number: int) {\n        this.number = number;\n    }\n\n    destruct {\n        released.fetch_add(1);\n    }\n}\n\n[ThreadLocal]\nvar badge: Badge;\n\nconst SEED: int = json.parse(\"41\").value().as_int().value() as int;\n\nmain(): int {\n    return 1;\n}\n\n[Export]\nexport geo_seed(): int {\n    return SEED;\n}\n\n[Export]\nexport geo_badge(n: int) {\n    badge = Badge(n);\n}\n\n[Export]\nexport geo_released(): int {\n    return released.load();\n}\n";

# A program that calls the library from a global's initializer, and sets
# the library's thread-local on a thread of its own.
const _MAIN = "import [Thread] from async;\n\n[Link(\"geo\")]\nextern int geo_seed();\n\n[Link(\"geo\")]\nextern void geo_badge(int n);\n\n[Link(\"geo\")]\nextern int geo_released();\n\nconst FROM_LIBRARY: int = geo_seed() + 1;\n\nwork() {\n    geo_badge(7);\n}\n\nmain(): int {\n    var thread = Thread.spawn(work);\n    thread.join();\n    print($\"{FROM_LIBRARY} {geo_released()}\");\n    return 0;\n}\n";

# Runs `pep-build` on `source`, writing `output`, with `options` after the
# build's own; the build and cache folders are beside `source`. The
# runtime's units go to a shared cache (`PEPPER_SHARED_CACHE`) that every
# test here uses, `.pep/pepper_library_runtime` where the tests run, so the
# runtime is checked and compiled once per optimization level rather than
# in each build's own cache.
_pep_build(source: Path, output: Path, options: Array<String>): process.Output {
    var folder = source.parent().value();
    return run(
        process
            .Command(tool("pep-build").to_string())
            .argument(source.to_string())
            .argument("-o")
            .argument(output.to_string())
            .argument("--build")
            .argument(folder.join("build").to_string())
            .argument("--cache")
            .argument(folder.join("cache").to_string())
            .arguments(options)
            .environment(
                "PEPPER_SHARED_CACHE",
                Directory.current().value().join(".pep").join("pepper_library_runtime").to_string()
            )
    );
}

# The archive `--lib pepper` writes for `name` in `folder`.
_archive(folder: Path, name: String): Path {
    return folder.join(driver.library_file_name(driver.LibraryKind.Pepper, name, link.Target()));
}

# Builds `_GEO` as a Pepper library in `root/geo`, with `options`, and
# returns its archive.
_build_geo(root: Path, options: Array<String> = Array<String>()): Path {
    var source = root.join("geo").join("geo.pep");
    write_file(source, _GEO);
    var archive = _archive(root.join("geo"), "geo");
    var lib = ["--lib", "pepper"];
    lib.append_all(options);
    var built = _pep_build(source, archive, lib);
    expect_exit(built, 0);
    return archive;
}

# Builds `_MAIN` in `root/app` against the library in `root/geo` with
# `options`, and returns how the build went and the program.
_build_main(root: Path, options: Array<String> = Array<String>()): (process.Output, Path) {
    var source = root.join("app").join("main.pep");
    write_file(source, _MAIN);
    var program = root.join("app").join("main" + toolchain.executable_suffix());
    var linking = ["-L", root.join("geo").to_string()];
    linking.append_all(options);
    return (_pep_build(source, program, linking), program);
}

# Runs `program`, which must succeed, and returns what it printed.
_run_program(program: Path): String {
    var ran = run(process.Command(program.to_string()));
    expect_exit(ran, 0);
    return ran.stdout.trim();
}

[Test]
a_program_links_a_pepper_library() {
    var folder = TempFolder("pepper_library");
    var archive = _build_geo(folder.path);
    # The library carries no runtime and no entry points of its own.
    var stamps = link.read_stamps(archive).value();
    expect_equal(stamps.count, 1 as ulong);
    expect_equal(stamps[0].kind, "pepper");
    expect_equal(stamps[0].init, "__pep_library_init.geo");
    expect_equal(stamps[0].release, "__pep_library_release.geo");
    bool json = false;
    for (var module in stamps[0].modules) {
        json = json or module.starts_with("json ");
    }
    expect_true(json);
    # Its `main` is left out: the program has its own.
    var (built, program) = _build_main(folder.path);
    expect_exit(built, 0);
    # No duplicate symbol, which Apple's linker only warns of.
    expect_false(built.stderr.contains("duplicate"));
    # The library's global is set before the program's, which reads it, and
    # its thread-local is released when the program's thread ends.
    expect_equal(_run_program(program), "42 1");
    # Optimized as one module, the program keeps the runtime the library
    # uses.
    var (optimized, _) = _build_main(folder.path, ["-O", "--lto=full"]);
    expect_exit(optimized, 0);
    expect_equal(_run_program(program), "42 1");
    # Checked whole, without the cache, the program's runtime interface is
    # the library's still.
    var (whole, _) = _build_main(folder.path, ["--no-cache"]);
    expect_exit(whole, 0);
    expect_equal(_run_program(program), "42 1");
}

[Test]
a_library_needing_another_initializes_after_it() {
    var folder = TempFolder("pepper_libraries");
    var root = folder.path;
    var base = root.join("base").join("base.pep");
    write_file(
        base,
        "const BASE: int = _compute();\n\n_compute(): int {\n    return 42;\n}\n\n[Export]\nexport base_value(): int {\n    return BASE;\n}\n"
    );
    expect_exit(_pep_build(base, _archive(root.join("base"), "base"), ["--lib", "pepper"]), 0);
    var top = root.join("top").join("top.pep");
    write_file(
        top,
        "[Link(\"base\")]\nextern int base_value();\n\nconst TOP: int = base_value() + 1;\n\n[Export]\nexport top_value(): int {\n    return TOP;\n}\n"
    );
    var archive = _archive(root.join("top"), "top");
    expect_exit(_pep_build(top, archive, ["--lib", "pepper", "-L", root.join("base").to_string()]), 0);
    expect_equal(",".join(link.read_stamps(archive).value()[0].needs), "base");
    # Linked in the other order, `base` still initializes first.
    var main = root.join("app").join("main.pep");
    write_file(
        main,
        "[Link(\"top\")]\nextern int top_value();\n\nmain(): int {\n    print($\"{top_value()}\");\n    return 0;\n}\n"
    );
    var program = root.join("app").join("main" + toolchain.executable_suffix());
    var built = _pep_build(
        main,
        program,
        ["-l", "top", "-l", "base", "-L", root.join("top").to_string(), "-L", root.join("base").to_string()]
    );
    expect_exit(built, 0);
    expect_equal(_run_program(program), "43");
}

# A library whose stamp says it was built against another `json` is
# refused at the `[Link]` naming it.
[Test]
a_library_built_against_another_module_is_refused() {
    var folder = TempFolder("pepper_library_module");
    var archive = _build_geo(folder.path);
    var bytes = File.read_bytes(archive).value();
    var at = _find(bytes, "module json ".bytes());
    expect_true(at < bytes.count);
    # One digit of the hash, changed.
    var digit = at + 12;
    bytes[digit] = bytes[digit] == ('0' as u8) ? ('1' as u8) : ('0' as u8);
    File.write_bytes(archive, bytes);
    var (built, _) = _build_main(folder.path);
    expect_exit(built, 1);
    expect_contains(built.stderr, "main.pep:3:7: error: ");
    expect_contains(built.stderr, "the runtime module 'json' differs");
}

# A Pepper program still links a self-contained shared library, which
# keeps its own runtime.
[Test]
a_program_links_a_self_contained_shared_library() {
    var folder = TempFolder("pepper_shared");
    var root = folder.path;
    var host = link.Target();
    var source = root.join("app").join("geo.pep");
    write_file(source, "[Export]\nexport geo_area(side: int): int {\n    return side * side;\n}\n");
    var shared = root.join("app").join(driver.library_file_name(driver.LibraryKind.Shared, "geo", host));
    expect_exit(_pep_build(source, shared, ["--lib", "shared"]), 0);
    var main = root.join("app").join("main.pep");
    write_file(
        main,
        "[Link(\"geo\")]\nextern int geo_area(int side);\n\nmain(): int {\n    print($\"{geo_area(3)}\");\n    return 0;\n}\n"
    );
    # Beside the library, where Windows looks for it.
    var program = root.join("app").join("main" + toolchain.executable_suffix());
    expect_exit(_pep_build(main, program, ["-L", root.join("app").to_string()]), 0);
    var command = process.Command(program.to_string());
    command.environment(host.is_apple() ? "DYLD_LIBRARY_PATH" : "LD_LIBRARY_PATH", root.join("app").to_string());
    var ran = run(command);
    expect_exit(ran, 0);
    expect_equal(ran.stdout.trim(), "9");
}

# A Pepper library is static only: it leaves the runtime out, which a
# shared library would need.
[Test]
a_shared_pepper_library_is_refused() {
    var folder = TempFolder("pepper_library_shared");
    var source = folder.path.join("geo.pep");
    write_file(source, "[Export]\nexport geo_area(side: int): int {\n    return side * side;\n}\n");
    var host = link.Target();
    var shared = folder.path.join(driver.library_file_name(driver.LibraryKind.Shared, "geo", host));
    var built = _pep_build(source, shared, ["--lib", "pepper"]);
    expect_exit(built, 2);
    expect_contains(
        built.stderr,
        "'--lib pepper' cannot build a shared library: it leaves the runtime out; build a static library for a Pepper program"
    );
    # Its interface comes from a check in compilation units, which records
    # no expanded `static` blocks.
    var archive = folder.path.join(driver.library_file_name(driver.LibraryKind.Pepper, "geo", host));
    var expanded = _pep_build(source, archive, ["--lib", "pepper", "-g", "--debug-static=expanded"]);
    expect_exit(expanded, 2);
    expect_contains(expanded.stderr, "'--debug-static=expanded' cannot build '--lib pepper'");
}

# Builds `testdata/imported_library/geo.pep` as the Pepper library `geo`
# into `root/lib`, with `geo.pep`'s text changed by `edit` (old -> new),
# then removes its source; returns its archive.
_build_imported_geo(root: Path, edit: (String, String)? = Optional<(String, String)>.Empty): Path {
    var text = File.read_to_string(Path("compiler/testdata/imported_library/geo.pep")).value();
    if (edit.is_value()) {
        var (old, now) = edit.value();
        expect_true(text.contains(old));
        text = text.replace(old, now);
    }
    var source = root.join("src").join("geo.pep");
    write_file(source, text);
    var archive = _archive(root.join("lib"), "geo");
    expect_exit(_pep_build(source, archive, ["--lib", "pepper"]), 0);
    File.remove(source);
    return archive;
}

# Builds `main` (a file's text) in `root/app` against the library in
# `root/lib`, with `options` after; returns how it went and the program.
_build_importer(root: Path, main: String, options: Array<String> = Array<String>()): (process.Output, Path) {
    var source = root.join("app").join("main.pep");
    write_file(source, main);
    var program = root.join("app").join("main" + toolchain.executable_suffix());
    var all = ["-L", root.join("lib").to_string()];
    all.append_all(options);
    return (_pep_build(source, program, all), program);
}

# A program imports a Pepper library's Pepper declarations with no source
# for it: its interface (`.pepi`) is checked already, the program
# instantiates its generics, and its archive defines the rest.
[Test]
a_program_imports_a_pepper_library() {
    var folder = TempFolder("pepper_library_import");
    var root = folder.path;
    var archive = _build_imported_geo(root);
    var interface = archive.with_extension(link.INTERFACE_EXTENSION);
    var before = link.interface_hash(File.read_bytes(interface).value());
    var main = File.read_to_string(Path("compiler/testdata/imported_library/main.pep")).value();
    var (built, program) = _build_importer(root, main);
    expect_exit(built, 0);
    expect_false(built.stderr.contains("duplicate"));
    # A trait's default method on a library struct and a program one, a
    # value struct, a shared object on another thread, a generic at a
    # program type and at one the library instantiates too, the library's
    # global and its extension of `String`.
    expect_equal(_run_program(program), "area 9,area 3 10 1 2 12 42 x!");
    # Without the cache, and optimized as one module.
    expect_exit(_build_importer(root, main, ["--no-cache"]).0, 0);
    expect_equal(_run_program(program), "area 9,area 3 10 1 2 12 42 x!");
    expect_exit(_build_importer(root, main, ["-O", "--lto=full"]).0, 0);
    expect_equal(_run_program(program), "area 9,area 3 10 1 2 12 42 x!");

    # A body edit leaves the interface as it was: the program links the
    # new archive.
    _build_imported_geo(root, Optional<(String, String)>.Value(("total += p.x + p.y;", "total += p.x * p.y;")));
    expect_equal(link.interface_hash(File.read_bytes(interface).value()), before);
    expect_exit(_build_importer(root, main).0, 0);
    expect_equal(_run_program(program), "area 9,area 3 14 1 2 12 42 x!");

    # A generic's body is in the interface, which the program compiles.
    var old_archive = File.read_bytes(archive).value();
    _build_imported_geo(root, Optional<(String, String)>.Value(("return [value, value];", "return [value];")));
    expect_true(link.interface_hash(File.read_bytes(interface).value()) != before);
    expect_exit(_build_importer(root, main).0, 0);
    expect_equal(_run_program(program), "area 9,area 3 10 1 1 12 21 x!");

    # An archive built with another interface is refused at the import.
    File.write_bytes(archive, old_archive);
    var (stale, _) = _build_importer(root, main);
    expect_exit(stale, 1);
    expect_contains(stale.stderr, "main.pep:5:8: error: the archive ");
    expect_contains(stale.stderr, "rebuild the library 'geo'");
}

# What a program cannot do with an imported Pepper library: call it
# wrongly (the error names the library's declaration as written, in its
# interface), use its extension from a file that does not import it,
# or check the program whole.
[Test]
an_imported_pepper_library_is_checked_against() {
    var folder = TempFolder("pepper_library_import_errors");
    var root = folder.path;
    _build_imported_geo(root);
    var (wrong, _) = _build_importer(root, "import geo;\n\nmain(): int {\n    return geo.sum(1);\n}\n");
    expect_exit(wrong, 1);
    expect_contains(
        wrong.stderr,
        "main.pep:4:20: error: cannot pass a value of type 'int' as argument 1 of 'sum', which has type 'Array<Point>'"
    );
    write_file(root.join("app").join("util.pep"), "export loud(): String {\n    return \"y\".shout();\n}\n");
    var (
        unseen, _
    ) = _build_importer(root, "import geo;\nimport \"util\";\n\nmain(): int {\n    print(loud());\n    return 0;\n}\n");
    expect_exit(unseen, 1);
    expect_contains(unseen.stderr, "util.pep:2:16: error: 'shout' is declared in an extension in ");
    expect_contains(unseen.stderr, "which this file does not import");
    # The note names the interface's file, which has no text to show.
    expect_contains(unseen.stderr, $"geo.{link.INTERFACE_EXTENSION}/geo/geo.pep:1:1: note: declared here");
    expect_false(unseen.stderr.contains("    1 |"));
    # A use of its deprecated function warns, as its link table keeps the
    # attribute.
    var (
        deprecated, _
    ) = _build_importer(root, "import geo;\n\nmain(): int {\n    return geo.old_sum([geo.Point(1, 1)]) - 2;\n}\n");
    expect_exit(deprecated, 0);
    expect_contains(deprecated.stderr, "main.pep:4:16: warning: 'old_sum' is deprecated: use 'sum' instead");
    var (whole, _) = _build_importer(root, "import geo;\n\nmain(): int {\n    return 0;\n}\n", ["--emit-llvm"]);
    expect_exit(whole, 1);
    expect_contains(whole.stderr, "cannot check the program whole: it imports the Pepper library 'geo'");
    # A library's own names are mangled with its namespace; its errors
    # name them as written.
    var locked = root.join("locked").join("locked.pep");
    write_file(
        locked,
        "import async;\n\nconst keepers = async.Mutex<Array<String>>(Array<String>());\n\nexport keep() {\n    var line = \"x\";\n    with (var kept = keepers.lock()) {\n        kept.append(line);\n    }\n}\n"
    );
    var keeping = _pep_build(locked, _archive(root.join("locked"), "locked"), ["--lib", "pepper"]);
    expect_exit(keeping, 1);
    expect_contains(keeping.stderr, "error: 'line' cannot move into the value locked by 'keepers'");
    expect_false(keeping.stderr.contains("@"));
    # An interface of another record version names the library to rebuild.
    var interface = _archive(root.join("lib"), "geo").with_extension(link.INTERFACE_EXTENSION);
    var bytes = File.read_bytes(interface).value();
    var renumbered = $"{link.INTERFACE_MAGIC}999".bytes();
    renumbered.append_all(bytes.slice(_find(bytes, "\n".bytes()), bytes.count).to_array());
    File.write_bytes(interface, renumbered);
    var (old, _) = _build_importer(root, "import geo;\n\nmain(): int {\n    return 0;\n}\n");
    expect_exit(old, 1);
    expect_contains(old.stderr, "main.pep:1:8: error: ");
    expect_contains(
        old.stderr,
        $"the interface is record version 999, and this compiler reads version {link.RECORD_VERSION}; rebuild the library 'geo' with this compiler"
    );
}

# A Pepper library that imports another (`top.pep` on `geo`) names it in
# its interface with the hash of the interface it read, and its stamp
# needs it. A program that imports `top`, alone or with `geo`, loads `geo`
# from its library folders and links both archives, setting `geo`'s
# globals first; `top`'s re-export is `geo`'s struct. A `geo` with another
# interface is refused at the import of `top` until `top` is rebuilt.
[Test]
a_pepper_library_imports_a_pepper_library() {
    var folder = TempFolder("pepper_library_imports_library");
    var root = folder.path;
    _build_imported_geo(root);
    var geo_interface = _archive(root.join("lib"), "geo").with_extension(link.INTERFACE_EXTENSION);
    var geo_hash = link.interface_hash(File.read_bytes(geo_interface).value());
    var top = _build_imported_top(root);
    var interface = File.read_bytes(top.with_extension(link.INTERFACE_EXTENSION)).value();
    expect_true(_find(interface, $"\nlibrary geo {geo_hash}\n".bytes()) < interface.count);
    expect_true(_find(interface, "\nimport geo\n".bytes()) < interface.count);
    expect_true(link.read_stamps(top).value()[0].needs.contains("geo"));
    var alone = "import top;\n\nmain(): int {\n    print($\"{top.scaled()} {top.twice([top.Point(1, 2)])} {top.twin(\"x\")}\");\n    return 0;\n}\n";
    var (built, program) = _build_importer(root, alone);
    expect_exit(built, 0);
    expect_false(built.stderr.contains("duplicate"));
    expect_equal(_run_program(program), "84 6 2");
    # Without `geo` in its library folders, the error names both.
    var alone_folder = root.join("alone");
    Directory.create_all(alone_folder);
    for (var file in [top, top.with_extension(link.INTERFACE_EXTENSION)]) {
        expect_true(File.copy(file, alone_folder.join(file.file_name().value())).is_ok());
    }
    var missing = _pep_build(root.join("app").join("main.pep"), program, ["-L", alone_folder.to_string()]);
    expect_exit(missing, 1);
    expect_contains(
        missing.stderr,
        "error: the Pepper library 'top' imports 'geo', which is no runtime module and no Pepper library in the library folders"
    );
    var both = "import geo;\nimport top;\n\nmain(): int {\n    print($\"{geo.answer()} {top.scaled()} {geo.sum([top.Point(3, 4)])}\");\n    return 0;\n}\n";
    var (together, linked) = _build_importer(root, both);
    expect_exit(together, 0);
    expect_equal(_run_program(linked), "42 84 7");
    expect_exit(_build_importer(root, both, ["--no-cache", "-O"]).0, 0);
    expect_equal(_run_program(linked), "42 84 7");
    # A C library can import it too.
    var source = root.join("c").join("c.pep");
    write_file(source, "import top;\n\n[Export]\nexport c_scaled(): int {\n    return top.scaled();\n}\n");
    expect_exit(
        _pep_build(
            source,
            root.join("c").join(driver.library_file_name(driver.LibraryKind.Static, "c", link.Target())),
            ["--lib", "static", "-L", root.join("lib").to_string()]
        ),
        0
    );
    # `geo` rebuilt with another interface, a generic's body changed.
    _build_imported_geo(root, Optional<(String, String)>.Value(("return [value, value];", "return [value];")));
    var (stale, _) = _build_importer(root, alone);
    expect_exit(stale, 1);
    expect_contains(
        stale.stderr,
        "main.pep:1:8: error: the Pepper library 'top' was built against another interface of the library 'geo' than "
    );
    _build_imported_top(root);
    expect_exit(_build_importer(root, alone).0, 0);
    expect_equal(_run_program(program), "42 6 1");
}

# Builds `testdata/imported_library/top.pep` as the Pepper library `top`
# into `root/lib`, against the `geo` there; returns its archive.
_build_imported_top(root: Path): Path {
    var source = root.join("src").join("top.pep");
    write_file(source, File.read_to_string(Path("compiler/testdata/imported_library/top.pep")).value());
    var archive = _archive(root.join("lib"), "top");
    expect_exit(_pep_build(source, archive, ["--lib", "pepper", "-L", root.join("lib").to_string()]), 0);
    return archive;
}

# A Pepper library (`measure.pep`) and a program (`extends.pep`) each extend
# a struct of the library `geo` they import: `geo`'s interface is checked
# already, not again with the files that extend it.
[Test]
a_program_and_a_library_extend_a_library_type() {
    var folder = TempFolder("pepper_library_extend");
    var root = folder.path;
    _build_imported_geo(root);
    var source = root.join("src").join("measure.pep");
    write_file(source, File.read_to_string(Path("compiler/testdata/imported_library/measure.pep")).value());
    expect_exit(
        _pep_build(
            source, _archive(root.join("lib"), "measure"), ["--lib", "pepper", "-L", root.join("lib").to_string()]
        ),
        0
    );
    var main = File.read_to_string(Path("compiler/testdata/imported_library/extends.pep")).value();
    for (var options in [Array<String>(), ["--no-cache"], ["-O", "--lto=full"]]) {
        var (built, program) = _build_importer(root, main, options);
        expect_exit(built, 0);
        expect_equal(_run_program(program), "7 12 12");
    }
}

# A program cannot import from source a module a library it imports
# carries: the error is at the program's import of the module, with a note
# at its import of the library.
[Test]
a_module_a_library_carries_is_not_imported_again() {
    var folder = TempFolder("pepper_library_shared_module");
    var root = folder.path;
    var deps = root.join("deps");
    write_file(deps.join("shapes").join("module.pep"), "export const SIDE: int = 3;\n");
    var source = root.join("src").join("geo.pep");
    write_file(source, "import shapes;\n\nexport side(): int {\n    return shapes.SIDE;\n}\n");
    expect_exit(_pep_build(source, _archive(root.join("lib"), "geo"), ["--lib", "pepper", "-I", deps.to_string()]), 0);
    var (
        built,
        _
    ) = _build_importer(
        root,
        "import geo;\nimport shapes;\n\nmain(): int {\n    return geo.side() - shapes.SIDE;\n}\n",
        ["-I", deps.to_string()]
    );
    expect_exit(built, 1);
    expect_contains(
        built.stderr,
        "main.pep:2:8: error: module 'shapes' is already part of the Pepper library 'geo'; drop this import and use what 'geo' exports, or rebuild 'geo' without it"
    );
    expect_contains(built.stderr, "main.pep:1:8: note: the Pepper library 'geo' is imported here");
}

# A program links a library's names exactly as the library build named
# them, which its interface's link tables carry: a generic the program
# instantiates calls a private helper of another file of the library, two
# files' private helpers share a name with each other and with the
# program's, and the root re-exports another file's declarations and
# exports an overload set. A name taken otherwise would be undefined in the
# library's archive.
[Test]
a_program_links_a_library_of_two_files_by_its_names() {
    var folder = TempFolder("pepper_library_split");
    var root = folder.path;
    var source = root.join("src").join("geo.pep");
    for (var name in ["geo", "util"]) {
        write_file(
            root.join("src").join($"{name}.pep"),
            File.read_to_string(Path($"compiler/testdata/split_library/{name}.pep")).value()
        );
    }
    expect_exit(_pep_build(source, _archive(root.join("lib"), "geo"), ["--lib", "pepper"]), 0);
    Directory.remove_all(root.join("src"));
    var main = "import geo;\n\n_secret(): int {\n    return 1;\n}\n\nmain(): int {\n    print($\"{geo.scale([1, 2, 3])} {geo.total(geo.Grid(4))} {geo.twice(\"x\")} {geo.area(3)} {geo.area(2, 5)} {_secret()}\");\n    return 0;\n}\n";
    var (built, program) = _build_importer(root, main);
    expect_exit(built, 0);
    expect_equal(_run_program(program), "15 9 14 9 10 1");
}

# A chain that runs through a library's structs and the program's in turn
# is released in a loop: the program compiles its own release of each
# library struct the chain runs through, and links it ahead of the
# archive's (`testdata/library_chain`). Linked with the archive's copy
# first, the release recurses, and overflows Windows' 1 MB main stack by
# 2,000 links, about 500 bytes a link: 100,000 needs some 50 MB, far past
# the 8 MB of a Linux or macOS main thread.
[Test]
a_chain_through_a_library_releases_without_overflow() {
    var folder = TempFolder("pepper_library_chain");
    var root = folder.path;
    var source = root.join("src").join("chain.pep");
    write_file(source, File.read_to_string(Path("compiler/testdata/library_chain/chain.pep")).value());
    expect_exit(_pep_build(source, _archive(root.join("lib"), "chain"), ["--lib", "pepper"]), 0);
    File.remove(source);
    var main = File.read_to_string(Path("compiler/testdata/library_chain/main.pep")).value();
    var (built, program) = _build_importer(root, main);
    expect_exit(built, 0);
    for (var depth in ["10", "100000"]) {
        var ran = run(process.Command(program.to_string()).argument(depth));
        expect_exit(ran, 0);
        expect_equal(ran.stdout, "wrap chain released true\npair chain released true\n");
    }
}

# A library's interface holds no source text: not a comment, nor a name
# used only inside a function body it leaves out (`sum`'s local), nor a
# string only such a body holds.
[Test]
an_interface_holds_no_source_text() {
    var folder = TempFolder("pepper_library_no_text");
    var root = folder.path;
    var archive = _build_imported_geo(root, Optional<(String, String)>.Value(("total", "zebra_tally")));
    var bytes = File.read_bytes(archive.with_extension(link.INTERFACE_EXTENSION)).value();
    expect_true(_find(bytes, "declare function sum@geo/geo".bytes()) < bytes.count);
    for (var text in ["zebra_tally", "A Pepper library a program imports", "a global set by a call"]) {
        expect_equal(_find(bytes, text.bytes()), bytes.count);
    }
    # The program links and runs as before.
    var main = File.read_to_string(Path("compiler/testdata/imported_library/main.pep")).value();
    var (built, program) = _build_importer(root, main);
    expect_exit(built, 0);
    expect_equal(_run_program(program), "area 9,area 3 10 1 2 12 42 x!");
}

# The index of the first `part` in `bytes`; `bytes.count` when none.
_find(bytes: u8[], part: u8[]): ulong {
    for (var i in 0..bytes.count) {
        bool here = i + part.count <= bytes.count;
        for (var k in 0..part.count) {
            here = here and bytes[i + k] == part[k];
        }
        if (here) {
            return i;
        }
    }
    return bytes.count;
}
