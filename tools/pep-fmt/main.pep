# pep-fmt: formats Pepper source in the standard style, like gofmt.
#
#     pep-fmt < file.pep > formatted.pep    # standard input to standard output
#     pep-fmt file.pep                      # a file's formatted text to standard output
#     pep-fmt -w file.pep src/              # rewrite files that are not formatted (--write)
#     pep-fmt --check src/                  # list files that are not formatted
#
# A directory stands for every `.pep` file under it, skipping directories whose
# names start with `.`. A syntax error is reported clang-style
# (`file.pep:3:14: error: ...`) and leaves that file untouched.
#
# Exit status: 0 on success; 1 when a file cannot be read, written or parsed,
# or when `--check` lists a file; 2 for a usage error.
#
# Build it from the repository root with the tools folder on the import path:
#
#     pepper build tools/pep-fmt/main.pep -o pep-fmt

import cli;
import [File, Path] from io;
import compiler.parse;
import process;
import syntax;
import "files";
import "format";

# The release this tool belongs to. `pep-doc check` keeps it equal to the
# version in VERSION.
version(): String {
    return "0.11.0";
}

# On a stack of `parse.STACK_SIZE`, which the deepest source fits in.
main(): int {
    return parse.on_compiler_stack(() => _main(process.arguments()));
}

_main(args: String[]): int {
    var parser = cli.Parser(
        "pep-fmt", "Formats Pepper source; with no files, standard input to standard output.", version = version()
    );
    var write = parser.flag("write", "w", "rewrite each file that is not formatted");
    var check = parser.flag("check", help = "list each file that is not formatted, and exit with 1 if any is");
    var sources = parser.positionals("paths", "files, and directories to search for .pep files");
    if (!parser.parse(args)) {
        return 2;
    }
    var paths = Array<Path>();
    for (var source in sources.values()) {
        paths.append(Path(source));
    }
    if (paths.is_empty) {
        if (write.is_set or check.is_set) {
            File.stderr().write_all("pep-fmt: error: -w and --check need files\n" + parser.usage() + "\n");
            return 2;
        }
        return format_standard_input();
    }
    var files = Array<Path>();
    var failed = false;
    for (var path in paths) {
        if (path.is_directory()) {
            if (!collect_sources(path, files)) {
                failed = true;
            }
        } else {
            files.append(path);
        }
    }
    var unformatted = false;
    for (var file in files) {
        var result = format_file(file, write.is_set, check.is_set);
        if (result == FILE_FAILED) {
            failed = true;
        } else if (result == FILE_CHANGED and check.is_set) {
            unformatted = true;
        }
    }
    return failed or unformatted ? 1 : 0;
}

# What `format_file` found.
const FILE_FORMATTED = 0;
const FILE_CHANGED = 1;
const FILE_FAILED = 2;

# Formats standard input to standard output.
format_standard_input(): int {
    var input = File.stdin().read_string();
    if (input.is_err()) {
        File.stderr().write_all("pep-fmt: error: cannot read standard input: " + input.error().message + "\n");
        return 1;
    }
    var formatted = format_or_report("<stdin>", input.value());
    if (formatted === __null) {
        return 1;
    }
    File.stdout().write_all(formatted);
    return 0;
}

# Formats one file: prints the result, or with `write` rewrites the file when
# it changes, and with `check` lists it when it changes.
format_file(path: Path, write: bool, check: bool): int {
    var name = path.to_string();
    var input = File.read_to_string(path);
    if (input.is_err()) {
        File.stderr().write_all("pep-fmt: error: cannot read '" + name + "': " + input.error().message + "\n");
        return FILE_FAILED;
    }
    var source = input.value();
    var formatted = format_or_report(name, source);
    if (formatted === __null) {
        return FILE_FAILED;
    }
    if (!write and !check) {
        File.stdout().write_all(formatted);
        return FILE_FORMATTED;
    }
    if (formatted == source) {
        return FILE_FORMATTED;
    }
    if (check) {
        File.stdout().write_all(name + "\n");
    }
    if (write) {
        var written = File.write_text(path, formatted);
        if (written.is_err()) {
            File.stderr().write_all("pep-fmt: error: cannot write '" + name + "': " + written.error().message + "\n");
            return FILE_FAILED;
        }
    }
    return FILE_CHANGED;
}

# The formatted `source`, or null after reporting its syntax error as `name`.
format_or_report(name: String, source: String): String {
    var formatted = format_source(source);
    if (formatted.is_err()) {
        var error = formatted.error();
        var line = syntax.line_of(source, error.offset);
        var column = syntax.column_of(source, error.offset);
        File.stderr().write_all(
            name + ":" + to_string(line) + ":" + to_string(column) + ": error: " + error.message + "\n"
        );
        return __null;
    }
    return formatted.value();
}
