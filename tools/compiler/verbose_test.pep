# `pep-build -v` as a user sees it (#361): standard error names the
# runtime, the build folder, the link command and the output; without
# `-v` the build prints nothing.

import [Path] from io;
import process;
import [TempFolder] from testing;
import [expect_contains, expect_exit, run, tool, write_file] from tool_testing;
import toolchain;

# Builds `folder`'s `main.pep`, with `options` after the build's own.
_build(folder: Path, options: Array<String>): process.Output {
    return run(
        process
            .Command(tool("pep-build").to_string())
            .argument(folder.join("main.pep").to_string())
            .argument("-o")
            .argument(folder.join("main" + toolchain.executable_suffix()).to_string())
            .argument("--build")
            .argument(folder.join("build").to_string())
            .argument("--cache")
            .argument(folder.join("cache").to_string())
            .arguments(options)
    );
}

# The value of the line of `text` that starts with `label: `, or empty.
_line(text: String, label: String): String {
    for (var line in text.lines()) {
        if (line.starts_with(label + ": ")) {
            return line.substr_bytes(label.size + 2, line.size - label.size - 2);
        }
    }
    return "";
}

[Test]
verbose_names_the_runtime_folders_link_and_output() {
    var folder = TempFolder("verbose");
    write_file(folder.path.join("main.pep"), "main(): int {\n    return 0;\n}\n");
    var program = folder.path.join("main" + toolchain.executable_suffix()).to_string();
    var built = _build(folder.path, ["-v"]);
    expect_exit(built, 0);
    expect_equal(built.stdout, "");
    var runtime = _line(built.stderr, "runtime");
    expect_true(Path(runtime).join("string.pep").is_file());
    expect_equal(_line(built.stderr, "build folder"), folder.path.join("build").to_string());
    expect_equal(_line(built.stderr, "cache folder"), folder.path.join("cache").to_string());
    expect_contains(_line(built.stderr, "clang"), "clang");
    # The link: clang, writing the program.
    var link = _line(built.stderr, "running");
    expect_contains(link, "clang");
    expect_contains(link, $" -o {process.Command(program).to_string()}");
    expect_equal(_line(built.stderr, "wrote"), program);
    # Without `-v`, the same build prints nothing.
    var quiet = _build(folder.path, Array<String>());
    expect_exit(quiet, 0);
    expect_equal(quiet.stderr, "");
    expect_equal(quiet.stdout, "");
}
