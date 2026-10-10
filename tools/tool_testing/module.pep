## Helpers for the tests that run the Pepper tools end to end (`pepper`,
## `pep-test`, `pep-fmt`, `pep-package`, `pep-profile`, and `pep-build` on
## the `tests/` corpus): finding a tool, running it, and building a small
## program with `pep-build`.
##
## The tools come from beside the test program or the PATH, where
## `scripts/pepper-tests.sh` puts the ones it builds from the checkout. To
## run such a test by hand, build the tools it runs and put their folder
## first on the PATH (`target/pepper-tests/bin` after a run of the script).

import [Directory, File, Path] from io;
import process;

## The Pepper tool `name` (`pep-fmt`, `pep-build`): the one beside the test
## program, or else the first on the PATH.
##
## @param name the tool's file name, without `.exe`
## @returns its path
## @panics if neither place holds it
export tool(name: String): Path {
    var found = process.find_companion(name);
    if (found.is_empty()) {
        panic($"cannot find {name} beside the test program or on the PATH; scripts/pepper-tests.sh builds the tools");
    }
    return found.value();
}

## Runs `command` to its end, with standard output and error piped unless
## set otherwise, and returns how it ended and what it wrote, with each
## `"\r\n"` (Windows' line end) read as `"\n"`.
##
## @param command the program to run
## @returns its exit status and output
## @panics if the program cannot be started
export run(command: process.Command): process.Output {
    var ran = command.run();
    if (ran.is_err()) {
        panic($"cannot run {command.program}: {ran.error().message}");
    }
    var output = ran.value();
    return process.Output(output.status, output.stdout.replace("\r\n", "\n"), output.stderr.replace("\r\n", "\n"));
}

## Runs `command` with `input` on its standard input, as `run` does
## otherwise. The input is written whole before the output is read, so it
## suits a few lines, which fit in the pipe.
##
## @param command the program to run
## @param input what it reads from standard input
## @returns its exit status and output
## @panics if the program cannot be started
export run_with_input(command: process.Command, input: String): process.Output {
    var spawned = command.stdin(process.Stream.Pipe).stdout(process.Stream.Pipe).stderr(process.Stream.Pipe).spawn();
    if (spawned.is_err()) {
        panic($"cannot run {command.program}: {spawned.error().message}");
    }
    var child = spawned.value();
    child.stdin().write_all(input);
    child.stdin().close();
    var stdout = child.stdout().read_string().ok_or("");
    var stderr = child.stderr().read_string().ok_or("");
    var status = child.wait().value();
    return process.Output(status, stdout.replace("\r\n", "\n"), stderr.replace("\r\n", "\n"));
}

## The exit code `output`'s program ended with: -1 when a signal ended it.
##
## @param output what `run` returned
## @returns the exit code
export exit_code(output: process.Output): int {
    return output.status.code().value_or(-1);
}

## Copies the executable `from` to `to`, which can then run.
##
## @param from the executable
## @param to the copy
## @panics if it cannot be copied
export copy_executable(from: Path, to: Path) {
    var copied = File.copy(from, to);
    if (copied.is_err()) {
        panic($"cannot copy '{from}' to '{to}': {copied.error().message}");
    }
    to.set_executable(true);
}

## Builds the program `source` with `pep-build` into `program`, keeping its
## build files in the folder `build`.
##
## @param source the entry file
## @param program the executable to write
## @param build the folder for the build files
## @param options more options for `pep-build`, such as `-I tests`
## @returns none when it builds; else what `pep-build` printed
export build_program(source: Path, program: Path, build: Path, options: Array<String> = Array<String>()): String? {
    var built = run(
        process
            .Command(tool("pep-build").to_string())
            .argument(source.to_string())
            .argument("-o")
            .argument(program.to_string())
            .argument("--build")
            .argument(build.to_string())
            .arguments(options)
    );
    if (built.status.success()) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value($"{built.stdout}{built.stderr}");
}

## Writes `text` to the file `path`, making the folders above it.
##
## @param path the file
## @param text its contents
## @panics if the file cannot be written
export write_file(path: Path, text: String) {
    var parent = path.parent();
    if (parent.is_value()) {
        Directory.create_all(parent.value());
    }
    var written = File.write_text(path, text);
    if (written.is_err()) {
        panic($"cannot write '{path}': {written.error().message}");
    }
}

## The text of the file `path`, or empty when it cannot be read.
##
## @param path the file
## @returns its text
export read_file(path: Path): String {
    return File.read_to_string(path).ok_or("");
}

## Checks that `output`'s program exited with `code`, and shows what it
## wrote when not.
##
## @param output what `run` returned
## @param code the exit code expected
## @panics with the program's output if it exited otherwise
export expect_exit(output: process.Output, code: int, location: __ptr<char> = __caller_location()) {
    if (exit_code(output) != code) {
        panic(
            $"expected exit code {code}, got {output.status.to_string()}\nstdout:\n{output.stdout}\nstderr:\n{output.stderr}",
            location
        );
    }
}

## Checks that `text` contains `part`, and shows `text` when not.
##
## @param text the text checked
## @param part what it must contain
## @panics with both if it does not
export expect_contains(text: String, part: String, location: __ptr<char> = __caller_location()) {
    if (!text.contains(part)) {
        panic($"expected the text to contain:\n{part}\nthe text:\n{text}", location);
    }
}

## Checks that `text` starts with `prefix`, and shows `text` when not.
##
## @param text the text checked
## @param prefix what it must start with
## @panics with both if it does not
export expect_starts_with(text: String, prefix: String, location: __ptr<char> = __caller_location()) {
    if (!text.starts_with(prefix)) {
        panic($"expected the text to start with:\n{prefix}\nthe text:\n{text}", location);
    }
}

## Checks that `text` ends with `suffix`, and shows `text` when not.
##
## @param text the text checked
## @param suffix what it must end with
## @panics with both if it does not
export expect_ends_with(text: String, suffix: String, location: __ptr<char> = __caller_location()) {
    if (!text.ends_with(suffix)) {
        panic($"expected the text to end with:\n{suffix}\nthe text:\n{text}", location);
    }
}
