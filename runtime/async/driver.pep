## I/O backends: how a task runtime waits for sockets.

# The driver seam. A worker owns one `_Driver`, chosen when `run` starts
# (`_async_open_driver`): epoll (driver_epoll.pep), kqueue
# (driver_kqueue.pep), IOCP (driver_iocp.pep), or poll(), the portable
# reference (driver_poll.pep). Every driver type exists on every OS; the
# system calls behind one are [Target]ed, with stubs elsewhere that make it
# unavailable, so the choice can be made at run time.

import io;
import "driver_epoll";
import "driver_iocp";
import "driver_kqueue";
import "driver_poll";
import "task";

## The I/O backend a runtime waits on sockets with (see
## `RuntimeOptions.backend`).
export enum Backend {
    ## The best one the system has: epoll on Linux, kqueue on macOS, IOCP on
    ## Windows. The `PEPPER_IO_BACKEND` environment variable (`epoll`,
    ## `kqueue`, `iocp` or `poll`) picks another.
    Automatic,
    ## Linux's epoll, edge-triggered.
    Epoll,
    ## The BSD and macOS kqueue, edge-triggered.
    Kqueue,
    ## A Windows I/O completion port, fed readiness by AFD poll requests.
    Iocp,
    ## `poll()` (`WSAPoll` on Windows): available everywhere, but each wait
    ## passes every waiting socket to the system, so it suits few
    ## connections. The reference the others are tested against.
    Poll,
}

# How a worker waits for sockets.
export trait _Driver {
    # Starts watching `handle`, the first time a task waits on it; false if
    # this driver cannot watch it.
    _watch(handle: io.SocketHandle): bool;

    # A task is about to wait for `interest` on `handle` (already watched);
    # false if the driver cannot wait for it (the task then blocks the
    # thread instead).
    _want(handle: io.SocketHandle, interest: int): bool;

    # Waits up to `timeout` milliseconds (forever when negative) until a
    # socket in `waits` may be ready for what its tasks wait for, and
    # appends each ready socket and what it allows (io._IO_READABLE and
    # io._IO_WRITABLE or'ed) to `handles` and `interests`. Returns early,
    # with nothing, on a signal.
    _poll(waits: HashMap<ulong, _SocketWaits>, timeout: long, handles: Array<ulong>, interests: Array<int>);

    # `handle` is about to be closed.
    _forget(handle: io.SocketHandle);

    # Releases the driver's system resources.
    _close();
}

# The driver for `requested`, and the backend it is. Automatic takes
# PEPPER_IO_BACKEND if set, else the system's best, and falls back to poll
# when that cannot start.
export _async_open_driver(requested: Backend): (_Driver, Backend) {
    var backend = requested;
    if (backend == Backend.Automatic) {
        backend = _async_backend_from_environment();
    }
    var automatic = backend == Backend.Automatic;
    if (automatic) {
        backend = _async_best_backend();
    }
    if (backend == Backend.Epoll) {
        var epoll = _EpollDriver.open();
        if (epoll.is_some()) {
            return (epoll.value(), backend);
        }
    } else if (backend == Backend.Kqueue) {
        var kqueue = _KqueueDriver.open();
        if (kqueue.is_some()) {
            return (kqueue.value(), backend);
        }
    } else if (backend == Backend.Iocp) {
        var iocp = _IocpDriver.open();
        if (iocp.is_some()) {
            return (iocp.value(), backend);
        }
    } else {
        return (_PollDriver(), Backend.Poll);
    }
    assert(automatic, "async.run: the " + backend.name() + " I/O backend is not available on this system");
    return (_PollDriver(), Backend.Poll);
}

[Target(OS(Linux))]
_async_best_backend(): Backend {
    return Backend.Epoll;
}

[Target(OS(Mac))]
_async_best_backend(): Backend {
    return Backend.Kqueue;
}

[Target(OS(Windows))]
_async_best_backend(): Backend {
    return Backend.Iocp;
}

extern char* getenv(char* name);

# PEPPER_IO_BACKEND as a backend: Automatic when unset.
# @panics when it names no backend
_async_backend_from_environment(): Backend {
    var name = "PEPPER_IO_BACKEND";
    var value = getenv(name.c_str());
    if (value == __null) {
        return Backend.Automatic;
    }
    if (_async_c_string_is(value, "epoll")) {
        return Backend.Epoll;
    }
    if (_async_c_string_is(value, "kqueue")) {
        return Backend.Kqueue;
    }
    if (_async_c_string_is(value, "iocp")) {
        return Backend.Iocp;
    }
    if (_async_c_string_is(value, "poll")) {
        return Backend.Poll;
    }
    panic("async.run: PEPPER_IO_BACKEND must be epoll, kqueue, iocp or poll");
    return Backend.Automatic;
}

# Whether the C string `c` holds exactly `text`.
_async_c_string_is(c: __ptr<char>, text: String): bool {
    var expected = text.c_str();
    var i: ulong = 0;
    while (i < text.size()) {
        if (c[i] != expected[i]) {
            return false;
        }
        i = i + 1;
    }
    return c[i] == 0;
}
