# Runtime modules in whole programs, built with `pep-build` (the one
# beside the test program or on the PATH) and run with the arguments and
# environment each needs: what `cli`'s `parse` prints and the error for a
# struct field `add_options` cannot declare; `os`'s environment and the
# host's name; `time`'s zones from TZif files, `TZ` and the system's
# database; `process`'s arguments, `exit` (and the `atexit` handlers it
# runs), `main`'s arguments, children that are copies of the program, and
# `exec`; and the error for a member a value's type lacks inside an
# interpolation or for another module's private extern; string literals
# that hold a NUL or sit in default arguments; an imported `const` string,
# typed alike whole and in compilation units; a `match` in a generic
# method of another module's struct, and a `match` arm in a module's file
# whose case shares its name with a type of the module; a `[Move]`
# argument called through a `shared` function value; externs bound to C symbols Pepper functions are
# named after, at each `-O` level; literals and generic calls nested 64
# levels deep, built in time; reference chains 100,000 deep, released
# without overflowing the stack; source nested as deep as the parser
# allows, and one level deeper; the message a stack overflow prints on
# the main thread, a `Thread` and a task; and the panic hook, which every
# other kind of panic runs first. The programs are in `testdata/`.

import [File, Path] from io;
import os;
import process;
import [TempFolder] from testing;
import [
    build_program,
    exit_code,
    expect_contains,
    expect_ends_with,
    expect_exit,
    expect_starts_with,
    read_file,
    run,
    tool,
    write_file
] from tool_testing;
import toolchain;
import [check_programs, headline, nesting_programs] from "expected_outcomes";

# Builds `testdata/<name>.pep`, copied into `folder` so that no project
# around this one applies, into the executable `name` there, with `pep-build`
# options `options`.
_build(name: String, folder: Path, options: Array<String> = Array<String>()): Path {
    var source = folder.join(name + ".pep");
    write_file(source, read_file(Path("compiler").join("testdata").join(name + ".pep")));
    var program = folder.join(name + toolchain.executable_suffix());
    var error = build_program(source, program, folder.join("build"), options);
    if (error.is_value()) {
        panic($"{name}.pep does not build:\n{error.value()}");
    }
    return program;
}

# The command that runs `testdata/<name>.pep`, built in `folder`, with
# `arguments`.
_program(name: String, folder: Path, arguments: Array<String> = Array<String>()): process.Command {
    return process.Command(_build(name, folder).to_string()).arguments(arguments);
}

# What the program `name` does with `arguments`.
_run(name: String, arguments: Array<String> = Array<String>()): process.Output {
    var folder = TempFolder("programs_" + name);
    return run(_program(name, folder.path, arguments));
}

# ── cli ─────────────────────────────────────────────────────────────────────

[Test]
cli_parse_prints_help_and_errors() {
    var folder = TempFolder("programs_cli_parse");
    var program = _build("cli_parse", folder.path).to_string();
    var ok = run(process.Command(program).arguments(["add", "yaml"]));
    expect_exit(ok, 0);
    expect_equal(ok.stdout, "adding yaml\n");

    var help = run(process.Command(program).argument("--help"));
    expect_exit(help, 0);
    expect_equal(
        help.stdout,
        "Manages packages\n\nusage: pkg [OPTIONS] <COMMAND>\n\nCommands:\n  add  Adds a dependency\n\nOptions:\n  -h, --help  show this help\n"
    );

    var error = run(process.Command(program).argument("add"));
    expect_exit(error, 2);
    expect_equal(error.stdout, "");
    expect_equal(
        error.stderr,
        "pkg: error: missing required argument '<name>'\nusage: pkg add [OPTIONS] <name>\nRun 'pkg add --help' for more information.\n"
    );
}

[Test]
cli_struct_options_name_an_unsupported_field() {
    var folder = TempFolder("programs_cli_struct_options");
    var source = folder.path.join("cli_struct_options.pep");
    write_file(source, read_file(Path("compiler").join("testdata").join("cli_struct_options.pep")));
    var error = build_program(source, folder.path.join("never"), folder.path.join("build"));
    expect_true(error.is_value(), "the program does not build");
    expect_contains(
        error.value(),
        "error: 'add_options' cannot declare field 'table' of type 'Map<String, int>'; use bool, String, a number type, io.Path or an enum, or one of those as T? or T[]"
    );
}

# ── interpolation ───────────────────────────────────────────────────────────

# Codegen names the member; sema's check of `_pep_interpolate`'s type
# arguments, which lowering wraps the value in, must not report first.
[Test]
an_unknown_member_in_an_interpolation_is_named() {
    var folder = TempFolder("programs_interpolation_unknown_member");
    var source = folder.path.join("interpolation_unknown_member.pep");
    write_file(source, read_file(Path("compiler").join("testdata").join("interpolation_unknown_member.pep")));
    var error = build_program(source, folder.path.join("never"), folder.path.join("build"));
    expect_true(error.is_value(), "the program does not build");
    expect_contains(error.value(), "interpolation_unknown_member.pep:5:20: error: no member named 'count' in 'String'");
}

# A syntax error in a function body, read after the declarations, is a
# diagnostic like any other: the line with a caret, and no `pepc:` (#158).
[Test]
a_syntax_error_in_a_body_shows_its_line() {
    var folder = TempFolder("programs_body_literal_too_large");
    var source = folder.path.join("body_literal_too_large.pep");
    # Written here: in testdata/, the repository's parse test would read it.
    write_file(source, "main(): int {\n    ulong a = 18446744073709551616;\n    return 0;\n}\n");
    var error = build_program(source, folder.path.join("never"), folder.path.join("build"));
    expect_true(error.is_value(), "the program does not build");
    expect_contains(
        error.value(),
        "body_literal_too_large.pep:2:15: error: integer literal is too large to be represented in a 64-bit integer\n    2 |     ulong a = 18446744073709551616;\n      |               ^~~~~~~~~~~~~~~~~~~~"
    );
    expect_true(!error.value().contains("pepc:"), "no 'pepc:' prefix");
}

# ── visibility ──────────────────────────────────────────────────────────────

# A module's private extern is not visible from another module, whose
# compilation unit a worker checks (#51).
[Test]
another_modules_private_extern_is_not_visible() {
    var folder = TempFolder("programs_private_extern");
    write_file(
        folder.path.join("lib").join("module.pep"),
        "extern int abs(int value);\nexport one(): int {\n    return abs(-1);\n}\n"
    );
    write_file(folder.path.join("user").join("module.pep"), "export two(): int {\n    return abs(-2);\n}\n");
    var source = folder.path.join("main.pep");
    write_file(source, "import \"lib\";\nimport \"user\";\nmain(): int {\n    return lib.one() + user.two() - 3;\n}\n");
    var error = build_program(source, folder.path.join("never"), folder.path.join("build"));
    expect_true(error.is_value(), "the program does not build");
    expect_contains(error.value(), "module.pep:2:12: error: 'abs' is internal to module 'lib'");
}

# ── match ───────────────────────────────────────────────────────────────────

# A generic method of a struct in another module, specialized by the
# compilation unit that calls it, has its `is Err(e)` lowered there.
[Test]
a_match_in_another_modules_generic_method_is_lowered() {
    var folder = TempFolder("programs_match_in_other_module");
    var testdata = Path("compiler").join("testdata");
    var module = Path("m").join("module.pep");
    write_file(folder.path.join(module), read_file(testdata.join("match_in_other_module").join(module)));
    var program = _build("match_in_other_module", folder.path, ["-I", folder.path.to_string()]);
    expect_exit(run(process.Command(program.to_string())), 3);
}

# Writes `testdata/case_named_like_module_type/demo/` into `folder`.
_write_demo(folder: Path) {
    var testdata = Path("compiler").join("testdata").join("case_named_like_module_type");
    for (var name in ["module.pep", "shapes.pep", "main.pep", "missing_case.pep"]) {
        var file = Path("demo").join(name);
        write_file(folder.join(file), read_file(testdata.join(file)));
    }
}

# In a file of a module that does not import the module's file declaring
# a type `Circle`, a `Circle(radius)` arm names the matched enum's case.
[Test]
a_case_named_like_a_type_of_its_module_matches_the_case() {
    var folder = TempFolder("programs_case_named_like_module_type");
    _write_demo(folder.path);
    var program = folder.path.join("demo_main" + toolchain.executable_suffix());
    var error = build_program(
        folder.path.join("demo").join("main.pep"), program, folder.path.join("build"), ["-I", folder.path.to_string()]
    );
    expect_equal(error.value_or(""), "");
    expect_exit(run(process.Command(program.to_string())), 143);
}

# The same match without an arm for one case reports that case.
[Test]
a_case_named_like_a_type_of_its_module_is_missing_from_a_match() {
    var folder = TempFolder("programs_case_named_like_module_type_missing");
    _write_demo(folder.path);
    var error = build_program(
        folder.path.join("demo").join("missing_case.pep"),
        folder.path.join("never"),
        folder.path.join("build"),
        ["-I", folder.path.to_string()]
    );
    expect_true(error.is_value(), "the program does not build");
    expect_contains(error.value_or(""), "error: match on 'Shape' does not handle 'Dot'");
}

# ── os ──────────────────────────────────────────────────────────────────────

[Test]
os_environment_reads_set_empty_and_missing_variables() {
    var folder = TempFolder("programs_os_environment");
    var output = run(
        _program("os_environment", folder.path)
            .environment("OS_TEST_SET", "héllo wörld")
            .environment("OS_TEST_EMPTY", "")
            .environment("OS_TEST_EQUALS", "a=b=c")
            .remove_environment("OS_TEST_MISSING")
    );
    for (var line in [
        "set=[héllo wörld]",
        "empty=[]",
        "missing=true",
        "blank=true",
        "listed OS_TEST_SET=[héllo wörld]",
        "listed OS_TEST_EMPTY=[]",
        "listed OS_TEST_EQUALS=[a=b=c]"
    ]) {
        expect_contains(output.stdout, line + "\n");
    }
    expect_exit(output, 3);
}

[Target(OS(Mac))]
_host_system(): String {
    return "macos\nMac\n";
}

[Target(OS(Windows))]
_host_system(): String {
    return "windows\nWindows\n";
}

[Target(OS(Linux))]
_host_system(): String {
    return "linux\nLinux\n";
}

[Target(Arch(aarch64))]
_host_architecture(): String {
    return "aarch64\n";
}

[Target(Arch(x64))]
_host_architecture(): String {
    return "x64\n";
}

[Test]
os_system_name_and_architecture_match_the_host() {
    var output = _run("os_machine");
    expect_exit(output, 0);
    expect_equal(output.stdout, _host_system() + _host_architecture());
}

# ── time ────────────────────────────────────────────────────────────────────

# Appends `value`'s low `bytes` bytes to `out`, most significant first.
_big_endian(out: Array<u8>, value: long, bytes: int) {
    var shift = (bytes - 1) * 8;
    while (shift >= 0) {
        out.append(((value >> shift) & 255) as u8);
        shift -= 8;
    }
}

# A TZif header (RFC 8536) of version 2 with `time_count` transitions and
# `type_count` local time types.
_tzif_header(out: Array<u8>, time_count: int, type_count: int) {
    for (var c in "TZif2".bytes()) {
        out.append(c);
    }
    for (var _ in 0..15) {
        out.append(0);
    }
    # isutcnt, isstdcnt, leapcnt, timecnt, typecnt, charcnt
    for (var count in [0, 0, 0, time_count, type_count, 4]) {
        _big_endian(out, count, 4);
    }
}

# A version 2 TZif file: transitions at the UTC seconds `starts`, each to
# the type at the same place in `indexes`, the types' UTC offsets in
# seconds `types`, and the POSIX TZ `footer`.
_tzif(starts: Array<long>, indexes: Array<int>, types: Array<int>, footer: String): Array<u8> {
    var out = Array<u8>();
    # The version 1 block, which readers of version 2 skip: one type.
    _tzif_header(out, 0, 1);
    _big_endian(out, types[0], 4);
    _big_endian(out, 0, 2);
    for (var c in "ZZZ".bytes()) {
        out.append(c);
    }
    out.append(0);
    _tzif_header(out, starts.count as int, types.count as int);
    for (var start in starts) {
        _big_endian(out, start, 8);
    }
    for (var index in indexes) {
        out.append(index as u8);
    }
    for (var offset in types) {
        _big_endian(out, offset, 4);
        _big_endian(out, 0, 2);
    }
    for (var c in "ZZZ".bytes()) {
        out.append(c);
    }
    out.append(0);
    out.append(10);
    for (var c in footer.bytes()) {
        out.append(c);
    }
    out.append(10);
    return out;
}

[Test]
time_zones_from_tzif_files_rules_and_the_local_zone() {
    var folder = TempFolder("programs_time_zones");
    var zones = folder.path.join("zones");
    var test = zones.join("Test");
    write_file(test.join("Garbage"), "not a zone");
    var none = Array<long>();
    var no_index = Array<int>();
    expect_true(
        File.write_bytes(test.join("Rule"), _tzif(none, no_index, [3600], "CET-1CEST,M3.5.0,M10.5.0/3")).is_ok()
    );
    expect_true(
        File.write_bytes(test.join("South"), _tzif(none, no_index, [36000], "AEST-10AEDT,M10.1.0,M4.1.0/3")).is_ok()
    );
    expect_true(
        File.write_bytes(
            test.join("History"), _tzif([0 as long, 1000000 as long], [1, 2], [1800, 3600, 7200], "")
        ).is_ok()
    );
    expect_true(File.write_bytes(test.join("Julian"), _tzif(none, no_index, [0], "<+00>0<+01>-1,J60/0,J61/0")).is_ok());
    # A POSIX TZ string needs no database; every system honors TZDIR.
    var output = run(
        _program("time_zones", folder.path).environment("TZDIR", zones.to_string()).environment("TZ", "<+03>-3")
    );
    expect_exit(output, 0);
    var lines = [
        "rule Test/Rule 2024-01-15T13:00:00+01:00 2024-07-15T14:00:00+02:00",
        "rule edge 2024-03-31T01:59:59+01:00 2024-03-31T03:00:00+02:00",
        "rule back 2024-10-27T02:59:59+02:00 2024-10-27T02:00:00+01:00",
        "gap 2024-03-31T03:30:00+02:00",
        "overlap 2024-10-27T02:30:00+02:00",
        "plain 2024-06-01T12:00:00+02:00",
        "south 2024-01-15T23:00:00+11:00 2024-07-15T22:00:00+10:00",
        "history 1970-01-01T00:29:59+00:30 1970-01-01T01:00:00+01:00 1970-01-12T15:46:40+02:00 2100-01-01T02:00:00+02:00",
        "julian 2024-02-29T12:00:00Z 2024-03-01T13:00:00+01:00 2024-03-02T12:00:00Z",
        "garbage true",
        "missing true true true",
        "utc UTC +00:00",
        "fixed +05:30 2024-01-01T05:30:00+05:30",
        "now true true"
    ];
    # Windows reads the zone in its settings, not TZ.
    if (toolchain.executable_suffix() == "") {
        lines.append("local 2024-01-15T15:00:00+03:00 2024-07-15T15:00:00+03:00");
    }
    for (var line in lines) {
        expect_contains(output.stdout, line + "\n");
    }
}

[Test]
time_named_zones_from_the_system_database() {
    var folder = TempFolder("programs_time_system_zones");
    var output = run(_program("time_system_zones", folder.path).remove_environment("TZDIR"));
    expect_exit(output, 0);
    if (output.stdout.contains("no database")) {
        # Linux without tzdata installed; macOS and Windows always have one.
        expect_equal(_host_system(), "linux\nLinux\n");
        return;
    }
    for (var line in [
        "paris 2024-07-14T12:00:00+02:00 2024-01-14T11:00:00+01:00 2100-07-14T12:00:00+02:00",
        "local 2024-12-25T18:00:00+01:00",
        "kolkata +05:30",
        "unknown true"
    ]) {
        expect_contains(output.stdout, line + "\n");
    }
}

# ── process ─────────────────────────────────────────────────────────────────

[Test]
process_arguments_follow_the_program_name() {
    var output = _run("process_arguments", ["one", "two words", "", "three"]);
    expect_equal(output.stdout, "[one]\n[two words]\n[]\n[three]\n");
    expect_exit(output, 5);
}

# Every character arrives whole as UTF-8, on Windows too, where the C
# runtime's `argv` is in the ANSI code page (pep-lang/pepper#165).
[Test]
process_arguments_arrive_as_utf8() {
    var output = _run("process_arguments", ["é", "日本語", "😀 ✓", "naïve\\\"q\""]);
    expect_equal(output.stdout, "[é]\n[日本語]\n[😀 ✓]\n[naïve\\\"q\"]\n");
    expect_exit(output, 5);
}

[Test]
process_argument_zero_names_the_program() {
    expect_exit(_run("process_program_name"), 0);
}

[Test]
process_exit_ends_with_the_code_and_keeps_printed_output() {
    # Standard output is a pipe here, so it is fully buffered: exit must
    # flush it.
    var output = _run("process_exit");
    expect_equal(output.stdout, "before\n");
    expect_exit(output, 7);
}

[Test]
process_exit_runs_atexit_handlers_except_in_a_forked_copy() {
    # Printed once, by the parent: the copy's exit skips the handler.
    var output = _run("process_exit_atexit");
    var first = toolchain.executable_suffix() == "" ? "child 5" : "no fork";
    expect_equal(output.stdout, $"{first}\nexit handler ran\n");
    expect_exit(output, 7);
}

[Test]
process_main_receives_the_arguments_when_it_declares_them() {
    var output = _run("process_main_arguments", ["one", "two words", ""]);
    expect_equal(output.stdout, "[one]\n[two words]\n[]\n");
    expect_exit(output, 4);
}

[Test]
process_main_with_arguments_falls_off_its_end_with_zero() {
    expect_exit(_run("process_main_falls_off"), 0);
}

[Test]
process_a_void_main_with_arguments_exits_zero() {
    var output = _run("process_void_main", ["x"]);
    expect_equal(output.stdout, "2\n");
    expect_exit(output, 0);
}

[Test]
process_main_arguments_ignore_a_program_function_named_arguments() {
    expect_exit(_run("process_arguments_function", ["a", "b"]), 39);
}

[Test]
process_the_deprecated_prelude_functions_still_work() {
    expect_exit(_run("process_deprecated_prelude", ["x"]), 4);
}

[Test]
process_command_starts_children_and_collects_their_output() {
    var output = _run("process_command");
    expect_equal(
        output.stdout,
        "path ok\n"
            + "[two words]\n[]\n[quote\"d]\n[back\\slash\\]\n[tab\there]\n\n"
            + "out|err|3|false\n"
            + "set\n<unset>\n\n"
            + "PEAR AND APPLE\n"
            + "true\n"
            + "process_command_directory\n\n"
            + "true\n"
            + "killed false\n"
            + "null 0 0\n"
            + "task 532480\ntask 532480\ntask 532480\n"
    );
    expect_exit(output, 0);
}

[Test]
process_exec_replaces_the_program_and_keeps_its_id() {
    if (toolchain.executable_suffix() != "") {
        return;  # POSIX only
    }
    # Standard output is a pipe, so the printed id sits in print's buffer:
    # exec flushes it. The shell prints its own id, which must be the one
    # printed before.
    var output = _run("process_exec");
    var lines = output.stdout.split("\n");
    expect_equal(lines.count, 5 as ulong);
    # The shell runs as the same process.
    expect_equal(lines[0], lines[1]);
    expect_equal(lines[2], "set");
    # `pwd` prints the physical folder, and on macOS `/tmp` is a link to
    # `/private/tmp`.
    expect_equal(lines[3], Path("/tmp").canonicalize().value().to_string());
    expect_exit(output, 9);
}

# ── literals ────────────────────────────────────────────────────────────────

[Test]
string_literal_with_nul_keeps_its_bytes_beside_its_prefix() {
    var output = _run("string_literal_nul");
    expect_exit(output, 0);
    expect_equal(output.stdout, "1 97\n3 97 0 98\n");
}

# A default argument is evaluated in the caller's compilation unit; its
# string literals and its `[Implicit]` conversion must be made there too.
[Test]
string_literals_in_default_arguments_arrive_whole() {
    var folder = TempFolder("programs_default_argument_literal");
    var testdata = Path("compiler").join("testdata");
    var module = Path("d").join("module.pep");
    write_file(folder.path.join(module), read_file(testdata.join("default_argument_literal").join(module)));
    var program = _build("default_argument_literal", folder.path, ["-I", folder.path.to_string()]);
    var output = run(process.Command(program.to_string()));
    expect_exit(output, 0);
    expect_equal(output.stdout, "3 default 4 5\n7 rex\n2 6 module\n");
}

# An imported `const` string types alike whole and in compilation units: a
# generic call infers `String` from it beside `Optional<String>.value()`,
# `var` and overloads take it as a `StringConstant` (#175).
[Test]
const_string_types_alike_whole_and_in_units() {
    var folder = TempFolder("programs_const_string_inference");
    var testdata = Path("compiler").join("testdata");
    var module = Path("k").join("module.pep");
    write_file(folder.path.join(module), read_file(testdata.join("const_string_inference").join(module)));
    var source = folder.path.join("const_string_inference.pep");
    write_file(source, read_file(testdata.join("const_string_inference.pep")));
    for (var whole in [true, false]) {
        var name = whole ? "whole" : "units";
        var program = folder.path.join(name + toolchain.executable_suffix());
        var command = process
            .Command(tool("pep-build").to_string())
            .arguments([source.to_string(), "-I", folder.path.to_string(), "-o", program.to_string()])
            .arguments(["--build", folder.path.join(name + ".build").to_string()]);
        if (whole) {
            command.environment("PEPC_NO_COMPILATION_UNITS", "1");
        } else {
            command.remove_environment("PEPC_NO_COMPILATION_UNITS");
        }
        var built = run(command);
        if (!built.status.success()) {
            panic($"the {name} build fails:\n{built.stdout}{built.stderr}");
        }
        var output = run(process.Command(program.to_string()));
        expect_exit(output, 0);
        expect_equal(
            output.stdout, "true\nfalse\ntrue\nStringConstant quickfix\nStringConstant quickfix\nquickfix/local\n"
        );
    }
}

# Nested collection literals and generic calls are typed in one walk, not
# one level per specialization round: 20 levels took 11 s and 120 more than
# 10 minutes (#202), and generic calls past eight levels failed to infer.
# 96 levels of array take about as long as 64 did before the passes asked
# a table of types (`type_ids.pep`) about each type rather than walk every
# level below it, and 254 (the nesting limit) build in about a minute and
# 2 GB (#210). The calls stay at 64 levels: each nests twice.
[Test]
nested_literals_build_in_time_and_run() {
    var folder = TempFolder("programs_nested_literals");
    ulong depth = 96;
    ulong calls = 64;
    var source = "id<T>(x: T): T {\n    return x;\n}\n\nexport main(): int {\n"
        + $"    var a = {"[".repeat(depth)}7{"]".repeat(depth)};\n"
        + $"    var m = {"[1: ".repeat(16)}2{"]".repeat(16)};\n"
        + $"    var i = {"id(".repeat(calls)}3{")".repeat(calls)};\n"
        + $"    return a{"[0]".repeat(depth)} + m{"[1]".repeat(16)} + i;\n}\n";
    var path = folder.path.join("nested.pep");
    write_file(path, source);
    var program = folder.path.join("nested" + toolchain.executable_suffix());
    var start = os.Instant.now();
    var error = build_program(path, program, folder.path.join("build"));
    var seconds = start.elapsed().seconds();
    if (error.is_value()) {
        panic($"nested.pep does not build:\n{error.value()}");
    }
    # Generous: it builds in about 30 s, and took about 40 without the table
    # of types.
    if (seconds >= 150) {
        panic($"nested.pep took {seconds} s to build");
    }
    expect_exit(run(process.Command(program.to_string())), 12);
}

# ── moves ───────────────────────────────────────────────────────────────────

[Test]
move_takes_a_call_through_a_shared_function_value() {
    var output = _run("move_shared_call");
    expect_exit(output, 0);
    expect_equal(output.stdout, "1\n6\n");
}

[Test]
move_takes_a_value_once_no_closure_holds_it() {
    var output = _run("move_after_closure");
    expect_exit(output, 0);
    expect_equal(output.stdout, "2\n11\n22\n");
}

[Test]
move_in_a_loop_takes_a_value_given_again_before_the_next_pass() {
    var output = _run("move_in_loop");
    expect_exit(output, 0);
    expect_equal(output.stdout, "40 2 10\n");
}

[Test]
move_takes_the_only_reference_from_a_call_result_unwrapped() {
    var output = _run("move_unwrapped");
    expect_exit(output, 0);
    expect_equal(output.stdout, "1\n1\n1\n1\n10\n");
}

[Test]
a_local_of_an_enclosing_with_block_keeps_a_copy_of_an_inner_locked_value() {
    var output = _run("nested_with");
    expect_exit(output, 0);
    expect_equal(output.stdout, "32\n");
}

# ── externs ─────────────────────────────────────────────────────────────────

[Test]
extern_bound_to_a_pepper_function_name_calls_the_c_symbol() {
    # The clash broke the link at every level; `-O` and `-O --lto full`
    # cover both ways the parts link (`-O0` links them as `-O` does).
    for (var options in [["-O"], ["-O", "--lto", "full"]]) {
        var folder = TempFolder("programs_extern_named_like_function");
        var program = _build("extern_named_like_function", folder.path, options);
        expect_exit(run(process.Command(program.to_string())), 100);
    }
}

# ── releases ────────────────────────────────────────────────────────────────

[Test]
deep_chains_release_without_overflow_and_shallow_order_holds() {
    var folder = TempFolder("programs_deep_release");
    var program = _build("deep_release", folder.path).to_string();
    var expected = "link chain released\nbranch tree released\ntrait chain released\nenum chain released\n"
        + "tree released\nclosure chain released\nchain released while a task waits in a destructor\n"
        + "destroy holder\ndestroy second\ndestroy second.piece\ndestroy first\ndestroy first.piece\n"
        + "destroy root\ndestroy second\ndestroy first\ndestroy first.second\ndestroy first.first\n";
    # 100,000 is far past the depth a recursive release overflows at.
    for (var depth in ["10", "100000"]) {
        var output = run(process.Command(program).argument(depth));
        expect_exit(output, 0);
        expect_equal(output.stdout, expected);
    }
}

[Test]
steered_chains_release_without_overflow_and_shallow_order_holds() {
    var folder = TempFolder("programs_chain_release");
    var program = _build("chain_release", folder.path).to_string();
    var expected = "shape chain released\nbag chain released\ncounted chain released true\n"
        + "watched chain released true\nclosure chain released\ntuple chain released while a task waits in a destructor\n"
        + "destroy root\ndestroy shape\ndestroy first\ndestroy first.first\ndestroy second\n";
    for (var depth in ["10", "100000"]) {
        var output = run(process.Command(program).argument(depth));
        expect_exit(output, 0);
        expect_equal(output.stdout, expected);
    }
}

# ── nesting ─────────────────────────────────────────────────────────────────

# `pep-build` builds source nested as deep as the parser allows, on the
# stack it gives the compiler (`parse.STACK_SIZE`; Windows gives the main
# thread 1 MiB), and the programs run; one level deeper is the parser's
# error.
[Test]
builds_and_runs_the_deepest_source() {
    var folder = TempFolder("programs_nesting");
    var mismatches = check_programs(folder, nesting_programs(), (root: Path): String => {
        var program = root.parent().value().join("main" + toolchain.executable_suffix());
        var error = build_program(root, program, root.parent().value().join("build"));
        if (error.is_value()) {
            return headline(error.value(), root);
        }
        var output = run(process.Command(program.to_string()));
        return output.status.success() ? "accepted" : $"exited with {exit_code(output)}";
    });
    expect_equal(mismatches, 0 as ulong);
}

# ── stack overflow ──────────────────────────────────────────────────────────

[Test]
stack_overflow_reports_itself_as_a_panic() {
    var folder = TempFolder("programs_stack_overflow");
    var program = _build("stack_overflow", folder.path).to_string();
    var safe = run(process.Command(program).argument("none"));
    expect_exit(safe, 0);
    expect_equal(safe.stdout, "1000\n");
    for (var where in ["main", "thread", "task"]) {
        var overflowed = run(process.Command(program).argument(where));
        # Prefixed so that a failure names the thread. No "hook" line: an
        # overflow skips the program's panic hook.
        expect_equal($"{where}: {overflowed.stderr}", $"{where}: panic: stack overflow\n");
        expect_equal(overflowed.stdout, "");
        expect_false(overflowed.status.success());
    }
}

# ── panic hook ──────────────────────────────────────────────────────────────

# Runs `panic_hook.pep` with `how` and checks what it wrote to standard
# error: `before` (what a chained hook wrote), the hook's line for
# `message`, then the panic's own, whose location ends with `at`.
_expect_hooked(program: String, how: String, message: String, at: String, before: String = "") {
    var output = run(process.Command(program).argument(how));
    expect_false(output.status.success());
    var text = output.stderr.replace("\r\n", "\n");
    expect_starts_with(text, before);
    var lines = text.substr_bytes(before.size, text.size - before.size).split("\n");
    var location = lines[1].split(": panic: ")[0];
    expect_ends_with(location, $"panic_hook.pep:{at}");
    expect_equal(lines[0], $"hook: {message} at {location}");
    expect_equal(lines[1], $"{location}: panic: {message}");
}

[Test]
panic_hook_runs_before_the_message() {
    var folder = TempFolder("programs_panic_hook");
    var program = _build("panic_hook", folder.path).to_string();
    _expect_hooked(program, "panic", "boom", "16:9");
    _expect_hooked(program, "assert", "not empty", "18:9");
    _expect_hooked(program, "bounds", "Array index read out of bounds", "21:18");
    _expect_hooked(program, "overflow", "integer overflow in 'int' addition", "24:22");
    # Set on the main thread, it runs on the thread that panics.
    _expect_hooked(program, "thread", "on a thread", "33:34");
    _expect_hooked(program, "chained", "chain", "40:9", "second\n");

    # Taken, the hook no longer runs, and the caller has it.
    var taken = run(process.Command(program).argument("taken"));
    expect_false(taken.status.success());
    var text = taken.stderr.replace("\r\n", "\n");
    expect_starts_with(text, "hook: called at directly\n");
    expect_contains(text, "panic_hook.pep:28:9: panic: no hook\n");
    expect_equal(text.find("hook: no hook"), -1);

    # A panic in the hook prints both messages and ends the program.
    var nested = run(process.Command(program).argument("nested"));
    expect_false(nested.status.success());
    var lines = nested.stderr.replace("\r\n", "\n").split("\n");
    expect_ends_with(lines[0], "panic_hook.pep:31:9: panic: first");
    expect_ends_with(lines[1], "panic_hook.pep:30:47: panic in the panic hook: in the hook");
}
