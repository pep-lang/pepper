# The epoll I/O driver (Linux) for the task runtime; see driver.pep.
#
# A socket is registered once, edge-triggered, for both reading and writing
# (EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET), the first time a task waits on
# it. Closing the socket removes it from the epoll set. The registration's
# data word is the socket, so an event names the socket it is for.
#
# struct epoll_event is { u32 events; u64 data; }: packed to 12 bytes on
# x86-64, 16 bytes with the data at offset 8 on AArch64. The system calls
# are [Target(OS(Linux))]; elsewhere `_async_epoll_create` fails, so the
# driver is unavailable.
#
# The doorbell is an eventfd registered like a socket, with
# `_async_doorbell_key()` as its data word; a ring writes 1 to it, and the
# poll that sees it reads it back to 0.

import io;
import "driver";
import "task";

[Target(OS(Linux))]
extern int epoll_create1(int flags);
[Target(OS(Linux))]
extern int epoll_ctl(int epoll, int operation, int descriptor, void* event);
[Target(OS(Linux))]
extern int epoll_wait(int epoll, void* events, int capacity, int timeout);
[Target(OS(Linux))]
extern int close(int descriptor);
[Target(OS(Linux))]
extern int eventfd(uint initial, int flags);
[Target(OS(Linux))]
extern long read(int fd, void* buf, ulong n);
[Target(OS(Linux))]
extern long write(int fd, void* buf, ulong n);

[Target(OS(Linux) && Arch(x64))]
const _EPOLL_EVENT_SIZE = 12;
[Target(OS(Linux) && Arch(x64))]
const _EPOLL_DATA_OFFSET = 4;
[Target(OS(Linux) && Arch(aarch64))]
const _EPOLL_EVENT_SIZE = 16;
[Target(OS(Linux) && Arch(aarch64))]
const _EPOLL_DATA_OFFSET = 8;

# EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET.
[Target(OS(Linux))]
const _EPOLL_INTEREST: uint = 2147491845;
# Events that let a reader make progress: EPOLLIN, EPOLLERR, EPOLLHUP,
# EPOLLRDHUP. A writer: EPOLLOUT, EPOLLERR, EPOLLHUP.
[Target(OS(Linux))]
const _EPOLL_READABLE_EVENTS: uint = 8217;
[Target(OS(Linux))]
const _EPOLL_WRITABLE_EVENTS: uint = 28;

# The most events one poll returns.
const _EPOLL_CAPACITY = 256;

# A worker's epoll instance.
export struct _EpollDriver {
    var _epoll: long;
    # Room for `_EPOLL_CAPACITY` events.
    var _events: __ptr<u8>;
    # The doorbell's eventfd.
    var _bell: long;

    construct(epoll: long, bell: long) {
        this._epoll = epoll;
        this._bell = bell;
        this._events = _async_epoll_events();
    }

    # A new driver, or none when the system has no epoll.
    static open(): _EpollDriver? {
        var epoll = _async_epoll_create();
        if (epoll < 0) {
            return Optional<_EpollDriver>.Empty;
        }
        var bell = _async_epoll_create_bell(epoll);
        if (bell < 0) {
            _async_epoll_close(epoll);
            return Optional<_EpollDriver>.Empty;
        }
        return Optional<_EpollDriver>.Value(_EpollDriver(epoll, bell));
    }
}

extend _EpollDriver with _Driver {
    _watch(handle: io.SocketHandle): bool {
        return _async_epoll_add(this._epoll, handle);
    }

    _poll(waits: HashMap<ulong, _SocketWaits>, timeout: long, ready_sockets: Array<(handle: ulong, interest: int)>) {
        var count = _async_epoll_wait(this._epoll, this._events, timeout);
        var i: ulong = 0;
        while (i < count) {
            var handle = _async_epoll_event_handle(this._events, i);
            if (handle == _async_doorbell_key()) {
                _async_epoll_drain(this._bell);
            } else {
                ready_sockets.append((handle, _async_epoll_event_interest(this._events, i)));
            }
            i = i + 1;
        }
    }

    _want(handle: io.SocketHandle, interest: int): bool {
        return true;
    }

    _forget(handle: io.SocketHandle) {}

    _release(handle: io.SocketHandle) {
        _async_epoll_remove(this._epoll, handle);
    }

    _doorbell(): _Doorbell {
        return _Doorbell(_DoorbellKind.EventFd, this._bell);
    }

    _close() {
        _async_epoll_close(this._bell);
        _async_epoll_close(this._epoll);
        _pep_free(this._events);
    }
}

# A new epoll instance (close-on-exec), or -1.
[Target(OS(Linux))]
_async_epoll_create(): long {
    return epoll_create1(524288) as long;  # EPOLL_CLOEXEC
}

[Target(OS(Linux))]
_async_epoll_close(epoll: long) {
    close(epoll as int);
}

[Target(OS(Linux))]
_async_epoll_events(): __ptr<u8> {
    return _pep_malloc((_EPOLL_CAPACITY * _EPOLL_EVENT_SIZE) as ulong);
}

# Watches `handle` for both reading and writing until it is closed; false
# for a descriptor epoll cannot watch.
[Target(OS(Linux))]
_async_epoll_add(epoll: long, handle: io.SocketHandle): bool {
    __ptr<u8> event = _pep_malloc(16);
    unsafe_cast<__ptr<uint>>(event)[0] = _EPOLL_INTEREST;
    unsafe_cast<__ptr<ulong>>(event + _EPOLL_DATA_OFFSET)[0] = handle as ulong;
    var rc = epoll_ctl(epoll as int, 1, handle, event);  # EPOLL_CTL_ADD
    _pep_free(event);
    return rc == 0;
}

# Stops watching `handle`.
[Target(OS(Linux))]
_async_epoll_remove(epoll: long, handle: io.SocketHandle) {
    __ptr<u8> event = _pep_malloc(16);          # ignored, but not null for kernels before 2.6.9
    epoll_ctl(epoll as int, 2, handle, event);  # EPOLL_CTL_DEL
    _pep_free(event);
}

# A non-blocking eventfd watched by `epoll` under the doorbell key, or -1.
[Target(OS(Linux))]
_async_epoll_create_bell(epoll: long): long {
    var bell = eventfd(0, 526336);  # EFD_NONBLOCK | EFD_CLOEXEC
    if (bell < 0) {
        return -1;
    }
    __ptr<u8> event = _pep_malloc(16);
    unsafe_cast<__ptr<uint>>(event)[0] = _EPOLL_INTEREST;
    unsafe_cast<__ptr<ulong>>(event + _EPOLL_DATA_OFFSET)[0] = _async_doorbell_key();
    var rc = epoll_ctl(epoll as int, 1, bell, event);  # EPOLL_CTL_ADD
    _pep_free(event);
    if (rc != 0) {
        close(bell);
        return -1;
    }
    return bell as long;
}

# Rings the doorbell eventfd `bell`.
[Target(OS(Linux))]
export _async_epoll_ring(bell: long) {
    __ptr<ulong> one = _pep_malloc(8);
    one[0] = 1;
    write(bell as int, one, 8);
    _pep_free(one);
}

# Resets the doorbell eventfd `bell` to 0. The io_uring driver's doorbell is
# an eventfd too, and drains with this.
[Target(OS(Linux))]
export _async_epoll_drain(bell: long) {
    __ptr<ulong> value = _pep_malloc(8);
    read(bell as int, value, 8);
    _pep_free(value);
}

# Waits up to `timeout` milliseconds (forever when negative) and returns how
# many events it stored; 0 on a timeout or a signal.
[Target(OS(Linux))]
_async_epoll_wait(epoll: long, events: __ptr<u8>, timeout: long): ulong {
    var count = epoll_wait(epoll as int, events, _EPOLL_CAPACITY, timeout as int);
    if (count < 0) {
        return 0;
    }
    return count as ulong;
}

[Target(OS(Linux))]
_async_epoll_event_handle(events: __ptr<u8>, index: ulong): ulong {
    var event = events + index * (_EPOLL_EVENT_SIZE as ulong);
    return unsafe_cast<__ptr<ulong>>(event + _EPOLL_DATA_OFFSET)[0];
}

[Target(OS(Linux))]
_async_epoll_event_interest(events: __ptr<u8>, index: ulong): int {
    var event = events + index * (_EPOLL_EVENT_SIZE as ulong);
    var bits = unsafe_cast<__ptr<uint>>(event)[0];
    return _async_ready_mask(bits, _EPOLL_READABLE_EVENTS, _EPOLL_WRITABLE_EVENTS);
}

# Elsewhere there is no epoll.

[Target(!OS(Linux))]
_async_epoll_create(): long {
    return -1;
}

[Target(!OS(Linux))]
_async_epoll_close(epoll: long) {}

[Target(!OS(Linux))]
_async_epoll_create_bell(epoll: long): long {
    return -1;
}

[Target(!OS(Linux))]
export _async_epoll_ring(bell: long) {}

[Target(!OS(Linux))]
export _async_epoll_drain(bell: long) {}

[Target(!OS(Linux))]
_async_epoll_events(): __ptr<u8> {
    return __null;
}

[Target(!OS(Linux))]
_async_epoll_add(epoll: long, handle: io.SocketHandle): bool {
    return false;
}

[Target(!OS(Linux))]
_async_epoll_remove(epoll: long, handle: io.SocketHandle) {}

[Target(!OS(Linux))]
_async_epoll_wait(epoll: long, events: __ptr<u8>, timeout: long): ulong {
    return 0;
}

[Target(!OS(Linux))]
_async_epoll_event_handle(events: __ptr<u8>, index: ulong): ulong {
    return 0;
}

[Target(!OS(Linux))]
_async_epoll_event_interest(events: __ptr<u8>, index: ulong): int {
    return 0;
}
