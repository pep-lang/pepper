# The command line as `pep-build` reads it, run on the compiler under test
# (`pep-build` beside the test or on the PATH, as `scripts/pepper-tests.sh`
# puts the stage-1 build there): `--help` lists every option;
# `--emit-steps`, `--emit-ast`, `--emit-llvm`, `-T passes`, `-m`, `--lib`,
# `--lto`, `--verify-cache` and `--MSVC` do what they document; a cached
# build of an entry file inside a module's folder links.

import [Directory, File, Path] from io;
import os;
import process;
import [TempFolder] from testing;
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
        "-O <LEVEL>",
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
        "-h, --help",
        "-V, --version"
    ]) {
        if (!help.contains(option)) {
            print($"--help leaves out {option}");
        }
        expect_true(help.contains(option));
    }
    for (var values in [
        "[possible values: static, shared]",
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
    expect_true(unknown.stderr.contains("unexpected argument '--no-such-option'"));
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
    expect_true(wrong.stderr.contains("[possible values: text, json]"));
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
        (["--lib", "dynamic", "main.pep"], 2, "invalid value 'dynamic' for '--lib <KIND>'"),
        (["--lib=static", "--test", "main.pep"], 2, "'--test' cannot be used with '--lib <KIND>'"),
        (["--lto=thin", "main.pep"], 2, "invalid value 'thin' for '--lto <MODE>'"),
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
        (["--entry", "start", "--test", "main.pep"], 2, "'--entry <NAME>' cannot be used with '--test'")
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
# defining `main`, and the module's files it never reads are not linked
# (#839).
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
