# The `tests/` corpus: each `tests/<Name>/test.pep` is a program that
# `pep-build` (the one beside the test program or on the PATH) builds with
# `-I tests`, and that must exit with 0 when run from the repository's
# root. Under wasmtime too, built for `wasm32-wasip1`, when `WASI_SDK_PATH`
# names a wasi-sdk and wasmtime is on the PATH (or `WASMTIME` names it).

import [Directory, Path] from io;
import os;
import process;
import [TempFolder] from testing;
import [build_program, run] from tool_testing;
import toolchain;

# The corpus is split in parts, each a test of its own, so they run side
# by side and each stays within the time a test may take.
[Test]
builds_and_runs_the_corpus_part_1() {
    _builds_and_runs(0);
}

[Test]
builds_and_runs_the_corpus_part_2() {
    _builds_and_runs(1);
}

[Test]
builds_and_runs_the_corpus_part_3() {
    _builds_and_runs(2);
}

[Test]
builds_and_runs_the_corpus_part_4() {
    _builds_and_runs(3);
}

const _PARTS = 4;

[Test]
runs_the_corpus_under_wasmtime_part_1() {
    _runs_under_wasmtime(0);
}

[Test]
runs_the_corpus_under_wasmtime_part_2() {
    _runs_under_wasmtime(1);
}

# The programs that need what WASI preview 1 lacks (see
# docs/src/language/platform-selection.md#webassembly).
_not_on_wasi(): Array<String> {
    return [
        "Generic.SharedConstraint"  # tasks
    ];
}

# The name of every program of the corpus, `tests/<name>/test.pep`, sorted.
_corpus(): Array<String> {
    var names = Array<String>();
    var listing = Directory.open(Path("../tests"));
    expect_true(listing.is_ok(), "the corpus is found from tools/");
    if (listing.is_err()) {
        return names;
    }
    for (var entry in listing.value().entries().value()) {
        if (entry.is_directory and entry.path.join("test.pep").is_file()) {
            names.append(entry.name);
        }
    }
    names.sort((a, b) => a.compare(b));
    expect_true(names.count > 30, "the corpus has its programs");
    return names;
}

# Builds and runs every `_PARTS`th program of the corpus, from the `part`th.
_builds_and_runs(part: ulong) {
    var names = _corpus();
    var root = Directory.current().value().parent().value();
    var failures = Array<String>();
    var index = part;
    while (index < names.count) {
        var name = names[index];
        index += _PARTS;
        var folder = TempFolder($"corpus_{name}");
        var program = folder.path.join("corpus_bin" + toolchain.executable_suffix());
        var error = build_program(
            root.join("tests").join(name).join("test.pep"),
            program,
            folder.path.join("build"),
            ["-I", root.join("tests").to_string()]
        );
        if (error.is_value()) {
            failures.append($"{name}: does not build:\n{error.value()}");
            continue;
        }
        var ran = run(process.Command(program.to_string()).working_directory(root));
        if (!ran.status.success()) {
            failures.append($"{name}: exited with {ran.status.to_string()}\n{ran.stdout}{ran.stderr}");
        }
    }
    _report(failures);
}

# Builds every `_PARTS`th program WASI can run for `wasm32-wasip1`, from
# the `part`th, and runs it under wasmtime; says it skips without a
# wasi-sdk or wasmtime.
_runs_under_wasmtime(part: ulong) {
    var sdk = os.environment("WASI_SDK_PATH").value_or("");
    var wasmtime = os.environment("WASMTIME").value_or("wasmtime");
    var works = false;
    if (!sdk.is_empty) {
        var version = process.Command(wasmtime).argument("--version").run();
        works = version.is_ok() and version.value().status.success();
    }
    if (!works) {
        print("skipped: set WASI_SDK_PATH and put wasmtime on the PATH (or set WASMTIME) to run it");
        return;
    }
    var names = _corpus();
    var root = Directory.current().value().parent().value();
    var failures = Array<String>();
    var index = part;
    while (index < names.count) {
        var name = names[index];
        index += 2;
        if (_not_on_wasi().contains(name)) {
            continue;
        }
        var folder = TempFolder($"corpus_wasm_{name}");
        var module = folder.path.join("main.wasm");
        var error = build_program(
            root.join("tests").join(name).join("test.pep"),
            module,
            folder.path.join("obj"),
            ["-I", root.join("tests").to_string(), "--target", "wasm32-wasip1", "--sysroot", sdk]
        );
        if (error.is_value()) {
            failures.append($"{name}: does not build for wasm32-wasip1:\n{error.value()}");
            continue;
        }
        # The host's temporary folder is the program's `/tmp`, which
        # `Directory.temp()` names on WASI.
        var ran = run(
            process
                .Command(wasmtime)
                .arguments(["run", "--dir", ".", "--dir", $"{Directory.temp()}::/tmp", "-S", "inherit-env"])
                .arguments(["--env", "TMPDIR=/tmp", module.to_string()])
                .working_directory(folder.path)
        );
        if (!ran.status.success()) {
            failures.append($"{name}: exited under wasmtime with {ran.status.to_string()}\n{ran.stdout}{ran.stderr}");
        }
    }
    _report(failures);
}

# Prints each of `failures` and fails the test when there is one.
_report(failures: Array<String>) {
    for (var failure in failures) {
        print(failure);
    }
    expect_equal(failures.count, 0 as ulong);
}
