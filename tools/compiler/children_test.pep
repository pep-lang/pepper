# The children a build starts end with it: `pep-build` killed while its
# `--compile-part` children run leaves none running (#530), on Windows
# through its job object, elsewhere through the children's
# `process.exit_with_parent`.

import [Path] from io;
import os;
import process;
import [TempFolder] from testing;
import [tool, write_file] from tool_testing;
import toolchain;

# The children inherit the build's standard error, so the pipe the test
# reads it from ends only when the build and every child have ended. Each
# child waits a minute first (`PEPC_STALL_PARTS`), so one left running
# keeps the pipe open that long.
[Test]
a_killed_build_leaves_no_part_running() {
    var folder = TempFolder("children");
    var source = folder.path.join(Path("main.pep"));
    write_file(source, "main(): int {\n    return 0;\n}\n");
    var build = process
        .Command(tool("pep-build").to_string())
        .argument(source.to_string())
        .argument("-o")
        .argument(folder.path.join(Path("main" + toolchain.executable_suffix())).to_string())
        .argument("--build")
        .argument(folder.path.join(Path("build")).to_string())
        .argument("--cache")
        .argument(folder.path.join(Path("cache")).to_string())
        .environment("PEPC_STALL_PARTS", "60")
        .stderr(process.Stream.Pipe)
        .spawn()
        .value();
    var text = "";
    var stalled = false;
    for (var line in build.stderr().lines()) {
        stalled = line.is_ok() and line.value() == "part stalled";
        if (line.is_err() or stalled) {
            break;
        }
        text = $"{text}{line.value()}\n";
    }
    if (!stalled) {
        panic($"the build started no part:\n{text}");
    }
    expect_true(build.kill().is_ok());
    expect_true(build.wait().is_ok());
    var start = os.Instant.now();
    # To its end: the end of the build and of every child.
    build.stderr().read_all();
    if (start.elapsed().seconds() >= 30) {
        panic($"a part outlived its build:\n{text}");
    }
}
