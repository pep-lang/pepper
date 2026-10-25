# Vendored packages: the copy of each locked package `pep-package vendor`
# writes into a project's `[fetch] vendor` folder, and the check a build
# and `pep-package fetch` run on it. Each package's folder holds its files,
# `.pep-commit` (the commit, as an unpacked archive in `.pep/deps` does)
# and `.pep-checksum` (`vendored_sha256` of the rest), so an edit to a
# vendored file is caught.

import digest;
import [Directory, File, Path] from io;

## The file in a vendored package's folder holding the checksum of its files.
export const VENDOR_CHECKSUM_FILE = ".pep-checksum";

## The file in a vendored package's folder naming the commit it holds.
export const VENDOR_COMMIT_FILE = ".pep-commit";

## The checksum of the files under `dir`, a vendored package: the sha256 of
## each file's path (from `dir`, with `/`) and contents, in path order,
## leaving out `VENDOR_CHECKSUM_FILE`. File modes are not covered: Windows
## has no executable bit to compare. A vendored package holds no symbolic
## link (`pep-package vendor` refuses one), so a link under `dir` fails.
##
## @param dir the package's folder
## @returns the checksum in hex, or why a file could not be read or which
##   symbolic link `dir` holds
export vendored_sha256(dir: Path): Result<String, String> {
    var files = Array<(String, Path)>();
    var listed = _list_files(dir, "", files);
    if (listed.is_err()) {
        return Result<String, String>.err(listed.error());
    }
    files.sort((a: (String, Path), b: (String, Path)) => a.0.compare(b.0));
    var hasher = digest.Sha256();
    for (var (name, path) in files) {
        var bytes = File.read_bytes(path);
        if (bytes.is_err()) {
            return Result<String, String>.err($"cannot read {path.to_string()}: {bytes.error().message}");
        }
        hasher.update($"{name}\n{bytes.value().count}\n");
        hasher.update(bytes.value());
    }
    return Result<String, String>.ok(hasher.finish_hex());
}

# Adds each file under `dir` to `files`, by its path below the package
# (`prefix`), failing at a symbolic link.
_list_files(dir: Path, prefix: String, files: Array<(String, Path)>): Result<void, String> {
    var opened = Directory.open(dir);
    if (opened.is_err()) {
        return Result<void, String>.err($"cannot open {dir.to_string()}: {opened.error().message}");
    }
    var listed = opened.value().entries();
    if (listed.is_err()) {
        return Result<void, String>.err($"cannot list {dir.to_string()}: {listed.error().message}");
    }
    for (var entry in listed.value()) {
        var name = prefix + entry.path.file_name().value_or("");
        if (entry.is_symlink) {
            return Result<void, String>.err(
                $"'{entry.path.to_string()}' is a symbolic link, which a vendored package cannot hold"
            );
        }
        if (name == VENDOR_CHECKSUM_FILE) {
            continue;
        }
        if (entry.is_directory) {
            var nested = _list_files(entry.path, name + "/", files);
            if (nested.is_err()) {
                return nested;
            }
        } else if (entry.is_file) {
            files.append((name, entry.path));
        }
    }
    return Result<void, String>.ok();
}

## Checks that `dir` holds the vendored package at `commit`, unedited: its
## `VENDOR_COMMIT_FILE` names `commit`, its files have the checksum its
## `VENDOR_CHECKSUM_FILE` records, and it holds no symbolic link.
##
## @param dir the package's folder in the vendor folder
## @param commit the commit `pep.lock` records for it
## @returns nothing, or what is wrong, ending in what to run
export check_vendored(dir: Path, commit: String): Result<void, String> {
    var again = "run 'pepper package vendor'";
    if (!dir.is_directory()) {
        return Result<void, String>.err($"{dir.to_string()} does not exist; {again}");
    }
    var at = File.read_to_string(dir.join(Path(VENDOR_COMMIT_FILE)));
    var recorded = File.read_to_string(dir.join(Path(VENDOR_CHECKSUM_FILE)));
    if (at.is_err() or recorded.is_err()) {
        return Result<void, String>.err(
            $"{dir.to_string()} is not a vendored package: it lacks {VENDOR_COMMIT_FILE} or {VENDOR_CHECKSUM_FILE}; {again}"
        );
    }
    if (at.value().trim() != commit) {
        return Result<void, String>.err(
            $"{dir.to_string()} holds commit {at.value().trim()}, and pep.lock locks {commit}; {again}"
        );
    }
    var sha256 = vendored_sha256(dir);
    if (sha256.is_err()) {
        return Result<void, String>.err($"{sha256.error()}; {again}");
    }
    if (sha256.value() != recorded.value().trim()) {
        return Result<void, String>.err(
            $"the files in {dir.to_string()} were changed since they were vendored (sha256 {sha256.value()}, recorded {recorded.value().trim()}); {again} to restore them, or make the change in the package itself"
        );
    }
    return Result<void, String>.ok();
}
