# The Windows layer of Watcher (see watch.pep): ReadDirectoryChangesW.
#
# The directory is opened for overlapped I/O, and one request watches the
# whole tree. In a task the request goes to the runtime
# (`_IoWaiter._directory_changes`), whose IOCP driver completes it on the
# worker's port; a cancel or timeout cancels it. Elsewhere, or when the
# runtime declines, the request completes on an event the thread waits for.
# Its event handle has the low bit set, so a completion never also goes to
# a port the directory is tied to.
#
# The system records changes from the first request on, also between
# requests, so `open` makes one and cancels it at once.

import "path";
import "sys_windows";
import "types";
import "wait";
import "watch";

[Target(OS(Windows))]
extern int ReadDirectoryChangesW(
    void* directory,
    void* buffer,
    uint length,
    int subtree,
    uint filter,
    uint* returned,
    void* overlapped,
    void* routine
);
[Target(OS(Windows))]
extern int GetOverlappedResult(void* file, void* overlapped, uint* transferred, int wait);
[Target(OS(Windows))]
extern void* CreateEventW(void* attributes, int manual_reset, int initial_state, ushort* name);
[Target(OS(Windows))]
extern int CancelIoEx(void* file, void* overlapped);

# FILE_NOTIFY_CHANGE_FILE_NAME | DIR_NAME | ATTRIBUTES | SIZE | LAST_WRITE.
const _IO_WATCH_FILTER: uint = 31;

# Starts watching the tree under `directory` for changes into the `count`
# bytes at `buffer`, completing through `overlapped`. For the async
# module's IOCP driver too.
[Target(OS(Windows))]
export _io_win_read_directory_changes(
    directory: __ptr<void>, buffer: __ptr<u8>, count: ulong, overlapped: __ptr<u8>
): bool {
    return ReadDirectoryChangesW(directory, buffer, count as uint, 1, _IO_WATCH_FILTER, __null, overlapped, __null)
        != 0;
}

[Target(OS(Windows))]
_io_watch_open(watcher: Watcher): IoResult<void> {
    var opened = _io_win_create(watcher.directory, 1, 3, 1073741824);  # FILE_LIST_DIRECTORY, OPEN_EXISTING, OVERLAPPED
    if (opened.is_err()) {
        return IoResult<void>.err(opened.error());
    }
    watcher._handle = _io_sys_handle_bits(opened.value());
    return _io_win_watch_blocking(watcher, true);
}

[Target(OS(Windows))]
_io_watch_read(watcher: Watcher): IoResult<void> {
    var slot = _io_waiter_slot();
    if (slot == __null || !slot[0]._in_task()) {
        return _io_win_watch_blocking(watcher, false);
    }
    var raw = slot[0]._directory_changes(
        watcher._handle as ulong, unsafe_cast<ulong>(watcher._buffer), _IO_WATCH_BUFFER_SIZE
    );
    if (raw == _IO_TRANSFER_DECLINED) {
        return _io_win_watch_blocking(watcher, false);
    }
    if (raw == _IO_TRANSFER_CANCELLED) {
        return IoResult<void>.err(IoError(_io_sys_code_cancelled(), "the task was cancelled"));
    }
    if (raw == _IO_TRANSFER_TIMED_OUT) {
        return IoResult<void>.err(_io_timed_out_error());
    }
    if (raw == _IO_TRANSFER_CLOSED) {
        return IoResult<void>.err(_io_watcher_closed_error());
    }
    if (raw < 0) {
        var code = (-1 - raw) as ErrorCode;
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    _io_win_watch_parse(watcher, raw as ulong);
    return _io_ok_void();
}

[Target(OS(Windows))]
_io_watch_close(handle: long, watches: HashMap<long, String>) {
    var directory = _io_sys_handle_from_bits(handle);
    # A request in flight in a task ends cancelled, and that wait fails.
    CancelIoEx(directory, __null);
    _io_socket_forget(handle as SocketHandle);
    CloseHandle(directory);
}

# Makes one request and waits for it, blocking the thread; with `cancel`,
# cancels it at once, which only starts the recording.
[Target(OS(Windows))]
_io_win_watch_blocking(watcher: Watcher, cancel: bool): IoResult<void> {
    var directory = _io_sys_handle_from_bits(watcher._handle);
    var event = CreateEventW(__null, 1, 0, __null);
    if (event == __null) {
        return IoResult<void>.err(IoError.last());
    }
    __ptr<u8> overlapped = _pep_malloc(32);
    __ptr<ulong> words = overlapped;
    words[0] = 0;
    words[1] = 0;
    words[2] = 0;
    words[3] = unsafe_cast<ulong>(event) | 1;
    var started = _io_win_read_directory_changes(directory, watcher._buffer, _IO_WATCH_BUFFER_SIZE, overlapped);
    var code = GetLastError();
    if (!started) {
        _pep_free(overlapped);
        CloseHandle(event);
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    if (cancel) {
        CancelIoEx(directory, overlapped);
    }
    __ptr<uint> transferred = _pep_malloc(4);
    transferred[0] = 0;
    var done = GetOverlappedResult(directory, overlapped, transferred, 1);
    code = GetLastError();
    var count = transferred[0] as ulong;
    _pep_free(transferred);
    _pep_free(overlapped);
    CloseHandle(event);
    if (done == 0) {
        if (cancel && code == 995) {  # ERROR_OPERATION_ABORTED
            return _io_ok_void();
        }
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    _io_win_watch_parse(watcher, count);
    return _io_ok_void();
}

# Records the FILE_NOTIFY_INFORMATION records a request wrote: `count`
# bytes, none when the system dropped changes.
[Target(OS(Windows))]
_io_win_watch_parse(watcher: Watcher, count: ulong) {
    if (count == 0) {
        watcher._report(ChangeKind.Overflow, watcher.directory.to_string());
        return;
    }
    ulong offset = 0;
    while (offset + 12 <= count) {
        var record = watcher._buffer + offset;
        var next = unsafe_cast<__ptr<uint>>(record)[0] as ulong;
        var action = unsafe_cast<__ptr<uint>>(record + 4)[0];
        var length = unsafe_cast<__ptr<uint>>(record + 8)[0];
        var name = _io_win_narrow(unsafe_cast<__ptr<u16>>(record + 12), (length / 2) as int);
        var path = watcher.directory.join(Path(name)).to_string();
        match (action) {
            1, 5 => {  # FILE_ACTION_ADDED, RENAMED_NEW_NAME
                watcher._report(ChangeKind.Created, path);
            }
            2, 4 => {  # FILE_ACTION_REMOVED, RENAMED_OLD_NAME
                watcher._report(ChangeKind.Removed, path);
            }
            3 => {  # FILE_ACTION_MODIFIED
                watcher._report(ChangeKind.Modified, path);
            }
            else => {}
        }
        if (next == 0) {
            return;
        }
        offset = offset + next;
    }
}
