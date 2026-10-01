# Directory, DirEntry.

import "file";
import "path";
import "sys_posix";
import "sys_windows";
import "types";

## One entry of a directory listing, as `Directory.entries()` returns it.
##
## The kind flags come from the listing itself and describe the entry
## without following symlinks. On POSIX a symlink has `is_symlink` set and
## `is_file` and `is_directory` clear; on Windows a symlink or junction to a
## directory has both `is_directory` and `is_symlink` set. Entries that are none of
## these (a FIFO, socket or device on POSIX) have all three flags clear. Call
## `metadata()` for the details of what the entry points to.
##
## @example
##     import io;
##
##     var list = io.Directory.open(io.Path("src")).value().entries().value();
##     ulong i = 0;
##     while (i < list.count()) {
##         if (list[i].is_file) {
##             print(list[i].Name);
##         }
##         i = i + 1;
##     }
export struct DirEntry {
    ## The entry's full path: the listed directory's path joined with
    ## `name` (relative when the directory's path was relative).
    Path path;
    ## The entry's own file name, without any directory part.
    String name;
    ## The kind of the entry, without following symlinks: `Symlink` for a
    ## symlink (on Windows, any reparse point, even one to a directory),
    ## `Other` for anything that is not a file, directory or symlink.
    FileType file_type;
    ## Whether the entry is a regular file (never true for a symlink).
    bool is_file;
    ## Whether the entry is a directory. On POSIX never true for a symlink;
    ## on Windows also true for a symlink or junction to a directory.
    bool is_directory;
    ## Whether the entry is a symlink (on Windows, any reparse point,
    ## junctions included), which is not followed.
    bool is_symlink;

    ## Creates an empty entry: empty `path` and `name`, all kind flags
    ## false and `file_type` `Other`. Entries are normally obtained from
    ## `Directory.entries()`.
    construct() {
        file_type = FileType.Other;
    }

    ## Returns the metadata of the entry, following symlinks, exactly like
    ## `Path.metadata()` on the entry's `path`. The file system is queried
    ## again now, so the result reflects any change since the listing was
    ## read.
    ##
    ## @returns the entry's `Metadata` (of the target, for a symlink); an
    ## error when it cannot be stat'ed, with `is_not_found()` when the entry
    ## was removed since the listing or is a dangling symlink
    ## @see Path.metadata
    metadata(): IoResult<Metadata> {
        return _io_sys_stat(path, true);
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
##     var dir = io.Directory.temp().join("scratch").join("logs");
##     if (io.Directory.create_all(dir).is_ok()) {
##         var d = io.Directory.open(dir).value();
##         var count = d.entries().value().count();
##         io.Directory.remove_all(io.Directory.temp().join("scratch"));
##     }
export struct Directory {
    ## The directory's path, as given to `open`.
    Path path;

    ## Creates a `Directory` with an empty `path`, which names no directory.
    ## Use `Directory.open` to get one for an existing directory.
    construct() {}

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
    ##     if (d.is_err() && d.error().is_not_a_directory()) {
    ##         print("src is a file");
    ##     }
    static open(path: Path): IoResult<Directory> {
        var m = _io_sys_stat(path, true);
        if (m.is_err()) {
            return IoResult<Directory>.err(m.error());
        }
        if (!m.value().is_directory) {
            return IoResult<Directory>.err(IoError(_io_sys_code_not_a_directory(), "not a directory"));
        }
        var d = Directory();
        d.path = path;
        return IoResult<Directory>.ok(d);
    }

    ## Reads the directory's listing now, all at once: every entry except
    ## `.` and `..`, in the order the operating system returns them (not
    ## sorted). Uses `opendir`/`readdir` on POSIX and
    ## `FindFirstFileW`/`FindNextFileW` on Windows. To read the entries one
    ## at a time instead, loop over the `Directory` itself (see `iterate`).
    ##
    ## @returns the entries, possibly none; an error when the directory
    ## cannot be read: `is_not_found()` when it no longer exists (or, on
    ## POSIX, `path` is empty), `is_permission_denied()`, or on POSIX
    ## `is_not_a_directory()` when `path` now names a file
    ## @example
    ##     import io;
    ##
    ##     var list = io.Directory.open(io.Path(".")).value().entries();
    ##     if (list.is_ok()) {
    ##         var n = list.value().count();
    ##     }
    entries(): IoResult<DirEntry[]> {
        return _io_list(path);
    }

    ## Returns an iterator that reads the directory's listing one entry at a
    ## time, as `for (var entry in dir)` does, without building an array.
    ##
    ## Each element is an `IoResult<DirEntry>`. The listing is opened by the
    ## first `next()`, so a directory that cannot be read yields one error
    ## (the same errors as `entries()`) and then ends; an error while
    ## reading also ends it. The entries come in the order the operating
    ## system returns them, without `.` and `..`. The listing is closed
    ## when it ends, or when the iterator is released, so leaving the loop
    ## early with `break` or `return` closes it too.
    ##
    ## @returns a new `DirectoryIterator` positioned before the first entry
    ## @example
    ##     import io;
    ##
    ##     var dir = io.Directory.open(io.Path(".")).value();
    ##     for (var entry in dir) {
    ##         if (entry.is_err()) {
    ##             print(entry.error().message);
    ##             break;
    ##         }
    ##         print(entry.value().name);
    ##     }
    iterate(): DirectoryIterator {
        return DirectoryIterator(path);
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
    static create(path: Path): IoResult<void> {
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
    ##     var r = io.Directory.create_all(io.Path("build").join("out").join("logs"));
    static create_all(path: Path): IoResult<void> {
        if (path._value.size() == 0) {
            return _io_ok_void();
        }
        if (path.is_directory()) {
            return _io_ok_void();
        }
        var parent = path.parent();
        if (parent) {
            var p = create_all(parent.value());
            if (p.is_err()) {
                return p;
            }
        }
        var r = _io_sys_mkdir(path);
        # Lost a race with another creator, or `path` ends in "." / "..":
        # fine as long as a directory is there now.
        if (r.is_err()) {
            if (path.is_directory()) {
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
    static remove(path: Path): IoResult<void> {
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
    ##     var tree = io.Directory.temp().join("my-scratch");
    ##     var r = io.Directory.remove_all(tree);
    ##     if (r.is_err() && !r.error().is_not_found()) {
    ##         print(r.error().message);
    ##     }
    ## @see remove
    static remove_all(path: Path): IoResult<void> {
        var m = _io_sys_stat(path, false);
        if (m.is_err()) {
            return IoResult<void>.err(m.error());
        }
        if (m.value().is_symlink || !m.value().is_directory) {
            return _io_sys_remove_link(path, m.value().is_directory);
        }
        var list = _io_list(path);
        if (list.is_err()) {
            return IoResult<void>.err(list.error());
        }
        var entries = list.value();
        ulong i = 0;
        while (i < entries.count()) {
            var entry = entries[i];
            i = i + 1;
            if (entry.is_directory && !entry.is_symlink) {
                var r = remove_all(entry.path);
                if (r.is_err()) {
                    return r;
                }
            } else {
                var r = _io_sys_remove_link(entry.path, entry.is_directory);
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
    static current(): IoResult<Path> {
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
    static set_current(path: Path): IoResult<void> {
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
    ##     var scratch = io.Directory.temp().join("my-tool");
    static temp(): Path {
        return _io_sys_temp_dir();
    }
}

## The iterator `Directory.iterate()` returns, and a `for` loop over a
## `Directory` drives: the directory's entries, read one at a time, each
## as an `IoResult<DirEntry>`.
##
## It holds the open listing (a `DIR*` on POSIX, a find handle on Windows)
## from the first `next()` until the listing ends, an error ends it, or the
## iterator is released.
##
## @example
##     import io;
##
##     var it = io.Directory.open(io.Path(".")).value().iterate();
##     while (it.next()) {
##         var entry = it.current();
##     }
## @see Directory.iterate
export struct DirectoryIterator {
    ## The directory being listed.
    Path _path;
    ## The open listing: a `DIR*` on POSIX, a find `HANDLE` on Windows; null
    ## before the first `next()` and once the listing is closed.
    __ptr<void> _handle;
    ## Windows only: the `WIN32_FIND_DATAW` the find functions fill; null on
    ## POSIX.
    __ptr<u8> _data;
    ## Windows only: whether `_data` holds an entry `FindFirstFileW` read that
    ## `next()` has not returned yet.
    bool _pending;
    ## Whether `next()` has been called.
    bool _started;
    ## Whether the listing has ended (or failed); `next()` then returns false.
    bool _finished;
    ## The entry the platform layer read last.
    DirEntry _entry;
    ## Whether `_value` holds the element the last `next()` moved to.
    bool _has_value;
    ## The current element.
    IoResult<DirEntry> _value;

    ## Makes an iterator over the entries of the directory at `path`. Nothing
    ## is opened until the first `next()`.
    ##
    ## @param path the directory to list
    construct(path: Path) {
        _path = path;
        _value = IoResult<DirEntry>.ok(DirEntry());
    }

    # Not through a call taking `this`: the destructor runs at refcount zero.
    destruct {
        _close();
    }

    # Closes the listing and frees the find data, if open.
    _close() {
        if (_handle != __null) {
            _io_sys_directory_close(_handle);
            _handle = __null;
        }
        if (_data != __null) {
            _pep_free(_data);
            _data = __null;
        }
    }

    ## Reads the next entry, opening the listing on the first call.
    ##
    ## Once it returns false it keeps returning false.
    ##
    ## @returns true if there is a current element (an entry, or the error
    ## that ends the listing), false once the listing has ended
    next(): bool {
        if (_finished) {
            _has_value = false;
            return false;
        }
        IoResult<bool> read;
        if (_started) {
            read = _io_sys_directory_next(this);
        } else {
            _started = true;
            read = _io_sys_directory_first(this);
        }
        if (read.is_err()) {
            _finished = true;
            _close();
            _value = IoResult<DirEntry>.err(read.error());
            _has_value = true;
            return true;
        }
        if (!read.value()) {
            _finished = true;
            _close();
            _has_value = false;
            return false;
        }
        _value = IoResult<DirEntry>.ok(_entry);
        _has_value = true;
        return true;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current entry, or the error that ended the listing
    ## @panics if `next()` was never called, or already returned false ("DirectoryIterator.current() without an entry")
    current(): IoResult<DirEntry> {
        assert(_has_value, "DirectoryIterator.current() without an entry");
        return _value;
    }
}

extend DirectoryIterator with Iterator<IoResult<DirEntry>>;

# Every entry of the directory at `path`, all at once (`Directory.entries()`).
export _io_list(path: Path): IoResult<DirEntry[]> {
    var out = Array<DirEntry>();
    for (var entry in DirectoryIterator(path)) {
        if (entry.is_err()) {
            return IoResult<DirEntry[]>.err(entry.error());
        }
        out.append(entry.value());
    }
    return IoResult<DirEntry[]>.ok(out);
}
