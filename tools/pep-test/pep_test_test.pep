# pep-test end to end, the one beside the test program or on the PATH
# (scripts/pepper-tests.sh builds it, beside the `pep-build` it runs): it
# finds the files that hold `[Test]` functions, builds each folder's with
# `pep-build --test`, runs every test in a process of its own, and
# reports. `testdata/math_test.pep.txt` is a test file whose tests pass,
# fail, panic as they should and as they should not, and time out, and
# `testdata/overflow_test.pep.txt` one that overflows its stack; the names
# keep the repository's own run from finding them.

import [Directory, Path] from io;
import process;
import [TempFolder] from testing;
import [
    expect_contains, expect_ends_with, expect_exit, expect_starts_with, read_file, run, tool, write_file
] from tool_testing;

# Runs pep-test with `arguments` in `folder`.
pep_test(folder: Path, arguments: Array<String>): process.Output {
    return run(
        process
            .Command(tool("pep-test").to_string())
            .arguments(arguments)
            .working_directory(folder)
            .remove_environment("PEPPER_BACKTRACE")
    );
}

[Test]
runs_every_test_in_a_folder() {
    var folder = TempFolder("pep_test_runs");
    write_file(
        folder.path.join("math_test.pep"), read_file(Path("pep-test").join("testdata").join("math_test.pep.txt"))
    );
    write_file(
        folder.path.join("more").join("text_test.pep"),
        "[Test]\nrepeats() {\n    expect_equal(\"ab\".repeat(2), \"abab\");\n}\n"
    );
    # No `[Test]` line: not built.
    write_file(folder.path.join("more").join("broken.pep"), "this does not parse");

    var ran = pep_test(folder.path, ["--jobs", "1", "--timeout", "1"]);
    expect_exit(ran, 1);
    var text = ran.stdout + ran.stderr;
    var math = "math_test.pep";
    var text_test = Path("more").join("text_test.pep").to_string();
    expect_starts_with(text, "running 6 tests\n");
    for (var line in [
        $"test {math}::doubles ... ok (",
        $"test {math}::doubles_wrongly ... FAILED (",
        $"test {math}::reads_past_the_end ... ok (",
        $"test {math}::returns_instead ... FAILED (",
        $"test {math}::spins ... FAILED (",
        $"test {text_test}::repeats ... ok ("
    ]) {
        expect_contains(text, line);
    }
    expect_contains(text, $"---- {math}::doubles_wrongly ({math}:14) ----\n{math}:15:5: panic: expect_equal failed\n");
    expect_contains(text, "note: the test returned, but should have panicked\n");
    expect_contains(text, "error: test 'spins' timed out after 1 second\n");
    # The failing test ends on its panic, not by the timeout (on Windows,
    # the program turns off the crash reporting that held it up).
    expect_equal(text.split("timed out").count, 2 as ulong);
    expect_ends_with(text, "3 passed, 3 failed\n");

    var listed = pep_test(folder.path, ["--list", "-f", "doubles"]);
    expect_exit(listed, 0);
    expect_equal(listed.stdout, $"{math}::doubles\n{math}::doubles_wrongly\n");

    # One file: the tests are named alone.
    var filtered = pep_test(folder.path, ["math_test.pep", "--filter", "reads", "-f", "doubles"]);
    expect_exit(filtered, 1);
    var filtered_text = filtered.stdout + filtered.stderr;
    expect_contains(filtered_text, "test doubles ... ok (");
    expect_ends_with(filtered_text, "2 passed, 1 failed, 2 filtered out\n");
}

[Test]
splits_the_tests_into_shards() {
    var folder = TempFolder("pep_test_shards");
    write_file(folder.path.join("a_test.pep"), "[Test]
one() {}

[Test]
two() {}

[Test]
three() {}
");
    write_file(folder.path.join("more").join("b_test.pep"), "[Test]
four() {}

[Test]
five() {}
");
    var b = Path("more").join("b_test.pep").to_string();
    # Every second test of the list, starting with the first or the second.
    var first = pep_test(folder.path, ["--list", "--shard", "1/2"]);
    expect_exit(first, 0);
    expect_equal(first.stdout, $"a_test.pep::one\na_test.pep::three\n{b}::five\n");
    var second = pep_test(folder.path, ["--list", "--shard", "2/2"]);
    expect_exit(second, 0);
    expect_equal(second.stdout, $"a_test.pep::two\n{b}::four\n");

    # The shard is taken from the tests the filter keeps.
    var ran = pep_test(folder.path, ["--shard", "2/2", "-f", "o"]);
    expect_exit(ran, 0);
    expect_contains(ran.stdout, "test a_test.pep::two ... ok (");
    expect_ends_with(ran.stdout, "1 passed, 0 failed, 2 filtered out, 2 in other shards\n");

    for (var shard in ["0/2", "3/2", "2", "1/0", "a/b"]) {
        var wrong = pep_test(folder.path, ["--shard", shard]);
        expect_exit(wrong, 2);
        expect_contains(
            wrong.stderr, $"pep-test: error: '--shard' must be I/N with 1 <= I <= N, such as 2/4, not '{shard}'\n"
        );
    }
}

[Test]
reports_a_file_that_does_not_build() {
    var folder = TempFolder("pep_test_broken");
    write_file(folder.path.join("good_test.pep"), "[Test]\npasses() {}\n");
    write_file(folder.path.join("bad_test.pep"), "[Test]\nfails_to_build() {\n    nope();\n}\n");
    var ran = pep_test(folder.path, Array<String>());
    expect_exit(ran, 1);
    var text = ran.stdout + ran.stderr;
    expect_contains(text, "error: cannot build the tests of 'bad_test.pep':\n");
    expect_contains(text, "bad_test.pep:3:5: error: call to undeclared function 'nope'");
    expect_contains(ran.stdout, "test good_test.pep::passes ... ok (");
    expect_ends_with(ran.stdout, "1 passed, 0 failed; 1 test program did not build\n");
}

[Test]
reports_a_test_that_leaks_or_over_releases() {
    # The runner counts live allocations around each test body
    # (runtime/testing/runner.pep): one left behind, or one freed that the
    # test did not allocate (from C's calloc, uncounted), fails the test.
    var folder = TempFolder("pep_test_leaks");
    write_file(
        folder.path.join("leak_test.pep"),
        "extern void* calloc(ulong count, ulong size);\n\n"
            + "[Test]\nleaks() {\n    _pep_malloc(1024);\n}\n\n"
            + "[Test]\nover_releases() {\n    _pep_free(calloc(1, 1024));\n}\n\n"
            + "[Test]\nbalances() {\n    _pep_free(_pep_malloc(1024));\n}\n"
    );
    var ran = pep_test(folder.path, Array<String>());
    expect_exit(ran, 1);
    var text = ran.stdout + ran.stderr;
    expect_contains(text, "test leaks ... FAILED (");
    expect_contains(text, "test over_releases ... FAILED (");
    expect_contains(text, "test balances ... ok (");
    expect_contains(text, "error: test 'leaks' left 1 allocation behind\n");
    expect_contains(text, "error: test 'over_releases' released 1 allocation too many\n");
    expect_ends_with(ran.stdout, "1 passed, 2 failed\n");
}

[Test]
reports_test_files_of_a_module_that_clash() {
    # The test files of a module's folder see each other's names (their
    # tests' included), so two `helper`s clash in their folder's program;
    # `private` keeps them apart.
    var folder = TempFolder("pep_test_clash");
    write_file(folder.path.join("shop").join("module.pep"), "");
    write_tests(folder.path, "");
    var clashed = pep_test(folder.path, Array<String>());
    expect_exit(clashed, 1);
    var text = clashed.stdout + clashed.stderr;
    expect_contains(text, "(2 files) together:\n");
    expect_contains(text, "error: redefinition of 'helper'");
    expect_ends_with(clashed.stdout, "2 passed, 0 failed; 1 test program did not build\n");

    write_tests(folder.path, "private ");
    var passed = pep_test(folder.path, Array<String>());
    expect_exit(passed, 0);
    expect_ends_with(passed.stdout, "2 passed, 0 failed\n");
}

[Test]
removes_what_tests_leave_in_the_temporary_folder() {
    # Neither test's TempFolder is removed by its destructor: one panics,
    # the other times out.
    var folder = TempFolder("pep_test_temp");
    write_file(
        folder.path.join("leak_test.pep"),
        "import io;\nimport [TempFolder] from testing;\n\n"
            + "[Test]\npanics() {\n    var folder = TempFolder(\"panics\");\n"
            + "    io.File.write_text(io.Directory.temp().join(\"left.txt\"), \"left\");\n    panic(\"stop\");\n}\n\n"
            + "[Test]\nspins() {\n    var folder = TempFolder(\"spins\");\n    while (true) {}\n}\n"
    );
    var temp = folder.path.join("temp");
    write_file(temp.join("kept.txt"), "kept");
    var command = process
        .Command(tool("pep-test").to_string())
        .arguments(["--timeout", "1"])
        .working_directory(folder.path)
        .remove_environment("PEPPER_BACKTRACE");
    for (var name in ["TMPDIR", "TMP", "TEMP"]) {
        command.environment(name, temp.to_string());
    }
    var ran = run(command);
    expect_exit(ran, 1);
    expect_ends_with(ran.stdout, "0 passed, 2 failed\n");
    var entries = Directory.open(temp).value().entries().value();
    expect_equal(entries.count, 1 as ulong);
    expect_equal(entries[0].name, "kept.txt");
}

# Writes the test files `a_test.pep` and `b_test.pep` of the module `shop`
# in `folder`, each declaring a `helper` with `modifier` (`private `).
write_tests(folder: Path, modifier: String) {
    for (var name in ["a", "b"]) {
        write_file(
            folder.join("shop").join("test").join($"{name}_test.pep"),
            modifier + "helper(): int { return 1; }\n\n[Test]\n" + name + "_runs() { expect_equal(helper(), 1); }\n"
        );
    }
}

# A test file's `hang()`: a command that runs a long time, writing to the
# output it inherits from the test program (pep-test's pipes).
_hang_source(): String {
    return "import async;\nimport process;\n\n"
        + "[Target(OS(Windows))]\nhang(): process.Command {\n"
        + "    return process.Command(\"ping\").arguments([\"-n\", \"1000\", \"127.0.0.1\"]);\n}\n\n"
        + "[Target(!OS(Windows))]\nhang(): process.Command {\n"
        + "    return process.Command(\"sleep\").argument(\"1000\");\n}\n\n";
}

[Test]
ends_what_a_test_that_times_out_started() {
    # The child holds pep-test's pipes to the test's output open: unless
    # the timeout ends it too, pep-test never finishes.
    var folder = TempFolder("pep_test_tree");
    write_file(
        folder.path.join("tree_test.pep"),
        _hang_source()
            + "[Test]\nstarts_a_child_that_hangs() {\n"
            + "    hang().spawn();\n"
            + "    async.Thread.sleep(1000000);\n}\n"
    );
    var ran = pep_test(folder.path, ["--timeout", "1"]);
    expect_exit(ran, 1);
    expect_contains(ran.stdout + ran.stderr, "error: test 'starts_a_child_that_hangs' timed out after 1 second\n");
    expect_ends_with(ran.stdout, "0 passed, 1 failed\n");
}

[Test]
ends_what_a_test_that_panics_or_returns_started() {
    # As for a timeout: the children of a test that panics or returns end
    # with it, or pep-test never finishes. No timeout: the watchdog
    # is not what ends them.
    var folder = TempFolder("pep_test_tree");
    write_file(
        folder.path.join("tree_test.pep"),
        _hang_source()
            + "[Test]\nstarts_a_child_and_panics() {\n"
            + "    hang().spawn();\n"
            + "    panic(\"on purpose\");\n}\n\n"
            + "[Test]\nstarts_a_child_and_returns() {\n"
            + "    hang().spawn();\n}\n"
    );
    var ran = pep_test(folder.path, ["--timeout", "0"]);
    expect_exit(ran, 1);
    expect_contains(ran.stdout + ran.stderr, "panic: on purpose\n");
    expect_ends_with(ran.stdout, "1 passed, 1 failed\n");
}

[Test]
reports_a_test_that_overflows_its_stack() {
    # The runner's crash handler takes only the faults that are not an
    # overflow, so the test reports it, and still ends its children.
    var folder = TempFolder("pep_test_overflow");
    write_file(
        folder.path.join("overflow_test.pep"),
        read_file(Path("pep-test").join("testdata").join("overflow_test.pep.txt"))
    );
    var ran = pep_test(folder.path, ["--timeout", "0"]);
    expect_exit(ran, 1);
    expect_contains(ran.stdout + ran.stderr, "panic: stack overflow\n");
    expect_ends_with(ran.stdout, "0 passed, 1 failed\n");
}

[Test]
warns_of_a_test_near_its_timeout() {
    # 2.7 s of a 4 s timeout is over the 60% that warns; 0 s is not.
    var folder = TempFolder("pep_test_slow");
    write_file(
        folder.path.join("slow_test.pep"),
        "import os;\n\n[Test]\nslow() {\n    var start = os.Instant.now();\n"
            + "    while (start.elapsed().milliseconds() < 2700) {}\n}\n\n[Test]\nquick() {}\n"
    );
    var ran = pep_test(folder.path, ["--timeout", "4"]);
    expect_exit(ran, 0);
    expect_contains(ran.stdout, "warning: test slow took ");
    expect_contains(ran.stdout, ", over 60% of its 4 s timeout\n");
    expect_equal(ran.stdout.split("warning:").count, 2 as ulong);
}
