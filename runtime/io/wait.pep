# How a socket waits until it can make progress: the seam between the
# sockets here and the task runtime in the `async` module.
#
# Sockets are non-blocking. When a call would block, the socket waits for
# the handle to become ready and tries again (`_io_socket_wait`). Outside a
# task that wait is poll() / WSAPoll(), which blocks the thread. Inside a
# task it is the runtime's `_IoWaiter`, which parks the task and lets the
# others run until the handle is ready.
#
# Files have no readiness to wait for, so a file read or write in a task
# goes to the runtime whole (`_IoWaiter._file_transfer`): it runs the
# system call where it cannot block the worker (on io_uring, or on a pool
# thread) and parks the task until it is done. The caller pins the array it
# reads into or writes from (`Array._pins`) for that time.
#
# `async` imports `io` (its sockets and errors), so `io` cannot import
# `async`. Instead `async.run` registers its worker as this thread's
# `_IoWaiter`, and the sockets find it through a thread-local key. These
# names are exported from the module for `async` only; they are not part of
# the public API.

import async;
import "socket_posix";
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
    # `Cancelled` or `TimedOut` when the task is cancelled or its timeout
    # expires first, or `Unwatched` when
    # the runtime cannot watch `handle` (the caller then blocks the thread
    # instead). Readiness is a hint: the caller tries the call again and
    # waits again if it would still block.
    _wait_ready(handle: SocketHandle, interest: int): _IoWait;

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
}

# One more than the key whose value is a malloc'd slot holding this
# thread's waiter (or null), once the first `_io_set_waiter` has made it; 0
# before. The key is made on first use so that a program that never runs
# tasks makes none.
const _io_waiter_key = async.Atomic<ulong>(0);

# This thread's waiter slot, or null.
_io_waiter_slot(): __ptr<_IoWaiter> {
    var key = _io_waiter_key.load();
    if (key == 0) {
        return __null;
    }
    return _io_sys_key_get(key - 1);
}

# Makes `waiter` this thread's waiter until `_io_clear_waiter`.
export _io_set_waiter(waiter: _IoWaiter) {
    if (_io_waiter_key.load() == 0) {
        # Two threads may race to make the key; the loser's goes unused.
        _io_waiter_key.compare_exchange(0, _io_sys_key_create() + 1);
    }
    __ptr<_IoWaiter> slot = _pep_malloc(16);
    __ptr<ulong> words = slot;
    words[0] = 0;
    words[1] = 0;
    slot[0] = waiter;
    _io_sys_key_set(_io_waiter_key.load() - 1, slot);
}

# Removes this thread's waiter.
export _io_clear_waiter() {
    var slot = _io_waiter_slot();
    if (slot == __null) {
        return;
    }
    _io_sys_key_set(_io_waiter_key.load() - 1, __null);
    slot[0] = __default<_IoWaiter>();
    _pep_free(slot);
}

# Waits until `h` may be ready for `interest`: parks the task inside a task,
# blocks the thread outside one. Fails when the task is cancelled or times
# out first.
export _io_socket_wait(h: SocketHandle, interest: int): IoResult<void> {
    var slot = _io_waiter_slot();
    if (slot != __null) {
        var waiter = slot[0];
        if (waiter._in_task()) {
            match (waiter._wait_ready(h, interest)) {
                Ready => {
                    return _io_ok_void();
                }
                Cancelled => {
                    return IoResult<void>.err(IoError(_io_sys_code_cancelled(), "the task was cancelled"));
                }
                TimedOut => {
                    return IoResult<void>.err(IoError(_io_sys_code_timed_out(), "the operation timed out"));
                }
                # The runtime cannot watch `h`: block the thread instead.
                Unwatched => {}
            }
        }
    }
    return _io_sys_socket_poll(h, interest);
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
        return _buffer as ulong;
    }
}

# Reads `count` bytes into `buffer` from `h` (or writes them from it, when
# `write`) with one system call: inside a task through the runtime, which
# keeps the worker running, and directly outside one.
export _io_file_transfer(h: FileHandle, buffer: __ptr<u8>, count: ulong, write: bool): IoResult<ulong> {
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
export _io_file_transfer_result(raw: long): IoResult<ulong> {
    if (raw >= 0) {
        return IoResult<ulong>.ok(raw as ulong);
    }
    var code = (-1 - raw) as ErrorCode;
    return IoResult<ulong>.err(IoError(code, _io_sys_error_message(code)));
}

# Whether the calling code runs in a task.
export _io_in_task(): bool {
    var slot = _io_waiter_slot();
    return slot != __null && slot[0]._in_task();
}

# Tells this thread's waiter that `h` is moving to another thread.
export _io_socket_release(h: SocketHandle) {
    var slot = _io_waiter_slot();
    if (slot != __null) {
        slot[0]._release(h);
    }
}

# Tells this thread's waiter to stop watching `h` unless a task waits on it.
export _io_socket_release_idle(h: SocketHandle) {
    var slot = _io_waiter_slot();
    if (slot != __null) {
        slot[0]._release_idle(h);
    }
}

# Tells this thread's waiter that `h` is about to be closed.
export _io_socket_forget(h: SocketHandle) {
    var slot = _io_waiter_slot();
    if (slot != __null) {
        slot[0]._forget(h);
    }
}
