## I/O backends: how a task runtime waits for sockets.

# The driver seam. A worker owns one `_Driver`, chosen when `run` starts
# (`_async_open_driver`): epoll (driver_epoll.pep), io_uring
# (driver_io_uring.pep), kqueue (driver_kqueue.pep), IOCP (driver_iocp.pep),
# or poll(), the portable reference (driver_poll.pep). Every driver type
# exists on every OS; the system calls behind one are [Target]ed, with stubs
# elsewhere that make it unavailable, so the choice can be made at run time.
#
# Each driver also has a doorbell (`_Doorbell`): any thread can ring it to
# end the worker's current or next wait early, so a worker blocked in its
# driver notices messages from other workers. It is an eventfd (epoll and
# io_uring), an EVFILT_USER event (kqueue), a posted completion (IOCP), or a
# self-pipe (poll on POSIX) or a loopback UDP socket that a second socket
# sends to (poll on Windows). A ring is remembered until the next wait, so a
# ring that lands just before the worker blocks still wakes it.

import io;
import "driver_epoll";
import "driver_io_uring";
import "driver_iocp";
import "driver_kqueue";
import "driver_poll";
import "task";

## The I/O backend a runtime waits on sockets with (see
## `RuntimeOptions.backend`).
export enum Backend {
    ## The best one the system has: epoll on Linux, kqueue on macOS, IOCP on
    ## Windows. The `PEPPER_IO_BACKEND` environment variable (`epoll`,
    ## `io_uring`, `kqueue`, `iocp` or `poll`) picks another.
    Automatic,
    ## Linux's epoll, edge-triggered.
    Epoll,
    ## Linux's io_uring (kernel 5.11 or later), waiting for sockets with
    ## one multishot poll request each. Not the default: container seccomp
    ## profiles and hardened kernels often refuse it.
    IoUring,
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

    # `handle` stays open but moves to another worker (see
    # `io.TcpStream.into_transfer`): stops watching it.
    _release(handle: io.SocketHandle);

    # Starts reading `count` bytes into the memory at address `buffer` from
    # the file `handle` (or writing them from it, when `write`) at the
    # file's position, for the task `task`; false if this driver cannot (the
    # worker then runs the call on a pool thread). `_finished_files` reports
    # it. (The address is a ulong: a `__ptr` parameter in a trait method
    # does not compile yet.)
    _start_file(handle: long, buffer: ulong, count: ulong, write: bool, task: ulong): bool {
        return false;
    }

    # Moves the file transfers finished since the last call to `tasks` and
    # `results` (a byte count, or -1 minus the error code, as
    # `io._io_file_transfer_raw` returns).
    _finished_files(tasks: Array<ulong>, results: Array<long>) {}

    # The doorbell that ends this driver's waits early, from any thread.
    _doorbell(): _Doorbell;

    # Releases the driver's system resources, the doorbell's included.
    _close();
}

# What a doorbell rings.
export const _DOORBELL_EVENTFD = 1;
export const _DOORBELL_KQUEUE = 2;
export const _DOORBELL_IOCP = 3;
export const _DOORBELL_POLL = 4;

# Wakes a worker blocked in its driver, from any thread (see the notes at
# the top of this file). The driver that made it keeps its resources open
# until every worker has stopped, so a ring never reaches a closed handle.
[Shared]
export struct _Doorbell {
    # One of the `_DOORBELL_*` kinds.
    const _kind: int;
    # The eventfd, kqueue or pipe's write end, or the sending UDP socket.
    const _descriptor: long;
    # The completion port (IOCP).
    const _port: __ptr<void>;
    # The address of the UDP socket a ring sends to (a sockaddr_in).
    const _address: __ptr<u8>;

    construct(kind: int, descriptor: long, port: __ptr<void>, address: __ptr<u8>) {
        _kind = kind;
        _descriptor = descriptor;
        _port = port;
        _address = address;
    }

    # Ends the worker's current wait, or its next one.
    _ring() {
        if (_kind == _DOORBELL_EVENTFD) {
            _async_epoll_ring(_descriptor);
        } else if (_kind == _DOORBELL_KQUEUE) {
            _async_kqueue_ring(_descriptor);
        } else if (_kind == _DOORBELL_IOCP) {
            _async_iocp_ring(_port);
        } else {
            _async_poll_ring(_descriptor, _address);
        }
    }
}

# The data word a driver gives its doorbell's registration, which no socket
# has.
export _async_doorbell_key(): ulong {
    return ~(0 as ulong);
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
    } else if (backend == Backend.IoUring) {
        var io_uring = _IoUringDriver.open();
        if (io_uring.is_some()) {
            return (io_uring.value(), backend);
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
    if (_async_c_string_is(value, "io_uring")) {
        return Backend.IoUring;
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
    panic("async.run: PEPPER_IO_BACKEND must be epoll, io_uring, kqueue, iocp or poll");
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
