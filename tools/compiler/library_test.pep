# Calling Pepper from C (`--lib static|shared`), link-time optimization
# (`--lto`) and the CPU the `-m` options choose: each kind of library is
# built, a C program compiled against it with the clang the compiler links
# with, and run.

import compiler.codegen;
import compiler.driver;
import compiler.incremental;
import [Directory, File, Path] from io;
import compiler.link;
import llvm;
import process;
import compiler.sema;
import [TempFolder] from testing;
import [Utf8] from text;

# A library that exercises each kind of value that crosses to C: numbers,
# `bool`, a C function pointer, a `String` in both directions, a struct
# handle in both directions, and a module-scope variable whose initializer
# must have run.
const _LIBRARY = "import async;\n\nconst freed = async.Atomic<int>(0);\nconst started = async.Atomic<int>(7);\n\nstruct Counter {\n    var count: int;\n\n    construct(this.count = 0) {}\n\n    destruct {\n        freed.fetch_add(1);\n    }\n}\n\n[Export]\nadd(a: int, b: int): int {\n    return a + b;\n}\n\n[Export(name = \"counter_new\")]\nmake_counter(start: int): Counter {\n    return Counter(start);\n}\n\n[Export]\ncounter_increment(counter: Counter): int {\n    counter.count += 1;\n    return counter.count;\n}\n\n[Export]\nfreed_count(): int {\n    return freed.load();\n}\n\n[Export]\nstarted_value(): int {\n    return started.load();\n}\n\n[Export]\nis_even(n: long): bool {\n    return n % 2 == 0;\n}\n\n[Export]\nscale(x: double, factor: float): double {\n    return x * factor;\n}\n\n[Export]\nnarrow(x: short): short {\n    return x;\n}\n\n[Export]\napply(f: extern (int) => int, x: int): int {\n    return f(x);\n}\n\n[Export]\nshout(text: String, times: int): String {\n    var out = \"\";\n    for (var i in 0..times) {\n        out += text.upper();\n    }\n    return out + \"!\";\n}\n\n[Export]\nlive_allocations(): long {\n    return _pep_live_allocs();\n}\n";

const _PROGRAM = "#include <stdio.h>\n#include <string.h>\n#include \"counter.h\"\n\nstatic int32_t twice(int32_t x) { return 2 * x; }\n\nint main(void) {\n    int64_t live = live_allocations();\n    char* shouted = shout(\"h\\xc3\\xa9\", 3, 2);\n    char* empty = shout(NULL, 0, 1);\n    printf(\"%s %s %d\\n\", shouted, empty, (int)strlen(shouted));\n    pepper_string_free(shouted);\n    pepper_string_free(empty);\n    Counter* counter = counter_new(10);\n    counter_increment(counter);\n    int32_t count = counter_increment(counter);\n    counter_retain(counter);\n    counter_release(counter);\n    int32_t freed_before = freed_count();\n    counter_release(counter);\n    printf(\"%d %d %d %d %d %d %d %g %d %d\\n\", add(2, 3), count, freed_before, freed_count(), started_value(),\n           is_even(4), is_even(7), scale(1.5, 2.0f), narrow(-3), apply(twice, 21));\n    printf(\"leaked %d\\n\", (int)(live_allocations() - live));\n    return 0;\n}\n";

const _EXPECTED = "HéHé! ! 7\n5 12 0 1 7 1 0 3 -3 42\nleaked 0";

# Builds `source`'s `main.pep` in `root` as `options` says, which must
# succeed; with `runtime`, the program uses the runtime.
_build(root: Path, source: String, options: driver.BuildOptions, runtime: bool, target: link.Target = link.Target()) {
    var file = root.join(Path("counter.pep"));
    File.write_text(file, source);
    var setup = link.Setup();
    setup.runtime = runtime;
    setup.target = target;
    var program = link.load_program(file, setup);
    expect_true(program.is_ok());
    options.in_process = true;
    var built = driver.build(program.value(), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
}

# Runs `command`, which must succeed, and returns what it printed.
_run(command: process.Command): String {
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var ran = command.run();
    expect_true(ran.is_ok());
    if (!ran.value().status.success()) {
        print(ran.value().stdout + ran.value().stderr);
    }
    expect_true(ran.value().status.success());
    return ran.value().stdout.trim();
}

# Compiles `_PROGRAM` in `root` against the library there with `link`
# arguments, runs it, and returns what it printed.
_run_program(root: Path, link: String[]): String {
    var main = root.join(Path("main.c"));
    File.write_text(main, _PROGRAM);
    var exe = root.join(Path("main"));
    var clang = process.Command(driver.find_link_driver().value().to_string());
    clang.argument(main.to_string()).argument($"-I{root}");
    for (var argument in link) {
        clang.argument(argument);
    }
    clang.argument("-o").argument(exe.to_string());
    _run(clang);
    return _run(process.Command(exe.to_string()));
}

# A static library, then a shared one, of `_LIBRARY` (sharing the build
# cache, so the runtime compiles once), each called from C on Linux.
[Test]
c_programs_call_a_static_and_a_shared_library() {
    if (link.Target().os != "linux") {
        return;
    }
    var folder = TempFolder("c_library");
    var root = folder.path;
    var host = link.Target();
    # Static: the archive, with the header naming what links with it.
    var archive = root.join(Path(driver.library_file_name(driver.LibraryKind.Static, "counter", host)));
    expect_equal(archive.file_name().value(), "libcounter.a");
    var options = driver.BuildOptions(archive, root.join(Path("build")));
    options.library = Optional<driver.LibraryKind>.Value(driver.LibraryKind.Static);
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
    _build(root, _LIBRARY, options, true);
    var header = File.read_to_string(root.join(Path("counter.h"))).value();
    expect_true(header.contains("Counter* counter_new(int32_t start);"));
    expect_true(header.contains("#ifndef COUNTER_H"));
    var link_with = [archive.to_string()];
    for (var line in header.lines()) {
        var prefix = "/* Link the static library with: ";
        if (line.starts_with(prefix)) {
            var flags = line.substr_bytes(prefix.size, line.size - prefix.size - 3);
            link_with.append_all(flags.split(" "));
        }
    }
    expect_true(link_with.contains("-lm"));
    expect_equal(_run_program(root, link_with), _EXPECTED);
    # Shared: the same exports, found on the program's run path.
    var shared = root.join(Path(driver.library_file_name(driver.LibraryKind.Shared, "counter", host)));
    expect_equal(shared.file_name().value(), "libcounter.so");
    options = driver.BuildOptions(shared, root.join(Path("build")));
    options.library = Optional<driver.LibraryKind>.Value(driver.LibraryKind.Shared);
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
    _build(root, _LIBRARY, options, true);
    # Linked by its file name, which is its `soname`.
    var dynamic = _run(process.Command("readelf").argument("-d").argument(shared.to_string()));
    expect_true(dynamic.contains("Library soname: [libcounter.so]"));
    File.remove(archive);
    expect_equal(_run_program(root, [shared.to_string(), $"-Wl,-rpath,{root}"]), _EXPECTED);
}

[Test]
header_declares_exports_and_handles() {
    var folder = TempFolder("c_header");
    var file = folder.path.join(Path("counter.pep"));
    File.write_text(file, _LIBRARY);
    var program = link.load_program(file, link.Setup());
    expect_true(program.is_ok());
    var module = sema.merge(program.value());
    expect_true(module.is_ok());
    var state = sema.run_passes(module.value(), program.value().target, program.value().sources());
    expect_true(state.is_ok());
    expect_equal(
        sema.header_declarations(state.value().exports, state.value().enum_representations),
        "/* Opaque handles to Pepper objects. A handle a function returns is one\n * reference, which the caller releases; a handle passed in stays the\n * caller's. */\ntypedef struct Counter Counter;\n\nvoid counter_retain(Counter* handle);\nvoid counter_release(Counter* handle);\n\n/* A string a function returns is a NUL-terminated UTF-8 copy, which the\n * caller frees with this. */\nvoid pepper_string_free(char* text);\n\nint32_t add(int32_t a, int32_t b);\nint32_t apply(int32_t (*f)(int32_t), int32_t x);\nint32_t counter_increment(Counter* counter);\nCounter* counter_new(int32_t start);\nint32_t freed_count(void);\nbool is_even(int64_t n);\nint64_t live_allocations(void);\nint16_t narrow(int16_t x);\ndouble scale(double x, float factor);\nchar* shout(const char* text, size_t text_size, int32_t times);\nint32_t started_value(void);\n"
    );
    var text = sema.header("counter.h", "int32_t add(int32_t a, int32_t b);\n", ["m"]);
    expect_true(
        text.starts_with(
            "/* counter.h: generated by the Pepper compiler. Do not edit. */\n/* Link the static library with: -lm */\n#ifndef COUNTER_H\n#define COUNTER_H\n"
        )
    );
    expect_true(text.ends_with("#endif /* COUNTER_H */\n"));
}

# A library's file and header names on each platform.
[Test]
names_libraries_and_headers_as_each_platform_does() {
    var linux = link.Target.parse("x86_64-unknown-linux-gnu").value();
    var mac = link.Target.parse("aarch64-apple-darwin").value();
    var windows = link.Target.parse("x86_64-pc-windows-msvc").value();
    expect_equal(driver.library_file_name(driver.LibraryKind.Static, "foo", linux), "libfoo.a");
    expect_equal(driver.library_file_name(driver.LibraryKind.Shared, "foo", linux), "libfoo.so");
    expect_equal(driver.library_file_name(driver.LibraryKind.Shared, "foo", mac), "libfoo.dylib");
    expect_equal(driver.library_file_name(driver.LibraryKind.Static, "foo", windows), "foo.lib");
    expect_equal(driver.library_file_name(driver.LibraryKind.Shared, "foo", windows), "foo.dll");
    expect_equal(
        driver.header_path(Path("out/libfoo.a"), linux).to_string(), Path("out").join(Path("foo.h")).to_string()
    );
    expect_equal(driver.header_path(Path("libfoo.so"), linux).to_string(), "foo.h");
    expect_equal(driver.header_path(Path("bar.dll"), windows).to_string(), "bar.h");
    expect_equal(driver.header_path(Path("libbar.lib"), windows).to_string(), "libbar.h");
}

const _NO_RUNTIME_LIBRARY = "[Export]\nadd(a: int, b: int): int {\n    return a + b;\n}\n[Export]\ntimes(a: int, b: int): int {\n    return a * b;\n}\n";

# The archive's index, as `llvm-nm --print-armap` reads it: each symbol
# and the member defining it; empty without llvm-nm.
_archive_map(archive: Path): String {
    var nm = process.find_executable("llvm-nm");
    if (!nm.is_value()) {
        nm = process.find_executable($"llvm-nm-{driver.LLVM_MAJOR}");
    }
    if (!nm.is_value()) {
        return "";
    }
    return _run(process.Command(nm.value().to_string()).argument("--print-armap").argument(archive.to_string()));
}

# A static library for another platform needs no system root: the
# compiler writes the archive in its format, with the index of its
# members' symbols, which the platform's linkers and LLVM's tools read.
[Test]
writes_each_platforms_archive_with_its_index() {
    var folder = TempFolder("c_archives");
    var root = folder.path;
    for (var (
        triple,
        file,
        add
    ) in [
        ("x86_64-unknown-linux-gnu", "libadd.a", "add"),
        ("aarch64-linux-android", "libadd.a", "add"),
        ("aarch64-apple-darwin", "libadd.a", "_add"),
        ("aarch64-apple-ios", "libadd.a", "_add"),
        ("x86_64-pc-windows-msvc", "add.lib", "add"),
        ("aarch64-pc-windows-msvc", "add.lib", "add")
    ]) {
        var target = link.Target.parse(triple).value();
        expect_equal(driver.library_file_name(driver.LibraryKind.Static, "add", target), file);
        var dir = root.join(Path(triple));
        Directory.create_all(dir);
        var archive = dir.join(Path(file));
        var options = driver.BuildOptions(archive, dir.join(Path("build")));
        options.library = Optional<driver.LibraryKind>.Value(driver.LibraryKind.Static);
        _build(dir, _NO_RUNTIME_LIBRARY, options, false, target);
        var bytes = File.read_bytes(archive).value();
        expect_true(bytes.count > 8);
        expect_true(
            File.read_to_string(dir.join(Path("add.h"))).value().contains("int32_t times(int32_t a, int32_t b);")
        );
        var map = _archive_map(archive);
        if (!map.is_empty) {
            if (!map.contains($"{add} in ")) {
                print($"{triple}: {map}");
            }
            expect_true(map.contains($"{add} in "));
        }
    }
}

# The ELF objects the compiler emits list their definitions, not what they
# use.
[Test]
reads_the_symbols_an_object_defines() {
    var folder = TempFolder("c_symbols");
    var root = folder.path;
    var target = link.Target.parse("x86_64-unknown-linux-gnu").value();
    var archive = root.join(Path("libadd.a"));
    var options = driver.BuildOptions(archive, root.join(Path("build")));
    options.library = Optional<driver.LibraryKind>.Value(driver.LibraryKind.Static);
    _build(
        root,
        "extern int abs(int x);\n[Export]\nmagnitude(x: int): int {\n    return abs(x);\n}\n",
        options,
        false,
        target
    );
    # The GNU index after the magic and its header: a big-endian count,
    # the members' offsets, then the names.
    var bytes = File.read_bytes(archive).value();
    ulong count = 0;
    for (var i in 68..72) {
        count = (count << 8) | (bytes[i] as ulong);
    }
    var names = Array<String>();
    var at = 72 + 4 * count;
    var name = Array<u8>();
    while (names.count < count) {
        if (bytes[at] == 0) {
            names.append(Utf8.decode_lossy(name));
            name = Array<u8>();
        } else {
            name.append(bytes[at]);
        }
        at += 1;
    }
    expect_true(names.contains("magnitude"));
    expect_false(names.contains("abs"));
}

# Two files, one calling the other: with link-time optimization the
# program is optimized as one module, and runs.
[Test]
links_an_optimized_program_as_one_module() {
    var folder = TempFolder("lto");
    var root = folder.path;
    File.write_text(root.join(Path("util.pep")), "export triple(x: int): int {\n    return x * 3;\n}\n");
    File.write_text(root.join(Path("main.pep")), "import \"util\";\nmain(): int {\n    return triple(14) - 42;\n}\n");
    var setup = link.Setup();
    setup.runtime = false;
    setup.import_dirs.append(root);
    for (var cached in [false, true, true]) {
        var program = link.load_program(root.join(Path("main.pep")), setup);
        expect_true(program.is_ok());
        var output = root.join(Path("main"));
        var options = driver.BuildOptions(output, root.join(Path("build")));
        options.opt_level = 2;
        options.lto = true;
        options.in_process = true;
        if (cached) {
            options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
        }
        var built = driver.build(program.value(), options);
        if (built.is_err()) {
            print(built.error());
        }
        expect_true(built.is_ok());
        var ran = process.Command(output.to_string()).spawn();
        expect_true(ran.is_ok() and ran.value().wait().value().success());
        File.remove(output);
    }
    # The cache kept each part as bitcode.
    expect_true(_holds(root.join(Path("cache")), "0.bc"));
}

# Whether `dir`, or a folder in it, holds a file named `name`.
_holds(dir: Path, name: String): bool {
    var opened = Directory.open(dir);
    if (opened.is_err()) {
        return false;
    }
    for (var entry in opened.value().entries().value()) {
        if (entry.name == name or (entry.path.is_directory() and _holds(entry.path, name))) {
            return true;
        }
    }
    return false;
}

# The CPU each `-m` option chooses, as clang chooses it.
[Test]
the_cpu_is_clangs_default_unless_an_option_names_one() {
    var x86 = "x86_64-unknown-linux-gnu";
    var arm = "aarch64-unknown-linux-gnu";
    var default = codegen.Cpu.from_options(x86, Array<String>()).value();
    expect_equal(default.name, "x86-64");
    expect_equal(default.tune, "generic");
    expect_equal(default.key(), "x86-64@generic");
    var v3 = codegen.Cpu.from_options(x86, ["arch=x86-64-v3", "no-avx2", "tune=znver4"]).value();
    expect_equal(v3.name, "x86-64-v3");
    expect_equal(v3.features, "-avx2");
    expect_equal(v3.tune, "znver4");
    expect_equal(v3.key(), "x86-64-v3-avx2@znver4");
    var error = codegen.Cpu.from_options(x86, ["cpu=skylake"]).error();
    expect_true(error.starts_with("unsupported option '-mcpu=' for target"));
    var m2 = codegen.Cpu.from_options(arm, ["cpu=apple-m2+nocrypto"]).value();
    expect_equal(m2.name, "apple-m2");
    expect_equal(m2.features, "-crypto");
    var arch = codegen.Cpu.from_options(arm, ["arch=armv8.2-a+crypto"]).value();
    expect_equal(arch.name, "generic");
    expect_equal(arch.features, "+v8.2a,+crypto");
    expect_true(codegen.Cpu.from_options(arm, ["arch=x86-64-v3"]).error().contains("invalid arch name"));
    expect_true(
        codegen.Cpu.from_options("wasm32-wasip1", ["arch=generic"]).error().starts_with("unsupported option '-march='")
    );
    expect_equal(codegen.Cpu.from_options(x86, ["arch="]).error(), "missing value for '-march='");
    expect_equal(codegen.Cpu.from_options(x86, ["foo=bar"]).error(), "unknown argument '-mfoo=bar'");
    var android = codegen.Cpu.from_options("x86_64-linux-android30", ["avx2"]).value();
    expect_equal(android.features, "+sse4.2,+popcnt,+cx16,+avx2");
    var host = llvm.default_triple();
    var native = codegen.Cpu.from_options(host, [host.starts_with("x86_64") ? "arch=native" : "cpu=native"]).value();
    expect_equal(native.name, llvm.host_cpu());
    # `native` names this machine, which another architecture's code
    # cannot run on.
    var other = host.starts_with("x86_64") ? arm : x86;
    expect_true(codegen.Cpu.from_options(other, ["tune=native"]).error().contains("cannot run on"));
}

# The CPU is part of each unit's key, and every function carries it: a
# build for another CPU compiles every unit again.
[Test]
another_cpu_misses_the_cache_and_marks_every_function() {
    var folder = TempFolder("cpu_key");
    var root = folder.path;
    File.write_text(root.join(Path("main.pep")), "[Export]\nanswer(): int {\n    return 42;\n}\n");
    var setup = link.Setup();
    setup.runtime = false;
    var target = link.Target.parse("x86_64-unknown-linux-gnu").value();
    setup.target = target;
    var misses = Array<ulong>();
    for (var machine in [Array<String>(), ["arch=x86-64-v2", "popcnt"], Array<String>()]) {
        var program = link.load_program(root.join(Path("main.pep")), setup);
        expect_true(program.is_ok());
        var options = driver.BuildOptions(root.join(Path("libmain.a")), root.join(Path("build")));
        options.library = Optional<driver.LibraryKind>.Value(driver.LibraryKind.Static);
        options.cpu = Optional<codegen.Cpu>.Value(codegen.Cpu.from_options(target.triple, machine).value());
        options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
        options.in_process = true;
        var built = driver.build(program.value(), options);
        expect_true(built.is_ok());
        misses.append(built.value().misses.count + (built.value().unchanged ? 100 : 0));
    }
    # The first build and the one for x86-64-v2 compile; the third finds
    # the first's objects, and the program they make is the first's.
    expect_true(misses[1] > 0);
    expect_equal(misses[2], 0);
    var ir = codegen.Cpu.from_options("x86_64-unknown-linux-gnu", ["arch=x86-64-v2", "popcnt"]).value();
    expect_equal(ir.key(), "x86-64-v2+popcnt");
}
