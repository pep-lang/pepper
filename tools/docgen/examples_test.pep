# The book's examples (`docs/examples/`) are real programs: each is built
# with `pep-build`, run, and must exit with 0. An example is a single
# `name.pep`, or a folder `name/` whose entry point is `main.pep` (for
# examples of several files, such as modules). The book includes the files
# verbatim, so what a reader sees is what was tested here.
#
# Every example is built unoptimized, as `pepper build` builds by default.
# A sample that reaches most of the compiler and the runtime is built again
# optimized and with debug info, where LLVM's verifier checks the debug info
# of each unit, including the inlined-at chains optimization creates.
#
# `PEPPER_DOCS_EXAMPLE=structs` runs only the examples whose name starts
# with `structs`.

import [Directory, Path] from io;
import os;
import process;
import [TempFolder] from testing;

# The examples are split in parts, each a test of its own, so they run side
# by side and each stays within the time a test may take.
[Test]
builds_and_runs_the_examples_part_1() {
    builds_and_runs(0);
}

[Test]
builds_and_runs_the_examples_part_2() {
    builds_and_runs(1);
}

[Test]
builds_and_runs_the_examples_part_3() {
    builds_and_runs(2);
}

[Test]
builds_and_runs_the_examples_part_4() {
    builds_and_runs(3);
}

[Test]
builds_and_runs_the_examples_part_5() {
    builds_and_runs(4);
}

[Test]
builds_and_runs_the_examples_part_6() {
    builds_and_runs(5);
}

[Test]
builds_and_runs_the_examples_part_7() {
    builds_and_runs(6);
}

[Test]
builds_and_runs_the_examples_part_8() {
    builds_and_runs(7);
}

const PARTS = 8;

[Test]
builds_and_runs_the_sample_optimized_with_debug_info_part_1() {
    builds_and_runs_optimized(0);
}

[Test]
builds_and_runs_the_sample_optimized_with_debug_info_part_2() {
    builds_and_runs_optimized(1);
}

[Test]
builds_and_runs_the_sample_optimized_with_debug_info_part_3() {
    builds_and_runs_optimized(2);
}

[Test]
builds_and_runs_the_sample_optimized_with_debug_info_part_4() {
    builds_and_runs_optimized(3);
}

const OPTIMIZED_PARTS = 4;

# The examples that between them reach most of the compiler and the runtime:
# tasks, threads and their locks, sockets, TLS and HTTP, processes, files
# and streams, generics, overloads, modules of several files, closures,
# enums, tuples, weak and value structs.
sample(): Array<String> {
    return [
        "cli-commands",
        "compression-tar",
        "enums-match-values",
        "function-types-closures",
        "generics-constrained-bodies",
        "generics-overrides",
        "hashing-custom",
        "http-basics",
        "interpolation-format",
        "iteration-streams",
        "maps-sorted",
        "memory-weak",
        "modules-same-name",
        "networking-tls",
        "os-environment",
        "overloading-modules",
        "processes-spawn",
        "regex-basics",
        "structs-operators",
        "tasks-select-sockets",
        "tasks-transfer",
        "threads-channel",
        "threads-local",
        "threads-mutex",
        "traits-values",
        "tuples-match",
        "tutorial-word-count",
        "value-structs-basics"
    ];
}

# One example: its name and its entry file.
struct Example {
    var name: String = "";
    var entry: Path = Path("");

    construct(name: String, entry: Path) {
        this.name = name;
        this.entry = entry;
    }
}

# Builds and runs every `PARTS`th example, from the `part`th, unoptimized.
builds_and_runs(part: ulong) {
    var examples = all_examples();
    expect_true(examples.count > 100 or !only().is_empty);
    var failures = Array<String>();
    var index = part;
    while (index < examples.count) {
        check(examples[index], Array<String>(), failures);
        index += PARTS;
    }
    report(failures);
}

# Builds and runs every `OPTIMIZED_PARTS`th example of the sample, from the
# `part`th, at `-O2` with debug info.
builds_and_runs_optimized(part: ulong) {
    var examples = all_examples();
    var failures = Array<String>();
    var chosen = Array<Example>();
    for (var name in sample()) {
        var found = false;
        for (var example in examples) {
            if (example.name == name) {
                chosen.append(example);
                found = true;
            }
        }
        if (!found and only().is_empty) {
            failures.append($"docs/examples has no '{name}'; update sample()");
        }
    }
    var index = part;
    while (index < chosen.count) {
        check(chosen[index], ["-O2", "-g"], failures);
        index += OPTIMIZED_PARTS;
    }
    report(failures);
}

# Prints each of `failures` and fails the test when there is one.
report(failures: Array<String>) {
    for (var failure in failures) {
        print(failure);
    }
    expect_equal(failures.count, 0 as ulong);
}

# The prefix `PEPPER_DOCS_EXAMPLE` limits the examples to; empty for all.
only(): String {
    return os.environment("PEPPER_DOCS_EXAMPLE").value_or("");
}

# Every example under `docs/examples`, sorted by name, limited by `only()`.
all_examples(): Array<Example> {
    var examples = Array<Example>();
    var root = Path("../docs/examples");
    var listing = Directory.open(root);
    expect_true(listing.is_ok());
    if (listing.is_err()) {
        return examples;
    }
    var prefix = only();
    for (var entry in listing.value().entries().value()) {
        if (!entry.name.starts_with(prefix)) {
            continue;
        }
        if (entry.is_directory) {
            var main = root.join(entry.name).join("main.pep");
            if (main.is_file()) {
                examples.append(Example(entry.name, main));
            }
            continue;
        }
        if (entry.name.ends_with(".pep")) {
            examples.append(Example(entry.name.substr_bytes(0, entry.name.size - 4), root.join(entry.name)));
        }
    }
    examples.sort((a, b) => a.name.compare(b.name));
    return examples;
}

# Builds `example` with `options`, runs it in a folder of its own, and adds
# what went wrong to `failures`.
check(example: Example, options: Array<String>, failures: Array<String>) {
    var compiler = process.find_companion("pep-build");
    if (compiler.is_empty()) {
        failures.append("cannot find pep-build beside pep-test or on the PATH");
        return;
    }
    var label = options.is_empty ? example.name : $"{example.name} ({" ".join(options)})";
    var folder = TempFolder($"docs_example_{example.name}{"".join(options)}");
    var program = folder.path.join(example.name);
    var build = process
        .Command(compiler.value().to_string())
        .argument(example.entry.to_string())
        .argument("-o")
        .argument(program.to_string())
        .argument("--build")
        .argument(folder.path.join("build").to_string())
        .arguments(options)
        .stdout(process.Stream.Pipe)
        .stderr(process.Stream.Pipe)
        .run();
    if (build.is_err()) {
        failures.append($"docs/examples/{label}: cannot run pep-build: {build.error().message}");
        return;
    }
    if (!build.value().status.success()) {
        failures.append($"docs/examples/{label}: does not build:\n{build.value().stdout}{build.value().stderr}");
        return;
    }
    var ran = process
        .Command(program.to_string())
        .working_directory(folder.path)
        .stdin(process.Stream.Null)
        .stdout(process.Stream.Pipe)
        .stderr(process.Stream.Pipe)
        .run();
    if (ran.is_err()) {
        failures.append($"docs/examples/{label}: cannot run it: {ran.error().message}");
        return;
    }
    if (!ran.value().status.success()) {
        var output = ran.value();
        failures.append(
            $"docs/examples/{label}: exited with {output.status.to_string()}\nstdout:\n{output.stdout}\nstderr:\n{output.stderr}"
        );
    }
}
