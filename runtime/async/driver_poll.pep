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

import io;
import "driver";
import "sys_posix";
import "sys_windows";
import "task";

[Target(!OS(Windows))]
extern int poll(void* descriptors, ulong count, int timeout);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int WSAPoll(void* descriptors, uint count, int timeout);

# The portable driver.
export struct _PollDriver {
    construct() {}
}

extend _PollDriver with _Driver {
    _watch(handle: io.SocketHandle): bool {
        return true;
    }

    _poll(waits: HashMap<ulong, _SocketWaits>, timeout: long, handles: Array<ulong>, interests: Array<int>) {
        var watched = Array<ulong>();
        var wanted = Array<int>();
        for (var entry in waits) {
            var (key, waiting) = entry;
            var interest = 0;
            if (waiting._readers.count() > 0) {
                interest = interest | io._IO_READABLE;
            }
            if (waiting._writers.count() > 0) {
                interest = interest | io._IO_WRITABLE;
            }
            if (interest != 0) {
                watched.append(key);
                wanted.append(interest);
            }
        }
        var count = watched.count();
        if (count == 0) {
            if (timeout > 0) {
                _async_sys_sleep(timeout as ulong);
            }
            return;
        }
        var size = _async_poll_entry_size();
        __ptr<u8> descriptors = _pep_malloc(count * size);
        var i: ulong = 0;
        while (i < count) {
            _async_poll_set(descriptors + i * size, watched[i], wanted[i]);
            i = i + 1;
        }
        if (_async_poll_call(descriptors, count, timeout) > 0) {
            i = 0;
            while (i < count) {
                var ready = _async_poll_ready(descriptors + i * size);
                if (ready != 0) {
                    handles.append(watched[i]);
                    interests.append(ready);
                }
                i = i + 1;
            }
        }
        _pep_free(descriptors);
    }

    _want(handle: io.SocketHandle, interest: int): bool {
        return true;
    }

    _forget(handle: io.SocketHandle) {}

    _close() {}
}

[Target(!OS(Windows))]
_async_poll_entry_size(): ulong {
    return 8;
}

# Fills a pollfd: POLLIN 1, POLLOUT 4.
[Target(!OS(Windows))]
_async_poll_set(descriptor: __ptr<u8>, handle: ulong, interest: int) {
    (descriptor as __ptr<int>)[0] = handle as int;
    var events = 0;
    if ((interest & io._IO_READABLE) != 0) {
        events = events | 1;
    }
    if ((interest & io._IO_WRITABLE) != 0) {
        events = events | 4;
    }
    ((descriptor + 4) as __ptr<u16>)[0] = events as u16;
    ((descriptor + 6) as __ptr<u16>)[0] = 0;
}

# What a pollfd's revents allow. POLLERR 8, POLLHUP 16 and POLLNVAL 32 wake
# both sides, so their waiters retry and see the error.
[Target(!OS(Windows))]
_async_poll_ready(descriptor: __ptr<u8>): int {
    var returned = ((descriptor + 6) as __ptr<u16>)[0] as int;
    if ((returned & 56) != 0) {
        return io._IO_READABLE | io._IO_WRITABLE;
    }
    var ready = 0;
    if ((returned & 1) != 0) {
        ready = ready | io._IO_READABLE;
    }
    if ((returned & 4) != 0) {
        ready = ready | io._IO_WRITABLE;
    }
    return ready;
}

[Target(!OS(Windows))]
_async_poll_call(descriptors: __ptr<u8>, count: ulong, timeout: long): int {
    return poll(descriptors, count, timeout as int);
}

[Target(OS(Windows))]
_async_poll_entry_size(): ulong {
    return 16;
}

# Fills a WSAPOLLFD: POLLRDNORM 256, POLLWRNORM 16.
[Target(OS(Windows))]
_async_poll_set(descriptor: __ptr<u8>, handle: ulong, interest: int) {
    (descriptor as __ptr<ulong>)[0] = handle;
    var events = 0;
    if ((interest & io._IO_READABLE) != 0) {
        events = events | 256;
    }
    if ((interest & io._IO_WRITABLE) != 0) {
        events = events | 16;
    }
    ((descriptor + 8) as __ptr<u16>)[0] = events as u16;
    ((descriptor + 10) as __ptr<u16>)[0] = 0;
}

# What a WSAPOLLFD's revents allow. POLLERR 1, POLLHUP 2 and POLLNVAL 4 wake
# both sides.
[Target(OS(Windows))]
_async_poll_ready(descriptor: __ptr<u8>): int {
    var returned = ((descriptor + 10) as __ptr<u16>)[0] as int;
    if ((returned & 7) != 0) {
        return io._IO_READABLE | io._IO_WRITABLE;
    }
    var ready = 0;
    if ((returned & 256) != 0) {
        ready = ready | io._IO_READABLE;
    }
    if ((returned & 16) != 0) {
        ready = ready | io._IO_WRITABLE;
    }
    return ready;
}

[Target(OS(Windows))]
_async_poll_call(descriptors: __ptr<u8>, count: ulong, timeout: long): int {
    return WSAPoll(descriptors, count as uint, timeout as int);
}
