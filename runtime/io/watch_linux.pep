# The Linux layer of Watcher (see watch.pep): inotify.
#
# inotify watches one directory per watch, so every directory of the tree
# gets one, and one that appears gets its own as its creation is read.
# The descriptor is non-blocking: a read that finds nothing waits for it to
# become readable, which parks the task like a socket wait (epoll, io_uring
# and poll all take an inotify descriptor).

import "directory";
import "path";
import "sys_posix";
import "types";
import "wait";
import "watch";

[Target(OS(Linux))]
extern int inotify_init1(int flags);
[Target(OS(Linux))]
extern int inotify_add_watch(int fd, char* path, uint mask);
[Target(OS(Linux))]
extern int inotify_rm_watch(int fd, int wd);

# The events: IN_MODIFY | IN_ATTRIB | IN_MOVED_FROM | IN_MOVED_TO |
# IN_CREATE | IN_DELETE, on directories only (IN_ONLYDIR).
const _IO_INOTIFY_MASK: uint = 16778182;

const _IO_IN_MODIFY: uint = 2;
const _IO_IN_ATTRIB: uint = 4;
const _IO_IN_MOVED_FROM: uint = 64;
const _IO_IN_MOVED_TO: uint = 128;
const _IO_IN_CREATE: uint = 256;
const _IO_IN_DELETE: uint = 512;
const _IO_IN_Q_OVERFLOW: uint = 16384;
const _IO_IN_IGNORED: uint = 32768;
const _IO_IN_ISDIR: uint = 1073741824;

[Target(OS(Linux))]
_io_watch_open(watcher: Watcher): IoResult<void> {
    var fd = inotify_init1(526336);  # IN_NONBLOCK | IN_CLOEXEC
    if (fd < 0) {
        return IoResult<void>.err(IoError.last());
    }
    watcher._handle = fd as long;
    return _io_inotify_add_tree(watcher, watcher.directory.to_string(), false);
}

[Target(OS(Linux))]
_io_watch_read(watcher: Watcher): IoResult<void> {
    var fd = watcher._handle as int;
    var count = read(fd, watcher._buffer, _IO_WATCH_BUFFER_SIZE);
    if (count < 0) {
        var code = _io_sys_last_error();
        if (code == 4) {  # EINTR
            return _io_ok_void();
        }
        if (code == 11) {  # EAGAIN: nothing yet
            return _io_socket_wait(fd as SocketHandle, _IO_READABLE);
        }
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    var offset: ulong = 0;
    while (offset + 16 <= count as ulong) {
        var event = watcher._buffer + offset;
        var wd = unsafe_cast<__ptr<int>>(event)[0];
        var mask = unsafe_cast<__ptr<uint>>(event + 4)[0];
        var length = unsafe_cast<__ptr<uint>>(event + 12)[0] as ulong;
        var name = "";
        if (length > 0) {
            name = String(unsafe_cast<__ptr<char>>(event + 16));
        }
        offset = offset + 16 + length;
        var handled = _io_inotify_event(watcher, wd as long, mask, name);
        if (handled.is_err()) {
            return handled;
        }
    }
    return _io_ok_void();
}

[Target(OS(Linux))]
_io_watch_close(handle: long, watches: HashMap<long, String>) {
    var fd = handle as int;
    _io_socket_forget(fd as SocketHandle);
    close(fd);
}

# Records one inotify event for the watch `wd`, about `name` in its
# directory (the directory itself when empty).
[Target(OS(Linux))]
_io_inotify_event(watcher: Watcher, wd: long, mask: uint, name: String): IoResult<void> {
    if ((mask & _IO_IN_Q_OVERFLOW) != 0) {
        watcher._report(ChangeKind.Overflow, watcher.directory.to_string());
        return _io_ok_void();
    }
    if (!watcher._watches.contains(wd)) {
        return _io_ok_void();
    }
    var directory = watcher._watches.get(wd);
    if ((mask & _IO_IN_IGNORED) != 0) {
        # The directory was removed, or moved away (then forgotten already).
        watcher._watches.remove(wd);
        if (directory == watcher.directory.to_string()) {
            watcher._report(ChangeKind.Removed, directory);
        }
        return _io_ok_void();
    }
    var path = directory;
    if (name != "") {
        path = Path(directory).join(Path(name)).to_string();
    }
    var is_directory = (mask & _IO_IN_ISDIR) != 0;
    if ((mask & (_IO_IN_CREATE | _IO_IN_MOVED_TO)) != 0) {
        watcher._report(ChangeKind.Created, path);
        if (is_directory) {
            return _io_inotify_add_tree(watcher, path, true);
        }
        return _io_ok_void();
    }
    if ((mask & (_IO_IN_DELETE | _IO_IN_MOVED_FROM)) != 0) {
        watcher._report(ChangeKind.Removed, path);
        if (is_directory && (mask & _IO_IN_MOVED_FROM) != 0) {
            _io_inotify_remove_tree(watcher, path);
        }
        return _io_ok_void();
    }
    if ((mask & (_IO_IN_MODIFY | _IO_IN_ATTRIB)) != 0) {
        watcher._report(ChangeKind.Modified, path);
    }
    return _io_ok_void();
}

# Watches `directory` and every directory below it. With `report`, for a
# directory that just appeared, what it holds is reported `Created`, and
# one gone again already is not an error.
[Target(OS(Linux))]
_io_inotify_add_tree(watcher: Watcher, directory: String, report: bool): IoResult<void> {
    var wd = inotify_add_watch(watcher._handle as int, directory.c_str(), _IO_INOTIFY_MASK);
    if (wd < 0) {
        var code = _io_sys_last_error();
        if (report && (code == 2 || code == 20)) {  # ENOENT, ENOTDIR
            return _io_ok_void();
        }
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    watcher._watches.insert(wd as long, directory);
    var listing = _io_list(Path(directory));
    if (listing.is_err()) {
        if (report) {
            return _io_ok_void();
        }
        return IoResult<void>.err(listing.error());
    }
    for (var entry in listing.value()) {
        var child = entry.path.to_string();
        if (report) {
            watcher._report(ChangeKind.Created, child);
        }
        if (!entry.is_directory) {
            continue;
        }
        var added = _io_inotify_add_tree(watcher, child, report);
        if (added.is_err()) {
            return added;
        }
    }
    return _io_ok_void();
}

# Stops watching `directory` and the directories below it, after it moved
# out of its place.
[Target(OS(Linux))]
_io_inotify_remove_tree(watcher: Watcher, directory: String) {
    var below = directory + "/";
    var gone = Array<long>();
    for (var (wd, path) in watcher._watches) {
        if (path == directory || path.starts_with(below)) {
            gone.append(wd);
        }
    }
    for (var wd in gone) {
        inotify_rm_watch(watcher._handle as int, wd as int);
        watcher._watches.remove(wd);
    }
}
