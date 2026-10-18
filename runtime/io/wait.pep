# How a socket waits until it can make progress: the seam between the
# sockets here and the task runtime in the `async` module.
#
# Sockets are non-blocking. When a call would block, the socket waits for
# the handle to become ready and tries again (`_io_socket_wait`). Outside a
# task that wait is poll() / WSAPoll(), which blocks the thread. Inside a
# task it is the runtime's `_IoWaiter`, which parks the task and lets the
# others run until the handle is ready.
#
# A Watcher (watch.pep) waits the same way: on Linux and macOS its inotify
# or kqueue descriptor is waited on for readability like a socket; on
# Windows its ReadDirectoryChangesW request goes to the runtime whole
# (`_IoWaiter._directory_changes`), like a socket transfer.
#
# Files have no readiness to wait for, so a file read or write in a task
# goes to the runtime whole (`_IoWaiter._file_transfer`): it runs the
# system call where it cannot block the worker (on io_uring, or on a pool
# thread) and parks the task until it is done. The caller pins the array it
# reads into or writes from (`Array._pins`) for that time.
#
# With io_uring, a stream socket's reads and writes in a task go to the
# runtime whole too (`_IoWaiter._socket_transfer`): the kernel does the
# receive or send itself when the socket is ready, and the worker submits
# many of them in one system call, rather than learning readiness and then
# calling `recv` or `send`. The other backends decline, and the socket
# waits for readiness as above.
#
# A socket may have a read and a write timeout (`set_read_timeout`,
# `set_write_timeout`): each wait for readiness then ends after that many
# milliseconds with a timed-out error, in a task (by lowering the task's
# deadline for the wait) and outside one (poll's timeout). The timeouts are
# kept by handle in `_io_socket_timeouts`, so every layer that waits on a
# socket, TLS's included, sees them without passing them down.
#
# `async` imports `io` (its sockets and errors), so `io` cannot import
# `async`. Instead `async.run` registers its worker as this thread's
# `_IoWaiter`, and the sockets find it through a thread-local. These
# names are exported from the module for `async` only; they are not part of
# the public API.

import async;
import "socket";
import "socket_posix";
import "socket_wasi";
import "socket_windows";
import "sys_posix";
import "sys_windows";
import "types";

# What a socket waits for.
export const _IO_READABLE = 1;
export const _IO_WRITABLE = 2;

# What `_IoWaiter._wait_ready` returns.
export enum _IoWait {
    Ready,
    Cancelled,
    TimedOut,
    Unwatched,
}

# The task runtime running on this thread, as the sockets see it.
export trait _IoWaiter {
    # Whether the calling code runs in a task (rather than in the runtime's
    # own loop, where nothing can park).
    _in_task(): bool;

    # Parks the running task until `handle` may be ready for `interest`
    # (`_IO_READABLE` or `_IO_WRITABLE`), and returns `Ready`; or returns
    # `Cancelled` or `TimedOut` when the task is cancelled, or its timeout
    # or `timeout` milliseconds (0 for none) expire first, or `Unwatched`
    # when the runtime cannot watch `handle` (the caller then blocks the
    # thread instead). Readiness is a hint: the caller tries the call again
    # and waits again if it would still block.
    _wait_ready(handle: SocketHandle, interest: int, timeout: ulong): _IoWait;

    # `handle` is about to be closed: forget it, and wake any task waiting
    # on it.
    _forget(handle: SocketHandle);

    # `handle` stays open but is moving to another thread: stop watching
    # it, and wake any task waiting on it.
    _release(handle: SocketHandle);

    # Stops watching `handle` if no task on this thread waits on it. For a
    # socket several threads wait on, which may be closed on any of them
    # (see `SharedTcpListener`): a thread watches it only while it waits.
    _release_idle(handle: SocketHandle);

    # Runs `transfer` without blocking the worker and returns what
    # `transfer._run()` would. Neither a cancel nor a timeout ends it: the
    # system is using the buffer until it returns. (It takes a struct
    # because a `__ptr` parameter in a trait method does not compile yet.)
    _file_transfer(transfer: _FileTransfer): long;

    # Receives up to `count` bytes on the stream socket `handle` into the
    # memory at address `buffer`, or sends them from it when `write`,
    # parking the task until the kernel has done it. Returns the byte count,
    # -1 minus the error code, or one of the `_IO_TRANSFER_*` results; with
    # `_IO_TRANSFER_DECLINED` nothing was done, and the caller makes the
    # call itself. `timeout` milliseconds (0 for none) end the wait like the
    # task's timeout. The buffer stays in use until this returns, even when
    # the task is cancelled. (The address is a ulong: a `__ptr` parameter in
    # a trait method does not compile yet.)
    _socket_transfer(handle: SocketHandle, buffer: ulong, count: ulong, write: bool, timeout: ulong): long;

    # Windows: waits for changes in the tree under the directory `handle`
    # (a HANDLE opened for overlapped I/O) with one ReadDirectoryChangesW
    # request into the `count` bytes at address `buffer`, parking the task
    # until it completes (see watch_windows.pep). Returns the byte count, -1
    # minus the error code, or one of the `_IO_TRANSFER_*` results, as
    # `_socket_transfer` does; `_IO_TRANSFER_CLOSED` when the watcher closed
    # the handle.
    _directory_changes(handle: ulong, buffer: ulong, count: ulong): long;
}

# What `_IoWaiter._socket_transfer` returns besides a count or an error
# code: the runtime declined; the task was cancelled, or its timeout
# expired, before the kernel moved any bytes; or the socket was closed.
export const _IO_TRANSFER_DECLINED: long = -9223372036854775807;
export const _IO_TRANSFER_CANCELLED: long = -9223372036854775806;
export const _IO_TRANSFER_TIMED_OUT: long = -9223372036854775805;
export const _IO_TRANSFER_CLOSED: long = -9223372036854775804;

# This thread's waiter: a malloc'd slot holding one reference to it, or
# null. A thread (not fiber) local: `async.run` sets and clears it on the
# worker's own thread, and a task never moves to another thread. The slot is
# `__ptr<void>` because a thread-local's type must be thread-safe and
# `_IoWaiter` is not.
[ThreadLocal]
var _io_waiter: __ptr<void>;

# This thread's waiter slot, or null.
_io_waiter_slot(): __ptr<_IoWaiter> {
    return _io_waiter;
}

# Makes `waiter` this thread's waiter until `_io_clear_waiter`.
export _io_set_waiter(waiter: _IoWaiter) {
    __ptr<_IoWaiter> slot = _pep_malloc(16);
    __ptr<ulong> words = slot;
    words[0] = 0;
    words[1] = 0;
    slot[0] = waiter;
    _io_waiter = slot;
}

# Removes this thread's waiter.
export _io_clear_waiter() {
    var slot = _io_waiter_slot();
    if (slot == __null) {
        return;
    }
    _io_waiter = __null;
    slot[0] = __default<_IoWaiter>();
    _pep_free(slot);
}

# ── Timeouts ─────────────────────────────────────────────────────────────────

# The largest timeout, in milliseconds (about 49.7 days): each is kept in 32
# bits.
export const _IO_MAX_TIMEOUT: ulong = 4294967295;

# The timeouts of the sockets that have one, keyed by handle: the read
# timeout in the high 32 bits, the write timeout in the low 32.
const _io_socket_timeouts = async.Mutex<HashMap<long, ulong>>(HashMap<long, ulong>());

# How many sockets have a timeout, so that waits skip the lock when none
# has.
const _io_socket_timeout_count = async.Atomic<ulong>(0);

# The timeout in milliseconds (0 for none) of a wait on `h` for `interest`:
# its read timeout for `_IO_READABLE`, its write timeout for
# `_IO_WRITABLE`.
_io_socket_timeout(h: SocketHandle, interest: int): ulong {
    if (_io_socket_timeout_count.load() == 0) {
        return 0;
    }
    ulong packed = 0;
    with (var timeouts = _io_socket_timeouts.lock()) {
        var key = h as long;
        if (timeouts.contains(key)) {
            packed = timeouts.get(key);
        }
    }
    if (interest == _IO_READABLE) {
        return packed >> 32;
    }
    return packed & _IO_MAX_TIMEOUT;
}

# Sets the timeout of `h`'s waits for `interest` to `milliseconds` (0 for
# none, at most `_IO_MAX_TIMEOUT`).
_io_socket_set_timeout(h: SocketHandle, interest: int, milliseconds: ulong) {
    with (var timeouts = _io_socket_timeouts.lock()) {
        var key = h as long;
        ulong old = 0;
        var had = timeouts.contains(key);
        if (had) {
            old = timeouts.get(key);
        }
        var packed = (old & _IO_MAX_TIMEOUT) | (milliseconds << 32);
        if (interest == _IO_WRITABLE) {
            packed = (old & (_IO_MAX_TIMEOUT << 32)) | milliseconds;
        }
        if (packed != 0) {
            timeouts.insert(key, packed);
            if (!had) {
                _io_socket_timeout_count.fetch_add(1);
            }
        } else if (had) {
            timeouts.remove(key);
            _io_socket_timeout_count.fetch_sub(1);
        }
    }
}

# Sets one of `h`'s timeouts for a socket method: fails when the socket is
# closed or `milliseconds` is too large.
_io_socket_timeout_setter(h: SocketHandle, interest: int, milliseconds: ulong): IoResult<void> {
    var c = _io_socket_require_open(h);
    if (c.is_err()) {
        return c;
    }
    if (milliseconds > _IO_MAX_TIMEOUT) {
        var message = $"a socket timeout must be at most {_IO_MAX_TIMEOUT} milliseconds";
        return IoResult<void>.err(IoError(_io_sys_code_invalid_input(), message));
    }
    _io_socket_set_timeout(h, interest, milliseconds);
    return _io_ok_void();
}

# poll's timeout argument for `timeout` milliseconds: -1 (forever) for 0.
_io_poll_timeout(timeout: ulong): int {
    if (timeout == 0) {
        return -1;
    }
    if (timeout > 2147483647) {
        return 2147483647;
    }
    return timeout as int;
}

# The error of a wait that timed out.
_io_timed_out_error(): IoError {
    return IoError(_io_sys_code_timed_out(), "the operation timed out");
}

# ── Waiting ──────────────────────────────────────────────────────────────────

# Waits until `h` may be ready for `interest`: parks the task inside a task,
# blocks the thread outside one. Fails when the task is cancelled or times
# out, or the socket's timeout for `interest` expires, first.
_io_socket_wait(h: SocketHandle, interest: int): IoResult<void> {
    var timeout = _io_socket_timeout(h, interest);
    var slot = _io_waiter_slot();
    if (slot != __null) {
        var waiter = slot[0];
        if (waiter._in_task()) {
            match (waiter._wait_ready(h, interest, timeout)) {
                Ready => {
                    return _io_ok_void();
                }
                Cancelled => {
                    return IoResult<void>.err(IoError(_io_sys_code_cancelled(), "the task was cancelled"));
                }
                TimedOut => {
                    return IoResult<void>.err(_io_timed_out_error());
                }
                # The runtime cannot watch `h`: block the thread instead.
                Unwatched => {}
            }
        }
    }
    return _io_sys_socket_poll(h, interest, timeout);
}

# One file read or write that a task hands to the runtime: `count` bytes
# into `buffer` from `handle`, or from `buffer` to it when `write`, at the
# file's position. `[Shared]` so a pool thread may run it.
[Shared]
export struct _FileTransfer {
    const _handle: FileHandle;
    const _buffer: __ptr<u8>;
    const _count: ulong;
    const _write: bool;

    construct(handle: FileHandle, buffer: __ptr<u8>, count: ulong, write: bool) {
        _handle = handle;
        _buffer = buffer;
        _count = count;
        _write = write;
    }

    # Makes the system call, blocking the thread: the byte count, or -1
    # minus the error code (a number, since a pool thread must not make a
    # String for the runtime's thread).
    _run(): long {
        var r = _write ? _io_sys_write(_handle, _buffer, _count) : _io_sys_read(_handle, _buffer, _count);
        if (r.is_ok()) {
            return r.value() as long;
        }
        return -1 - (r.error().code as long);
    }

    # The buffer's address, for a driver that hands it to the kernel.
    _address(): ulong {
        return unsafe_cast<ulong>(_buffer);
    }
}

# Reads `count` bytes into `buffer` from `h` (or writes them from it, when
# `write`) with one system call: inside a task through the runtime, which
# keeps the worker running, and directly outside one.
_io_file_transfer(h: FileHandle, buffer: __ptr<u8>, count: ulong, write: bool): IoResult<ulong> {
    var slot = _io_waiter_slot();
    if (slot != __null) {
        var waiter = slot[0];
        if (waiter._in_task()) {
            var transfer = _FileTransfer(h, buffer, count, write);
            return _io_file_transfer_result(waiter._file_transfer(transfer));
        }
    }
    if (write) {
        return _io_sys_write(h, buffer, count);
    }
    return _io_sys_read(h, buffer, count);
}

# The result `_FileTransfer._run` encoded.
_io_file_transfer_result(raw: long): IoResult<ulong> {
    if (raw >= 0) {
        return IoResult<ulong>.ok(raw as ulong);
    }
    var code = (-1 - raw) as ErrorCode;
    return IoResult<ulong>.err(IoError(code, _io_sys_error_message(code)));
}

# Receives into, or sends from, the `n` bytes at `p` on the stream socket
# `h` through the task runtime (see `_IoWaiter._socket_transfer`): none
# when the caller is not in a task or the runtime declines, and the caller
# then makes the call itself.
_io_task_socket_transfer(h: SocketHandle, p: __ptr<u8>, n: ulong, write: bool): IoResult<ulong>? {
    var slot = _io_waiter_slot();
    if (slot == __null) {
        return Optional<IoResult<ulong>>.Empty;
    }
    var waiter = slot[0];
    if (!waiter._in_task()) {
        return Optional<IoResult<ulong>>.Empty;
    }
    var interest = _IO_READABLE;
    if (write) {
        interest = _IO_WRITABLE;
    }
    var raw = waiter._socket_transfer(h, unsafe_cast<ulong>(p), n, write, _io_socket_timeout(h, interest));
    if (raw == _IO_TRANSFER_DECLINED) {
        return Optional<IoResult<ulong>>.Empty;
    }
    if (raw == _IO_TRANSFER_CANCELLED) {
        return Optional<IoResult<ulong>>.Value(
            IoResult<ulong>.err(IoError(_io_sys_code_cancelled(), "the task was cancelled"))
        );
    }
    if (raw == _IO_TRANSFER_TIMED_OUT) {
        return Optional<IoResult<ulong>>.Value(IoResult<ulong>.err(_io_timed_out_error()));
    }
    if (raw == _IO_TRANSFER_CLOSED) {
        return Optional<IoResult<ulong>>.Value(IoResult<ulong>.err(_io_socket_closed_error()));
    }
    return Optional<IoResult<ulong>>.Value(_io_file_transfer_result(raw));
}

# Whether the calling code runs in a task.
export _io_in_task(): bool {
    var slot = _io_waiter_slot();
    return slot != __null && slot[0]._in_task();
}

# Tells this thread's waiter that `h` is moving to another thread.
_io_socket_release(h: SocketHandle) {
    var slot = _io_waiter_slot();
    if (slot != __null) {
        slot[0]._release(h);
    }
}

# Tells this thread's waiter to stop watching `h` unless a task waits on it.
_io_socket_release_idle(h: SocketHandle) {
    var slot = _io_waiter_slot();
    if (slot != __null) {
        slot[0]._release_idle(h);
    }
}

# Tells this thread's waiter that `h` is about to be closed, and drops its
# timeouts.
_io_socket_forget(h: SocketHandle) {
    if (_io_socket_timeout_count.load() != 0) {
        _io_socket_set_timeout(h, _IO_READABLE, 0);
        _io_socket_set_timeout(h, _IO_WRITABLE, 0);
    }
    var slot = _io_waiter_slot();
    if (slot != __null) {
        slot[0]._forget(h);
    }
}
