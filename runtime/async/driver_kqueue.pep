# The kqueue I/O driver (macOS) for the task runtime; see driver.pep.
#
# A socket is registered once, edge-triggered (EV_CLEAR), with a read filter
# and a write filter, the first time a task waits on it. Closing the socket
# removes both. An event's ident is the socket.
#
# struct kevent is 32 bytes: ident (u64) at 0, filter (i16) at 8, flags
# (u16) at 10, fflags (u32) at 12, data (i64) at 16, udata at 24. The system
# calls are [Target(OS(Mac))]; elsewhere `_async_kqueue_create` fails, so
# the driver is unavailable.

import io;
import "driver";
import "task";

[Target(OS(Mac))]
extern int kqueue();
[Target(OS(Mac))]
extern int kevent(int queue, void* changes, int change_count, void* events, int event_count, void* timeout);
[Target(OS(Mac))]
extern int close(int descriptor);

# The most events one poll returns.
const _KQUEUE_CAPACITY = 256;
# EVFILT_READ and EVFILT_WRITE.
const _KQUEUE_FILTER_READ = -1;
const _KQUEUE_FILTER_WRITE = -2;
# EV_EOF | EV_ERROR: the peer closed, or the socket failed; wake both sides.
const _KQUEUE_END_FLAGS = 49152;

# A worker's kqueue.
export struct _KqueueDriver {
    var _queue: long;
    # Room for `_KQUEUE_CAPACITY` events of 32 bytes.
    var _events: __ptr<u8>;

    construct(queue: long) {
        this._queue = queue;
        this._events = _pep_malloc((_KQUEUE_CAPACITY * 32) as ulong);
    }

    # A new driver, or none when the system has no kqueue.
    static open(): _KqueueDriver? {
        var queue = _async_kqueue_create();
        if (queue < 0) {
            return Optional<_KqueueDriver>.none();
        }
        return Optional<_KqueueDriver>.some(_KqueueDriver(queue));
    }
}

extend _KqueueDriver with _Driver {
    _watch(handle: io.SocketHandle): bool {
        __ptr<u8> changes = _pep_malloc(64);
        _async_kqueue_change(changes, 0, handle, _KQUEUE_FILTER_READ);
        _async_kqueue_change(changes, 1, handle, _KQUEUE_FILTER_WRITE);
        var added = _async_kqueue_call(this._queue, changes, 2, __null, 0, -1) == 0;
        _pep_free(changes);
        return added;
    }

    _poll(waits: HashMap<ulong, _SocketWaits>, timeout: long, handles: Array<ulong>, interests: Array<int>) {
        var count = _async_kqueue_call(this._queue, __null, 0, this._events, _KQUEUE_CAPACITY, timeout);
        var i = 0;
        while (i < count) {
            var event = this._events + (i as ulong) * 32;
            var filter = ((event + 8) as __ptr<i16>)[0] as int;
            var flags = ((event + 10) as __ptr<u16>)[0] as int;
            var interest = io._IO_WRITABLE;
            if ((flags & _KQUEUE_END_FLAGS) != 0) {
                interest = io._IO_READABLE | io._IO_WRITABLE;
            } else if (filter == _KQUEUE_FILTER_READ) {
                interest = io._IO_READABLE;
            }
            handles.append((event as __ptr<ulong>)[0]);
            interests.append(interest);
            i = i + 1;
        }
    }

    _want(handle: io.SocketHandle, interest: int): bool {
        return true;
    }

    _forget(handle: io.SocketHandle) {}

    _close() {
        _async_kqueue_close(this._queue);
        _pep_free(this._events);
    }
}

# Fills the `index`th kevent in `changes`: EV_ADD | EV_CLEAR on `filter`.
_async_kqueue_change(changes: __ptr<u8>, index: ulong, handle: io.SocketHandle, filter: int) {
    var change = changes + index * 32;
    (change as __ptr<ulong>)[0] = handle as ulong;
    ((change + 8) as __ptr<i16>)[0] = filter as i16;
    ((change + 10) as __ptr<u16>)[0] = 33;  # EV_ADD | EV_CLEAR
}

# A new kqueue, or -1.
[Target(OS(Mac))]
_async_kqueue_create(): long {
    return kqueue() as long;
}

[Target(OS(Mac))]
_async_kqueue_close(queue: long) {
    close(queue as int);
}

# kevent(2), waiting up to `timeout` milliseconds (forever when negative):
# the number of events stored, 0 on a timeout or a signal, or -1 when the
# changes failed.
[Target(OS(Mac))]
_async_kqueue_call(
    queue: long, changes: __ptr<u8>, change_count: int, events: __ptr<u8>, capacity: int, timeout: long
): int {
    var count = 0;
    if (timeout < 0) {
        count = kevent(queue as int, changes, change_count, events, capacity, __null);
    } else {
        __ptr<long> span = _pep_malloc(16);  # struct timespec
        span[0] = timeout / 1000;
        span[1] = timeout % 1000 * 1000000;
        count = kevent(queue as int, changes, change_count, events, capacity, span);
        _pep_free(span);
    }
    if (count < 0 && change_count == 0) {
        return 0;
    }
    return count;
}

# Elsewhere there is no kqueue.

[Target(!OS(Mac))]
_async_kqueue_create(): long {
    return -1;
}

[Target(!OS(Mac))]
_async_kqueue_close(queue: long) {}

[Target(!OS(Mac))]
_async_kqueue_call(
    queue: long, changes: __ptr<u8>, change_count: int, events: __ptr<u8>, capacity: int, timeout: long
): int {
    return -1;
}
