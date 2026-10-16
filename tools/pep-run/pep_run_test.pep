# `pep-run` end to end: the `pep-run` and `pep-build` that
# scripts/pepper-tests.sh built (beside the test program or on the PATH)
# build and run the programs in `testdata/`, with a Pepper home of the
# test's own, so the run folder and the build cache start empty.

import [File, Path] from io;
import process;
import [TempFolder] from testing;
import [expect_contains, expect_exit, expect_starts_with, run, tool, write_file] from tool_testing;

# Runs `pep-run` in `folder`, with `PEPPER_HOME` set to its `home`.
pep_run(folder: Path, arguments: Array<String>): process.Output {
    return run(
        process
            .Command(tool("pep-run").to_string())
            .arguments(arguments)
            .working_directory(folder)
            .environment("PEPPER_HOME", folder.join("home").to_string())
            .remove_environment("PEPPER_CACHE_DIR")
    );
}

# The test program `name` from `testdata/`, copied into `folder`.
copy_source(name: String, folder: Path) {
    File.copy(Path("pep-run").join("testdata").join(name), folder.join(name)).value();
}

[Test]
builds_and_runs_a_program_in_the_folder_it_starts_in() {
    var folder = TempFolder("pep_run_runs");
    copy_source("script.pep", folder.path);
    write_file(folder.path.join("data.txt"), "found");
    # `-T cache` shows whether pep-build had anything to do; the build
    # options are part of the key, so every run here passes it.
    var first = pep_run(folder.path, ["-T", "cache", "script.pep"]);
    expect_exit(first, 0);
    expect_equal(first.stdout, "data found\n");
    # The arguments after the file are the program's, options included,
    # and its exit status is pep-run's.
    var again = pep_run(folder.path, ["-T", "cache", "script.pep", "3", "--help"]);
    expect_exit(again, 3);
    expect_equal(again.stdout, "argument 3\nargument --help\ndata found\n");
    # Nothing changed, so the program is not built again.
    expect_contains(again.stderr, "is up to date");
    # After `--`, every argument is the program's.
    expect_equal(
        pep_run(folder.path, ["-T", "cache", "script.pep", "--", "x"]).stdout, "argument --\nargument x\ndata found\n"
    );
}

# `--entry` names the function the program starts in, and the program's
# arguments still follow the file.
[Test]
starts_in_the_function_entry_names() {
    var folder = TempFolder("pep_run_entry");
    write_file(
        folder.path.join("tool.pep"),
        "main(): int {\n    return 7;\n}\n\nbench(args: String[]): int {\n    print($\"bench {args[1]}\");\n    return 4;\n}\n"
    );
    var started = pep_run(folder.path, ["--entry", "bench", "tool.pep", "x"]);
    expect_exit(started, 4);
    expect_equal(started.stdout, "bench x\n");
    expect_exit(pep_run(folder.path, ["tool.pep"]), 7);
}

[Test]
reports_a_compile_error_and_runs_nothing() {
    var folder = TempFolder("pep_run_broken");
    copy_source("broken.pep", folder.path);
    var broken = pep_run(folder.path, ["broken.pep"]);
    expect_exit(broken, 1);
    expect_equal(broken.stdout, "");
    expect_starts_with(broken.stderr, "broken.pep:2:12: error: use of undeclared identifier 'nope'\n");
}

[Test]
refuses_the_options_that_choose_what_pep_build_writes() {
    var folder = TempFolder("pep_run_refuses");
    for (var option in ["-o", "-oout", "--lib", "--test", "--target=x86_64-pc-windows-msvc", "--emit-llvm"]) {
        var refused = pep_run(folder.path, [option, "script.pep"]);
        expect_exit(refused, 2);
        expect_contains(refused.stderr, "is not taken: pep-run runs the executable it builds\n");
    }
    expect_starts_with(pep_run(folder.path, ["--help"]).stdout, "Builds a Pepper program and runs it.\n");
}
