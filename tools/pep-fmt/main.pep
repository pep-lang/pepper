# pep-fmt: formats Pepper source in the standard style, like gofmt.
#
#     pep-fmt < file.pep > formatted.pep    # standard input to standard output
#     pep-fmt file.pep                      # a file's formatted text to standard output
#     pep-fmt -w file.pep src/              # rewrite files that are not formatted
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
#     pepper -I tools tools/pep-fmt/main.pep -o pep-fmt

import [Directory, File, Path] from io;
import syntax;
import "format";

# The help text. (A function: a module-scope `const` cannot hold a String.)
usage(): String {
    return "usage: pep-fmt [-w] [--check] [FILE | DIRECTORY]...\n\n"
        + "With no files, formats standard input to standard output.\n\n"
        + "  -w       rewrite each file that is not formatted\n"
        + "  --check  list each file that is not formatted, and exit with 1 if any is\n"
        + "  -h       show this help\n";
}

main(args: String[]): int {
    var write = false;
    var check = false;
    var paths = Array<Path>();
    ulong index = 1;
    while (index < args.count()) {
        var part = args[index];
        if (part == "-w") {
            write = true;
        } else if (part == "--check") {
            check = true;
        } else if (part == "-h" or part == "--help") {
            File.stdout().write_all(usage());
            return 0;
        } else if (part.starts_with("-") and part.size() > 1) {
            File.stderr().write_all("pep-fmt: error: unknown option '" + part + "'\n" + usage());
            return 2;
        } else {
            paths.append(Path(part));
        }
        index += 1;
    }
    if (paths.empty()) {
        if (write or check) {
            File.stderr().write_all("pep-fmt: error: -w and --check need files\n" + usage());
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
        var result = format_file(file, write, check);
        if (result == FILE_FAILED) {
            failed = true;
        } else if (result == FILE_CHANGED and check) {
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

# Appends every `.pep` file under `directory` to `files`, in name order,
# skipping directories whose names start with `.`. Returns false after
# reporting a directory it cannot list.
collect_sources(directory: Path, files: Array<Path>): bool {
    var opened = Directory.open(directory);
    if (opened.is_err()) {
        File.stderr().write_all(
            "pep-fmt: error: cannot list '" + directory.to_string() + "': " + opened.error().message + "\n"
        );
        return false;
    }
    var listed = opened.value().entries();
    if (listed.is_err()) {
        File.stderr().write_all(
            "pep-fmt: error: cannot list '" + directory.to_string() + "': " + listed.error().message + "\n"
        );
        return false;
    }
    var entries = listed.value();
    # Listing order depends on the file system: sort for stable output.
    entries.sort((a, b) => a.name.compare(b.name));
    var succeeded = true;
    for (var entry in entries) {
        if (entry.is_directory and !entry.is_symlink) {
            if (!entry.name.starts_with(".") and !collect_sources(entry.path, files)) {
                succeeded = false;
            }
        } else if (entry.is_file and entry.name.ends_with(".pep")) {
            files.append(entry.path);
        }
    }
    return succeeded;
}
