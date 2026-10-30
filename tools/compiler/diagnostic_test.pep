# Tests of how diagnostics name files (`compiler.diagnostic`).

import [shown_path] from compiler.diagnostic;
import os;
import [TempFolder] from testing;
import [build_program, expect_contains, write_file] from tool_testing;

# On Windows a file's name loses the verbatim prefix and keeps one
# separator (#311); other systems show it as it is.
[Test]
shows_a_file_name_as_the_user_reads_it() {
    if (os.system_os() != os.OperatingSystem.Windows) {
        expect_equal(shown_path("a\\b/c.pep"), "a\\b/c.pep");
        return;
    }
    expect_equal(shown_path("\\\\?\\D:\\x\\runtime\\string.pep"), "D:\\x\\runtime\\string.pep");
    expect_equal(shown_path("\\\\?\\UNC\\server\\share\\a.pep"), "\\\\server\\share\\a.pep");
    expect_equal(shown_path("D:/x/e2\\lib.pep"), "D:/x/e2/lib.pep");
    expect_equal(shown_path("main.pep"), "main.pep");
}

# A note in the runtime names its file without Windows' verbatim prefix.
[Test]
names_a_runtime_file_without_the_verbatim_prefix() {
    var folder = TempFolder("diagnostic_runtime_note");
    var source = folder.path.join("main.pep");
    write_file(source, "to_string(value: int): int {\n    return value;\n}\nmain(): int {\n    return 0;\n}\n");
    var error = build_program(source, folder.path.join("never"), folder.path.join("build"));
    expect_true(error.is_value(), "the program does not build");
    expect_contains(error.value(), "string.pep:");
    expect_true(!error.value().contains("\\\\?\\"), "no verbatim prefix");
}
