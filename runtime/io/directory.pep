# Directory, DirEntry.

import "types";
import "path";
import "file";
import "sys_posix";
import "sys_windows";

## One entry of a directory listing, as `Directory.entries()` returns it.
##
## The kind flags come from the listing itself and describe the entry
## without following symlinks. On POSIX a symlink has `IsSymlink` set and
## `IsFile` and `IsDir` clear; on Windows a symlink or junction to a
## directory has both `IsDir` and `IsSymlink` set. Entries that are none of
## these (a FIFO, socket or device on POSIX) have all three flags clear. Call
## `metadata()` for the details of what the entry points to.
##
## @example
##     import io;
##
##     var list = io.Directory.open(io.Path("src")).Value.entries().Value;
##     ulong i = 0;
##     while (i < list.count()) {
##         if (list[i].IsFile) {
##             print(list[i].Name);
##         }
##         i = i + 1;
##     }
export struct DirEntry {
    ## The entry's full path: the listed directory's path joined with
    ## `Name` (relative when the directory's path was relative).
    Path Path;
    ## The entry's own file name, without any directory part.
    String Name;
    ## Whether the entry is a regular file (never true for a symlink).
    bool IsFile;
    ## Whether the entry is a directory. On POSIX never true for a symlink;
    ## on Windows also true for a symlink or junction to a directory.
    bool IsDir;
    ## Whether the entry is a symlink (on Windows, any reparse point,
    ## junctions included), which is not followed.
    bool IsSymlink;

    ## Creates an empty entry: empty `Path` and `Name`, all kind flags
    ## false. Entries are normally obtained from `Directory.entries()`.
    construct() {
    }

    ## Returns the metadata of the entry, following symlinks, exactly like
    ## `Path.metadata()` on the entry's `Path`. The file system is queried
    ## again now, so the result reflects any change since the listing was
    ## read.
    ##
    ## @returns the entry's `Metadata` (of the target, for a symlink); an
    ## error when it cannot be stat'ed, with `is_not_found()` when the entry
    ## was removed since the listing or is a dangling symlink
    ## @see Path.metadata
    IoResult<Metadata> metadata() {
        return _io_sys_stat(Path, true);
    }
}

## A directory on the file system, identified by its path, together with
## static functions that create, remove and inspect directories and the
## process's current and temporary directories.
##
## A `Directory` holds no operating-system handle: `open` only checks that
## the path is a directory, and each call to `entries()` reads the listing
## afresh.
##
## @example
##     import io;
##
##     var dir = io.Directory.temp().join_str("scratch").join_str("logs");
##     if (io.Directory.create_all(dir).is_ok()) {
##         var d = io.Directory.open(dir).Value;
##         var count = d.entries().Value.count();
##         io.Directory.remove_all(io.Directory.temp().join_str("scratch"));
##     }
export struct Directory {
    ## The directory's path, as given to `open`.
    Path Path;

    ## Creates a `Directory` with an empty `Path`, which names no directory.
    ## Use `Directory.open` to get one for an existing directory.
    construct() {
    }

    ## Checks that `path` exists and is a directory (following symlinks) and
    ## returns a `Directory` for it. Nothing is kept open, so the directory
    ## can still be renamed or removed afterwards.
    ##
    ## @param path the directory's path; a relative path is resolved against
    ## the current directory whenever the `Directory` is used
    ## @returns the `Directory`; an error when `path` cannot be stat'ed
    ## (`is_not_found()` for a missing or empty path,
    ## `is_permission_denied()`) or is not a directory (`is_not_a_directory()`,
    ## message `"not a directory"`)
    ## @example
    ##     import io;
    ##
    ##     var d = io.Directory.open(io.Path("src"));
    ##     if (d.is_err() && d.Error.is_not_a_directory()) {
    ##         print("src is a file");
    ##     }
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

    ## Reads the directory's listing now, all at once: every entry except
    ## `.` and `..`, in the order the operating system returns them (not
    ## sorted). Uses `opendir`/`readdir` on POSIX and
    ## `FindFirstFileW`/`FindNextFileW` on Windows.
    ##
    ## @returns the entries, possibly none; an error when the directory
    ## cannot be read: `is_not_found()` when it no longer exists (or, on
    ## POSIX, `Path` is empty), `is_permission_denied()`, or on POSIX
    ## `is_not_a_directory()` when `Path` now names a file
    ## @example
    ##     import io;
    ##
    ##     var list = io.Directory.open(io.Path(".")).Value.entries();
    ##     if (list.is_ok()) {
    ##         var n = list.Value.count();
    ##     }
    IoResult<DirEntry[]> entries() {
        return _io_sys_list(Path);
    }

    ## Creates one directory (`mkdir` on POSIX, with mode 0777 less the
    ## umask; `CreateDirectoryW` on Windows). Its parent must already exist.
    ##
    ## @param path the directory to create
    ## @returns an Ok result on success; an error when the directory cannot be
    ## created: `is_already_exists()` when anything (a file too) is already
    ## at `path`, `is_not_found()` when the parent is missing or the path is
    ## empty, `is_permission_denied()` when the parent is not writable
    ## @see create_all
    static IoResult<void> create(Path path) {
        return _io_sys_mkdir(path);
    }

    ## Creates a directory and any missing parents, like `mkdir -p`.
    ## Succeeds without doing anything when `path` is empty or already a
    ## directory (or a symlink to one). Parents are found lexically with
    ## `Path.parent()`; a relative path is created under the current
    ## directory. It is safe against another process creating the same
    ## directories at the same time.
    ##
    ## @param path the directory to create, with its parents
    ## @returns an Ok result on success; an error when a directory cannot be
    ## created: `is_already_exists()` when a file (not a directory) is at
    ## `path` or at one of its parents, `is_permission_denied()`, and so on.
    ## Parents created before the failure are left in place
    ## @example
    ##     import io;
    ##
    ##     var r = io.Directory.create_all(io.Path("build").join_str("out").join_str("logs"));
    static IoResult<void> create_all(Path path) {
        if (path.Value.Size == 0) {
            return _io_ok_void();
        }
        if (path.is_dir()) {
            return _io_ok_void();
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
                return _io_ok_void();
            }
        }
        return r;
    }

    ## Removes an empty directory (`rmdir` on POSIX, `RemoveDirectoryW` on
    ## Windows).
    ##
    ## @param path the directory to remove; it must be empty
    ## @returns an Ok result on success; an error when it cannot be removed:
    ## `is_directory_not_empty()` when it still has entries, `is_not_found()`
    ## when it is missing or the path is empty, `is_not_a_directory()` when
    ## `path` is a file, `is_permission_denied()`
    ## @see remove_all
    static IoResult<void> remove(Path path) {
        return _io_sys_rmdir(path);
    }

    ## Removes `path` and, if it is a directory, everything inside it,
    ## recursively. Symlinks are removed, never followed, so nothing outside
    ## the tree is touched. A file or symlink at `path` itself is simply
    ## removed.
    ##
    ## Stops at the first failure, leaving whatever was not yet removed; on
    ## Windows a read-only file inside the tree is such a failure
    ## (`is_permission_denied()`).
    ##
    ## @param path the file, symlink or directory tree to remove
    ## @returns an Ok result on success; an error when something cannot be
    ## removed: `is_not_found()` when `path` does not exist (unlike
    ## `rm -rf`, a missing path is an error) or is empty,
    ## `is_permission_denied()`, and so on
    ## @example
    ##     import io;
    ##
    ##     var tree = io.Directory.temp().join_str("my-scratch");
    ##     var r = io.Directory.remove_all(tree);
    ##     if (r.is_err() && !r.Error.is_not_found()) {
    ##         print(r.Error.Message);
    ##     }
    ## @see remove
    static IoResult<void> remove_all(Path path) {
        var m = _io_sys_stat(path, false);
        if (m.is_err()) {
            return IoResult<void>.err(m.Error);
        }
        if (m.Value.IsSymlink || !m.Value.IsDir) {
            return _io_sys_remove_link(path, m.Value.IsDir);
        }
        var list = _io_sys_list(path);
        if (list.is_err()) {
            return IoResult<void>.err(list.Error);
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

    ## Returns the process's current directory, against which relative paths
    ## are resolved (`getcwd` on POSIX, `GetCurrentDirectoryW` on Windows).
    ##
    ## @returns the current directory as an absolute path; an error when it
    ## cannot be determined, such as `is_not_found()` on POSIX when the
    ## directory has been removed
    ## @see set_current
    static IoResult<Path> current() {
        return _io_sys_getcwd();
    }

    ## Changes the process's current directory (`chdir` on POSIX,
    ## `SetCurrentDirectoryW` on Windows). This affects the whole process,
    ## every thread included: relative paths used anywhere afterwards
    ## resolve against the new directory.
    ##
    ## @param path the new current directory; a relative path is resolved
    ## against the old one
    ## @returns an Ok result on success; an error when the directory cannot be
    ## entered: `is_not_found()` when it is missing or the path is empty,
    ## `is_not_a_directory()` when it is a file, `is_permission_denied()`
    ## @see current
    static IoResult<void> set_current(Path path) {
        return _io_sys_chdir(path);
    }

    ## Returns the directory for temporary files. It is not created or
    ## checked, so it may not exist.
    ##
    ## On POSIX it is `$TMPDIR` with any trailing `/` removed, or `/tmp`
    ## when `TMPDIR` is unset or empty. On Windows it is what
    ## `GetTempPathW` reports (from `TMP`, `TEMP`, `USERPROFILE`, or the
    ## Windows directory) with its trailing separator removed unless it is
    ## a root, or `.` if that call fails.
    ##
    ## @returns the temporary directory's path, never an error
    ## @example
    ##     import io;
    ##
    ##     var scratch = io.Directory.temp().join_str("my-tool");
    static Path temp() {
        return _io_sys_temp_dir();
    }
}
