# The book's examples (`docs/examples/`) are real programs: each is built
# with `pep-build`, run, and must exit with 0. An example is a single
# `name.pep`, or a folder `name/` whose entry point is `main.pep` (for
# examples of several files, such as modules). The book includes the files
# verbatim, so what a reader sees is what was tested here.
#
# An example that ends with an `# Output:` comment block must also print
# exactly that: each following `# ` line is a line of its standard output.
#
# Every example is built unoptimized, as `pepper build` builds by default.
# A sample that reaches most of the compiler and the runtime is built again
# optimized and with debug info, where LLVM's verifier checks the debug info
# of each unit, including the inlined-at chains optimization creates.
#
# The runtime's doc comments are checked the same way: each `@example` that
# is a whole program (it declares `main`) is built and run, and a failure
# is reported at its `@example` tag.
#
# `PEPPER_DOCS_EXAMPLE=structs` runs only the examples whose name starts
# with `structs`. `PEPPER_DOCS_EXAMPLES=platform` runs only the examples
# that select code per platform (`marked_per_platform`): CI sets it on a
# pull request's macOS and Windows jobs, where the others would only repeat
# what Linux shows.

import [Span] from compiler.ast;
import [Diagnostic, Location, SourceText] from compiler.diagnostic;
import [dedent, doc_comments] from compiler.doc;
import [Directory, File, Path] from io;
import os;
import process;
import [TempFolder] from testing;
import "reference";

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

[Test]
builds_and_runs_the_examples_part_9() {
    builds_and_runs(8);
}

[Test]
builds_and_runs_the_examples_part_10() {
    builds_and_runs(9);
}

[Test]
builds_and_runs_the_examples_part_11() {
    builds_and_runs(10);
}

[Test]
builds_and_runs_the_examples_part_12() {
    builds_and_runs(11);
}

[Test]
builds_and_runs_the_examples_part_13() {
    builds_and_runs(12);
}

[Test]
builds_and_runs_the_examples_part_14() {
    builds_and_runs(13);
}

[Test]
builds_and_runs_the_examples_part_15() {
    builds_and_runs(14);
}

[Test]
builds_and_runs_the_examples_part_16() {
    builds_and_runs(15);
}

const PARTS = 16;

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

[Test]
builds_and_runs_the_runtime_examples_part_1() {
    builds_and_runs_runtime(0);
}

[Test]
builds_and_runs_the_runtime_examples_part_2() {
    builds_and_runs_runtime(1);
}

[Test]
builds_and_runs_the_runtime_examples_part_3() {
    builds_and_runs_runtime(2);
}

[Test]
builds_and_runs_the_runtime_examples_part_4() {
    builds_and_runs_runtime(3);
}

const RUNTIME_PARTS = 4;

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

    # For a runtime `@example`, its file and its tag, where a failure is
    # reported.
    var doc: SourceText? = Optional<SourceText>.Empty;
    var tag: Location = Location(0, Span(0, 0));
    # False for an `@example no-run`, which is only built.
    var run: bool = true;

    construct(name: String, entry: Path) {
        this.name = name;
        this.entry = entry;
    }

    # `problem` with this example, in its build that `label` names.
    failure(label: String, problem: String): String {
        if (doc.is_empty()) {
            return $"docs/examples/{label}: {problem}";
        }
        var lines = problem.split("\n");
        lines[0] = Diagnostic.error($"@example {lines[0]}").at(tag).render([doc.value()]);
        return "\n".join(lines);
    }
}

# Builds and runs every `PARTS`th example, from the `part`th, unoptimized.
builds_and_runs(part: ulong) {
    var examples = all_examples();
    expect_true(examples.count > 100 or !only().is_empty or (platform_only() and examples.count > 0));
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
        if (!found and only().is_empty and !platform_only()) {
            fail(failures, $"docs/examples has no '{name}'; update sample()");
        }
    }
    var index = part;
    while (index < chosen.count) {
        check(chosen[index], ["-O2", "-g"], failures);
        index += OPTIMIZED_PARTS;
    }
    report(failures);
}

# Builds and runs every `RUNTIME_PARTS`th runtime `@example`, from the
# `part`th, unoptimized.
builds_and_runs_runtime(part: ulong) {
    var folder = TempFolder($"runtime_examples_{part}");
    var examples = runtime_examples(folder.path);
    expect_true(examples.count > 80 or !only().is_empty or platform_only());
    var failures = Array<String>();
    var index = part;
    while (index < examples.count) {
        check(examples[index], Array<String>(), failures);
        index += RUNTIME_PARTS;
    }
    report(failures);
}

# Every `@example` in the runtime's doc comments that is a whole program,
# each written to a file in `folder`, limited by `only()`; none when
# `platform_only()`.
runtime_examples(folder: Path): Array<Example> {
    var examples = Array<Example>();
    if (platform_only()) {
        return examples;
    }
    var files = Array<String>();
    var root = Path("../runtime");
    expect_true(pep_files(root, "", files).is_ok());
    for (var file in files) {
        var text = File.read_to_string(root.join(file));
        expect_true(text.is_ok());
        if (text.is_err()) {
            continue;
        }
        var source = SourceText($"runtime/{file}", text.value());
        for (var doc in doc_comments(source.text)) {
            for (var tag in doc.tags_of("example")) {
                var code = dedent(tag.text);
                if (!code.starts_with("main(") and !code.contains("\nmain(")) {
                    continue;
                }
                var name = $"runtime-{file.replace("/", "-").replace(".pep", "")}-{tag.span.start}";
                if (!name.starts_with(only())) {
                    continue;
                }
                var entry = folder.join($"{name}.pep");
                expect_true(File.write_text(entry, code + "\n").is_ok());
                var example = Example(name, entry);
                example.doc = Optional<SourceText>.Value(source);
                example.tag = Location(0, tag.span);
                example.run = tag.name != "no-run";
                examples.append(example);
            }
        }
    }
    return examples;
}

# Prints `failure` now, so a part that later hangs still shows it, and adds
# it to `failures`.
fail(failures: Array<String>, failure: String) {
    print(failure);
    failures.append(failure);
}

# Fails the test when there is a failure; each was printed as it happened.
report(failures: Array<String>) {
    expect_equal(failures.count, 0 as ulong);
}

# The standard output `entry` says it prints in its `# Output:` block, or
# empty when it has none.
expected_output(entry: Path): String? {
    var text = File.read_to_string(entry);
    expect_true(text.is_ok());
    if (text.is_err()) {
        return Optional<String>.Empty;
    }
    var lines = text.value().replace("\r", "").split("\n");
    var start = 0 as ulong;
    while (start < lines.count and lines[start] != "# Output:") {
        start += 1;
    }
    if (start == lines.count) {
        return Optional<String>.Empty;
    }
    var output = "";
    for (var line in lines.slice(start + 1, lines.count)) {
        if (line == "#") {
            output += "\n";
            continue;
        }
        if (!line.starts_with("# ")) {
            break;
        }
        output += line.substr_bytes(2, line.size - 2) + "\n";
    }
    return Optional<String>.Value(output);
}

# The prefix `PEPPER_DOCS_EXAMPLE` limits the examples to; empty for all.
only(): String {
    return os.environment("PEPPER_DOCS_EXAMPLE").value_or("");
}

[Test]
marks_the_examples_that_select_code_per_platform() {
    var root = Path("../docs/examples");
    expect_true(marked_per_platform(root.join("platform-externs.pep")));
    expect_true(marked_per_platform(root.join("visibility-basics")));
    expect_false(marked_per_platform(root.join("hello.pep")));
    expect_false(marked_per_platform(root.join("build-options.pep")));
}

# Whether `PEPPER_DOCS_EXAMPLES=platform` limits the examples to those
# `marked_per_platform`.
platform_only(): bool {
    return os.environment("PEPPER_DOCS_EXAMPLES").value_or("") == "platform";
}

# Whether the example at `path`, a file or a folder of files at any depth, selects code
# per platform: a line with a `[Target(...)]` that names an `OS(...)` or an
# `Arch(...)`.
marked_per_platform(path: Path): bool {
    if (path.is_directory()) {
        var listing = Directory.open(path);
        expect_true(listing.is_ok());
        if (listing.is_err()) {
            return false;
        }
        # Its modules' folders too.
        for (var entry in listing.value().entries().value()) {
            if ((entry.is_directory or entry.name.ends_with(".pep")) and marked_per_platform(path.join(entry.name))) {
                return true;
            }
        }
        return false;
    }
    var text = File.read_to_string(path);
    expect_true(text.is_ok());
    if (text.is_err()) {
        return false;
    }
    for (var line in text.value().split("\n")) {
        if (line.contains("[Target(") and (line.contains("OS(") or line.contains("Arch("))) {
            return true;
        }
    }
    return false;
}

# Every example under `docs/examples`, sorted by name, limited by `only()`
# and `platform_only()`.
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
        var path = root.join(entry.name);
        if (entry.is_directory) {
            var main = path.join("main.pep");
            if (main.is_file() and (!platform_only() or marked_per_platform(path))) {
                examples.append(Example(entry.name, main));
            }
            continue;
        }
        if (entry.name.ends_with(".pep") and (!platform_only() or marked_per_platform(path))) {
            examples.append(Example(entry.name.substr_bytes(0, entry.name.size - 4), path));
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
        fail(failures, "cannot find pep-build beside pep-test or on the PATH");
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
        fail(failures, example.failure(label, $"cannot run pep-build: {build.error().message}"));
        return;
    }
    if (!build.value().status.success()) {
        fail(failures, example.failure(label, $"does not build:\n{build.value().stdout}{build.value().stderr}"));
        return;
    }
    if (!example.run) {
        return;
    }
    # Its own temporary folder: an example that writes under
    # `Directory.temp()` runs at once in its plain and its optimized build.
    var temp = run_temp(label);
    Directory.remove_all(temp);
    Directory.create_all(temp);
    var ran = process
        .Command(program.to_string())
        .working_directory(folder.path)
        .environment("TMPDIR", temp.to_string())
        .environment("TMP", temp.to_string())
        .environment("TEMP", temp.to_string())
        .stdin(process.Stream.Null)
        .stdout(process.Stream.Pipe)
        .stderr(process.Stream.Pipe)
        .run();
    Directory.remove_all(temp);
    if (ran.is_err()) {
        fail(failures, example.failure(label, $"cannot run it: {ran.error().message}"));
        return;
    }
    var output = ran.value();
    if (!output.status.success()) {
        fail(
            failures,
            example.failure(
                label, $"exited with {output.status.to_string()}\nstdout:\n{output.stdout}\nstderr:\n{output.stderr}"
            )
        );
        return;
    }
    var expected = expected_output(example.entry);
    if (expected.is_value() and output.stdout.replace("\r", "") != expected.value()) {
        fail(
            failures,
            example.failure(
                label,
                $"printed what its '# Output:' block does not say\nexpected:\n{expected.value()}\nprinted:\n{output.stdout}"
            )
        );
    }
}

# The temporary folder of the run labeled `label`: short, since examples
# bind Unix sockets in it and macOS caps a socket's path at 104 bytes (its
# own temporary folder already takes about half), Windows at 108. So it is
# under `/tmp`, or on Windows the user's own temporary folder: pep-test's
# per-test one, which `Directory.temp()` is here, nests too deep.
run_temp(label: String): Path {
    var root = Path("/tmp");
    [Target(OS(Windows))]
    {
        var local = os.environment("LOCALAPPDATA");
        root = local.is_empty() ? Directory.temp() : Path(local.value()).join("Temp");
    }
    # FNV-1a of the label: the plain and optimized runs differ.
    ulong hash = 2166136261;
    for (var b in label.bytes()) {
        hash = ((hash ^ (b as ulong)) * 16777619) & 0xffffffff;
    }
    return root.join($"pd{hash}_{process.id()}");
}
