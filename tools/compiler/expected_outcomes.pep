# The curated programs of the compiler's tests: each states, on its first
# lines, how compiling it ends (`# expect: accepted`, or the first line of
# each diagnostic), and `check_programs` holds the compiler to it. The
# expectations were recorded when pepc matched the Rust compiler byte for
# byte (#225's cutover); one that changes marks a changed diagnostic or a
# change in what the language accepts.
#
# PEPC_RECORD_EXPECTATIONS=<folder> records instead: each test's outcomes,
# in order, go to a file of that folder named after the test's folder.

import [Directory, File, Path] from io;
import os;
import [TempFolder] from testing;

## Writes each program to a `main.pep` of its own in `folder`, compiles it
## with `outcome`, and returns how many did not end as their first lines
## expect.
##
## @param folder where the programs go
## @param programs the programs, each starting with `# expect: ...`
## @param outcome how compiling the `main.pep` it is given ends
## @returns how many programs ended otherwise
export check_programs(folder: TempFolder, programs: String[], outcome: (Path) => String): ulong {
    var trees = Array<String[]>();
    for (var program in programs) {
        trees.append(["main.pep", program]);
    }
    return check_trees(folder, trees, outcome);
}

## `check_programs` for programs of several files: each tree (name, text,
## name, text, ...) goes to a folder of its own in `folder`, with a `deps`
## folder, and its `main.pep`, which starts with the expectation, is the
## root `outcome` is given.
##
## @param folder where the trees go
## @param trees the programs' files, each with a `main.pep`
## @param outcome how compiling the `main.pep` it is given ends
## @returns how many programs ended otherwise
export check_trees(folder: TempFolder, trees: String[][], outcome: (Path) => String): ulong {
    var recording = os.environment("PEPC_RECORD_EXPECTATIONS");
    var recorded = StringBuilder();
    ulong mismatches = 0;
    ulong t = 0;
    while (t < trees.count) {
        var root = folder.path.join($"program{t}");
        var files = trees[t];
        var main = "";
        ulong i = 0;
        while (i + 1 < files.count) {
            var path = root.join(files[i]);
            Directory.create_all(path.parent().value());
            File.write_text(path, files[i + 1]);
            if (files[i] == "main.pep") {
                main = files[i + 1];
            }
            i += 2;
        }
        Directory.create_all(root.join("deps"));
        var ended = outcome(root.join("main.pep"));
        if (recording.is_value()) {
            var line = ended.replace("\n", "\t");
            recorded.append($"{line}\n");
        } else if (ended != expectation(main)) {
            print($"program {t}:\n{ended}\n  expected:\n{expectation(main)}");
            mismatches += 1;
        }
        t += 1;
    }
    if (recording.is_value()) {
        var name = folder.path.file_name().value();
        File.write_text(
            Path(recording.value()).join(name.substr_bytes(0, name.rfind("_") as ulong)), recorded.to_string()
        );
    }
    return mismatches;
}

## What `program`'s first lines, `# expect: ...`, say compiling it ends
## as: `accepted`, or the first line of each diagnostic, one per line.
##
## @param program the program's text
## @returns the expected lines, joined by newlines
export expectation(program: String): String {
    var prefix = "# expect: ";
    var lines = Array<String>();
    for (var line in program.split("\n")) {
        if (!line.starts_with(prefix)) {
            break;
        }
        lines.append(line.substr_bytes(prefix.size, line.size - prefix.size));
    }
    return lines.is_empty ? "(no expectation)" : "\n".join(lines);
}

## The first line of each diagnostic of `report` (its errors, warnings and
## notes, as rendered), each as `headline` gives it, joined by newlines;
## `accepted` when there are none.
##
## @param report rendered diagnostics
## @param root the program's root file
## @returns the lines
export headlines(report: String, root: Path): String {
    var lines = Array<String>();
    for (var line in report.split("\n")) {
        if (line.contains(": error: ") or line.contains(": warning: ") or line.contains(": note: ")) {
            lines.append(headline(line, root));
        }
    }
    return lines.is_empty ? "accepted" : "\n".join(lines);
}

## The first line of `error`, with the folder of `root` and the runtime's
## left out of the file names in it (`main.pep`, `runtime/...`).
##
## @param error an error, as the compiler reports it
## @param root the program's root file
## @returns the line
export headline(error: String, root: Path): String {
    var end = error.find("\n");
    var line = end < 0 ? error : error.substr_bytes(0, end as ulong);
    # Windows' paths take `/` too, as the expectations are written.
    bool windows = os.system_os() == os.OperatingSystem.Windows;
    if (windows) {
        line = line.replace("\\", "/");
    }
    var folder = root.parent();
    if (folder.is_value()) {
        var prefix = folder.value().to_string();
        if (windows) {
            prefix = prefix.replace("\\", "/");
        }
        line = line.replace(prefix + "/", "");
    }
    return _without_runtime_folder(line);
}

# `line` with each absolute path to the runtime's folder, or into it, cut
# to start at `runtime`.
_without_runtime_folder(line: String): String {
    var out = StringBuilder();
    ulong copied = 0;
    ulong at = 0;
    while (true) {
        var found = line.substr_bytes(at, line.size - at).find("/runtime");
        if (found < 0) {
            break;
        }
        var k = at + found as ulong;
        var after = k + 8;
        var ends = after == line.size
            or line.byte_at(after) == '/'
            or line.byte_at(after) == ':'
            or line.byte_at(after) == ','
            or line.byte_at(after) == ' '
            or line.byte_at(after) == '\'';
        # The path's start: after a space, a quote or a parenthesis.
        ulong start = k;
        while (start > copied
            and line.byte_at(start - 1) != ' '
            and line.byte_at(start - 1) != '\''
            and line.byte_at(start - 1) != '"'
            and line.byte_at(start - 1) != '(') {
            start -= 1;
        }
        var absolute = start < k and (line.byte_at(start) == '/' or line.byte_at(start + 1) == ':');
        if (ends and absolute) {
            out.append(line.substr_bytes(copied, start - copied));
            copied = k + 1;
        }
        at = after;
    }
    out.append(line.substr_bytes(copied, line.size - copied));
    return out.to_string();
}
