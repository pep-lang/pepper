# The io_uring I/O driver (Linux) for the task runtime; see driver.pep.
#
# Readiness through io_uring's poll requests, the way the epoll driver uses
# an edge-triggered registration: the first time a task waits on a socket,
# `_want` queues one multishot IORING_OP_POLL_ADD (IORING_POLL_ADD_MULTI)
# for the direction it waits on, which stays armed and posts a completion
# each time the socket wakes. So a wait costs no submission once the socket
# is armed; arming a one-shot poll per wait made the kernel set up and tear
# down a poll on every read. A wait in a direction the poll does not cover
# replaces it with one that covers both. When the kernel ends a request (a
# completion without IORING_CQE_F_MORE: an error, or a kernel before 5.13
# that runs every poll one-shot), `_poll` arms a new one for the directions
# that still have tasks parked and did not just become ready; the new poll
# reports readiness that is already there, so no wakeup is lost. `_poll` submits what is queued and waits for
# completions in the same `io_uring_enter` call. Each request's user data is
# a number unique to this driver, mapped in `_requests` to the socket, so a
# completion for a socket that was closed (and whose descriptor may be
# reused) is recognized and dropped.
#
# A pending poll holds a reference to its socket's file, so closing the
# descriptor would not close the socket. `_forget` therefore queues an
# IORING_OP_POLL_REMOVE for the socket's request and submits at once,
# before the caller closes it.
#
# Everything is written over the raw system calls (no liburing):
# `io_uring_setup` and `io_uring_enter` through `syscall`, one mmap for both
# rings (IORING_FEAT_SINGLE_MMAP) and one for the submission entries. The
# kernel moves the submission head and the completion tail; the driver
# reads those with acquire loads and publishes its own tail and head with
# release stores. A timed wait passes its timeout through
# IORING_ENTER_EXT_ARG. A kernel without both features (before 5.11), or one
# that refuses io_uring (a seccomp filter, `io_uring_disabled`), makes the
# driver unavailable.
#
# Layouts (struct io_uring_params, 120 bytes): sq_entries at 0, cq_entries
# at 4, features at 20, the submission ring offsets (head, tail, ring_mask,
# ring_entries, flags, dropped, array: u32 each) from 40, the completion
# ring offsets (head, tail, ring_mask, ring_entries, overflow, cqes) from
# 80. A submission entry is 64 bytes: opcode at 0, fd at 4, addr at 16,
# len (a poll's flags) at 24, poll32_events at 28, user_data at 32. A
# completion entry is 16 bytes: user_data at 0, res (i32) at 8, flags at 12.
#
# Files: `_start_file` queues an IORING_OP_READ or IORING_OP_WRITE at the
# file's position (offset -1), mapped in `_files` to the task waiting for
# it, and the completion's result goes back through `_finished_files`.
#
# The doorbell is an eventfd with its own poll request, whose user data is
# `_async_doorbell_key()`; the poll that sees it reads it back to 0 and
# queues a new request.
#
# The ring is made with IORING_SETUP_DEFER_TASKRUN where the kernel has it
# (6.1), else IORING_SETUP_COOP_TASKRUN (5.19): otherwise every socket
# wakeup on another CPU interrupts the worker to post its completion, which
# made this driver twice as slow as epoll. Only the worker's own thread
# touches its ring, as IORING_SETUP_SINGLE_ISSUER requires.

import io;
import "driver";
import "task";
import "workers";

[Target(OS(Linux))]
extern long syscall(long number, ...);
[Target(OS(Linux))]
extern void* mmap(void* address, ulong length, int protection, int flags, int descriptor, long offset);
[Target(OS(Linux))]
extern int munmap(void* address, ulong length);
[Target(OS(Linux))]
extern int close(int descriptor);
[Target(OS(Linux))]
extern int eventfd(uint initial, int flags);
[Target(OS(Linux))]
extern long read(int fd, void* buf, ulong n);

# System call numbers: the same on x86-64 and AArch64.
const _IO_URING_SETUP = 425;
const _IO_URING_ENTER = 426;

# Setup flags, tried in order until the kernel takes one:
# IORING_SETUP_SINGLE_ISSUER | IORING_SETUP_DEFER_TASKRUN (6.1), then
# IORING_SETUP_COOP_TASKRUN (5.19), then none. Without them a socket's
# wakeup on another CPU interrupts the worker to post the completion.
const _IO_URING_SETUP_DEFERRED: uint = 12288;
const _IO_URING_SETUP_COOPERATIVE: uint = 256;

# How many submission entries the ring has.
const _IO_URING_ENTRIES: uint = 256;

# mmap offsets of the rings and of the submission entries.
const _IO_URING_OFF_SQ_RING: long = 0;
const _IO_URING_OFF_SQES: long = 268435456;

# IORING_FEAT_SINGLE_MMAP | IORING_FEAT_EXT_ARG.
const _IO_URING_FEATURES: uint = 257;

# Opcodes.
const _IO_URING_OP_POLL_ADD: u8 = 6;
const _IO_URING_OP_POLL_REMOVE: u8 = 7;
const _IO_URING_OP_READ: u8 = 22;
const _IO_URING_OP_WRITE: u8 = 23;

# The most bytes one read or write asks for, as on POSIX.
const _IO_URING_MAX_TRANSFER: ulong = 2147479552;

# io_uring_enter flags: IORING_ENTER_GETEVENTS, IORING_ENTER_EXT_ARG.
const _IO_URING_GETEVENTS: uint = 1;
const _IO_URING_EXT_ARG: uint = 8;

# What a poll asks for: POLLIN | POLLRDHUP to read, POLLOUT to write. What lets a reader continue: POLLIN,
# POLLERR, POLLHUP, POLLRDHUP; a writer: POLLOUT, POLLERR, POLLHUP.
const _IO_URING_POLL_READ: uint = 8193;
const _IO_URING_POLL_WRITE: uint = 4;
const _IO_URING_READABLE_EVENTS: int = 8217;
const _IO_URING_WRITABLE_EVENTS: int = 28;

# IORING_POLL_ADD_MULTI, in a poll's len; IORING_CQE_F_MORE, set on a
# completion when its request stays armed.
const _IO_URING_POLL_MULTI: uint = 1;
const _IO_URING_CQE_MORE: uint = 2;

# A worker's io_uring instance.
export struct _IoUringDriver {
    var _ring_fd: long;
    # The rings' shared mapping and the submission entries' mapping.
    var _rings: __ptr<u8>;
    var _rings_size: ulong;
    var _entries: __ptr<u8>;
    var _entries_size: ulong;
    # Byte offsets in `_rings` of the submission head, tail and index
    # array, and of the completion head, tail and entries.
    var _sq_head: ulong;
    var _sq_tail: ulong;
    var _sq_array: ulong;
    var _cq_head: ulong;
    var _cq_tail: ulong;
    var _cqes: ulong;
    # The rings' index masks and the number of submission entries.
    var _sq_mask: uint;
    var _cq_mask: uint;
    var _sq_entries: uint;
    # The next submission tail, which the kernel sees once released.
    var _tail: uint;
    # The doorbell's eventfd.
    var _bell: long;
    # Each poll in flight: its user data, and its socket times 4 plus the
    # directions it covers (io._IO_READABLE, io._IO_WRITABLE or both).
    var _requests: HashMap<ulong, ulong>;
    # The poll in flight on each armed socket.
    var _armed: HashMap<ulong, ulong>;
    var _next_request: ulong;
    # Each file transfer in flight: its user data, and the task it is for.
    var _files: HashMap<ulong, ulong>;
    # File transfers finished since `_finished_files` last took them.
    var _finished_tasks: Array<ulong>;
    var _finished_results: Array<long>;
    # A struct io_uring_getevents_arg (24 bytes) followed by the
    # __kernel_timespec it points to (16 bytes), for timed waits.
    var _wait_argument: __ptr<u8>;

    construct() {
        this._ring_fd = -1;
        this._bell = -1;
        this._requests = HashMap<ulong, ulong>();
        this._armed = HashMap<ulong, ulong>();
        this._next_request = 1;
        this._files = HashMap<ulong, ulong>();
        this._finished_tasks = Array<ulong>();
        this._finished_results = Array<long>();
    }

    # A new driver, or none when the system has no usable io_uring.
    static open(): _IoUringDriver? {
        var driver = _IoUringDriver();
        if (!_async_io_uring_setup(driver)) {
            return Optional<_IoUringDriver>.none();
        }
        driver._bell = _async_io_uring_create_bell();
        if (driver._bell < 0) {
            driver._unmap();
            return Optional<_IoUringDriver>.none();
        }
        driver._wait_argument = _pep_malloc(40);
        driver._arm_bell();
        return Optional<_IoUringDriver>.some(driver);
    }

    # Queues a one-shot poll on the doorbell.
    _arm_bell() {
        this._queue(_IO_URING_OP_POLL_ADD, this._bell, 0, _IO_URING_POLL_READ, 0, _async_doorbell_key());
    }

    # Queues a submission entry, first submitting what is queued when the
    # ring is full. `events` is poll32_events for a poll and the length for a
    # read or write, whose offset is always the file's position (-1);
    # `flags` is a poll's len.
    _queue(opcode: u8, fd: long, address: ulong, events: uint, flags: uint, data: ulong) {
        if (this._tail - _async_io_uring_load(this._rings, this._sq_head) >= this._sq_entries) {
            this._enter(0, false);
        }
        var index = this._tail & this._sq_mask;
        var entry = this._entries + (index as ulong) * 64;
        _async_zero(entry, 64);
        entry[0] = opcode;
        ((entry + 4) as __ptr<int>)[0] = fd as int;
        ((entry + 16) as __ptr<ulong>)[0] = address;
        if (opcode == _IO_URING_OP_READ || opcode == _IO_URING_OP_WRITE) {
            ((entry + 8) as __ptr<ulong>)[0] = ~(0 as ulong);
            ((entry + 24) as __ptr<uint>)[0] = events;
        } else {
            ((entry + 24) as __ptr<uint>)[0] = flags;
            ((entry + 28) as __ptr<uint>)[0] = events;
        }
        ((entry + 32) as __ptr<ulong>)[0] = data;
        ((this._rings + this._sq_array) as __ptr<uint>)[index as ulong] = index;
        this._tail = this._tail + 1;
        _async_io_uring_store(this._rings, this._sq_tail, this._tail);
    }

    # Submits every queued entry and, when `wait` is set, waits up to
    # `timeout` milliseconds (forever when negative) for a completion. A
    # zero timeout still enters with GETEVENTS, which runs the completion
    # work a ring with IORING_SETUP_DEFER_TASKRUN leaves for its thread.
    _enter(timeout: long, wait: bool) {
        var pending = this._tail - _async_io_uring_load(this._rings, this._sq_head);
        if (!wait) {
            if (pending > 0) {
                _async_io_uring_enter(this._ring_fd, pending, 0, 0, __null, 0);
            }
            return;
        }
        if (timeout == 0) {
            _async_io_uring_enter(this._ring_fd, pending, 0, _IO_URING_GETEVENTS, __null, 0);
            return;
        }
        if (timeout < 0) {
            _async_io_uring_enter(this._ring_fd, pending, 1, _IO_URING_GETEVENTS, __null, 0);
            return;
        }
        # struct io_uring_getevents_arg { sigmask, sigmask_sz, pad, ts }.
        __ptr<ulong> words = this._wait_argument;
        words[0] = 0;
        words[1] = 0;
        words[2] = (this._wait_argument + 24) as ulong;
        words[3] = (timeout / 1000) as ulong;
        words[4] = ((timeout % 1000) * 1000000) as ulong;
        _async_io_uring_enter(
            this._ring_fd, pending, 1, _IO_URING_GETEVENTS | _IO_URING_EXT_ARG, this._wait_argument, 24
        );
    }

    # Arms a multishot poll on socket `key` for the directions in `mask`.
    _arm(key: ulong, mask: int) {
        var data = this._next_request;
        this._next_request = data + 1;
        this._requests.insert(data, key * 4 + mask as ulong);
        this._armed.insert(key, data);
        var events: uint = 0;
        if ((mask & io._IO_READABLE) != 0) {
            events = events | _IO_URING_POLL_READ;
        }
        if ((mask & io._IO_WRITABLE) != 0) {
            events = events | _IO_URING_POLL_WRITE;
        }
        this._queue(_IO_URING_OP_POLL_ADD, key as long, 0, events, _IO_URING_POLL_MULTI, data);
    }

    # Forgets the request `data` and asks the kernel to remove it.
    _cancel(data: ulong) {
        this._requests.remove(data);
        this._queue(_IO_URING_OP_POLL_REMOVE, -1, data, 0, 0, 0);
    }

    _unmap() {
        _async_io_uring_unmap(this);
    }
}

extend _IoUringDriver with _Driver {
    _watch(handle: io.SocketHandle): bool {
        return true;
    }

    _want(handle: io.SocketHandle, interest: int): bool {
        var key = handle as ulong;
        var mask = interest;
        if (this._armed.contains(key)) {
            var data = this._armed.get(key);
            var covered = (this._requests.get(data) % 4) as int;
            if ((covered & interest) != 0) {
                return true;
            }
            this._cancel(data);
            mask = covered | interest;
        }
        this._arm(key, mask);
        return true;
    }

    _poll(waits: HashMap<ulong, _SocketWaits>, timeout: long, handles: Array<ulong>, interests: Array<int>) {
        this._enter(timeout, true);
        var head = _async_io_uring_load(this._rings, this._cq_head);
        var tail = _async_io_uring_load(this._rings, this._cq_tail);
        while (head != tail) {
            var entry = this._rings + this._cqes + ((head & this._cq_mask) as ulong) * 16;
            var data = (entry as __ptr<ulong>)[0];
            var result = ((entry + 8) as __ptr<int>)[0];
            var flags = ((entry + 12) as __ptr<uint>)[0];
            head = head + 1;
            if (this._files.contains(data)) {
                # A file transfer: the count, or -errno as -1 minus the code.
                this._finished_tasks.append(this._files.get(data));
                this._finished_results.append(result >= 0 ? result as long : -1 + result as long);
                this._files.remove(data);
            } else if (data == _async_doorbell_key()) {
                _async_io_uring_drain(this._bell);
                this._arm_bell();
            } else if (this._requests.contains(data)) {
                var request = this._requests.get(data);
                var handle = request / 4;
                var covered = (request % 4) as int;
                # A failed request wakes every waiter, which retries the call
                # and sees any error.
                var ready = covered;
                if (result > 0) {
                    ready = 0;
                    if ((result & _IO_URING_READABLE_EVENTS) != 0) {
                        ready = ready | io._IO_READABLE;
                    }
                    if ((result & _IO_URING_WRITABLE_EVENTS) != 0) {
                        ready = ready | io._IO_WRITABLE;
                    }
                }
                if (ready != 0) {
                    handles.append(handle);
                    interests.append(ready);
                }
                if ((flags & _IO_URING_CQE_MORE) == 0) {
                    # The kernel ended the request: arm a new one for the
                    # tasks this completion does not wake.
                    this._requests.remove(data);
                    this._armed.remove(handle);
                    var still = 0;
                    if (waits.contains(handle)) {
                        var parked = waits.get(handle);
                        if (parked._readers.count() > 0) {
                            still = still | io._IO_READABLE;
                        }
                        if (parked._writers.count() > 0) {
                            still = still | io._IO_WRITABLE;
                        }
                    }
                    still = still & ~ready;
                    if (still != 0) {
                        this._arm(handle, still);
                    }
                }
            }
        }
        _async_io_uring_store(this._rings, this._cq_head, head);
    }

    _forget(handle: io.SocketHandle) {
        var key = handle as ulong;
        # The poll holds the socket open until the kernel removes it.
        if (this._armed.contains(key)) {
            this._cancel(this._armed.get(key));
            this._armed.remove(key);
            this._enter(0, false);
        }
    }

    _release(handle: io.SocketHandle) {
        this._forget(handle);
    }

    _start_file(handle: long, buffer: ulong, count: ulong, write: bool, task: ulong): bool {
        var data = this._next_request;
        this._next_request = data + 1;
        this._files.insert(data, task);
        var length = count;
        if (length > _IO_URING_MAX_TRANSFER) {
            length = _IO_URING_MAX_TRANSFER;
        }
        var opcode = write ? _IO_URING_OP_WRITE : _IO_URING_OP_READ;
        this._queue(opcode, handle, buffer, length as uint, 0, data);
        return true;
    }

    _finished_files(tasks: Array<ulong>, results: Array<long>) {
        for (var task in this._finished_tasks) {
            tasks.append(task);
        }
        for (var result in this._finished_results) {
            results.append(result);
        }
        this._finished_tasks.clear();
        this._finished_results.clear();
    }

    _doorbell(): _Doorbell {
        return _Doorbell(_DoorbellKind.EventFd, this._bell);
    }

    _close() {
        # Closing the ring cancels every request still in flight.
        _async_io_uring_close(this._ring_fd);
        _async_io_uring_close(this._bell);
        this._unmap();
        _pep_free(this._wait_argument);
    }
}

# Reads the u32 at `offset` in the rings with acquire ordering.
_async_io_uring_load(rings: __ptr<u8>, offset: ulong): uint {
    __ptr<uint> slot = rings + offset;
    return __atomic_load<uint>(slot);
}

# Writes the u32 at `offset` in the rings with release ordering.
_async_io_uring_store(rings: __ptr<u8>, offset: ulong, value: uint) {
    __ptr<uint> slot = rings + offset;
    __atomic_store<uint>(slot, value);
}

# Makes the ring and maps it into `driver`; false when the system has no
# io_uring with the features this driver needs.
[Target(OS(Linux))]
_async_io_uring_setup(driver: _IoUringDriver): bool {
    __ptr<u8> parameters = _pep_malloc(120);
    __ptr<uint> words = parameters;
    var fd = _async_io_uring_try_setup(parameters, _IO_URING_SETUP_DEFERRED);
    if (fd < 0) {
        fd = _async_io_uring_try_setup(parameters, _IO_URING_SETUP_COOPERATIVE);
    }
    if (fd < 0) {
        fd = _async_io_uring_try_setup(parameters, 0);
    }
    if (fd < 0 || (words[5] & _IO_URING_FEATURES) != _IO_URING_FEATURES) {
        if (fd >= 0) {
            close(fd as int);
        }
        _pep_free(parameters);
        return false;
    }
    var sq_entries = words[0];
    var cq_entries = words[1];
    # Submission ring offsets from word 10, completion ring offsets from
    # word 20.
    var sq_size = (words[16] + sq_entries * 4) as ulong;
    var cq_size = (words[25] + cq_entries * 16) as ulong;
    var size = sq_size;
    if (cq_size > size) {
        size = cq_size;
    }
    var rings = mmap(__null, size, 3, 32769, fd as int, _IO_URING_OFF_SQ_RING);  # PROT_READ | PROT_WRITE; MAP_SHARED | MAP_POPULATE
    var entries_size = (sq_entries * 64) as ulong;
    var entries = mmap(__null, entries_size, 3, 32769, fd as int, _IO_URING_OFF_SQES);
    # MAP_FAILED is (void*)-1.
    if ((rings as ulong) == ~(0 as ulong) || (entries as ulong) == ~(0 as ulong)) {
        if ((rings as ulong) != ~(0 as ulong)) {
            munmap(rings, size);
        }
        if ((entries as ulong) != ~(0 as ulong)) {
            munmap(entries, entries_size);
        }
        close(fd as int);
        _pep_free(parameters);
        return false;
    }
    driver._ring_fd = fd;
    driver._rings = rings;
    driver._rings_size = size;
    driver._entries = entries;
    driver._entries_size = entries_size;
    driver._sq_head = words[10] as ulong;
    driver._sq_tail = words[11] as ulong;
    driver._sq_mask = ((rings + words[12] as ulong) as __ptr<uint>)[0];
    driver._sq_entries = ((rings + words[13] as ulong) as __ptr<uint>)[0];
    driver._sq_array = words[16] as ulong;
    driver._cq_head = words[20] as ulong;
    driver._cq_tail = words[21] as ulong;
    driver._cq_mask = ((rings + words[22] as ulong) as __ptr<uint>)[0];
    driver._cqes = words[25] as ulong;
    driver._tail = _async_io_uring_load(rings, driver._sq_tail);
    _pep_free(parameters);
    return true;
}

# Makes a ring with setup `flags` (struct io_uring_params flags at 8); the
# ring's descriptor, or negative when the kernel refuses them.
[Target(OS(Linux))]
_async_io_uring_try_setup(parameters: __ptr<u8>, flags: uint): long {
    _async_zero(parameters, 120);
    ((parameters + 8) as __ptr<uint>)[0] = flags;
    return syscall(_IO_URING_SETUP, _IO_URING_ENTRIES, parameters);
}

# Submits `count` entries and waits for `minimum` completions. Errors
# (EINTR, ETIME on a timeout, EBUSY) are left for the next poll.
[Target(OS(Linux))]
_async_io_uring_enter(fd: long, count: uint, minimum: uint, flags: uint, argument: __ptr<u8>, size: ulong) {
    syscall(_IO_URING_ENTER, fd as int, count, minimum, flags, argument, size);
}

[Target(OS(Linux))]
_async_io_uring_unmap(driver: _IoUringDriver) {
    munmap(driver._entries, driver._entries_size);
    munmap(driver._rings, driver._rings_size);
    close(driver._ring_fd as int);
    driver._ring_fd = -1;
}

[Target(OS(Linux))]
_async_io_uring_close(fd: long) {
    if (fd >= 0) {
        close(fd as int);
    }
}

# A non-blocking eventfd for the doorbell, or -1.
[Target(OS(Linux))]
_async_io_uring_create_bell(): long {
    return eventfd(0, 526336) as long;  # EFD_NONBLOCK | EFD_CLOEXEC
}

# Resets the doorbell eventfd `bell` to 0.
[Target(OS(Linux))]
_async_io_uring_drain(bell: long) {
    __ptr<ulong> value = _pep_malloc(8);
    read(bell as int, value, 8);
    _pep_free(value);
}

# Elsewhere there is no io_uring.

[Target(!OS(Linux))]
_async_io_uring_setup(driver: _IoUringDriver): bool {
    return false;
}

[Target(!OS(Linux))]
_async_io_uring_enter(fd: long, count: uint, minimum: uint, flags: uint, argument: __ptr<u8>, size: ulong) {}

[Target(!OS(Linux))]
_async_io_uring_unmap(driver: _IoUringDriver) {}

[Target(!OS(Linux))]
_async_io_uring_close(fd: long) {}

[Target(!OS(Linux))]
_async_io_uring_create_bell(): long {
    return -1;
}

[Target(!OS(Linux))]
_async_io_uring_drain(bell: long) {}
