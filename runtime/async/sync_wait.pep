# How a task waits on a `Mutex`, `Condition` or `Channel` without blocking
# its worker thread.
#
# A thread that must wait for one of them blocks on the platform lock or
# condition variable, as before. A task on a worker cannot: every other task
# on that thread would stop too. Instead it adds a `_SyncWaiter` to the
# object's `_SyncQueue` and parks (`_async_sync_park` in task.pep). Whoever
# makes progress possible (an unlock, a notify, a send) calls `_wake_one` or
# `_wake_all` on the queue as well as notifying the platform condition, so
# both kinds of waiter hear it.
#
# A waiter is woken once: `_state` goes from `_WAITER_WAITING` to
# `_WAITER_WOKEN` by a waker, or to `_WAITER_ABANDONED` by the task when it
# stops waiting on its own (cancelled, or its time ran out), which also
# takes it out of the queue. The wake reaches the task through its worker:
# directly when the waker runs on that worker, otherwise as a
# `_MESSAGE_WAKE` in the worker's inbox. The task re-checks what it waits
# for after every wake, as a condition-variable waiter does.
#
# A plain thread normally waits on the platform condition instead, but a
# `Select` must sleep on several channels at once, so it joins each one's
# `_SyncQueue` with a waiter that carries a `_ThreadWake`: `_async_sync_wake`
# signals that instead of a worker's inbox, and the thread sleeps in
# `_async_thread_park`.
#
# `_size` lets `_wake_one` and `_wake_all` return without locking when no
# task waits. That read is only safe when the waiter's `_push` and the
# waker's change are ordered by some other lock (a Channel's, or the
# Mutex a Condition waits on); `Mutex` unlocks outside any such lock, so it
# calls `_wake_one_locked`, which always looks.

import "sys_posix";
import "sys_windows";
import "task";
import "workers";

export const _WAITER_WAITING = 0;
export const _WAITER_WOKEN = 1;
export const _WAITER_ABANDONED = 2;

# Gives every waiter its own id.
const _async_waiter_ids = Atomic<ulong>(1);

# One task, or one plain thread in a `Select`, waiting on sync objects.
[Shared]
export struct _SyncWaiter {
    # Unique among waiters, for `_SyncQueue._remove`.
    const _id: ulong;
    # The inbox of the task's worker, and the task's id there (null and 0
    # for a thread).
    const _inbox: _Inbox;
    const _task: ulong;
    # What a thread sleeps on (null for a task).
    const _thread: _ThreadWake;
    # `_WAITER_WAITING`, `_WAITER_WOKEN` or `_WAITER_ABANDONED`.
    const _state: Atomic<int>;

    construct(inbox: _Inbox, task: ulong) {
        _id = _async_waiter_ids.fetch_add(1);
        _inbox = inbox;
        _task = task;
        _thread = __default<_ThreadWake>();
        _state = Atomic<int>(_WAITER_WAITING);
    }

    construct(thread: _ThreadWake) {
        _id = _async_waiter_ids.fetch_add(1);
        _inbox = __default<_Inbox>();
        _task = 0;
        _thread = thread;
        _state = Atomic<int>(_WAITER_WAITING);
    }
}

# What a plain thread waiting in a `Select` sleeps on: a platform lock and
# condition variable. A waker sets the waiter's state first and signals
# under the lock, and the thread checks the state under it, so no wake is
# missed.
[Shared]
export struct _ThreadWake {
    const _lock: __ptr<void>;
    const _condition: __ptr<void>;

    construct() {
        _lock = _async_sys_mutex_create();
        _condition = _async_sys_condition_create();
    }

    destruct {
        _async_sys_condition_destroy(_condition);
        _async_sys_mutex_destroy(_lock);
    }

    # Wakes the thread.
    _signal() {
        _async_sys_mutex_lock(_lock);
        _async_sys_condition_notify_all(_condition);
        _async_sys_mutex_unlock(_lock);
    }
}

# Sleeps the calling thread (outside a task) until `waiter`, made with a
# `_ThreadWake`, is woken, or until `deadline` (monotonic milliseconds, 0
# for none) passes; returns `_SYNC_WOKEN` or `_SYNC_TIMED_OUT`. A wait that
# times out abandons the waiter; the caller takes it out of its queues.
export _async_thread_park(waiter: _SyncWaiter, deadline: ulong): int {
    var wake = waiter._thread;
    var result = _SYNC_WOKEN;
    _async_sys_mutex_lock(wake._lock);
    while (waiter._state.load() == _WAITER_WAITING) {
        if (deadline == 0) {
            _async_sys_condition_wait(wake._condition, wake._lock);
            continue;
        }
        var now = _async_sys_monotonic_milliseconds();
        if (now >= deadline) {
            if (waiter._state.compare_exchange(_WAITER_WAITING, _WAITER_ABANDONED)) {
                result = _SYNC_TIMED_OUT;
            }
            break;
        }
        _async_sys_condition_wait_for(wake._condition, wake._lock, deadline - now);
    }
    _async_sys_mutex_unlock(wake._lock);
    return result;
}

# The tasks waiting on one sync object, first come first woken. The ring
# buffer exists only while some task waits.
[Shared]
export struct _SyncQueue {
    # The platform mutex that guards `_state` and `_buffer`.
    const _lock: __ptr<void>;
    # The head index, the number of waiters, and the number of slots.
    const _state: __ptr<ulong>;
    # Holds the ring buffer of `_SyncWaiter` slots (null while no task
    # waits).
    const _buffer: __ptr<__ptr<void>>;
    # The number of waiters, readable without the lock.
    const _size: Atomic<ulong>;

    construct() {
        _lock = _async_sys_mutex_create();
        _state = _pep_malloc(3 * sizeof<ulong>());
        _state[0] = 0;
        _state[1] = 0;
        _state[2] = 0;
        _buffer = _pep_malloc(sizeof<__ptr<void>>());
        _buffer[0] = __null;
        _size = Atomic<ulong>(0);
    }

    destruct {
        __ptr<_SyncWaiter> slots = this._slots();
        var i: ulong = 0;
        while (i < _state[1]) {
            slots[(_state[0] + i) % _state[2]] = __default<_SyncWaiter>();
            i = i + 1;
        }
        if (_buffer[0] != __null) {
            _pep_free(slots);
        }
        _pep_free(_buffer);
        _pep_free(_state);
        _async_sys_mutex_destroy(_lock);
    }

    # Adds `waiter` at the tail.
    _push(waiter: _SyncWaiter) {
        _async_sys_mutex_lock(_lock);
        if (_state[1] == _state[2]) {
            this._grow();
        }
        __ptr<_SyncWaiter> slots = this._slots();
        slots[(_state[0] + _state[1]) % _state[2]] = waiter;
        _state[1] = _state[1] + 1;
        _size.store(_state[1]);
        _async_sys_mutex_unlock(_lock);
    }

    # Takes `waiter` out of the queue, if it is there.
    _remove(waiter: _SyncWaiter) {
        _async_sys_mutex_lock(_lock);
        __ptr<_SyncWaiter> slots = this._slots();
        var count = _state[1];
        var i: ulong = 0;
        while (i < count) {
            if (slots[(_state[0] + i) % _state[2]]._id == waiter._id) {
                # Close the gap by moving the later waiters forward.
                while (i + 1 < count) {
                    slots[(_state[0] + i) % _state[2]] = slots[(_state[0] + i + 1) % _state[2]];
                    i = i + 1;
                }
                slots[(_state[0] + count - 1) % _state[2]] = __default<_SyncWaiter>();
                _state[1] = count - 1;
                _size.store(count - 1);
                this._shrink();
                break;
            }
            i = i + 1;
        }
        _async_sys_mutex_unlock(_lock);
    }

    # Wakes the first waiter, if any task waits (see the notes on `_size`).
    _wake_one() {
        if (_size.load() != 0) {
            this._wake_one_locked();
        }
    }

    # Wakes the first waiter still waiting, if any.
    _wake_one_locked() {
        while (true) {
            var next = this._pop();
            if (next.is_none()) {
                return;
            }
            var waiter = next.value();
            if (waiter._state.compare_exchange(_WAITER_WAITING, _WAITER_WOKEN)) {
                _async_sync_wake(waiter);
                return;
            }
        }
    }

    # Wakes every waiter.
    _wake_all() {
        if (_size.load() == 0) {
            return;
        }
        while (true) {
            var next = this._pop();
            if (next.is_none()) {
                return;
            }
            var waiter = next.value();
            if (waiter._state.compare_exchange(_WAITER_WAITING, _WAITER_WOKEN)) {
                _async_sync_wake(waiter);
            }
        }
    }

    # Takes the waiter at the head, if any.
    _pop(): _SyncWaiter? {
        _async_sys_mutex_lock(_lock);
        if (_state[1] == 0) {
            _async_sys_mutex_unlock(_lock);
            return Optional<_SyncWaiter>.none();
        }
        __ptr<_SyncWaiter> slots = this._slots();
        var head = _state[0];
        var waiter = slots[head];
        slots[head] = __default<_SyncWaiter>();
        _state[0] = (head + 1) % _state[2];
        _state[1] = _state[1] - 1;
        _size.store(_state[1]);
        this._shrink();
        _async_sys_mutex_unlock(_lock);
        return Optional<_SyncWaiter>.some(waiter);
    }

    # Frees the buffer once no task waits, so an object that tasks waited on
    # once holds no memory for it. The caller holds the lock.
    _shrink() {
        if (_state[1] == 0 && _buffer[0] != __null) {
            _pep_free(_buffer[0]);
            _buffer[0] = __null;
            _state[0] = 0;
            _state[2] = 0;
        }
    }

    # The ring buffer, as `_SyncWaiter` slots.
    _slots(): __ptr<_SyncWaiter> {
        __ptr<void> raw = _buffer[0];
        return raw;
    }

    # Moves the waiters, in order, into a buffer twice the size (4 slots at
    # first). The caller holds the lock.
    _grow() {
        __ptr<_SyncWaiter> old = this._slots();
        var slots = _state[2];
        var size: ulong = slots * 2;
        if (size == 0) {
            size = 4;
        }
        __ptr<_SyncWaiter> grown = _pep_malloc(size * sizeof<_SyncWaiter>());
        _async_zero(grown, size * sizeof<_SyncWaiter>());
        var i: ulong = 0;
        while (i < _state[1]) {
            var from = (_state[0] + i) % slots;
            grown[i] = old[from];
            old[from] = __default<_SyncWaiter>();
            i = i + 1;
        }
        if (_buffer[0] != __null) {
            _pep_free(old);
        }
        _buffer[0] = grown;
        _state[0] = 0;
        _state[2] = size;
    }
}
