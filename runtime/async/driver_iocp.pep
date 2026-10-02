# The IOCP I/O driver (Windows) for the task runtime; see driver.pep.
#
# Readiness through an I/O completion port, the way mio (tokio) and libuv
# do it: a poll request (IOCTL_AFD_POLL) sent to the socket's AFD driver
# through a helper handle on \Device\Afd completes, on the port, once the
# socket is ready for what it asked. A request is one-shot: when a task
# starts waiting for reading or writing and no request for that is in
# flight, `_want` sends one. Completions are dequeued in batches with
# GetQueuedCompletionStatusEx.
#
# Each request is a malloc'd block that stays alive until its completion is
# dequeued, because the kernel writes into it:
#
#     0   IO_STATUS_BLOCK   { Status (8), Information (8) }
#     16  AFD_POLL_INFO     { Timeout (i64), NumberOfHandles (u32),
#                             Exclusive (u32), Handle (8), Events (u32),
#                             Status (u32) }
#     48  the socket (u64)
#     56  what the request waits for (io._IO_READABLE or io._IO_WRITABLE)
#     64  1 once the socket was forgotten (closed): the completion is
#         dropped
#
# The doorbell posts a completion with no OVERLAPPED
# (PostQueuedCompletionStatus), which `_poll` skips.
#
# The system calls are [Target(OS(Windows))]; elsewhere
# `_async_iocp_create` fails, so the driver is unavailable.

import io;
import "driver";
import "task";

[Target(OS(Windows))]
extern void* CreateIoCompletionPort(void* file, void* port, ulong key, uint threads);
[Target(OS(Windows))]
extern int GetQueuedCompletionStatusEx(
    void* port, void* entries, uint count, uint* removed, uint milliseconds, int alertable
);
[Target(OS(Windows))]
extern int CloseHandle(void* handle);
[Target(OS(Windows))]
extern int PostQueuedCompletionStatus(void* port, uint bytes, ulong key, void* overlapped);
[Target(OS(Windows))]
extern int SetFileCompletionNotificationModes(void* file, u8 flags);
[Target(OS(Windows))]
[Link("ntdll")]
extern int NtCreateFile(
    void* file,
    uint access,
    void* attributes,
    void* status,
    void* size,
    uint file_attributes,
    uint share,
    uint disposition,
    uint options,
    void* extended,
    uint extended_length
);
[Target(OS(Windows))]
[Link("ntdll")]
extern int NtDeviceIoControlFile(
    void* file,
    void* event,
    void* routine,
    void* context,
    void* status,
    uint code,
    void* input,
    uint input_length,
    void* output,
    uint output_length
);
[Target(OS(Windows))]
[Link("ntdll")]
extern int NtCancelIoFileEx(void* file, void* request, void* status);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int WSAIoctl(
    ulong s,
    uint code,
    void* input,
    uint input_length,
    void* output,
    uint output_length,
    uint* returned,
    void* overlapped,
    void* routine
);

# The most completions one poll dequeues.
const _IOCP_CAPACITY = 256;
# The size of a request block (see above).
const _IOCP_REQUEST_SIZE = 72;

# AFD_POLL_* events: what lets a reader continue (RECEIVE, DISCONNECT,
# ACCEPT), what lets a writer (SEND), and what wakes both (ABORT,
# LOCAL_CLOSE, CONNECT_FAIL).
const _AFD_POLL_READABLE = 137;
const _AFD_POLL_WRITABLE = 4;
const _AFD_POLL_ERRORS = 304;

# A worker's completion port and AFD helper handle.
export struct _IocpDriver {
    var _port: __ptr<void>;
    var _afd: __ptr<void>;
    # Room for `_IOCP_CAPACITY` OVERLAPPED_ENTRY records of 32 bytes.
    var _entries: __ptr<u8>;
    # The request in flight for reading and for writing on each socket.
    var _reading: HashMap<ulong, __ptr<u8>>;
    var _writing: HashMap<ulong, __ptr<u8>>;
    # Every request block not yet dequeued.
    var _pending: HashSet<__ptr<u8>>;

    construct(port: __ptr<void>, afd: __ptr<void>) {
        this._port = port;
        this._afd = afd;
        this._entries = _pep_malloc((_IOCP_CAPACITY * 32) as ulong);
        this._reading = HashMap<ulong, __ptr<u8>>();
        this._writing = HashMap<ulong, __ptr<u8>>();
        this._pending = HashSet<__ptr<u8>>();
    }

    # A new driver, or none when the system cannot make one.
    static open(): _IocpDriver? {
        var port = _async_iocp_create();
        if (port == __null) {
            return Optional<_IocpDriver>.none();
        }
        var afd = _async_iocp_open_afd(port);
        if (afd == __null) {
            _async_iocp_close_handle(port);
            return Optional<_IocpDriver>.none();
        }
        return Optional<_IocpDriver>.some(_IocpDriver(port, afd));
    }

    # Handles one dequeued request block.
    _complete(block: __ptr<u8>, ready_sockets: Array<(handle: ulong, interest: int)>) {
        this._pending.remove(block);
        __ptr<ulong> words = block;
        var handle = words[6];
        var asked = words[7] as int;
        var forgotten = words[8] != 0;
        if (!forgotten) {
            if (asked == io._IO_READABLE) {
                this._reading.remove(handle);
            } else {
                this._writing.remove(handle);
            }
            var status = (block as __ptr<int>)[0];
            var events = ((block + 40) as __ptr<uint>)[0];
            var ready = asked;
            if (status == 0) {
                if ((events & _AFD_POLL_ERRORS) != 0) {
                    ready = io._IO_READABLE | io._IO_WRITABLE;
                } else if ((events & (_AFD_POLL_READABLE | _AFD_POLL_WRITABLE)) == 0) {
                    ready = 0;
                }
            }
            # A failed request (not STATUS_SUCCESS) wakes its waiters, which
            # retry the call and see any error.
            if (ready != 0) {
                ready_sockets.append((handle, ready));
            }
        }
        _pep_free(block);
    }
}

extend _IocpDriver with _Driver {
    _watch(handle: io.SocketHandle): bool {
        return true;
    }

    _want(handle: io.SocketHandle, interest: int): bool {
        var key = handle as ulong;
        var requests = this._reading;
        var events = _AFD_POLL_READABLE | _AFD_POLL_ERRORS;
        if (interest == io._IO_WRITABLE) {
            requests = this._writing;
            events = _AFD_POLL_WRITABLE | _AFD_POLL_ERRORS;
        }
        if (requests.contains(key)) {
            return true;
        }
        __ptr<u8> block = _pep_malloc(_IOCP_REQUEST_SIZE as ulong);
        __ptr<ulong> words = block;
        words[6] = key;
        words[7] = interest as ulong;
        if (!_async_iocp_submit(this._afd, block, _async_iocp_base_socket(key), events as uint)) {
            _pep_free(block);
            return false;
        }
        requests.insert(key, block);
        this._pending.insert(block);
        return true;
    }

    _poll(waits: HashMap<ulong, _SocketWaits>, timeout: long, ready_sockets: Array<(handle: ulong, interest: int)>) {
        var count = _async_iocp_dequeue(this._port, this._entries, _IOCP_CAPACITY, timeout);
        var i: ulong = 0;
        while (i < count) {
            __ptr<u8> block = ((this._entries + i * 32 + 8) as __ptr<__ptr<u8>>)[0];
            if (block != __null) {
                this._complete(block, ready_sockets);
            }
            i = i + 1;
        }
    }

    _forget(handle: io.SocketHandle) {
        var key = handle as ulong;
        if (this._reading.contains(key)) {
            (this._reading.get(key) as __ptr<ulong>)[8] = 1;
            this._reading.remove(key);
        }
        if (this._writing.contains(key)) {
            (this._writing.get(key) as __ptr<ulong>)[8] = 1;
            this._writing.remove(key);
        }
    }

    # AFD polls do not tie the socket to this port, so dropping the pending
    # ones is all a move needs.
    _release(handle: io.SocketHandle) {
        this._forget(handle);
    }

    _doorbell(): _Doorbell {
        return _Doorbell(this._port);
    }

    _close() {
        # Cancel what is still in flight and wait for the cancellations, so
        # the kernel is done with every block before it is freed.
        for (var block in this._pending) {
            _async_iocp_cancel(this._afd, block);
        }
        var drained = Array<(handle: ulong, interest: int)>();
        var rounds = 0;
        while (this._pending.count > 0 && rounds < 100) {
            this._poll(HashMap<ulong, _SocketWaits>(), 10, drained);
            rounds = rounds + 1;
        }
        _async_iocp_close_handle(this._afd);
        _async_iocp_close_handle(this._port);
        _pep_free(this._entries);
    }
}

# The pointer at `address`: an integer cannot be cast to a pointer.
_async_iocp_block(address: ulong): __ptr<ulong> {
    __ptr<ulong> slot = _pep_malloc(8);
    slot[0] = address;
    var block = (slot as __ptr<__ptr<ulong>>)[0];
    _pep_free(slot);
    return block;
}

# A new completion port, or null.
[Target(OS(Windows))]
_async_iocp_create(): __ptr<void> {
    # INVALID_HANDLE_VALUE (all ones) for the file asks for a new port.
    var invalid = _async_iocp_block(~(0 as ulong)) as __ptr<void>;
    return CreateIoCompletionPort(invalid, __null, 0, 1);
}

[Target(OS(Windows))]
_async_iocp_close_handle(handle: __ptr<void>) {
    CloseHandle(handle);
}

# Opens a helper handle on \Device\Afd and ties it to `port`; null on
# failure.
[Target(OS(Windows))]
_async_iocp_open_afd(port: __ptr<void>): __ptr<void> {
    var name = "\\Device\\Afd\\Pepper";
    var units = name.size;
    var wide = io._io_win_wide(name);
    __ptr<u8> unicode = _pep_malloc(16);  # UNICODE_STRING
    (unicode as __ptr<u16>)[0] = (units * 2) as u16;
    ((unicode + 2) as __ptr<u16>)[0] = ((units + 1) * 2) as u16;
    ((unicode + 8) as __ptr<__ptr<u16>>)[0] = wide;
    __ptr<u8> attributes = _pep_malloc(48);  # OBJECT_ATTRIBUTES
    (attributes as __ptr<uint>)[0] = 48;
    ((attributes + 16) as __ptr<__ptr<u8>>)[0] = unicode;
    __ptr<u8> status = _pep_malloc(16);
    __ptr<__ptr<void>> afd = _pep_malloc(8);
    var rc = NtCreateFile(afd, 1048576, attributes, status, __null, 0, 3, 1, 0, __null, 0);  # SYNCHRONIZE, FILE_SHARE_READ | WRITE, FILE_OPEN
    var handle = afd[0];
    _pep_free(afd);
    _pep_free(status);
    _pep_free(attributes);
    _pep_free(unicode);
    _pep_free(wide);
    if (rc != 0) {
        return __null;
    }
    if (CreateIoCompletionPort(handle, port, 0, 0) == __null) {
        CloseHandle(handle);
        return __null;
    }
    SetFileCompletionNotificationModes(handle, 2);  # FILE_SKIP_SET_EVENT_ON_HANDLE
    return handle;
}

# The base provider socket under `socket` (SIO_BASE_HANDLE), which AFD
# polls; `socket` itself if the query fails.
[Target(OS(Windows))]
_async_iocp_base_socket(socket: ulong): ulong {
    __ptr<ulong> base = _pep_malloc(8);
    __ptr<uint> returned = _pep_malloc(4);
    var result = socket;
    if (WSAIoctl(socket, 1207959586, __null, 0, base, 8, returned, __null, __null) == 0) {  # SIO_BASE_HANDLE
        result = base[0];
    }
    _pep_free(base);
    _pep_free(returned);
    return result;
}

# Sends the poll request in `block` for `events` on `socket`; false if AFD
# refused it.
[Target(OS(Windows))]
_async_iocp_submit(afd: __ptr<void>, block: __ptr<u8>, socket: ulong, events: uint): bool {
    __ptr<long> status = block;
    status[0] = 259;  # STATUS_PENDING
    var info = block + 16;
    (info as __ptr<long>)[0] = 9223372036854775807;  # no timeout
    ((info + 8) as __ptr<uint>)[0] = 1;              # one handle
    ((info + 12) as __ptr<uint>)[0] = 0;             # not exclusive
    ((info + 16) as __ptr<ulong>)[0] = socket;
    ((info + 24) as __ptr<uint>)[0] = events;
    ((info + 28) as __ptr<uint>)[0] = 0;
    var rc = NtDeviceIoControlFile(afd, __null, __null, block, block, 73764, info, 32, info, 32);  # IOCTL_AFD_POLL
    return rc == 0 || rc == 259;
}

[Target(OS(Windows))]
_async_iocp_cancel(afd: __ptr<void>, block: __ptr<u8>) {
    __ptr<u8> status = _pep_malloc(16);
    NtCancelIoFileEx(afd, block, status);
    _pep_free(status);
}

# Dequeues up to `capacity` completions, waiting up to `timeout`
# milliseconds (forever when negative); how many it stored.
[Target(OS(Windows))]
_async_iocp_dequeue(port: __ptr<void>, entries: __ptr<u8>, capacity: int, timeout: long): ulong {
    __ptr<uint> removed = _pep_malloc(4);
    var milliseconds: uint = 4294967295;  # INFINITE
    if (timeout >= 0) {
        milliseconds = timeout as uint;
    }
    var count: ulong = 0;
    if (GetQueuedCompletionStatusEx(port, entries, capacity as uint, removed, milliseconds, 0) != 0) {
        count = removed[0] as ulong;
    }
    _pep_free(removed);
    return count;
}

# Rings the doorbell of the driver whose completion port is `port`.
[Target(OS(Windows))]
export _async_iocp_ring(port: __ptr<void>) {
    PostQueuedCompletionStatus(port, 0, 0, __null);
}

# Elsewhere there are no completion ports.

[Target(!OS(Windows))]
_async_iocp_create(): __ptr<void> {
    return __null;
}

[Target(!OS(Windows))]
_async_iocp_close_handle(handle: __ptr<void>) {}

[Target(!OS(Windows))]
export _async_iocp_ring(port: __ptr<void>) {}

[Target(!OS(Windows))]
_async_iocp_open_afd(port: __ptr<void>): __ptr<void> {
    return __null;
}

[Target(!OS(Windows))]
_async_iocp_base_socket(socket: ulong): ulong {
    return socket;
}

[Target(!OS(Windows))]
_async_iocp_submit(afd: __ptr<void>, block: __ptr<u8>, socket: ulong, events: uint): bool {
    return false;
}

[Target(!OS(Windows))]
_async_iocp_cancel(afd: __ptr<void>, block: __ptr<u8>) {}

[Target(!OS(Windows))]
_async_iocp_dequeue(port: __ptr<void>, entries: __ptr<u8>, capacity: int, timeout: long): ulong {
    return 0;
}
