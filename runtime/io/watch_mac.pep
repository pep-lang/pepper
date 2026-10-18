# The macOS layer of Watcher (see watch.pep): kqueue.
#
# A vnode filter (EVFILT_VNODE) reports changes to one open file, so every
# directory and file of the tree is opened for events only (O_EVTONLY) and
# registered on the Watcher's own kqueue. A directory's write means entries
# came or went: it is listed again and compared with the names last seen.
# A file's write or attribute change is `Modified`; a file deleted or
# renamed is forgotten, and watched again when a new file took its name (a
# save by rename). The kqueue descriptor becomes readable when events are
# queued, so the wait parks the task like a socket wait.
#
# struct kevent is 32 bytes: ident (u64) at 0, filter (i16) at 8, flags
# (u16) at 10, fflags (u32) at 12, data (i64) at 16, udata at 24.

import "directory";
import "path";
import "sys_posix";
import "types";
import "wait";
import "watch";

[Target(OS(Mac))]
extern int kqueue();
[Target(OS(Mac))]
extern int kevent(int queue, void* changes, int change_count, void* events, int event_count, void* timeout);

# The most events one read takes: the buffer holds this many.
const _IO_KQUEUE_EVENTS = 2048;

const _IO_NOTE_DELETE: uint = 1;
const _IO_NOTE_WRITE: uint = 2;
const _IO_NOTE_EXTEND: uint = 4;
const _IO_NOTE_ATTRIB: uint = 8;
const _IO_NOTE_RENAME: uint = 32;
const _IO_NOTE_REVOKE: uint = 64;
# Every NOTE_* the watch asks for.
const _IO_NOTE_ALL: uint = 127;

[Target(OS(Mac))]
_io_watch_open(watcher: Watcher): IoResult<void> {
    var queue = kqueue();
    if (queue < 0) {
        return IoResult<void>.err(IoError.last());
    }
    watcher._handle = queue as long;
    return _io_kqueue_add(watcher, watcher.directory.to_string(), true, false);
}

[Target(OS(Mac))]
_io_watch_read(watcher: Watcher): IoResult<void> {
    var queue = watcher._handle as int;
    __ptr<long> zero = _pep_malloc(16);  # a timespec of 0: do not block
    zero[0] = 0;
    zero[1] = 0;
    var count = kevent(queue, __null, 0, watcher._buffer, _IO_KQUEUE_EVENTS, zero);
    var code = _io_sys_last_error();
    _pep_free(zero);
    if (count < 0) {
        if (code == 4) {  # EINTR
            return _io_ok_void();
        }
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    if (count == 0) {
        return _io_socket_wait(queue as SocketHandle, _IO_READABLE);
    }
    var i: ulong = 0;
    while (i < count as ulong) {
        var event = watcher._buffer + i * 32;
        var descriptor = unsafe_cast<__ptr<ulong>>(event)[0] as long;
        var flags = unsafe_cast<__ptr<uint>>(event + 12)[0];
        var handled = _io_kqueue_event(watcher, descriptor, flags);
        if (handled.is_err()) {
            return handled;
        }
        i = i + 1;
    }
    return _io_ok_void();
}

[Target(OS(Mac))]
_io_watch_close(handle: long, watches: HashMap<long, String>) {
    for (var (descriptor, path) in watches) {
        close(descriptor as int);
    }
    var queue = handle as int;
    _io_socket_forget(queue as SocketHandle);
    close(queue);
}

# Records what the vnode event `flags` on `descriptor` means.
[Target(OS(Mac))]
_io_kqueue_event(watcher: Watcher, descriptor: long, flags: uint): IoResult<void> {
    if (!watcher._watches.contains(descriptor)) {
        return _io_ok_void();
    }
    var path = watcher._watches.get(descriptor);
    var gone = (flags & (_IO_NOTE_DELETE | _IO_NOTE_RENAME | _IO_NOTE_REVOKE)) != 0;
    if (watcher._listings.contains(path)) {
        # A directory: its parent's listing reports it going, except the
        # watched directory's own.
        if (gone) {
            if (path == watcher.directory.to_string()) {
                watcher._report(ChangeKind.Removed, path);
            }
            _io_kqueue_remove(watcher, path);
            return _io_ok_void();
        }
        if ((flags & _IO_NOTE_ATTRIB) != 0) {
            watcher._report(ChangeKind.Modified, path);
        }
        if ((flags & _IO_NOTE_WRITE) != 0) {
            return _io_kqueue_rescan(watcher, path);
        }
        return _io_ok_void();
    }
    if (!gone) {
        if ((flags & (_IO_NOTE_WRITE | _IO_NOTE_EXTEND | _IO_NOTE_ATTRIB)) != 0) {
            watcher._report(ChangeKind.Modified, path);
        }
        return _io_ok_void();
    }
    # The file was deleted or renamed. A new file under its name replaced
    # it; otherwise its directory's listing reports it removed.
    _io_kqueue_remove(watcher, path);
    if (!Path(path).exists()) {
        return _io_ok_void();
    }
    watcher._report(ChangeKind.Modified, path);
    return _io_kqueue_add(watcher, path, false, true);
}

# Lists `directory` again and reports the names that came and went.
[Target(OS(Mac))]
_io_kqueue_rescan(watcher: Watcher, directory: String): IoResult<void> {
    var listing = _io_list(Path(directory));
    if (listing.is_err()) {
        # Gone: its own event or its parent's reports it.
        return _io_ok_void();
    }
    var known = watcher._listings.get(directory);
    var current = HashSet<String>();
    for (var entry in listing.value()) {
        current.insert(entry.name);
        if (known.contains(entry.name)) {
            continue;
        }
        known.insert(entry.name);
        var child = entry.path.to_string();
        watcher._report(ChangeKind.Created, child);
        var added = _io_kqueue_add(watcher, child, entry.is_directory, true);
        if (added.is_err()) {
            return added;
        }
    }
    var removed = Array<String>();
    for (var name in known) {
        if (!current.contains(name)) {
            removed.append(name);
        }
    }
    for (var name in removed) {
        known.remove(name);
        var child = Path(directory).join(Path(name)).to_string();
        watcher._report(ChangeKind.Removed, child);
        _io_kqueue_remove(watcher, child);
    }
    return _io_ok_void();
}

# Watches `path`, and when it is a directory everything below it. With
# `report`, for a directory that just appeared, what it holds is reported
# `Created`, and a path gone again already is not an error.
[Target(OS(Mac))]
_io_kqueue_add(watcher: Watcher, path: String, is_directory: bool, report: bool): IoResult<void> {
    # O_EVTONLY | O_NONBLOCK | O_CLOEXEC: no read access needed, and a FIFO
    # does not block the open.
    var descriptor = open(path.c_str(), 16809988);
    if (descriptor < 0) {
        var code = _io_sys_last_error();
        if (report && code == 2) {  # ENOENT
            return _io_ok_void();
        }
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    __ptr<u8> change = _pep_malloc(32);
    unsafe_cast<__ptr<ulong>>(change)[0] = descriptor as ulong;
    unsafe_cast<__ptr<i16>>(change + 8)[0] = -4 as i16;   # EVFILT_VNODE
    unsafe_cast<__ptr<u16>>(change + 10)[0] = 33 as u16;  # EV_ADD | EV_CLEAR
    unsafe_cast<__ptr<uint>>(change + 12)[0] = _IO_NOTE_ALL;
    unsafe_cast<__ptr<long>>(change + 16)[0] = 0;
    unsafe_cast<__ptr<ulong>>(change + 24)[0] = 0;
    var registered = kevent(watcher._handle as int, change, 1, __null, 0, __null);
    var code = _io_sys_last_error();
    _pep_free(change);
    if (registered < 0) {
        close(descriptor);
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    watcher._watches.insert(descriptor as long, path);
    if (!is_directory) {
        return _io_ok_void();
    }
    var names = HashSet<String>();
    watcher._listings.insert(path, names);
    var listing = _io_list(Path(path));
    if (listing.is_err()) {
        if (report) {
            return _io_ok_void();
        }
        return IoResult<void>.err(listing.error());
    }
    for (var entry in listing.value()) {
        names.insert(entry.name);
        var child = entry.path.to_string();
        if (report) {
            watcher._report(ChangeKind.Created, child);
        }
        var added = _io_kqueue_add(watcher, child, entry.is_directory, report);
        if (added.is_err()) {
            return added;
        }
    }
    return _io_ok_void();
}

# Stops watching `path` and everything below it.
[Target(OS(Mac))]
_io_kqueue_remove(watcher: Watcher, path: String) {
    var below = path + "/";
    var gone = Array<long>();
    for (var (descriptor, watched) in watcher._watches) {
        if (watched == path || watched.starts_with(below)) {
            gone.append(descriptor);
        }
    }
    for (var descriptor in gone) {
        close(descriptor as int);
        watcher._watches.remove(descriptor);
    }
    var listings = Array<String>();
    for (var (directory, names) in watcher._listings) {
        if (directory == path || directory.starts_with(below)) {
            listings.append(directory);
        }
    }
    for (var directory in listings) {
        watcher._listings.remove(directory);
    }
}
