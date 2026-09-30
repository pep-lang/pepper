# The macOS I/O driver for the task runtime in task.pep: kqueue. Every
# declaration carries [Target(OS(Mac))]; driver_epoll.pep declares the same
# `_async_driver_*` functions for Linux, and driver_windows.pep for Windows.
#
# A socket is registered once, edge-triggered (EV_CLEAR), with a read filter
# and a write filter, the first time a task waits on it. Closing the socket
# removes both. An event's ident is the socket.
#
# struct kevent is 32 bytes: ident (u64) at 0, filter (i16) at 8, flags
# (u16) at 10, fflags (u32) at 12, data (i64) at 16, udata at 24.

import io;

[Target(OS(Mac))]
extern int kqueue();
[Target(OS(Mac))]
extern int kevent(int queue, void* changes, int change_count, void* events, int event_count, void* timeout);
[Target(OS(Mac))]
extern int close(int descriptor);

[Target(OS(Mac))]
const _DRIVER_EVENT_SIZE = 32;
# The most events one poll returns.
[Target(OS(Mac))]
const _DRIVER_CAPACITY = 256;
# EVFILT_READ and EVFILT_WRITE.
[Target(OS(Mac))]
const _DRIVER_FILTER_READ = -1;
[Target(OS(Mac))]
const _DRIVER_FILTER_WRITE = -2;
# EV_EOF | EV_ERROR: the peer closed, or the socket failed; wake both sides.
[Target(OS(Mac))]
const _DRIVER_END_FLAGS = 49152;

# A new kqueue, or -1.
[Target(OS(Mac))]
export _async_driver_open(): long {
    return kqueue() as long;
}

[Target(OS(Mac))]
export _async_driver_close(driver: long) {
    close(driver as int);
}

# A buffer for the events one poll returns; free it with _pep_free.
[Target(OS(Mac))]
export _async_driver_events(): __ptr<u8> {
    return _pep_malloc((_DRIVER_CAPACITY * _DRIVER_EVENT_SIZE) as ulong);
}

# Fills the `index`th kevent in `changes`: EV_ADD | EV_CLEAR on `filter`.
[Target(OS(Mac))]
export _async_driver_change(changes: __ptr<u8>, index: ulong, handle: io.SocketHandle, filter: int) {
    var change = changes + index * 32;
    ((change) as __ptr<ulong>)[0] = handle as ulong;
    ((change + 8) as __ptr<i16>)[0] = filter as i16;
    ((change + 10) as __ptr<u16>)[0] = 33;  # EV_ADD | EV_CLEAR
    ((change + 12) as __ptr<uint>)[0] = 0;
    ((change + 16) as __ptr<long>)[0] = 0;
    ((change + 24) as __ptr<ulong>)[0] = 0;
}

# Watches `handle` for both reading and writing from now until it is closed.
# Fails (false) for a descriptor kqueue cannot watch.
[Target(OS(Mac))]
export _async_driver_register(driver: long, handle: io.SocketHandle): bool {
    __ptr<u8> changes = _pep_malloc(64);
    _async_driver_change(changes, 0, handle, _DRIVER_FILTER_READ);
    _async_driver_change(changes, 1, handle, _DRIVER_FILTER_WRITE);
    var rc = kevent(driver as int, changes, 2, __null, 0, __null);
    _pep_free(changes);
    return rc == 0;
}

# Waits up to `timeout` milliseconds (forever when negative) for events and
# returns how many it stored in `events`; 0 on a timeout or a signal.
[Target(OS(Mac))]
export _async_driver_poll(driver: long, events: __ptr<u8>, timeout: long): ulong {
    var count = 0;
    if (timeout < 0) {
        count = kevent(driver as int, __null, 0, events, _DRIVER_CAPACITY, __null);
    } else {
        __ptr<long> span = _pep_malloc(16);  # struct timespec
        span[0] = timeout / 1000;
        span[1] = timeout % 1000 * 1000000;
        count = kevent(driver as int, __null, 0, events, _DRIVER_CAPACITY, span);
        _pep_free(span);
    }
    if (count < 0) {
        return 0;
    }
    return count as ulong;
}

# The socket the `index`th event is for.
[Target(OS(Mac))]
export _async_driver_event_handle(events: __ptr<u8>, index: ulong): io.SocketHandle {
    var event = events + index * 32;
    return (event as __ptr<ulong>)[0] as io.SocketHandle;
}

# What the `index`th event lets a waiting task do: io._IO_READABLE and
# io._IO_WRITABLE or'ed together.
[Target(OS(Mac))]
export _async_driver_event_interest(events: __ptr<u8>, index: ulong): int {
    var event = events + index * 32;
    var filter = ((event + 8) as __ptr<i16>)[0] as int;
    var flags = ((event + 10) as __ptr<u16>)[0] as int;
    if ((flags & _DRIVER_END_FLAGS) != 0) {
        return io._IO_READABLE | io._IO_WRITABLE;
    }
    if (filter == _DRIVER_FILTER_READ) {
        return io._IO_READABLE;
    }
    return io._IO_WRITABLE;
}

# Polls use registrations, not a list of waiting sockets (see
# driver_windows.pep).
[Target(OS(Mac))]
export _async_driver_uses_interest(): bool {
    return false;
}

[Target(OS(Mac))]
export _async_driver_poll_interest(
    driver: long, handles: Array<ulong>, interests: Array<int>, events: __ptr<u8>, timeout: long
): ulong {
    return 0;
}
