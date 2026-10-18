# Watcher, FileChange, ChangeKind: notifications of changes in a directory
# tree.
#
# The platform layer is in watch_linux.pep (inotify), watch_mac.pep
# (kqueue) and watch_windows.pep (ReadDirectoryChangesW); each defines
# `_io_watch_open`, `_io_watch_read` and `_io_watch_close` for its OS, and
# the WASI ones below fail; `_io_watch_close` takes fields, not the
# Watcher, because the destructor calls it. `_io_watch_read` waits for the system to report
# something and appends what it found to `_pending`, possibly nothing (an
# event about a path no longer watched), so `wait` loops until a change
# comes. In a task the wait parks the task (see wait.pep): on Linux and
# macOS the inotify or kqueue descriptor is waited on like a socket; on
# Windows the read goes to the runtime whole (`_IoWaiter._directory_changes`).

import "path";
import "sys_posix";
import "sys_windows";
import "types";
import "watch_linux";
import "watch_mac";
import "watch_windows";

# The size of the buffer the system writes events into.
const _IO_WATCH_BUFFER_SIZE: ulong = 65536;

## What happened to a path, as a `FileChange` reports it.
export enum ChangeKind {
    ## The path was created, or moved into the tree.
    Created,
    ## The path was removed, or moved out of the tree.
    Removed,
    ## The file's contents or attributes changed.
    Modified,
    ## The system dropped changes because they came faster than they were
    ## read; the `path` is the watched directory. List it again to catch up.
    Overflow,
}

## One change `Watcher.wait` reports.
export struct FileChange {
    ## What happened.
    const kind: ChangeKind;
    ## The path that changed: the watched directory's path, as given to
    ## `Watcher.open`, joined with the path inside it.
    const path: Path;

    ## Creates a change.
    ##
    ## @param kind what happened
    ## @param path the path that changed
    construct(kind: ChangeKind, path: Path) {
        this.kind = kind;
        this.path = path;
    }
}

## Watches a directory and everything below it for changes: files and
## directories created, removed, renamed or written.
##
## `wait()` returns the next batch of changes, waiting until there is one.
## In a task (inside `async.run`) the wait parks only the task, and the
## task's cancel or timeout ends it; elsewhere it blocks the thread. A
## rename reports the old path `Removed` and the new one `Created`. One write
## may report `Modified` more than once, and consecutive repeats within a
## batch are dropped.
##
## Each system watches its own way: inotify on Linux, with a watch on every
## directory of the tree (new ones are added as they appear, and what they
## already hold is reported `Created`); kqueue on macOS, which holds a
## descriptor for every directory and file, so a large tree may need a
## higher `ulimit -n`; `ReadDirectoryChangesW` on Windows. Changes are
## recorded from `open` on, also while no `wait` is running. When the
## system drops changes, `wait` reports an `Overflow` change. A change made
## right as a new directory appears may be missed on Linux and macOS: look
## at the directory when its `Created` arrives if that matters. Watching is
## not supported on WASI.
##
## @example
##     import io;
##
##     var watcher = io.Watcher.open(io.Path("src")).value();
##     while (true) {
##         var changes = watcher.wait();
##         if (changes.is_err()) {
##             break;
##         }
##         for (var change in changes.value()) {
##             print($"{change.kind.name()}: {change.path}");
##         }
##     }
[NotCopyable("owns an operating-system handle and cannot be copied; open another Watcher on the receiving thread")]
export struct Watcher {
    ## The directory being watched, as given to `open`.
    Path directory;
    # The inotify or kqueue descriptor, or the directory's HANDLE as a
    # number on Windows; -1 once closed.
    long _handle;
    # The buffer the system writes events into.
    __ptr<u8> _buffer;
    # Linux: each inotify watch's directory. macOS: each descriptor's path.
    var _watches: HashMap<long, String>;
    # macOS: the names last seen in each watched directory.
    var _listings: HashMap<String, HashSet<String>>;
    # Changes found but not returned yet.
    var _pending: Array<FileChange>;

    ## Creates a closed Watcher; `wait()` on it fails. Use `Watcher.open`.
    construct() {
        _handle = -1;
        _buffer = _pep_malloc(_IO_WATCH_BUFFER_SIZE);
        _watches = HashMap<long, String>();
        _listings = HashMap<String, HashSet<String>>();
        _pending = Array<FileChange>();
    }

    ## Stops watching when the last reference goes, as `close()` does.
    destruct {
        close();
        # Only here: until a `wait` running in a task returns, the system
        # may still be writing into the buffer.
        _pep_free(_buffer);
    }

    ## Starts watching `directory` and everything below it.
    ##
    ## @param directory the directory to watch; a symlink to one is followed
    ## @returns the Watcher; an error when `directory` cannot be stat'ed
    ## (`is_not_found()`, `is_permission_denied()`), is not a directory
    ## (`is_not_a_directory()`), or the system cannot watch it (on Linux
    ## when the inotify watch limit is reached, on macOS when the process
    ## runs out of descriptors, and on WASI always)
    ## @example
    ##     import io;
    ##
    ##     var watcher = io.Watcher.open(io.Path("."));
    ##     if (watcher.is_err()) {
    ##         print(watcher.error().message);
    ##     }
    static open(directory: Path): IoResult<Watcher> {
        var m = _io_sys_stat(directory, true);
        if (m.is_err()) {
            return IoResult<Watcher>.err(m.error());
        }
        if (!m.value().is_directory) {
            return IoResult<Watcher>.err(IoError(_io_sys_code_not_a_directory(), "not a directory"));
        }
        var watcher = Watcher();
        watcher.directory = directory;
        var opened = _io_watch_open(watcher);
        if (opened.is_err()) {
            return IoResult<Watcher>.err(opened.error());
        }
        return IoResult<Watcher>.ok(watcher);
    }

    ## Waits for changes and returns them, oldest first: those recorded
    ## since the last call, or, when there are none, the next ones to come.
    ##
    ## @returns at least one change; an error when the Watcher is closed
    ## (also when another task closes it during the wait), when the task
    ## is cancelled or times out first (`is_cancelled()`, `is_timed_out()`),
    ## or when the system fails, as on Windows when the watched directory
    ## is removed
    wait(): IoResult<FileChange[]> {
        while (true) {
            if (_handle < 0) {
                return IoResult<FileChange[]>.err(_io_watcher_closed_error());
            }
            if (_pending.count > 0) {
                var changes = _io_watch_without_repeats(_pending);
                _pending = Array<FileChange>();
                return IoResult<FileChange[]>.ok(changes);
            }
            var read = _io_watch_read(this);
            if (read.is_err()) {
                return IoResult<FileChange[]>.err(read.error());
            }
        }
        return IoResult<FileChange[]>.ok(Array<FileChange>());
    }

    ## Stops watching and releases the system resources. A `wait` running in
    ## another task ends with an error. Closing again does nothing.
    close() {
        if (_handle < 0) {
            return;
        }
        # Fields, not `this`: the destructor calls this too, and passing
        # `this` there would count it back up and destroy it again.
        _io_watch_close(_handle, _watches);
        _handle = -1;
        _watches.clear();
        _listings.clear();
        _pending.clear();
    }

    ## Returns whether the Watcher is still watching (not closed).
    ##
    ## @returns true until `close()`
    is_open(): bool {
        return _handle >= 0;
    }

    # Records a change.
    _report(kind: ChangeKind, path: String) {
        _pending.append(FileChange(kind, Path(path)));
    }
}

# The error of a wait on a closed Watcher.
_io_watcher_closed_error(): IoError {
    return IoError(_io_sys_code_bad_handle(), "the watcher is closed");
}

# `changes` without a change that repeats the one before it.
_io_watch_without_repeats(changes: Array<FileChange>): FileChange[] {
    var kept = Array<FileChange>();
    for (var change in changes) {
        if (kept.count > 0) {
            var last = kept[kept.count - 1];
            if (last.kind == change.kind && last.path.to_string() == change.path.to_string()) {
                continue;
            }
        }
        kept.append(change);
    }
    return kept;
}

# The error of watching where the system cannot.
_io_watch_unsupported(): IoError {
    return IoError(_io_sys_code_invalid_input(), "watching files is not supported on this system");
}

[Target(OS(Wasi))]
_io_watch_open(watcher: Watcher): IoResult<void> {
    return IoResult<void>.err(_io_watch_unsupported());
}

[Target(OS(Wasi))]
_io_watch_read(watcher: Watcher): IoResult<void> {
    return IoResult<void>.err(_io_watch_unsupported());
}

[Target(OS(Wasi))]
_io_watch_close(handle: long, watches: HashMap<long, String>) {}
