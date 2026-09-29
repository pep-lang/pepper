# Directory, DirEntry.

import "types";
import "path";
import "file";
import "sys_posix";
import "sys_windows";

export struct DirEntry {
    Path Path;     # full path: the directory joined with Name
    String Name;
    bool IsFile;
    bool IsDir;
    bool IsSymlink;

    construct() {
    }

    # Follows symlinks, like Path.metadata().
    IoResult<Metadata> metadata() {
        return _io_sys_stat(Path, true);
    }
}

export struct Directory {
    Path Path;

    construct() {
    }

    # Checks that `path` exists and is a directory.
    static IoResult<Directory> open(Path path) {
        var m = _io_sys_stat(path, true);
        if (m.is_err()) {
            return IoResult<Directory>.err(m.Error);
        }
        if (!m.Value.IsDir) {
            return IoResult<Directory>.err(IoError(_io_sys_code_not_a_directory(), "not a directory"));
        }
        var d = Directory();
        d.Path = path;
        return IoResult<Directory>.ok(d);
    }

    # Every entry except "." and "..", read eagerly.
    IoResult<DirEntry[]> entries() {
        return _io_sys_list(Path);
    }

    # mkdir / CreateDirectoryW: fails if it exists or the parent is missing.
    static IoResult<None> create(Path path) {
        return _io_sys_mkdir(path);
    }

    # mkdir -p: creates missing parents; succeeds if the directory exists.
    static IoResult<None> create_all(Path path) {
        if (path.Value.Size == 0) {
            return _io_ok_none();
        }
        if (path.is_dir()) {
            return _io_ok_none();
        }
        var parent = path.parent();
        if (parent.Value.Size > 0) {
            var p = Directory.create_all(parent);
            if (p.is_err()) {
                return p;
            }
        }
        var r = _io_sys_mkdir(path);
        # Lost a race with another creator, or `path` ends in "." / "..":
        # fine as long as a directory is there now.
        if (r.is_err()) {
            if (path.is_dir()) {
                return _io_ok_none();
            }
        }
        return r;
    }

    # Must be empty.
    static IoResult<None> remove(Path path) {
        return _io_sys_rmdir(path);
    }

    # Recursive. Symlinks are removed, never followed.
    static IoResult<None> remove_all(Path path) {
        var m = _io_sys_stat(path, false);
        if (m.is_err()) {
            return IoResult<None>.err(m.Error);
        }
        if (m.Value.IsSymlink || !m.Value.IsDir) {
            return _io_sys_remove_link(path, m.Value.IsDir);
        }
        var list = _io_sys_list(path);
        if (list.is_err()) {
            return IoResult<None>.err(list.Error);
        }
        var entries = list.Value;
        ulong i = 0;
        while (i < entries.count()) {
            var entry = entries[i];
            i = i + 1;
            if (entry.IsDir && !entry.IsSymlink) {
                var r = Directory.remove_all(entry.Path);
                if (r.is_err()) {
                    return r;
                }
            } else {
                var r = _io_sys_remove_link(entry.Path, entry.IsDir);
                if (r.is_err()) {
                    return r;
                }
            }
        }
        return _io_sys_rmdir(path);
    }

    # getcwd / GetCurrentDirectoryW.
    static IoResult<Path> current() {
        return _io_sys_getcwd();
    }

    static IoResult<None> set_current(Path path) {
        return _io_sys_chdir(path);
    }

    # $TMPDIR or /tmp (POSIX), GetTempPathW (Windows).
    static Path temp() {
        return _io_sys_temp_dir();
    }
}
