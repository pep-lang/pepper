# The pep-fmt program end to end, the one beside the test program or on
# the PATH (scripts/pepper-tests.sh builds it): standard input to
# standard output, syntax errors where the compiler reports them, files
# and folders with --check and -w, usage errors and --version. Run with
# `-I tools`.

import [Directory, Path] from io;
import process;
import [TempFolder] from testing;
import [
    expect_contains, expect_exit, expect_starts_with, read_file, run, run_with_input, tool, write_file
] from tool_testing;

# The error pep-fmt prints for `source` on standard input, which must
# fail to format.
error_of(source: String): String {
    var output = run_with_input(process.Command(tool("pep-fmt").to_string()), source);
    expect_exit(output, 1);
    return output.stderr;
}

[Test]
formats_standard_input_to_standard_output() {
    var output = run_with_input(process.Command(tool("pep-fmt").to_string()), "main(): int {\nreturn 0;\n}\n");
    expect_equal(output.stderr, "");
    expect_equal(output.stdout, "main(): int {\n    return 0;\n}\n");
    expect_true(output.status.success());
}

[Test]
reports_a_missing_semicolon_after_the_statement() {
    # As the compiler does: right after the last token, not at the next line.
    expect_equal(
        error_of("main(): int {\n    var total = 1\n    return total;\n}\n"), "<stdin>:2:18: error: expected ';'\n"
    );
    expect_equal(error_of("import io\nvar x = 1;\n"), "<stdin>:1:10: error: expected ';'\n");
    expect_equal(error_of("struct S {\n    int x\n}\n"), "<stdin>:2:10: error: expected ';'\n");
    expect_equal(error_of("extern int puts(char* s)\n"), "<stdin>:1:25: error: expected ';'\n");
}

[Test]
reports_syntax_errors_with_their_location() {
    expect_equal(error_of("main(): int {\n    return (1;\n}\n"), "<stdin>:2:14: error: expected ')'\n");
    expect_equal(
        error_of("main(): int {\n    var c = 'a;\n}\n"), "<stdin>:2:13: error: missing terminating ' character\n"
    );
    expect_equal(
        error_of("main(): int {\n    var s = $\"a;\n}\n"), "<stdin>:2:13: error: missing terminating '\"' character\n"
    );
    expect_equal(
        error_of("main(): int {\n    var s = $\"{a # b}\";\n}\n"),
        "<stdin>:2:18: error: a comment cannot appear inside '{}' in an interpolated string\n"
    );
    expect_equal(error_of("main(): int {\n    var s = $\"{a;\n}\n"), "<stdin>:2:18: error: expected '}'\n");
}

[Test]
checks_and_rewrites_files_and_folders() {
    var folder = TempFolder("pep_fmt_files");
    var root = folder.path;
    var messy = "main(): int {\nreturn 0;\n}\n";
    var tidy = "main(): int {\n    return 0;\n}\n";
    write_file(root.join("src").join("b.pep"), messy);
    write_file(root.join("src").join("a.pep"), tidy);
    write_file(root.join("src").join("nested").join("c.pep"), messy);
    write_file(root.join("src").join(".cache").join("skipped.pep"), "not pepper (");
    write_file(root.join("src").join("notes.txt"), messy);
    var pep_fmt = tool("pep-fmt").to_string();

    # A file argument prints its formatted text.
    var printed = run(process.Command(pep_fmt).argument("src/b.pep").working_directory(root));
    expect_exit(printed, 0);
    expect_equal(printed.stdout, tidy);
    expect_equal(printed.stderr, "");
    # --check lists what would change, in name order, and changes nothing.
    var checked = run(process.Command(pep_fmt).arguments(["--check", "src"]).working_directory(root));
    expect_exit(checked, 1);
    var b = Path("src").join("b.pep").to_string();
    var c = Path("src").join("nested").join("c.pep").to_string();
    expect_equal(checked.stdout, $"{b}\n{c}\n");
    expect_equal(read_file(root.join("src").join("b.pep")), messy);
    # -w rewrites them; afterwards --check is clean.
    var written = run(process.Command(pep_fmt).arguments(["-w", "src"]).working_directory(root));
    expect_exit(written, 0);
    expect_equal(written.stdout + written.stderr, "");
    expect_equal(read_file(root.join("src").join("nested").join("c.pep")), tidy);
    expect_equal(read_file(root.join("src").join("notes.txt")), messy);
    var clean = run(process.Command(pep_fmt).arguments(["--check", "src"]).working_directory(root));
    expect_exit(clean, 0);
    expect_equal(clean.stdout + clean.stderr, "");

    # A syntax error names the file and leaves it alone.
    write_file(root.join("broken.pep"), "g(: int {}\n");
    var broken = run(process.Command(pep_fmt).arguments(["-w", "broken.pep"]).working_directory(root));
    expect_exit(broken, 1);
    expect_equal(broken.stdout, "");
    expect_equal(broken.stderr, "broken.pep:1:3: error: expected a type\n");
    expect_equal(read_file(root.join("broken.pep")), "g(: int {}\n");
}

[Test]
rejects_bad_usage() {
    var pep_fmt = tool("pep-fmt").to_string();
    var unknown = run(process.Command(pep_fmt).argument("--frobnicate"));
    expect_exit(unknown, 2);
    expect_starts_with(unknown.stderr, "pep-fmt: error: unknown option '--frobnicate'\nusage: pep-fmt");
    var no_files = run(process.Command(pep_fmt).argument("-w"));
    expect_exit(no_files, 2);
    expect_starts_with(no_files.stderr, "pep-fmt: error: -w and --check need files\n");
    var help = run(process.Command(pep_fmt).argument("-h"));
    expect_exit(help, 0);
    expect_contains(help.stdout, "\nusage: pep-fmt [OPTIONS] [paths]...\n");
    expect_contains(help.stdout, "  -w, --write  ");
}
