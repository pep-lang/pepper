# The command line as `pep-build` reads it, run on the compiler under test
# (`pep-build` beside the test or on the PATH, as `scripts/pepper-tests.sh`
# puts the stage-1 build there): `--help` lists every option;
# `--emit-steps`, `--emit-ast`, `--emit-llvm`, `-T passes`, `-m`, `--lib`
# (an iOS `.xcframework` and Swift package too),
# `--lto`, `--verify-cache` and `--MSVC` do what they document; a cached
# build of an entry file inside a module's folder links; `-o` makes the
# output's missing folders.

import [Directory, File, Path] from io;
import os;
import process;
import [TempFolder] from testing;
import [expect_contains, expect_exit] from tool_testing;
import toolchain;

const _PROGRAM = "square(x: int): int {\n    return x * x;\n}\n\nmain(): int {\n    var total = 0;\n    for (var i in 0..4) {\n        total += square(i);\n    }\n    return total - 14;\n}\n";

const _LIBRARY = "[Export]\nadd(a: int, b: int): int {\n    return a + b;\n}\n";

# The compiler under test.
_compiler(): Path {
    var found = process.find_companion("pep-build");
    expect_true(found.is_value());
    return found.value();
}

# Runs the compiler with `arguments` in `folder`, and returns how it ended
# and what it printed.
_pep_build(folder: Path, arguments: String[]): process.Output {
    var command = process.Command(_compiler().to_string());
    for (var argument in arguments) {
        command.argument(argument);
    }
    command.working_directory(folder);
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var ran = command.run();
    expect_true(ran.is_ok());
    # Windows writes a line ending as `\r\n`.
    var output = ran.value();
    return process.Output(output.status, output.stdout.replace("\r\n", "\n"), output.stderr.replace("\r\n", "\n"));
}

# Runs the compiler, which must succeed, and returns what it printed on
# standard output.
_succeeds(folder: Path, arguments: String[]): process.Output {
    var ran = _pep_build(folder, arguments);
    if (!ran.status.success()) {
        print(ran.stdout + ran.stderr);
    }
    expect_true(ran.status.success());
    return ran;
}

# `main.pep` holding `source` in a new folder named for the test.
_program(name: String, source: String): TempFolder {
    var folder = TempFolder(name);
    File.write_text(folder.path.join(Path("main.pep")), source);
    return folder;
}

# The exit code of a run.
_code(ran: process.Output): int {
    var code = ran.status.code();
    return code.is_value() ? code.value() : -1;
}

[Test]
help_lists_every_option_of_the_rust_compiler() {
    var folder = TempFolder("options_help");
    var help = _succeeds(folder.path, ["--help"]).stdout;
    for (var option in [
        "-I <DIR>",
        "--import <NAME>",
        "-l <LIB>",
        "-L <DIR>",
        "-D <NAME[=VALUE]>",
        "-o <OUT>",
        "--lib <KIND>",
        "--build <DIR>",
        "-O[<LEVEL>]",
        "--lto <MODE>",
        "--target <TRIPLE>",
        "--sysroot <DIR>",
        "-m <OPTION>",
        "--no-runtime-checks <CHECKS>",
        "--test",
        "--emit-llvm",
        "--emit-static[=<MODE>]",
        "-g, --emit-debug",
        "--debug-static <VIEW>",
        "--frame-pointers",
        "-v, --verbose",
        "--no-runtime",
        "--emit-ast[=<FORMAT>]",
        "--emit-linked",
        "--emit-checked",
        "--emit-model",
        "--emit-model-step <N>",
        "--emit-steps",
        "-T <CHAN>",
        "--Tall",
        "--no-cache",
        "--cache <DIR>",
        "--verify-cache",
        "--no-verify-cache",
        "--MSVC",
        "--compile-part <DIR>",
        "--part <N=OBJECT>",
        "--compilation-unit-worker <DIR>",
        "-h, --help",
        "-V, --version"
    ]) {
        if (!help.contains(option)) {
            print($"--help leaves out {option}");
        }
        expect_true(help.contains(option));
    }
    for (var values in [
        "[possible values: static, shared, xcframework, swift-package, aar]",
        "[possible values: full, off]",
        "[possible values: expand, keep]",
        "[possible values: source, expanded]",
        "[possible values: text, json]"
    ]) {
        expect_true(help.contains(values));
    }
    expect_false(help.contains("not supported"));
    # An option it does not know is still a usage error.
    var unknown = _pep_build(folder.path, ["--no-such-option", "main.pep"]);
    expect_equal(_code(unknown), 2);
    expect_true(unknown.stderr.contains("pep-build: error: unknown option '--no-such-option'"));
    # `-O` takes its level only attached, so the file after it is the entry.
    var program = _program("options_level", _PROGRAM);
    _succeeds(program.path, ["-O", "main.pep", "-o", "main", "--build", "build", "--no-cache"]);
    var level = _pep_build(program.path, ["-O7", "main.pep"]);
    expect_equal(_code(level), 2);
    expect_true(level.stderr.contains("invalid value '7' for '-O': expected 0, 1, 2 or 3"));
    # `--part` belongs to `--compile-part`, which needs one.
    for (var arguments in [["--part", "0=a.o"], ["--compile-part", "parts"]]) {
        var ran = _pep_build(folder.path, arguments);
        expect_equal(_code(ran), 2);
        expect_true(ran.stderr.contains("needs"));
    }
}

[Test]
emit_steps_names_each_sema_step_in_order() {
    var folder = _program("options_steps", _PROGRAM);
    var steps = _succeeds(folder.path, ["--emit-steps", "main.pep"]).stdout.trim().split("\n");
    expect_true(steps.count > 39);
    expect_equal(steps[0], "apply_platform_filters(module)");
    expect_equal(steps[1], "struct_body::derive_equatable(module)");
    expect_equal(steps[6], "static_blocks::check_attributes(module)");
    expect_equal(steps[38], "resolve_operators(module)");
    expect_equal(steps[39], "gather_generics(module)");
    expect_equal(steps[steps.count - 1], "static_strings::share_string_literals(module)");
    # With `--emit-model-step N`, the first N.
    var first = _succeeds(
        folder.path, ["--emit-steps", "--emit-model-step", "7", "main.pep"]
    ).stdout.trim().split("\n");
    expect_equal(first.count, 7);
    expect_equal(first[6], steps[6]);
}

[Test]
emit_ast_prints_the_tree_as_text_or_json() {
    var folder = _program(
        "options_ast",
        "import io;\n\n[Inline]\nf(x: int, y: int = 2): int {\n    if (x > 0) {\n        return x * y + 1;\n    }\n    var g = (a: int) => a - 1;\n    return g(x);\n}\n\nstruct P {\n    var x: int = 0;\n}\n"
    );
    var expected = "import io;\n[Inline] f(var x: int, var y: int = 2): int {\n    if (x > 0) {\n    return ((x * y) + 1);\n}\n    var g: __auto = (a: int) => (a - 1);\n    return g(x);\n}\nstruct P {\n    var x: int = 0\n}";
    expect_equal(_succeeds(folder.path, ["--emit-ast", "main.pep"]).stdout.trim(), expected);
    expect_equal(_succeeds(folder.path, ["--emit-ast=text", "main.pep"]).stdout.trim(), expected);
    var json = _succeeds(folder.path, ["--emit-ast=json", "main.pep"]).stdout;
    expect_true(json.starts_with("{\"imports\":"));
    var wrong = _pep_build(folder.path, ["--emit-ast=yaml", "main.pep"]);
    expect_equal(_code(wrong), 2);
    expect_true(wrong.stderr.contains("invalid value 'yaml' for '--emit-ast': expected 'text' or 'json'"));
}

[Test]
emit_llvm_writes_the_ir_optimized_at_the_level() {
    var folder = _program("options_llvm", _PROGRAM);
    var build = folder.path.join(Path("build"));
    var ran = _succeeds(folder.path, ["--emit-llvm", "-O0", "main.pep", "--build", build.to_string(), "--no-cache"]);
    expect_equal(ran.stdout, "");
    var plain = File.read_to_string(build.join(Path("main.ll")));
    expect_true(plain.is_ok());
    expect_true(plain.value().contains("define"));
    # `-O0` above, whatever `PEPPER_OPT_LEVEL` says. Named for `-o`, and optimized: fewer locals stay on the stack.
    _succeeds(
        folder.path, ["--emit-llvm", "-O2", "main.pep", "-o", "out/prog", "--build", build.to_string(), "--no-cache"]
    );
    var optimized = File.read_to_string(build.join(Path("prog.ll")));
    expect_true(optimized.is_ok());
    expect_true(optimized.value() != plain.value());
    expect_true(optimized.value().split("alloca").count < plain.value().split("alloca").count);
}

[Test]
emit_llvm_names_an_extern_by_its_c_symbol() {
    # Externs bound to `abs` and `exit`, which Pepper functions are named
    # after (pepper#100): the IR names each extern by its C symbol.
    var source = File.read_to_string(Path("compiler").join("testdata").join("extern_named_like_function.pep"));
    var folder = _program("options_llvm_extern", source.value());
    var build = folder.path.join(Path("build"));
    _succeeds(folder.path, ["--emit-llvm", "-O0", "main.pep", "--build", build.to_string(), "--no-cache"]);
    var ir = File.read_to_string(build.join(Path("main.ll"))).value();
    expect_false(ir.contains("__extern."));
    expect_true(ir.contains(" @abs(i32"));
    expect_true(ir.contains(" @exit(i32"));
    expect_true(ir.contains("define i32 @_Pabs("));
}

[Test]
constructors_zero_their_object_inline() {
    # A constructor's allocation has a constant size, so it skips the
    # runtime's zeroing and zeroes the object inline, where LLVM can see it.
    var folder = _program(
        "options_zeroing",
        "struct Point {\n    var x: long;\n    var y: long;\n\n    construct(x: long, y: long) {\n        this.x = x;\n        this.y = y;\n    }\n}\n\nmain(): int {\n    var p = Point(3, 4);\n    return (p.x + p.y - 7) as int;\n}\n"
    );
    var build = folder.path.join(Path("build"));
    _succeeds(folder.path, ["--emit-llvm", "-O0", "main.pep", "--build", build.to_string(), "--no-cache"]);
    var ir = File.read_to_string(build.join(Path("main.ll")));
    expect_true(ir.is_ok());
    var start = ir.value().find("define ptr @Point(");
    expect_true(start >= 0);
    var body = ir.value().substr_bytes(start as ulong, ir.value().size - start as ulong);
    body = body.substr_bytes(0, body.find("\n}\n") as ulong);
    expect_true(body.contains("call ptr @_pep_malloc_uninit(i64 "));
    expect_true(body.contains("call void @llvm.memset"));
    expect_false(body.contains("@_pep_malloc("));
}

[Test]
trace_passes_prints_each_sema_pass_slowest_first() {
    var folder = _program("options_passes", _PROGRAM);
    var ran = _succeeds(
        folder.path, ["-T", "passes", "main.pep", "-o", "main", "--build", "build", "--cache", "cache"]
    );
    var lines = Array<String>();
    for (var line in ran.stderr.split("\n")) {
        if (line.starts_with("pass: ")) {
            lines.append(line);
        }
    }
    expect_true(lines.count > 10);
    expect_true(ran.stderr.contains("x resolve_implicit_types\n"));
    expect_true(ran.stderr.contains("x value_structs::check\n"));
    # `pass: <ms> ms <runs>x <pass>`, the slowest first.
    double before = 1e300;
    for (var line in lines) {
        var ms = double.parse(line.substr_bytes(6, line.find(" ms") as ulong - 6).trim());
        expect_true(ms.is_value());
        expect_true(ms.value() <= before);
        before = ms.value();
    }
    # `--Tall` includes it.
    var all = _succeeds(folder.path, ["--Tall", "main.pep", "-o", "main", "--build", "build", "--no-cache"]);
    expect_true(all.stderr.contains("pass: "));
    expect_true(all.stderr.contains("time: "));
}

[Test]
m_options_choose_the_cpu_as_clang_does() {
    # For x86-64 whatever the machine: the IR needs no system libraries.
    var folder = _program("options_cpu", _PROGRAM);
    _succeeds(
        folder.path,
        [
            "--emit-llvm",
            "--target",
            "x86_64-unknown-linux-gnu",
            "-march=x86-64-v3",
            "-mno-avx2",
            "main.pep",
            "--build",
            "build",
            "--no-cache"
        ]
    );
    var ir = File.read_to_string(folder.path.join(Path("build")).join(Path("main.ll"))).value();
    expect_true(ir.contains("\"target-cpu\"=\"x86-64-v3\""));
    expect_true(ir.contains("-avx2"));
    # `-m <option>` is `-m<option>`.
    _succeeds(
        folder.path,
        [
            "--emit-llvm",
            "--target",
            "x86_64-unknown-linux-gnu",
            "-m",
            "arch=znver4",
            "main.pep",
            "--build",
            "build",
            "--no-cache"
        ]
    );
    ir = File.read_to_string(folder.path.join(Path("build")).join(Path("main.ll"))).value();
    expect_true(ir.contains("\"target-cpu\"=\"znver4\""));
    var wrong = _pep_build(
        folder.path, ["--target", "x86_64-unknown-linux-gnu", "-mcpu=generic", "main.pep", "--no-cache"]
    );
    expect_equal(_code(wrong), 1);
    expect_true(wrong.stderr.contains("unsupported option '-mcpu=' for target"));
}

[Test]
lib_and_lto_are_checked_and_name_their_output() {
    var folder = _program("options_lib", _LIBRARY);
    _succeeds(folder.path, ["--lib", "static", "main.pep", "--build", "build", "--no-cache"]);
    expect_true(
        folder.path.join(Path(os.system_os() == os.OperatingSystem.Windows ? "main.lib" : "libmain.a")).is_file()
    );
    expect_true(folder.path.join(Path("main.h")).is_file());
    expect_true(File.read_to_string(folder.path.join(Path("main.h"))).value().contains("add(int32_t a, int32_t b);"));
    for (var (
        arguments,
        code,
        says
    ) in [
        (["--lib", "dynamic", "main.pep"], 2, "invalid value 'dynamic' for '--lib': expected 'static', 'shared', "),
        (["--lib=static", "--test", "main.pep"], 2, "'--test' cannot be used with '--lib'"),
        (["--lto=thin", "main.pep"], 2, "invalid value 'thin' for '--lto': expected 'full' or 'off'"),
        (["--lto=full", "-O0", "main.pep"], 1, "'--lto=full' needs optimization: add '-O'")
    ]) {
        var ran = _pep_build(folder.path, arguments);
        expect_equal(_code(ran), code);
        if (!ran.stderr.contains(says)) {
            print(ran.stderr);
        }
        expect_true(ran.stderr.contains(says));
    }
    # `--lto=off` builds at `-O2` too.
    var program = _program("options_lto", _PROGRAM);
    for (var lto in ["--lto=off", "--lto=full"]) {
        _succeeds(program.path, ["-O2", lto, "main.pep", "-o", "main", "--build", "build", "--no-cache"]);
        var ran = process.Command(program.path.join(Path("main")).to_string()).run();
        expect_true(ran.is_ok() and ran.value().status.success());
    }
}

# `--lib swift-package`: a Swift package around an iOS `.xcframework`,
# built on any system, whose simulator library is a universal file of two
# archives; and the output names and options it refuses.
[Test]
lib_swift_package_writes_an_xcframework_for_ios() {
    var folder = _program("options_xcframework", _LIBRARY);
    _succeeds(folder.path, ["--lib", "swift-package", "main.pep", "-o", "Adder", "--build", "build"]);
    var package = folder.path.join(Path("Adder"));
    var framework = package.join(Path("Adder.xcframework"));
    expect_contains(
        File.read_to_string(package.join(Path("Package.swift"))).value(),
        ".binaryTarget(name: \"Adder\", path: \"Adder.xcframework\")"
    );
    expect_contains(
        File.read_to_string(framework.join(Path("Info.plist"))).value(), "<string>ios-arm64_x86_64-simulator</string>"
    );
    for (var slice in ["ios-arm64", "ios-arm64_x86_64-simulator"]) {
        var headers = framework.join(Path(slice)).join(Path("Headers"));
        expect_contains(File.read_to_string(headers.join(Path("Adder.h"))).value(), "add(int32_t a, int32_t b);");
        expect_contains(File.read_to_string(headers.join(Path("module.modulemap"))).value(), "module Adder {");
    }
    var device = File.read_bytes(framework.join(Path("ios-arm64")).join(Path("libAdder.a"))).value();
    expect_true(_starts_with(device, 0, "!<arch>\n".bytes()));
    # FAT_MAGIC and two architectures, arm64 first, its archive 16 KiB in.
    var simulator = File.read_bytes(
        framework.join(Path("ios-arm64_x86_64-simulator")).join(Path("libAdder.a"))
    ).value();
    expect_true(
        _starts_with(simulator, 0, [0xca as u8, 0xfe, 0xba, 0xbe, 0, 0, 0, 2, 1, 0, 0, 0x0c, 0, 0, 0, 0, 0, 0, 0x40, 0])
    );
    expect_true(_starts_with(simulator, 0x4000, "!<arch>\n".bytes()));
    for (var (
        arguments,
        code,
        says
    ) in [
        (
            ["--lib", "xcframework", "--target", "aarch64-apple-ios", "main.pep"],
            2,
            "'--target' cannot be used with '--lib xcframework'"
        ),
        (["--lib", "xcframework", "main.pep", "-o", "my-adder.xcframework"], 1, "does not name a Swift module"),
        (["--lib", "aar", "main.pep", "-o", "my-adder.aar"], 1, "does not name an Android library"),
        (
            ["--lib", "aar", "--target", "x86_64-linux-android", "main.pep"],
            2,
            "which build for every iOS or Android target"
        ),
        (["--lib", "xcframework", "main.pep", "-o", "Adder"], 2, "must end in '.xcframework'"),
        (["--lib", "swift-package", "--emit-llvm", "main.pep"], 2, "the --emit options cannot be used")
    ]) {
        var ran = _pep_build(folder.path, arguments);
        expect_equal(_code(ran), code);
        expect_contains(ran.stderr, says);
    }
}

# Whether `bytes` holds `prefix` at `at`.
_starts_with(bytes: u8[], at: ulong, prefix: u8[]): bool {
    if (at + prefix.count > bytes.count) {
        return false;
    }
    for (var i in 0..prefix.count) {
        if (bytes[at + i] != prefix[i]) {
            return false;
        }
    }
    return true;
}

# `--entry` starts the program in the function it names, with the program's
# arguments when it takes them, and leaves `main` out.
[Test]
entry_names_the_function_the_program_starts_in() {
    var folder = _program(
        "options_entry",
        "main(): int {\n    return 7;\n}\n\nstart(args: String[]) {\n    print($\"start {args.count}\");\n}\n\nquiet(): int {\n    return 3;\n}\n"
    );
    var program = folder.path.join(Path("main")).to_string();
    _succeeds(folder.path, ["--entry", "start", "main.pep", "-o", "main", "--build", "build", "--no-cache"]);
    var started = process.Command(program).argument("a").stdout(process.Stream.Pipe).run();
    expect_true(started.is_ok());
    expect_equal(_code(started.value()), 0);
    expect_equal(started.value().stdout.trim(), "start 2");
    _succeeds(folder.path, ["--entry=quiet", "main.pep", "-o", "main", "--build", "build", "--no-cache"]);
    var quiet = process.Command(program).run();
    expect_true(quiet.is_ok());
    expect_equal(_code(quiet.value()), 3);
    for (var (
        arguments,
        code,
        says
    ) in [
        (
            ["--entry", "nope", "main.pep", "--no-cache"],
            1,
            "no function named 'nope' in 'main.pep' to start the program in"
        ),
        (["--entry", "start", "--test", "main.pep"], 2, "'--entry' cannot be used with '--test'")
    ]) {
        var ran = _pep_build(folder.path, arguments);
        expect_equal(_code(ran), code);
        if (!ran.stderr.contains(says)) {
            print(ran.stderr);
        }
        expect_true(ran.stderr.contains(says));
    }
}

[Test]
verify_cache_finds_a_cached_object_that_differs() {
    var folder = _program("options_verify", _PROGRAM);
    var arguments = ["main.pep", "-o", "main", "--build", "build", "--cache", "cache", "--verify-cache"];
    # A first build, then one that reuses everything: both check out.
    _succeeds(folder.path, arguments);
    _succeeds(folder.path, arguments);
    # An object the cache holds, changed (bytes past its end, which the
    # linker ignores): the next check fails, naming it.
    var objects = Array<Path>();
    _objects(folder.path.join(Path("cache")), objects);
    expect_true(!objects.is_empty);
    var bytes = File.read_bytes(objects[0]).value();
    bytes.append(0);
    File.write_bytes(objects[0], bytes);
    var ran = _pep_build(folder.path, arguments);
    expect_equal(_code(ran), 1);
    expect_true(ran.stderr.contains("differ from the code generated for them again"));
    # Without `--verify-cache` the build trusts the cache.
    _succeeds(folder.path, ["main.pep", "-o", "main", "--build", "build", "--cache", "cache"]);
    # `PEPPER_CACHE_VERIFY` checks too, unless `--no-verify-cache`.
    var command = process.Command(_compiler().to_string());
    for (var argument in ["main.pep", "-o", "main", "--build", "build", "--cache", "cache"]) {
        command.argument(argument);
    }
    command.working_directory(folder.path).environment("PEPPER_CACHE_VERIFY", "1");
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var by_variable = command.run();
    expect_true(by_variable.is_ok());
    expect_equal(_code(by_variable.value()), 1);
    command.argument("--no-verify-cache");
    var unchecked = command.run();
    expect_true(unchecked.is_ok() and unchecked.value().status.success());
    var both = _pep_build(folder.path, ["main.pep", "--verify-cache", "--no-verify-cache"]);
    expect_equal(_code(both), 2);
    expect_true(both.stderr.contains("'--verify-cache' cannot be used with '--no-verify-cache'"));
}

# An entry file in a module's folder (a package's example) brings in the
# module's files, which come before it in namespace order. Built from the
# cache, cold and warm, its compilation unit is still the program's own,
# defining `main`, and the module's files it never reads are not linked.
[Test]
builds_an_entry_inside_a_modules_folder_with_the_cache() {
    var folder = TempFolder("options_module_entry");
    var module = folder.path.join(Path("pkg"));
    Directory.create_all(module.join(Path("app")));
    File.write_text(module.join(Path("module.pep")), "export * from \"extra\";\n");
    # Defined nowhere: linking `extra.pep`'s object fails.
    File.write_text(
        module.join(Path("extra.pep")),
        "extern int _pepper_missing_839();\n\nexport extra(): int {\n    return _pepper_missing_839();\n}\n"
    );
    File.write_text(module.join(Path("app")).join(Path("main.pep")), _PROGRAM);
    # `-o` names the file as given, so it carries the platform's suffix.
    var program = "main" + toolchain.executable_suffix();
    for (var _ in 0..2) {
        var command = process.Command(_compiler().to_string());
        command.arguments(["pkg/app/main.pep", "-o", program, "--build", "build", "--cache", "cache"]);
        # Compilation unit workers, which compile each unit's object, even on
        # one CPU.
        command.working_directory(folder.path).environment("PEPC_COMPILATION_UNIT_JOBS", "2");
        command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
        var built = command.run();
        expect_true(built.is_ok());
        if (!built.value().status.success()) {
            print(built.value().stderr);
        }
        expect_true(built.value().status.success());
        var ran = process.Command(folder.path.join(Path(program)).to_string()).run();
        expect_true(ran.is_ok() and ran.value().status.success());
    }
}

# A build in compilation unit workers links after a whole-program build
# filled the cache: it compiled every body itself, rather than skipping the
# bodies whose whole-program objects the cache held and linking none of them.
[Test]
builds_in_compilation_units_after_a_whole_program_build_with_the_cache() {
    var folder = _program(
        "options_whole_then_units", "import geo;\n\nmain(): int {\n    return geo.area(2, 3) - 6;\n}\n"
    );
    Directory.create_all(folder.path.join(Path("geo")));
    File.write_text(
        folder.path.join(Path("geo")).join(Path("module.pep")),
        "export area(w: int, h: int): int {\n    return w * h;\n}\n"
    );
    for (var whole in [true, false]) {
        var program = (whole ? "whole" : "units") + toolchain.executable_suffix();
        var command = process.Command(_compiler().to_string());
        command.arguments(["main.pep", "-I", ".", "-o", program, "--build", program + ".build", "--cache", "cache"]);
        command.working_directory(folder.path).stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
        if (whole) {
            command.environment("PEPC_NO_COMPILATION_UNITS", "1");
        } else {
            command.remove_environment("PEPC_NO_COMPILATION_UNITS").environment("PEPC_COMPILATION_UNIT_JOBS", "2");
        }
        var built = command.run();
        expect_true(built.is_ok());
        if (!built.value().status.success()) {
            print(built.value().stderr);
        }
        expect_true(built.value().status.success());
        var ran = process.Command(folder.path.join(Path(program)).to_string()).run();
        expect_true(ran.is_ok() and ran.value().status.success());
    }
}

# A program of several compilation units with location strings (an index's
# bounds check) builds with link-time optimization and runs: a part that
# only declares a location string once kept it in a comdat, and the linked
# program did not verify.
[Test]
lto_links_compilation_units_with_location_strings() {
    var folder = _program(
        "options_lto_units",
        "import \"items\";\n\nmain(): int {\n    var made = items(3);\n    return first(made) + made[2].value - 2;\n}\n"
    );
    File.write_text(
        folder.path.join(Path("items.pep")),
        "export struct Item {\n    var value: int;\n\n    construct(value: int) {\n        this.value = value;\n    }\n}\n\nexport items(n: int): Item[] {\n    var made = Array<Item>();\n    for (var i in 0..n) {\n        made.append(Item(i));\n    }\n    return made;\n}\n\nexport first(items: Item[]): int {\n    return items[0].value;\n}\n"
    );
    var program = "main" + toolchain.executable_suffix();
    var command = process.Command(_compiler().to_string());
    command.arguments(["-O2", "--lto=full", "main.pep", "-o", program, "--build", "build", "--cache", "cache"]);
    command.working_directory(folder.path).environment("PEPC_COMPILATION_UNIT_JOBS", "2");
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var built = command.run();
    expect_true(built.is_ok());
    if (!built.value().status.success()) {
        print(built.value().stderr);
    }
    expect_true(built.value().status.success());
    var ran = process.Command(folder.path.join(Path(program)).to_string()).run();
    expect_true(ran.is_ok() and ran.value().status.success());
}

# A compilation unit worker reports the linking errors of the files it
# checks, as the build does: a missing import in a module reached through
# `-I` is located at the import, not at the first use of its name (#62).
[Test]
workers_report_a_missing_import_in_an_included_module() {
    var folder = _program("options_worker_import", "import lib;\n\nmain(): int {\n    return lib.S.make();\n}\n");
    Directory.create_all(folder.path.join(Path("lib")));
    File.write_text(
        folder.path.join(Path("lib")).join(Path("module.pep")),
        "import nope;\n\nexport struct S {\n    static make(): int {\n        return nope.f();\n    }\n}\n"
    );
    var command = process.Command(_compiler().to_string());
    command.arguments(["-I", ".", "main.pep", "-o", "main", "--build", "build", "--cache", "cache"]);
    command.working_directory(folder.path).environment("PEPC_COMPILATION_UNIT_JOBS", "2");
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var built = command.run();
    expect_true(built.is_ok());
    expect_false(built.value().status.success());
    expect_true(built.value().stderr.contains("module.pep:1:8: error: cannot find module 'nope'"));
    expect_false(built.value().stderr.contains("undeclared identifier"));
}

# A compilation unit's cached object only declares the instantiations the
# objects below it define. A body edit below that stops using one
# (`Array<Foo>`) leaves the keys above alone, so the objects above, a
# worker's (`x.pep`) and the last's (`main.pep`), are compiled again rather
# than linked without it: they failed on undefined symbols (#24).
[Test]
rebuilds_the_objects_that_need_what_an_edit_below_drops() {
    var folder = _program(
        "options_below_drops",
        "import \"foo\";\nimport \"l\";\nimport \"x\";\n\nmain(): int {\n    var a = Array<Foo>();\n    a.append(Foo(3));\n    return a.count as int + x_value() - 4;\n}\n"
    );
    File.write_text(
        folder.path.join(Path("foo.pep")),
        "export struct Foo {\n    var v: int = 0;\n\n    construct(v: int) {\n        this.v = v;\n    }\n}\n"
    );
    File.write_text(
        folder.path.join(Path("x.pep")),
        "import \"foo\";\nimport \"l\";\n\nexport x_value(): int {\n    var a = Array<Foo>();\n    a.append(Foo(2));\n    return a.count as int + l_count() + 0;\n}\n"
    );
    var uses = "import \"foo\";\n\nexport l_count(): int {\n    var a = Array<Foo>();\n    a.append(Foo(1));\n    return a.count as int + 1;\n}\n";
    var drops = "import \"foo\";\n\nexport l_count(): int {\n    return 2;\n}\n";
    var program = "main" + toolchain.executable_suffix();
    for (var source in [uses, drops, uses, drops]) {
        File.write_text(folder.path.join(Path("l.pep")), source);
        var command = process.Command(_compiler().to_string());
        command.arguments(["main.pep", "-o", program, "--build", "build", "--cache", "cache"]);
        # Compilation unit workers, which compile each unit's object, even on
        # one CPU.
        command.working_directory(folder.path).environment("PEPC_COMPILATION_UNIT_JOBS", "2");
        command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
        var built = command.run();
        expect_true(built.is_ok());
        if (!built.value().status.success()) {
            print(built.value().stdout + built.value().stderr);
        }
        expect_true(built.value().status.success());
        var ran = process.Command(folder.path.join(Path(program)).to_string()).run();
        expect_true(ran.is_ok() and ran.value().status.success());
    }
}

# Every object (`.o`, `.obj`, `.bc`) under `folder`.
_objects(folder: Path, out: Path[]) {
    var opened = Directory.open(folder);
    if (opened.is_err()) {
        return;
    }
    for (var entry in opened.value().entries().value()) {
        if (entry.is_directory) {
            _objects(entry.path, out);
        } else if (entry.name.ends_with(".o") or entry.name.ends_with(".obj") or entry.name.ends_with(".bc")) {
            out.append(entry.path);
        }
    }
}

[Test]
msvc_is_an_error_as_in_the_rust_compiler() {
    var folder = _program("options_msvc", _PROGRAM);
    var ran = _pep_build(folder.path, ["--MSVC", "main.pep", "--no-cache"]);
    expect_equal(_code(ran), 1);
    expect_equal(ran.stderr, "error: the MSVC linker path is not ported\n");
    # Accepted with an `--emit-*` option that does not link.
    _succeeds(folder.path, ["--MSVC", "--emit-steps", "main.pep"]);
}

[Test]
no_runtime_checks_at_o0_warns_as_the_rust_compiler_does() {
    var folder = _program("options_checks", _PROGRAM);
    var ran = _succeeds(
        folder.path, ["--no-runtime-checks=overflow", "-O0", "main.pep", "-o", "main", "--build", "build", "--no-cache"]
    );
    expect_true(ran.stderr.contains("warning: '--no-runtime-checks' has no effect at -O0\n"));
}

# Builds `source` at `-O` into `name` in `folder`, runs it, checks it
# printed `expected`, and returns the program's size in bytes.
_built_size(folder: Path, name: String, source: String, expected: String): ulong {
    File.write_text(folder.join(Path($"{name}.pep")), source);
    var program = folder.join(Path(name + toolchain.executable_suffix()));
    _succeeds(folder, ["-O", $"{name}.pep", "-o", program.to_string(), "--build", "build", "--no-cache"]);
    var command = process.Command(program.to_string());
    command.stdout(process.Stream.Pipe);
    var ran = command.run();
    expect_true(ran.is_ok());
    expect_equal(ran.value().stdout.replace("\r\n", "\n"), expected);
    return program.metadata().value().size;
}

[Test]
an_unused_string_constant_is_left_out_of_the_program() {
    # pepper#155: a 100 KB constant nothing reads adds nothing; one the
    # program reads is kept.
    var folder = TempFolder("options_unused_constant");
    var table = "a".repeat(100000);
    var hello = "main(): int {\n    print(\"hi\");\n    return 0;\n}\n";
    var without = _built_size(folder.path, "without", hello, "hi\n");
    var unused = _built_size(folder.path, "unused", $"const TABLE = \"{table}\";\n\n{hello}", "hi\n");
    expect_true(unused < without + 20000);
    var reads = "main(): int {\n    print(TABLE.size);\n    print(TABLE[99999]);\n    return 0;\n}\n";
    var used = _built_size(folder.path, "used", $"const TABLE = \"{table}\";\n\n{reads}", "100000\na\n");
    # Less than the 100,000 bytes on macOS, whose segments round to 16 KB
    # pages: the text segment's slack can hold part of them.
    expect_true(used > without + 80000);
}

# pepper#230: `-o` into folders that do not exist yet makes them, and a
# folder it cannot make is an error naming it.
[Test]
output_into_a_missing_folder_makes_the_folder() {
    var folder = _program("options_missing_output_folder", _PROGRAM);
    var program = Path("out").join(Path("missing")).join(Path("main" + toolchain.executable_suffix()));
    _succeeds(folder.path, ["main.pep", "-o", program.to_string(), "--no-cache"]);
    var ran = process.Command(folder.path.join(program).to_string()).run();
    expect_true(ran.is_ok() and ran.value().status.success());

    # A file where a folder must go.
    File.write_text(folder.path.join(Path("blocker")), "");
    var blocked = Path("blocker").join(Path("sub"));
    var failed = _pep_build(folder.path, ["main.pep", "-o", blocked.join(Path("main")).to_string(), "--no-cache"]);
    expect_exit(failed, 1);
    expect_contains(failed.stderr, $"cannot create output folder {blocked}");
}
