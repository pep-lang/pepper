# The poll() I/O driver for the task runtime (WSAPoll on Windows); see
# driver.pep. It runs everywhere and is the reference the other drivers are
# tested against.
#
# poll() is level-triggered and keeps no registrations, so each wait passes
# every socket a task is waiting on, with what it waits for. That costs a
# pass over the waiting sockets per wait, which is fine for a few and slow
# for thousands.
#
# struct pollfd is { int fd; short events; short revents; } (8 bytes) on
# POSIX; WSAPOLLFD is { SOCKET fd; short events; short revents; } (16 bytes)
# on Windows, with different flag values.
#
# The doorbell is a readable handle every wait also watches: a self-pipe on
# POSIX (a ring writes a byte to the write end), and on Windows, where
# WSAPoll takes only sockets, a UDP socket bound to a loopback port that a
# ring sends one byte to. The wait that sees it readable reads it empty.
#
# On Windows a Watcher's ReadDirectoryChangesW request
# (`_start_directory_changes`) completes on an event of its own, which
# WSAPoll cannot wait for: while one is in flight a wait lasts at most
# `_POLL_DIRECTORY_INTERVAL` milliseconds, and each wait looks for finished
# requests. The request block is the IOCP driver's (see driver_iocp.pep)
# with the event's handle at 48.
#
# WASI has no pipe, and no task can run there (see fiber_wasi.pep): making
# the doorbell panics.

import io;
import "driver";
import "driver_iocp";
import "sys_posix";
import "sys_wasi";
import "sys_windows";
import "task";

[Target(!OS(Windows))]
extern int poll(void* descriptors, ulong count, int timeout);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int WSAPoll(void* descriptors, uint count, int timeout);

[Target(OS(Linux) || OS(Mac))]
extern int pipe(int* descriptors);
[Target(!OS(Windows))]
extern long read(int fd, void* buf, ulong n);
[Target(!OS(Windows))]
extern long write(int fd, void* buf, ulong n);
[Target(!OS(Windows))]
extern int close(int fd);
[Target(!OS(Windows))]
extern int fcntl(int fd, int command, ...);

[Target(OS(Windows))]
[Link("ws2_32")]
extern int WSAStartup(ushort version, void* data);
[Target(OS(Windows))]
[Link("ws2_32")]
extern ulong WSASocketW(int family, int kind, int protocol, void* info, uint group, uint flags);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int closesocket(ulong s);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int bind(ulong s, void* address, int length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int getsockname(ulong s, void* address, int* length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int recv(ulong s, void* buffer, int length, int flags);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int sendto(ulong s, void* buffer, int length, int flags, void* address, int address_length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int ioctlsocket(ulong s, int command, uint* argument);

[Target(OS(Windows))]
extern void* CreateEventW(void* attributes, int manual_reset, int initial_state, ushort* name);
[Target(OS(Windows))]
extern int GetOverlappedResult(void* file, void* overlapped, uint* transferred, int wait);
[Target(OS(Windows))]
extern int CloseHandle(void* handle);

# The longest wait, in milliseconds, while a directory request is in flight.
const _POLL_DIRECTORY_INTERVAL: long = 10;
# STATUS_PENDING: a request's status until it finishes.
const _POLL_PENDING = 259;

# The portable driver.
struct _PollDriver {
    # The handle the doorbell makes readable: the pipe's read end, or the
    # UDP socket.
    var _bell: ulong;
    # The doorbell: the pipe's write end, or a second UDP socket and the
    # address of `_bell`.
    var _ring_descriptor: long;
    var _ring_address: __ptr<u8>;
    # Each directory request in flight: its block's address, and the
    # directory.
    var _directory_requests: HashMap<ulong, ulong>;
    # The directory requests finished since `_finished_files` last ran.
    var _finished: Array<(task: ulong, result: long)>;

    construct() {
        this._directory_requests = HashMap<ulong, ulong>();
        this._finished = Array<(task: ulong, result: long)>();
        __ptr<long> made = _pep_malloc(16);
        made[0] = -1;
        made[1] = -1;
        this._ring_address = _async_poll_create_bell(made);
        assert(made[0] >= 0, "async.run: cannot create the poll backend's doorbell");
        this._bell = made[0] as ulong;
        this._ring_descriptor = made[1];
        _pep_free(made);
    }

    # Moves the directory requests that finished to `_finished`; with
    # `wait`, waits for each first.
    _collect_directories(wait: bool) {
        var done = Array<ulong>();
        for (var (request, handle) in this._directory_requests) {
            var block = unsafe_cast<__ptr<u8>>(_async_iocp_block(request));
            if (wait) {
                _async_poll_wait_directory(_async_iocp_block(handle) as __ptr<void>, block);
            }
            if (unsafe_cast<__ptr<int>>(block)[0] != _POLL_PENDING) {
                done.append(request);
            }
        }
        for (var request in done) {
            this._directory_requests.remove(request);
            var block = unsafe_cast<__ptr<u8>>(_async_iocp_block(request));
            __ptr<ulong> words = block;
            this._finished.append((words[4], _async_directory_result(block, words[1])));
            _async_poll_close_event(words[6]);
            _pep_free(block);
        }
    }
}

extend _PollDriver with _Driver {
    _watch(handle: io.SocketHandle): bool {
        return true;
    }

    _poll(waits: HashMap<ulong, _SocketWaits>, timeout: long, ready_sockets: Array<(handle: ulong, interest: int)>) {
        var watched = Array<(handle: ulong, interest: int)>();
        for (var entry in waits) {
            var (key, waiting) = entry;
            var interest = 0;
            if (waiting._readers.count > 0) {
                interest = interest | io._IO_READABLE;
            }
            if (waiting._writers.count > 0) {
                interest = interest | io._IO_WRITABLE;
            }
            if (interest != 0) {
                watched.append((key, interest));
            }
        }
        watched.append((this._bell as ulong, io._IO_READABLE));
        var count = watched.count;
        var size = _async_poll_entry_size();
        __ptr<u8> descriptors = _pep_malloc(count * size);
        var i: ulong = 0;
        while (i < count) {
            var (handle, interest) = watched[i];
            _async_poll_set(descriptors + i * size, handle, interest);
            i = i + 1;
        }
        var limit = timeout;
        if (this._directory_requests.count > 0 && (limit < 0 || limit > _POLL_DIRECTORY_INTERVAL)) {
            limit = _POLL_DIRECTORY_INTERVAL;
        }
        if (_async_poll_call(descriptors, count, limit) > 0) {
            i = 0;
            while (i < count) {
                var ready = _async_poll_ready(descriptors + i * size);
                if (ready != 0 && i + 1 == count) {
                    _async_poll_drain(this._bell);
                } else if (ready != 0) {
                    var (handle, _) = watched[i];
                    ready_sockets.append((handle, ready));
                }
                i = i + 1;
            }
        }
        _pep_free(descriptors);
        this._collect_directories(false);
    }

    _start_directory_changes(handle: ulong, buffer: ulong, count: ulong, task: ulong): ulong {
        var event = _async_poll_create_event();
        if (event == 0) {
            return 0;
        }
        __ptr<u8> block = _pep_malloc(56);
        __ptr<ulong> words = block;
        words[0] = 0;
        words[1] = 0;
        words[2] = 0;
        # The low bit keeps the completion off any port the directory is
        # tied to.
        words[3] = event | 1;
        words[4] = task;
        words[5] = handle;
        words[6] = event;
        var directory = _async_iocp_block(handle) as __ptr<void>;
        if (!_async_iocp_read_directory(directory, unsafe_cast<__ptr<u8>>(_async_iocp_block(buffer)), count, block)) {
            _async_poll_close_event(event);
            _pep_free(block);
            return 0;
        }
        var request = unsafe_cast<ulong>(block);
        this._directory_requests.insert(request, handle);
        return request;
    }

    _cancel_transfer(request: ulong) {
        if (!this._directory_requests.contains(request)) {
            return;
        }
        var directory = _async_iocp_block(this._directory_requests.get(request)) as __ptr<void>;
        _async_iocp_cancel_directory(directory, unsafe_cast<__ptr<u8>>(_async_iocp_block(request)));
    }

    _finished_files(finished: Array<(task: ulong, result: long)>) {
        for (var item in this._finished) {
            finished.append(item);
        }
        this._finished.clear();
    }

    _want(handle: io.SocketHandle, interest: int): bool {
        return true;
    }

    _forget(handle: io.SocketHandle) {}

    _release(handle: io.SocketHandle) {}

    _doorbell(): _Doorbell {
        return _Doorbell(this._ring_descriptor, this._ring_address);
    }

    _close() {
        # The system writes into a block until its request finishes.
        for (var (request, handle) in this._directory_requests) {
            this._cancel_transfer(request);
        }
        this._collect_directories(true);
        _async_poll_close_bell(this._bell, this._ring_descriptor, this._ring_address);
    }
}

# A new manual-reset event's handle, as a number; 0 where there are none.
[Target(OS(Windows))]
_async_poll_create_event(): ulong {
    return unsafe_cast<ulong>(CreateEventW(__null, 1, 0, __null));
}

[Target(OS(Windows))]
_async_poll_close_event(event: ulong) {
    CloseHandle(_async_iocp_block(event) as __ptr<void>);
}

# Waits for the request whose OVERLAPPED is at `block` on `directory` to
# finish.
[Target(OS(Windows))]
_async_poll_wait_directory(directory: __ptr<void>, block: __ptr<u8>) {
    __ptr<uint> transferred = _pep_malloc(4);
    GetOverlappedResult(directory, block, transferred, 1);
    _pep_free(transferred);
}

[Target(!OS(Windows))]
_async_poll_create_event(): ulong {
    return 0;
}

[Target(!OS(Windows))]
_async_poll_close_event(event: ulong) {}

[Target(!OS(Windows))]
_async_poll_wait_directory(directory: __ptr<void>, block: __ptr<u8>) {}

# Makes a non-blocking self-pipe: stores the read end in `made[0]` and the
# write end in `made[1]` (both stay -1 on failure). Returns the address a
# ring sends to: none on POSIX.
[Target(OS(Linux) || OS(Mac))]
_async_poll_create_bell(made: __ptr<long>): __ptr<u8> {
    __ptr<int> ends = _pep_malloc(8);
    if (pipe(ends) == 0) {
        _async_poll_set_nonblocking(ends[0]);
        _async_poll_set_nonblocking(ends[1]);
        made[0] = ends[0] as long;
        made[1] = ends[1] as long;
    }
    _pep_free(ends);
    return __null;
}

# The first thing `async.run` makes, so where WASI reports it cannot run
# tasks.
[Target(OS(Wasi))]
_async_poll_create_bell(made: __ptr<long>): __ptr<u8> {
    panic("async.run: tasks are not supported on WASI, which cannot switch stacks");
    return __null;
}

# O_NONBLOCK and FD_CLOEXEC on `fd` (F_SETFL 4, F_SETFD 2).
[Target(OS(Linux))]
_async_poll_set_nonblocking(fd: int) {
    fcntl(fd, 4, 2048);
    fcntl(fd, 2, 1);
}

[Target(OS(Mac))]
_async_poll_set_nonblocking(fd: int) {
    fcntl(fd, 4, 4);
    fcntl(fd, 2, 1);
}

# Writes a byte to the pipe's write end `descriptor`.
[Target(!OS(Windows))]
_async_poll_ring(descriptor: long, address: __ptr<u8>) {
    __ptr<u8> byte = _pep_malloc(1);
    byte[0] = 1;
    write(descriptor as int, byte, 1);
    _pep_free(byte);
}

# Reads the pipe's read end `bell` empty.
[Target(!OS(Windows))]
_async_poll_drain(bell: ulong) {
    __ptr<u8> bytes = _pep_malloc(64);
    while (read(bell as int, bytes, 64) > 0) {}
    _pep_free(bytes);
}

[Target(!OS(Windows))]
_async_poll_close_bell(bell: ulong, descriptor: long, address: __ptr<u8>) {
    close(bell as int);
    close(descriptor as int);
}

[Target(!OS(Windows))]
_async_poll_entry_size(): ulong {
    return 8;
}

# Fills a pollfd: POLLIN 1, POLLOUT 4.
[Target(!OS(Windows))]
_async_poll_set(descriptor: __ptr<u8>, handle: ulong, interest: int) {
    unsafe_cast<__ptr<int>>(descriptor)[0] = handle as int;
    var events = 0;
    if ((interest & io._IO_READABLE) != 0) {
        events = events | 1;
    }
    if ((interest & io._IO_WRITABLE) != 0) {
        events = events | 4;
    }
    unsafe_cast<__ptr<u16>>(descriptor + 4)[0] = events as u16;
    unsafe_cast<__ptr<u16>>(descriptor + 6)[0] = 0;
}

# What a pollfd's revents allow. POLLERR 8, POLLHUP 16 and POLLNVAL 32 wake
# both sides, so their waiters retry and see the error.
[Target(!OS(Windows))]
_async_poll_ready(descriptor: __ptr<u8>): int {
    var returned = unsafe_cast<__ptr<u16>>(descriptor + 6)[0] as int;
    if ((returned & 56) != 0) {
        return io._IO_READABLE | io._IO_WRITABLE;
    }
    return _async_ready_mask(returned, 1, 4);  # POLLIN, POLLOUT
}

[Target(!OS(Windows))]
_async_poll_call(descriptors: __ptr<u8>, count: ulong, timeout: long): int {
    return poll(descriptors, count, timeout as int);
}

# Makes a non-blocking UDP socket bound to a free loopback port, stored in
# `made[0]`, and a second UDP socket that rings it, stored in `made[1]` (both
# -1 on failure); returns the first one's address, which a ring sends to.
#
# A ring never uses the socket the worker is polling: a socket made without
# WSA_FLAG_OVERLAPPED serializes its I/O, so a `sendto` on it from another
# worker waits for that worker's `WSAPoll` to return, which it never does.
# Both sockets are overlapped as well.
[Target(OS(Windows))]
_async_poll_create_bell(made: __ptr<long>): __ptr<u8> {
    __ptr<u8> data = _pep_malloc(512);  # WSADATA
    WSAStartup(514, data);              # version 2.2
    _pep_free(data);
    # AF_INET, SOCK_DGRAM, IPPROTO_UDP, WSA_FLAG_OVERLAPPED | WSA_FLAG_NO_HANDLE_INHERIT
    var socket = WSASocketW(2, 2, 17, __null, 0, 129);
    if (socket == ~(0 as ulong)) {
        return __null;
    }
    var sender = WSASocketW(2, 2, 17, __null, 0, 129);
    if (sender == ~(0 as ulong)) {
        closesocket(socket);
        return __null;
    }
    __ptr<u8> address = _pep_malloc(16);  # sockaddr_in: 127.0.0.1, any port
    __ptr<ulong> words = address;
    words[0] = 0;
    words[1] = 0;
    unsafe_cast<__ptr<u16>>(address)[0] = 2;
    address[4] = 127;
    address[7] = 1;
    __ptr<int> length = _pep_malloc(4);
    length[0] = 16;
    __ptr<uint> on = _pep_malloc(4);
    on[0] = 1;
    var made_ok = bind(socket, address, 16) == 0 && getsockname(socket, address, length) == 0;
    if (made_ok) {
        made_ok = ioctlsocket(socket, -2147195266, on) == 0;  # FIONBIO (0x8004667E)
    }
    _pep_free(on);
    _pep_free(length);
    if (!made_ok) {
        closesocket(sender);
        closesocket(socket);
        _pep_free(address);
        return __null;
    }
    made[0] = socket as long;
    made[1] = sender as long;
    return address;
}

# Sends a byte from the UDP socket `descriptor` to the bell at `address`.
[Target(OS(Windows))]
_async_poll_ring(descriptor: long, address: __ptr<u8>) {
    __ptr<u8> byte = _pep_malloc(1);
    byte[0] = 1;
    sendto(descriptor as ulong, byte, 1, 0, address, 16);
    _pep_free(byte);
}

# Receives every datagram waiting on the UDP socket `bell`.
[Target(OS(Windows))]
_async_poll_drain(bell: ulong) {
    __ptr<u8> bytes = _pep_malloc(64);
    while (recv(bell, bytes, 64, 0) >= 0) {}
    _pep_free(bytes);
}

[Target(OS(Windows))]
_async_poll_close_bell(bell: ulong, descriptor: long, address: __ptr<u8>) {
    closesocket(descriptor as ulong);
    closesocket(bell);
    _pep_free(address);
}

[Target(OS(Windows))]
_async_poll_entry_size(): ulong {
    return 16;
}

# Fills a WSAPOLLFD: POLLRDNORM 256, POLLWRNORM 16.
[Target(OS(Windows))]
_async_poll_set(descriptor: __ptr<u8>, handle: ulong, interest: int) {
    unsafe_cast<__ptr<ulong>>(descriptor)[0] = handle;
    var events = 0;
    if ((interest & io._IO_READABLE) != 0) {
        events = events | 256;
    }
    if ((interest & io._IO_WRITABLE) != 0) {
        events = events | 16;
    }
    unsafe_cast<__ptr<u16>>(descriptor + 8)[0] = events as u16;
    unsafe_cast<__ptr<u16>>(descriptor + 10)[0] = 0;
}

# What a WSAPOLLFD's revents allow. POLLERR 1, POLLHUP 2 and POLLNVAL 4 wake
# both sides.
[Target(OS(Windows))]
_async_poll_ready(descriptor: __ptr<u8>): int {
    var returned = unsafe_cast<__ptr<u16>>(descriptor + 10)[0] as int;
    if ((returned & 7) != 0) {
        return io._IO_READABLE | io._IO_WRITABLE;
    }
    return _async_ready_mask(returned, 256, 16);  # POLLRDNORM, POLLWRNORM
}

[Target(OS(Windows))]
_async_poll_call(descriptors: __ptr<u8>, count: ulong, timeout: long): int {
    return WSAPoll(descriptors, count as uint, timeout as int);
}
