# The Windows I/O driver for the task runtime in task.pep: WSAPoll. Every
# declaration carries [Target(OS(Windows))]; driver_epoll.pep and
# driver_kqueue.pep declare the same `_async_driver_*` functions for Linux
# and macOS.
#
# WSAPoll is level-triggered and keeps no registrations, so each poll passes
# the sockets tasks are waiting on and what they wait for
# (`_async_driver_uses_interest` makes the worker collect them). It costs a
# pass over the waiting sockets per poll; the I/O completion port driver
# replaces it.
#
# An event in the buffer is 16 bytes: the socket (u64) at 0, what it lets a
# task do (io._IO_READABLE | io._IO_WRITABLE) at 8.

import io;

[Target(OS(Windows))]
[Link("ws2_32")]
extern int WSAPoll(void* descriptors, uint count, int timeout);

# The most events one poll returns.
[Target(OS(Windows))]
const _DRIVER_CAPACITY = 256;

[Target(OS(Windows))]
export _async_driver_open(): long {
    return 0;
}

[Target(OS(Windows))]
export _async_driver_close(driver: long) {}

[Target(OS(Windows))]
export _async_driver_events(): __ptr<u8> {
    return _pep_malloc((_DRIVER_CAPACITY * 16) as ulong);
}

# Nothing to register: each poll names its sockets.
[Target(OS(Windows))]
export _async_driver_register(driver: long, handle: io.SocketHandle): bool {
    return true;
}

# Whether polls take the waiting sockets (`_async_driver_poll_interest`)
# rather than using registrations (`_async_driver_poll`).
[Target(OS(Windows))]
export _async_driver_uses_interest(): bool {
    return true;
}

[Target(OS(Windows))]
export _async_driver_poll(driver: long, events: __ptr<u8>, timeout: long): ulong {
    return 0;
}

# Waits up to `timeout` milliseconds (forever when negative) until one of
# `handles` is ready for its `interests` entry, and stores what is ready in
# `events`; returns how many. An error or hang-up on a socket counts as
# both readable and writable, so its waiters retry and see the error.
[Target(OS(Windows))]
export _async_driver_poll_interest(
    driver: long, handles: Array<ulong>, interests: Array<int>, events: __ptr<u8>, timeout: long
): ulong {
    var count = handles.count();
    if (count == 0) {
        return 0;
    }
    __ptr<u8> descriptors = _pep_malloc(count * 16);  # WSAPOLLFD
    var i: ulong = 0;
    while (i < count) {
        var descriptor = descriptors + i * 16;
        (descriptor as __ptr<ulong>)[0] = handles[i];
        var wanted = 0;
        if ((interests[i] & io._IO_READABLE) != 0) {
            wanted = wanted | 256;  # POLLRDNORM
        }
        if ((interests[i] & io._IO_WRITABLE) != 0) {
            wanted = wanted | 16;  # POLLWRNORM
        }
        ((descriptor + 8) as __ptr<u16>)[0] = wanted as u16;
        ((descriptor + 10) as __ptr<u16>)[0] = 0;
        i = i + 1;
    }
    var ready = WSAPoll(descriptors, count as uint, timeout as int);
    var stored: ulong = 0;
    if (ready > 0) {
        i = 0;
        while (i < count && stored < _DRIVER_CAPACITY as ulong) {
            var descriptor = descriptors + i * 16;
            var returned = ((descriptor + 10) as __ptr<u16>)[0] as int;
            var interest = 0;
            if ((returned & 256) != 0) {
                interest = interest | io._IO_READABLE;
            }
            if ((returned & 16) != 0) {
                interest = interest | io._IO_WRITABLE;
            }
            if ((returned & 7) != 0) {  # POLLERR | POLLHUP | POLLNVAL
                interest = io._IO_READABLE | io._IO_WRITABLE;
            }
            if (interest != 0) {
                var event = events + stored * 16;
                (event as __ptr<ulong>)[0] = handles[i];
                ((event + 8) as __ptr<int>)[0] = interest;
                stored = stored + 1;
            }
            i = i + 1;
        }
    }
    _pep_free(descriptors);
    return stored;
}

[Target(OS(Windows))]
export _async_driver_event_handle(events: __ptr<u8>, index: ulong): io.SocketHandle {
    return ((events + index * 16) as __ptr<ulong>)[0];
}

[Target(OS(Windows))]
export _async_driver_event_interest(events: __ptr<u8>, index: ulong): int {
    return ((events + index * 16 + 8) as __ptr<int>)[0];
}
