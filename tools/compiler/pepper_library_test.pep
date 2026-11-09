# A Pepper library linked into a Pepper program (`--lib pepper`, #220), as
# `pep-build` builds both: the program supplies the one runtime, runs the
# library's initializers before its own, releases the library's
# thread-locals when a thread ends, and refuses a library whose stamp does
# not fit it.

import compiler.driver;
import [File, Path] from io;
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
# build's own; the build and cache folders are beside `source`.
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
