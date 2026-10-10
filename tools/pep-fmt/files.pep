# Finding the files pep-fmt formats.

import [Directory, File, Path] from io;

## Appends every `.pep` file under `directory` to `files`, in name order,
## skipping directories whose names start with `.`. Returns false after
## reporting a directory it cannot list.
export collect_sources(directory: Path, files: Array<Path>): bool {
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
