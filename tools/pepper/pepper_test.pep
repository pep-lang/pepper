# The `pepper` entry point end to end. Each test copies the `pepper` that
# scripts/pepper-tests.sh built (beside the test program or on the PATH)
# into a folder `bin` of its own, beside stand-in tools, and runs it with
# only another folder, `elsewhere`, on the PATH. The stand-ins are built
# from `testdata/`: `pep-echo` prints its arguments and exits with a
# chosen status, and `pep-build` and `elsewhere/pep-elsewhere` are copies
# of it; `pep-ask` prints a line, then reads its standard input to the
# end.

import [Directory, Path] from io;
import process;
import regex;
import [TempFolder] from testing;
import text;
import [
    build_program,
    copy_executable,
    exit_code,
    expect_contains,
    expect_ends_with,
    expect_exit,
    expect_starts_with,
    read_file,
    run,
    tool
] from tool_testing;
import toolchain;

const USAGE = "usage: pepper [+<version>] [-C <dir>]... <command> [arguments]\n";

# A test's folders: `bin` holding `pepper` and the stand-in tools, and
# `elsewhere`, the only folder on the PATH.
struct Layout {
    var folder: TempFolder;
    var bin: Path;
    var elsewhere: Path;

    # Copies `pepper` into a fresh `bin` and adds the stand-in tools that
    # `tools` names (`echo`, `ask`); `pep-build` and `pep-elsewhere` come
    # with `echo`. With `stand_ins`, each tool is a copy of `pepper`
    # instead, which lists as a command as well but does not run as one.
    construct(name: String, tools: Array<String>, stand_ins: bool = false) {
        folder = TempFolder(name);
        bin = folder.path.join("bin");
        elsewhere = folder.path.join("elsewhere");
        Directory.create_all(bin);
        Directory.create_all(elsewhere);
        copy_executable(tool("pepper"), executable(bin, "pepper"));
        for (var tool_name in tools) {
            var program = executable(bin, $"pep-{tool_name}");
            if (stand_ins) {
                copy_executable(tool("pepper"), program);
            } else {
                var source = Path("pepper").join("testdata").join($"{tool_name}.pep");
                var error = build_program(source, program, folder.path.join($"build_{tool_name}"));
                if (error.is_value()) {
                    panic($"cannot build pep-{tool_name}:\n{error.value()}");
                }
            }
            if (tool_name == "echo") {
                copy_executable(program, executable(bin, "pep-build"));
                copy_executable(program, executable(elsewhere, "pep-elsewhere"));
            }
        }
    }

    # The command that runs this layout's `pepper` with `arguments`, with
    # only `elsewhere` on the PATH.
    pepper(arguments: Array<String>): process.Command {
        return process
            .Command(executable(bin, "pepper").to_string())
            .arguments(arguments)
            .environment("PATH", elsewhere.to_string());
    }
}

# The executable `name` in `folder`.
executable(folder: Path, name: String): Path {
    return folder.join(name + toolchain.executable_suffix());
}

[Test]
runs_the_tool_beside_it_with_the_remaining_arguments() {
    var layout = Layout("pepper_runs", ["echo"]);
    var echoed = run(layout.pepper(["echo", "a", "b c"]));
    expect_equal(echoed.stdout, "a|b c\n");
    expect_exit(echoed, 0);
    # It exits with the tool's exit status.
    expect_equal(exit_code(run(layout.pepper(["echo", "exit", "7"]))), 7);
    # A tool only the PATH names.
    expect_equal(run(layout.pepper(["elsewhere", "x"])).stdout, "x\n");
    # `help <command>` runs the command's help.
    expect_equal(run(layout.pepper(["help", "echo"])).stdout, "--help\n");
    # A source file first runs pep-build, after a warning.
    var built = run(layout.pepper(["main.pep", "-o", "main"]));
    expect_equal(built.stdout, "main.pep|-o|main\n");
    expect_equal(
        built.stderr, "pepper: warning: 'pepper main.pep ...' is deprecated; use 'pepper build main.pep ...'\n"
    );
}

[Test]
streams_the_tools_output_and_input_while_it_runs() {
    # `pep-ask` prints a line and then waits for standard input, so the
    # line must reach this pipe before the tool exits: if `print` buffered
    # it, or `pepper` held the tool's output, the first read would wait
    # for an exit that never comes, and the test would time out.
    var layout = Layout("pepper_streams", ["ask"]);
    var child = layout
        .pepper(Array<String>())
        .argument("ask")
        .stdin(process.Stream.Pipe)
        .stdout(process.Stream.Pipe)
        .spawn()
        .value();
    var read = Array<u8>();
    while (!read.contains('\n' as u8) and child.stdout().read(read, 64).value() > 0) {}
    var first = text.Utf8.decode_lossy(read).replace("\r\n", "\n");
    child.stdin().write_all("answer");
    child.stdin().close();
    var rest = child.stdout().read_string().value().replace("\r\n", "\n");
    var status = child.wait().value();
    expect_equal(first + rest, "ready\ngot answer\n");
    expect_equal(status.code().value_or(-1), 0);
}

[Test]
reports_unknown_commands_and_lists_the_ones_it_finds() {
    var layout = Layout("pepper_commands", ["ask", "build", "echo"], stand_ins = true);
    copy_executable(tool("pepper"), executable(layout.elsewhere, "pep-elsewhere"));
    var commands = "Commands:\n  ask\n  build\n  echo\n  elsewhere\n";
    # The closest command to an unknown one.
    var unknown = run(layout.pepper(["ecoh"]));
    expect_exit(unknown, 1);
    expect_equal(unknown.stderr, $"pepper: error: 'ecoh' is not a pepper command; did you mean 'echo'?\n\n{commands}");
    # A command that names a path.
    var path = run(layout.pepper(["../bin/pep-echo"]));
    expect_exit(path, 1);
    expect_starts_with(path.stderr, "pepper: error: '../bin/pep-echo' is not a pepper command\n");
    # `help` lists every command, beside it and on the PATH.
    var help = run(layout.pepper(["help"]));
    expect_exit(help, 0);
    expect_starts_with(help.stdout, USAGE);
    expect_ends_with(help.stdout, commands);
    # With no command, the usage.
    var bare = run(layout.pepper(Array<String>()));
    expect_exit(bare, 2);
    expect_starts_with(bare.stderr, USAGE);
}

[Test]
dash_c_runs_the_tool_in_that_folder() {
    var layout = Layout("pepper_dash_c", ["echo"]);
    var nested = layout.folder.path.join("c").join("d");
    Directory.create_all(nested);
    var dir = nested.canonicalize().value();
    var changed = run(layout.pepper(["-C", dir.to_string(), "echo", "cwd"]));
    expect_exit(changed, 0);
    expect_equal(Path(changed.stdout.trim()).canonicalize().value().to_string(), dir.to_string());
    # Repeated, each is relative to the one before; an empty one stays.
    var parent = dir.parent().value().to_string();
    var repeated = run(layout.pepper(["-C", parent, "-C", "", "-C", "d", "echo", "cwd"]));
    expect_exit(repeated, 0);
    expect_equal(Path(repeated.stdout.trim()).canonicalize().value().to_string(), dir.to_string());
    # Options after the command are the tool's.
    expect_equal(run(layout.pepper(["-C", dir.to_string(), "echo", "-C", "x"])).stdout, "-C|x\n");
    # A missing folder.
    var missing = layout.folder.path.join("missing");
    var failed = run(layout.pepper(["-C", missing.to_string(), "echo"]));
    expect_exit(failed, 1);
    expect_starts_with(failed.stderr, $"pepper: error: cannot change to '{missing}': ");
    # No folder, or no command after it.
    var no_folder = run(layout.pepper(["-C"]));
    expect_exit(no_folder, 2);
    expect_equal(no_folder.stderr, "pepper: error: option '-C' requires a directory\n");
    var no_command = run(layout.pepper(["-C", dir.to_string()]));
    expect_exit(no_command, 2);
    expect_starts_with(no_command.stderr, USAGE);
}

# Every tool's `version()` names one release, which `scripts/set-version.sh`
# stamps into each `tools/*/main.pep` (pep-lsp's, into its `arguments.pep`;
# and, while it is there, Cargo.toml), and the tools built from them report
# it with `--version`.
[Test]
every_tool_reports_the_release_version() {
    var pattern = regex.Regex("\n(export )?version\\(\\): String \\{\\s*return \"([^\"]+)\";");
    var release = pattern.find(read_file(Path("pepper").join("main.pep"))).value().group(2).value();
    var listing = Directory.open(Path(".")).value().entries().value();
    ulong stamped = 0;
    for (var entry in listing) {
        var found = pattern.find(read_file(entry.path.join("main.pep")));
        if (entry.name == "pep-lsp") {
            found = pattern.find(read_file(entry.path.join("arguments.pep")));
        }
        if (found.is_value()) {
            expect_equal($"{entry.name} {found.value().group(2).value()}", $"{entry.name} {release}");
            stamped += 1;
        }
    }
    expect_true(stamped >= 10, "the tools' version() functions are found from tools/");
    var cargo = Path("..").join("Cargo.toml");
    if (cargo.is_file()) {
        expect_contains(read_file(cargo), $"\n[workspace.package]\nversion = \"{release}\"\n");
    }
    for (var name in [
        "pepper", "pep-fmt", "pep-init", "pep-new", "pep-package", "pep-profile", "pep-run", "pep-test"
    ]) {
        var reported = run(process.Command(tool(name).to_string()).argument("--version"));
        expect_equal(reported.stdout, $"{name} {release}\n");
    }
    # pep-lsp is not built by scripts/pepper-tests.sh (it needs the pepper-lsp
    # package fetched), so only its source is checked, above.
    # pep-build is the toolchain's, which can be another build.
    expect_starts_with(run(process.Command(tool("pep-build").to_string()).argument("--version")).stdout, "pep-build ");
}
