# Removing a package's folder.

import [Directory, Path] from io;
import io;
import os;

# Removes `path` and everything under it. On Windows it first makes every
# file writable: git marks its object files read-only, and Windows will not
# delete a read-only file, so `Directory.remove_all` stops there (Go's
# `os.RemoveAll` clears the attribute the same way).
export remove_tree(path: Path): io.IoResult<void> {
    if (os.system_name() == "windows") {
        _make_writable(path);
    }
    return Directory.remove_all(path);
}

# Clears the read-only flag of every file under `path`, not following
# symlinks; what cannot be listed or changed is left for the removal to
# report.
_make_writable(path: Path) {
    var opened = Directory.open(path);
    if (opened.is_err()) {
        return;
    }
    var listed = opened.value().entries();
    if (listed.is_err()) {
        return;
    }
    for (var entry in listed.value()) {
        if (entry.is_symlink) {
            continue;
        }
        if (entry.is_directory) {
            _make_writable(entry.path);
        } else if (entry.is_file) {
            entry.path.set_read_only(false);
        }
    }
}
