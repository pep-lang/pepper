# The Linux I/O driver for the task runtime in task.pep: epoll. Every
# declaration carries [Target(OS(Linux))]; driver_kqueue.pep declares the
# same `_async_driver_*` functions for macOS, and driver_windows.pep for
# Windows.
#
# A socket is registered once, edge-triggered, for both reading and writing
# (EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET), the first time a task waits on
# it. Closing the socket removes it from the epoll set. The registration's
# data word is the socket, so an event names the socket it is for.
#
# struct epoll_event is { u32 events; u64 data; }: packed to 12 bytes on
# x86-64, 16 bytes with the data at offset 8 on AArch64.

import io;

[Target(OS(Linux))]
extern int epoll_create1(int flags);
[Target(OS(Linux))]
extern int epoll_ctl(int epoll, int operation, int descriptor, void* event);
[Target(OS(Linux))]
extern int epoll_wait(int epoll, void* events, int capacity, int timeout);
[Target(OS(Linux))]
extern int close(int descriptor);

[Target(OS(Linux) && Arch(x64))]
const _DRIVER_EVENT_SIZE = 12;
[Target(OS(Linux) && Arch(x64))]
const _DRIVER_DATA_OFFSET = 4;
[Target(OS(Linux) && Arch(aarch64))]
const _DRIVER_EVENT_SIZE = 16;
[Target(OS(Linux) && Arch(aarch64))]
const _DRIVER_DATA_OFFSET = 8;

# EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET.
[Target(OS(Linux))]
const _DRIVER_INTEREST: uint = 2147491845;
# Events that let a reader make progress: EPOLLIN, EPOLLERR, EPOLLHUP,
# EPOLLRDHUP. A writer: EPOLLOUT, EPOLLERR, EPOLLHUP.
[Target(OS(Linux))]
const _DRIVER_READABLE_EVENTS: uint = 8217;
[Target(OS(Linux))]
const _DRIVER_WRITABLE_EVENTS: uint = 28;

# The most events one poll returns.
[Target(OS(Linux))]
const _DRIVER_CAPACITY = 256;

# A new epoll instance (close-on-exec), or -1.
[Target(OS(Linux))]
export _async_driver_open(): long {
    return epoll_create1(524288) as long;  # EPOLL_CLOEXEC
}

[Target(OS(Linux))]
export _async_driver_close(driver: long) {
    close(driver as int);
}

# A buffer for the events one poll returns; free it with _pep_free.
[Target(OS(Linux))]
export _async_driver_events(): __ptr<u8> {
    return _pep_malloc((_DRIVER_CAPACITY * _DRIVER_EVENT_SIZE) as ulong);
}

# Watches `handle` for both reading and writing from now until it is closed.
# Fails (false) for a descriptor epoll cannot watch.
[Target(OS(Linux))]
export _async_driver_register(driver: long, handle: io.SocketHandle): bool {
    __ptr<u8> event = _pep_malloc(16);
    ((event) as __ptr<uint>)[0] = _DRIVER_INTEREST;
    ((event + _DRIVER_DATA_OFFSET) as __ptr<ulong>)[0] = handle as ulong;
    var rc = epoll_ctl(driver as int, 1, handle, event);  # EPOLL_CTL_ADD
    _pep_free(event);
    return rc == 0;
}

# Waits up to `timeout` milliseconds (forever when negative) for events and
# returns how many it stored in `events`; 0 on a timeout or a signal.
[Target(OS(Linux))]
export _async_driver_poll(driver: long, events: __ptr<u8>, timeout: long): ulong {
    var count = epoll_wait(driver as int, events, _DRIVER_CAPACITY, timeout as int);
    if (count < 0) {
        return 0;
    }
    return count as ulong;
}

# The socket the `index`th event is for.
[Target(OS(Linux))]
export _async_driver_event_handle(events: __ptr<u8>, index: ulong): io.SocketHandle {
    var event = events + index * (_DRIVER_EVENT_SIZE as ulong);
    return ((event + _DRIVER_DATA_OFFSET) as __ptr<ulong>)[0] as io.SocketHandle;
}

# What the `index`th event lets a waiting task do: io._IO_READABLE and
# io._IO_WRITABLE or'ed together.
[Target(OS(Linux))]
export _async_driver_event_interest(events: __ptr<u8>, index: ulong): int {
    var event = events + index * (_DRIVER_EVENT_SIZE as ulong);
    var bits = (event as __ptr<uint>)[0];
    var interest = 0;
    if ((bits & _DRIVER_READABLE_EVENTS) != 0) {
        interest = interest | io._IO_READABLE;
    }
    if ((bits & _DRIVER_WRITABLE_EVENTS) != 0) {
        interest = interest | io._IO_WRITABLE;
    }
    return interest;
}

# Polls use registrations, not a list of waiting sockets (see
# driver_windows.pep).
[Target(OS(Linux))]
export _async_driver_uses_interest(): bool {
    return false;
}

[Target(OS(Linux))]
export _async_driver_poll_interest(
    driver: long, handles: Array<ulong>, interests: Array<int>, events: __ptr<u8>, timeout: long
): ulong {
    return 0;
}
