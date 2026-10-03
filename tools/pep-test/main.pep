# pep-test: finds the `[Test]` functions in Pepper files, runs each in a
# child process of its own, and reports which pass.
#
#     pep-test                          # every test under the current folder
#     pep-test src/math_test.pep        # the tests of one file
#     pep-test -f parse src             # only tests whose name contains "parse"
#     pep-test --list src               # list them without running them
#
# Each file holding a `[Test]` function is built with `pep-build --test`
# into a test program, which lists its tests (`--list`) and runs one
# (`--run NAME`). The tests of every program run in parallel, one child
# process each, so a panic, a crash or a timeout fails that test and the
# rest carry on. The exit status is 0 only when every file builds and
# every test passes.
#
# Build it from the repository root, next to the compiler:
#
#     target/release/pep-build tools/pep-test/main.pep -o target/release/pep-test

import async;
import cli;
import [Directory, File, Path] from io;
import os;
import process;

# The release this tool belongs to. A test keeps it equal to the workspace
# version in Cargo.toml.
version(): String {
    return "0.3.0";
}

# How long a test may run, in seconds, when `--timeout` is not given.
const DEFAULT_TIMEOUT = "60";

# The exit status a test program ends with when its test runs too long.
const TIMED_OUT = 124;

main(args: String[]): int {
    var parser = cli.Parser("pep-test", "Builds and runs the [Test] functions of Pepper files.", version = version());
    var filters = parser.multiple(
        "filter",
        "f",
        "run only the tests whose name contains this text (any of them, when repeated)",
        value_name = "TEXT"
    );
    var list = parser.flag("list", "l", "list the tests instead of running them");
    var jobs = parser.option(
        "jobs", "j", "how many tests run at once (default: one per logical CPU)", value_name = "COUNT"
    );
    var timeout = parser.option(
        "timeout",
        "t",
        "fail a test still running after this many seconds; 0 for no limit",
        value_name = "SECONDS",
        default_value = DEFAULT_TIMEOUT
    );
    var imports = parser.multiple("import-path", "I", "a directory pep-build searches for imports", value_name = "DIR");
    var defines = parser.multiple(
        "define", "D", "a build option for pep-build: NAME or NAME=VALUE", value_name = "OPTION"
    );
    var paths = parser.positionals(
        "path", "a .pep file, or a folder to search for files holding [Test] functions (default: the current folder)"
    );
    if (!parser.parse(args)) {
        return 2;
    }
    var options = Options();
    options.filters = filters.values();
    options.imports = imports.values();
    options.defines = defines.values();
    var limit = ulong.parse(timeout.value());
    if (limit.is_empty()) {
        return usage_error(parser, $"'--timeout' must be a number of seconds, not '{timeout.value()}'");
    }
    options.timeout = limit.value();
    options.jobs = async.logical_cpus();
    if (jobs.value_or("") != "") {
        var count = ulong.parse(jobs.value());
        if (count.is_empty() or count.value() == 0) {
            return usage_error(parser, $"'--jobs' must be a positive number, not '{jobs.value()}'");
        }
        options.jobs = count.value();
    }
    if (options.jobs == 0) {
        options.jobs = 1;
    }

    var roots = paths.values();
    if (roots.is_empty) {
        roots.append(".");
    }
    var files = Array<String>();
    for (var root in roots) {
        var found = find_test_files(root, files);
        if (found.is_value()) {
            return fail(found.value());
        }
    }
    if (files.is_empty) {
        print("no [Test] functions found");
        return 0;
    }

    var compiler = process.find_companion("pep-build");
    if (compiler.is_empty()) {
        return fail("cannot find pep-build next to pep-test or on the PATH");
    }
    var scratch = Directory.temp().join($"pep-test-{process.id()}");
    var made = Directory.create_all(scratch);
    if (made.is_err()) {
        return fail($"cannot create '{scratch.to_string()}': {made.error().message}");
    }
    var status = build_and_run(options, list.is_set, files, compiler.value().to_string(), scratch);
    Directory.remove_all(scratch);
    return status;
}

# What to build and run, from the command line.
struct Options {
    var filters: Array<String> = __null;
    var imports: Array<String> = __null;
    var defines: Array<String> = __null;
    var jobs: ulong = 1;
    var timeout: ulong = 60;

    construct() {
        this.filters = Array<String>();
        this.imports = Array<String>();
        this.defines = Array<String>();
    }
}

# One test of a test program, as its `--list` describes it.
struct Test {
    var program: String = "";
    var file: String = "";
    var name: String = "";
    var location: String = "";
    var should_panic: bool = false;
    var panic_message: String = "";

    construct() {}
}

# How a test's run ended.
struct Outcome {
    var passed: bool = false;
    var output: String = "";
    var reason: String = "";

    construct() {}
}

# The next piece of work for the tasks of `in_parallel` to take.
struct Counter {
    var next: ulong = 0;

    construct() {}
}

# Builds each file's test program, then lists or runs the tests.
build_and_run(options: Options, list_only: bool, files: Array<String>, compiler: String, scratch: Path): int {
    var programs = Array<String>();
    var builds = Array<String>();
    ulong index = 0;
    for (var file in files) {
        var stem = Path(file).file_stem();
        var name = $"{index}-{stem.is_value() ? stem.value() : "test"}{executable_suffix()}";
        programs.append(scratch.join(name).to_string());
        builds.append("");
        index += 1;
    }
    in_parallel(files.count, options.jobs, (i: ulong) => {
        builds[i] = build(compiler, files[i], programs[i], options);
    });

    var tests = Array<Test>();
    ulong broken = 0;
    index = 0;
    while (index < files.count) {
        if (!builds[index].is_empty) {
            File.stderr().write_all($"error: cannot build the tests of '{files[index]}':\n{builds[index]}");
            broken += 1;
        } else {
            var listed = list_tests(programs[index], files[index], tests);
            if (listed.is_value()) {
                File.stderr().write_all($"error: cannot list the tests of '{files[index]}': {listed.value()}\n");
                broken += 1;
            }
        }
        index += 1;
    }
    var selected = Array<Test>();
    for (var test in tests) {
        if (matches(test.name, options.filters)) {
            selected.append(test);
        }
    }
    var qualify = files.count > 1;

    if (list_only) {
        for (var test in selected) {
            print(display_name(test, qualify));
        }
        return broken == 0 ? 0 : 1;
    }

    print($"running {selected.count} {plural(selected.count, "test", "tests")}");
    var outcomes = Array<Outcome>();
    for (var test in selected) {
        outcomes.append(Outcome());
    }
    in_parallel(selected.count, options.jobs, (i: ulong) => {
        var outcome = run_test(selected[i], options.timeout);
        outcomes[i] = outcome;
        print($"test {display_name(selected[i], qualify)} ... {outcome.passed ? "ok" : "FAILED"}");
    });

    ulong passed = 0;
    var failed = Array<ulong>();
    index = 0;
    while (index < selected.count) {
        if (outcomes[index].passed) {
            passed += 1;
        } else {
            failed.append(index);
        }
        index += 1;
    }
    if (!failed.is_empty) {
        print("\nfailures:");
        for (var i in failed) {
            var outcome = outcomes[i];
            print($"\n---- {display_name(selected[i], qualify)} ({selected[i].location}) ----");
            if (!outcome.output.is_empty) {
                File.stdout().write_all(outcome.output.ends_with("\n") ? outcome.output : outcome.output + "\n");
            }
            if (!outcome.reason.is_empty) {
                print($"note: {outcome.reason}");
            }
        }
        print("");
    }
    var summary = $"{passed} passed, {failed.count} failed";
    if (selected.count < tests.count) {
        summary += $", {tests.count - selected.count} filtered out";
    }
    if (broken > 0) {
        summary += $"; {broken} {plural(broken, "file", "files")} did not build";
    }
    print(summary);
    return failed.is_empty and broken == 0 ? 0 : 1;
}

# Calls `work` with each index below `count`, at most `jobs` at once: each
# call runs as a task, and a task waiting on a child process lets the
# others run.
in_parallel(count: ulong, jobs: ulong, work: (ulong) => void) {
    var counter = Counter();
    async.run_with(async.RuntimeOptions().workers(1), () => {
        var workers = Array<async.Task<void>>();
        while (workers.count < jobs and workers.count < count) {
            workers.append(async.Task<void>.spawn_local(() => {
                while (counter.next < count) {
                    var index = counter.next;
                    counter.next += 1;
                    work(index);
                }
            }));
        }
        for (var worker in workers) {
            worker.join();
        }
    });
}

# Builds `file`'s test program at `program`, returning what pep-build
# printed when it fails, else empty.
build(compiler: String, file: String, program: String, options: Options): String {
    var arguments = Array<String>();
    arguments.append("--test");
    arguments.append(file);
    for (var directory in options.imports) {
        arguments.append("-I");
        arguments.append(directory);
    }
    for (var define in options.defines) {
        arguments.append("-D");
        arguments.append(define);
    }
    arguments.append("-o");
    arguments.append(program);
    var ran = process.Command(compiler).arguments(arguments).run();
    if (ran.is_err()) {
        return $"cannot run pep-build: {ran.error().message}\n";
    }
    var output = ran.value();
    if (output.status.success()) {
        return "";
    }
    var text = output.stdout + output.stderr;
    return text.is_empty ? $"pep-build failed ({output.status.to_string()})\n" : text;
}

# Adds the tests `program` (built from `file`) lists to `tests`, returning
# why it could not list them, if it could not.
list_tests(program: String, file: String, tests: Array<Test>): String? {
    var ran = process.Command(program).argument("--list").run();
    if (ran.is_err()) {
        return Optional<String>.Value(ran.error().message);
    }
    var output = ran.value();
    if (!output.status.success()) {
        return Optional<String>.Value(output.stderr.is_empty ? output.status.to_string() : output.stderr.trim());
    }
    # Windows writes a text-mode stdout with "\r\n" line ends.
    for (var line in output.stdout.replace("\r\n", "\n").split("\n")) {
        if (line.is_empty) {
            continue;
        }
        var fields = line.split("\t");
        if (fields.count != 4) {
            return Optional<String>.Value($"unexpected line '{line}'");
        }
        var test = Test();
        test.program = program;
        test.file = file;
        test.name = fields[0];
        test.location = fields[1];
        test.should_panic = fields[2] == "panics";
        test.panic_message = fields[3];
        tests.append(test);
    }
    return Optional<String>.Empty;
}

# Runs `test` in a child process and judges how it ended.
run_test(test: Test, timeout: ulong): Outcome {
    var command = process.Command(test.program).argument("--run").argument(test.name);
    if (timeout > 0) {
        command.argument("--timeout").argument($"{timeout}");
    }
    # A failing test's panic message is the report; its backtrace is
    # noise unless asked for.
    if (os.environment("PEPPER_BACKTRACE").is_empty()) {
        command.environment("PEPPER_BACKTRACE", "0");
    }
    var outcome = Outcome();
    var ran = command.run();
    if (ran.is_err()) {
        outcome.reason = $"cannot run the test program: {ran.error().message}";
        return outcome;
    }
    var output = ran.value();
    outcome.output = output.stdout + output.stderr;
    var success = output.status.success();
    var code = output.status.code();
    var timed_out = code.is_value() and code.value() == TIMED_OUT;
    if (!test.should_panic) {
        outcome.passed = success;
        if (!success and !timed_out and !output.stderr.contains("panic: ")) {
            outcome.reason = $"the test program ended with {output.status.to_string()}";
        }
        return outcome;
    }
    if (success) {
        outcome.reason = test.panic_message.is_empty ?
            "the test returned, but should have panicked" :
            $"the test returned, but should have panicked with '{test.panic_message}'";
        return outcome;
    }
    if (timed_out or !output.stderr.contains("panic: ")) {
        outcome.reason = $"the test should have panicked, but ended with {output.status.to_string()}";
        return outcome;
    }
    if (!test.panic_message.is_empty and !output.stderr.contains(test.panic_message)) {
        outcome.reason = $"the panic's message does not contain '{test.panic_message}'";
        return outcome;
    }
    outcome.passed = true;
    outcome.output = "";
    return outcome;
}

# Adds `root`, or the files under it that hold a `[Test]` function, to
# `files`, returning why it cannot, if it cannot.
find_test_files(root: String, files: Array<String>): String? {
    var path = Path(root);
    var metadata = path.metadata();
    if (metadata.is_err()) {
        return Optional<String>.Value($"cannot read '{root}': {metadata.error().message}");
    }
    if (metadata.value().is_file) {
        files.append(root);
        return Optional<String>.Empty;
    }
    var opened = Directory.open(path);
    if (opened.is_err()) {
        return Optional<String>.Value($"cannot read '{root}': {opened.error().message}");
    }
    var listed = opened.value().entries();
    if (listed.is_err()) {
        return Optional<String>.Value($"cannot read '{root}': {listed.error().message}");
    }
    var entries = listed.value();
    entries.sort((a, b) => a.name.compare(b.name));
    for (var entry in entries) {
        # Hidden folders (.git, .pep) hold no tests; symlinks are not
        # followed, so a loop of them cannot recurse forever.
        if (entry.name.starts_with(".") or entry.is_symlink) {
            continue;
        }
        if (entry.is_directory) {
            var found = find_test_files(shown_path(entry.path), files);
            if (found.is_value()) {
                return found;
            }
        } else if (entry.is_file and entry.name.ends_with(".pep") and declares_tests(entry.path)) {
            files.append(shown_path(entry.path));
        }
    }
    return Optional<String>.Empty;
}

# `path` as messages show it: without the `./` that joining it to the
# current folder adds.
shown_path(path: Path): String {
    var text = path.to_string();
    if (text.starts_with("./") or text.starts_with(".\\")) {
        return text.substr_bytes(2, text.size - 2);
    }
    return text;
}

# Whether the file at `path` has a line that starts with `[Test]`.
declares_tests(path: Path): bool {
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return false;
    }
    for (var line in text.value().split("\n")) {
        if (line.trim().starts_with("[Test]")) {
            return true;
        }
    }
    return false;
}

# Whether `name` contains one of `filters`, or there are none.
matches(name: String, filters: Array<String>): bool {
    if (filters.is_empty) {
        return true;
    }
    for (var filter in filters) {
        if (name.contains(filter)) {
            return true;
        }
    }
    return false;
}

# The test's name, after its file's when tests from several files run.
display_name(test: Test, qualify: bool): String {
    return qualify ? $"{test.file}::{test.name}" : test.name;
}

plural(count: ulong, one: String, many: String): String {
    return count == 1 ? one : many;
}

executable_suffix(): String {
    return os.system_os() == os.OperatingSystem.Windows ? ".exe" : "";
}

# Reports a usage error and returns the usage-error status.
usage_error(parser: cli.Parser, message: String): int {
    File.stderr().write_all($"pep-test: error: {message}\n{parser.usage()}\n");
    return 2;
}

# Reports an error and returns the failure status.
fail(message: String): int {
    File.stderr().write_all($"pep-test: error: {message}\n");
    return 1;
}
