## Channels: `Channel<T>` carries values from threads that send to threads
## that receive, and `ChannelIterator<T>` receives in a `for` loop.

# A Channel is `[Shared]`, so its fields are const. Its changing state lives
# in raw heap blocks that are read and written only under `_lock`:
#
# - `_state`: four `ulong`s: the head index, the number of queued values, the
#   number of slots in the buffer, and 1 once closed.
# - `_buffer`: one pointer to the ring buffer of `T` slots (one reference each
#   for a struct `T`). An unbounded channel replaces the buffer with one
#   twice the size when it fills.
#
# `_buffer` is a `__ptr<__ptr<void>>`, so `check_shared_types` accepts any
# `T`; the methods view the buffer as `T` slots. A value that is not
# thread-safe counts its references plainly, so no two threads may ever
# touch its counts. `send` takes a `[Move]` value, which nothing else
# references (the compiler checks the caller), and the caller hands its one
# reference over; under the lock `_push` moves it into its slot, so after
# unlocking only the slot references the value. `_pop` takes it out with
# `move(buffer[head])` under the lock the same way: the runtime's promise (the
# compiler cannot follow raw memory) that the slot held the only reference.
# No count step on a sent value happens on either side, and what `receive`
# returns is a new value, which may move into a locked value.
#
# Senders wait on `_not_full` (bounded channels only) and receivers on
# `_not_empty`; `close` wakes both. A task on a worker waits in
# `_senders` or `_receivers` instead (see sync_wait.pep), so its worker
# keeps running other tasks: whatever notifies a condition also wakes one
# task from the matching queue. A task adds its waiter under `_lock`, and a
# waker wakes under it, so no wake is missed.
#
# A `Select` (select.pep) waits on several channels through the same
# queues: `_select_join` adds its one waiter to `_receivers` unless a value
# is already there or the channel is closed, and `_select_take` takes a
# value the way `try_receive` does, telling an empty channel from a closed
# one.

import "atomic";
import "lock";
import "sync_wait";
import "sys_posix";
import "sys_wasi";
import "sys_windows";
import "task";

## A queue that carries values from threads that send to threads that
## receive, like Go channels or Rust's `mpsc`, with any number of each.
##
## Values arrive in the order they were sent (from any one sender). A
## bounded channel holds at most `capacity` values, and `send` waits while it
## is full; `Channel<T>(0)`, the default, is unbounded and `send` never waits.
##
## `close()` ends the stream: later sends fail, and receivers take what is
## left and then get an error. Only `close()` closes a channel; dropping it
## or the threads that use it does not. `for (var v in channel)` receives
## until the channel is closed and empty.
##
## `send` takes a new value, which nothing on the sending thread references,
## and hands it to the receiver without copying it: a constructor call, a
## literal, a call that returns a fresh value, `move(x)` (a variable that
## holds the only reference) or `copy(x)` (a copy, when the sender keeps
## using `x`). Sending a variable that something else still references is a
## compile error. A thread-safe value (a number, a `[Shared]` struct, a
## `shared` function value such as a `ThreadBody`) passes freely.
##
## A Channel is `[Shared]`: keep it in a module-scope variable or pass it to
## threads.
##
## @typeParam T the type of the values carried
## @example
##     import async;
##
##     const jobs = async.Channel<long>(64);
##     const total = Atomic<long>(0);
##
##     worker() {
##         for (var job in jobs) {
##             total.fetch_add(job);
##         }
##     }
##
##     main(): int {
##         var thread = async.Thread.spawn(worker);
##         jobs.send(20);
##         jobs.send(22);
##         jobs.close();
##         thread.join();
##         assert(total.load() == 42, "the worker received both jobs");
##         return 0;
##     }
[Shared]
export struct Channel<T> {
    # The most values that may wait before `send` blocks, or 0 for no limit.
    const _capacity: ulong;

    # The platform mutex that guards `_state` and `_buffer`.
    const _lock: __ptr<void>;

    # The platform condition variable receivers wait on.
    const _not_empty: __ptr<void>;

    # The platform condition variable senders wait on while a bounded
    # channel is full.
    const _not_full: __ptr<void>;

    # The head index, the number of queued values, the number of slots in
    # the buffer, and 1 once closed. Read and written only under `_lock`.
    const _state: __ptr<ulong>;

    # Holds the ring buffer of values (`T` slots). Read and written only
    # under `_lock`.
    const _buffer: __ptr<__ptr<void>>;

    # The tasks waiting to receive, and to send to a full bounded channel.
    const _receivers: _SyncQueue;
    const _senders: _SyncQueue;

    ## Creates an open, empty channel.
    ##
    ## @param capacity how many values may wait before `send` blocks; 0 (the default) for no limit
    ## @example
    ##     var bounded = async.Channel<long>(16);
    ##     var unbounded = async.Channel<long>();
    construct(capacity: ulong = 0) {
        _capacity = capacity;
        _lock = _async_sys_mutex_create();
        _not_empty = _async_sys_condition_create();
        _not_full = _async_sys_condition_create();
        _state = _pep_malloc(4 * sizeof<ulong>());
        var slots = capacity > 0 ? capacity : 16;
        _state[2] = slots;
        _buffer = _pep_malloc(sizeof<__ptr<void>>());
        _buffer[0] = _pep_malloc(slots * sizeof<T>());
        _receivers = _SyncQueue();
        _senders = _SyncQueue();
    }

    destruct {
        # Release the values still queued, under the lock the senders stored
        # them under.
        _async_sys_mutex_lock(_lock);
        __ptr<T> buffer = this._slots();
        var i: ulong = 0;
        while (i < _state[1]) {
            buffer[(_state[0] + i) % _state[2]] = __default<T>();
            i = i + 1;
        }
        _async_sys_mutex_unlock(_lock);
        _pep_free(buffer);
        _pep_free(_buffer);
        _pep_free(_state);
        _async_sys_condition_destroy(_not_full);
        _async_sys_condition_destroy(_not_empty);
        _async_sys_mutex_destroy(_lock);
    }

    ## Queues `value`, first waiting while a bounded channel is full.
    ##
    ## `value` must be a new value: nothing else may reference it. The caller
    ## hands its reference over and the value itself is queued, with no copy.
    ## Pass `move(x)` to send a variable's value, or `copy(x)` to keep using
    ## `x`.
    ##
    ## In a task (see `run`), waiting parks the task and its worker runs
    ## other tasks; a cancel or the task's `timeout` ends the wait.
    ##
    ## @param value the value to send; a new value, which the compiler checks
    ## @returns true if the value was queued, false if the channel is closed or the task's wait was cancelled or timed out (the value is dropped)
    ## @example
    ##     var line = "hello";
    ##     lines.send(copy(line));
    ##     line.append(" again");   # the receiver still gets "hello"
    ##     lines.send(move(line));   # line is null now
    send([Move] value: T): bool {
        _async_sys_mutex_lock(_lock);
        var in_task = _async_in_task();
        while (_capacity > 0 && _state[1] == _capacity && _state[3] == 0) {
            if (!in_task) {
                _async_sys_condition_wait(_not_full, _lock);
            } else if (this._park_task(_senders, 0) != _SyncWake.Woken) {
                _async_sys_mutex_unlock(_lock);
                return false;
            }
        }
        var queued = this._push(move(value));
        _async_sys_mutex_unlock(_lock);
        return queued;
    }

    ## Queues `value` only if there is room right now, without waiting. The
    ## value is dropped when it is not queued.
    ##
    ## @param value the value to send; a new value, as for `send`
    ## @returns true if the value was queued, false if the channel is full or closed
    try_send([Move] value: T): bool {
        _async_sys_mutex_lock(_lock);
        var queued = false;
        if (_capacity == 0 || _state[1] < _capacity) {
            queued = this._push(move(value));
        }
        _async_sys_mutex_unlock(_lock);
        return queued;
    }

    ## Takes the next value, waiting until one arrives.
    ##
    ## In a task (see `run`), waiting parks the task and its worker runs
    ## other tasks; a cancel or the task's `timeout` ends the wait.
    ##
    ## @returns the value, or an error once the channel is closed and empty, or when the task's wait was cancelled or timed out
    ## @example
    ##     var job = jobs.receive();
    ##     if (job.is_ok()) {
    ##         run(job.value());
    ##     }
    receive(): Result<T> {
        _async_sys_mutex_lock(_lock);
        var in_task = _async_in_task();
        while (_state[1] == 0 && _state[3] == 0) {
            if (!in_task) {
                _async_sys_condition_wait(_not_empty, _lock);
                continue;
            }
            var woken = this._park_task(_receivers, 0);
            if (woken == _SyncWake.Cancelled) {
                _async_sys_mutex_unlock(_lock);
                return Result<T>.err(Error("the task was cancelled"));
            }
            if (woken == _SyncWake.TimedOut) {
                break;
            }
        }
        var received = this._pop();
        _async_sys_mutex_unlock(_lock);
        return received;
    }

    ## Takes the next value if one is waiting, without waiting.
    ##
    ## @returns the value, or an error if none is waiting (see `is_closed()` to tell an empty channel from a closed one)
    try_receive(): Result<T> {
        _async_sys_mutex_lock(_lock);
        var received = this._pop();
        _async_sys_mutex_unlock(_lock);
        return received;
    }

    ## Like `receive()`, but gives up after about `milliseconds` milliseconds.
    ##
    ## @param milliseconds the longest time to wait
    ## @returns the value, or an error if the time ran out, once the channel is closed and empty, or when the task's wait was cancelled
    receive_for(milliseconds: ulong): Result<T> {
        var deadline = _async_sys_monotonic_milliseconds() + milliseconds;
        _async_sys_mutex_lock(_lock);
        var in_task = _async_in_task();
        while (_state[1] == 0 && _state[3] == 0) {
            if (in_task) {
                var woken = this._park_task(_receivers, deadline);
                if (woken == _SyncWake.Cancelled) {
                    _async_sys_mutex_unlock(_lock);
                    return Result<T>.err(Error("the task was cancelled"));
                }
                if (woken == _SyncWake.TimedOut) {
                    break;
                }
                continue;
            }
            var now = _async_sys_monotonic_milliseconds();
            if (now >= deadline) {
                break;
            }
            _async_sys_condition_wait_for(_not_empty, _lock, deadline - now);
        }
        var received = this._pop();
        _async_sys_mutex_unlock(_lock);
        return received;
    }

    ## Closes the channel and wakes every waiting sender and receiver.
    ##
    ## Later sends fail. Values already queued stay, and receivers still get
    ## them; after the last one, `receive()` returns an error and `for` loops
    ## end. Closing a closed channel does nothing.
    close() {
        _async_sys_mutex_lock(_lock);
        _state[3] = 1;
        _async_sys_condition_notify_all(_not_empty);
        _async_sys_condition_notify_all(_not_full);
        _receivers._wake_all();
        _senders._wake_all();
        _async_sys_mutex_unlock(_lock);
    }

    ## Reports whether `close()` has been called.
    ##
    ## @returns true once the channel is closed, even while values are still queued
    is_closed(): bool {
        _async_sys_mutex_lock(_lock);
        var closed = _state[3] != 0;
        _async_sys_mutex_unlock(_lock);
        return closed;
    }

    ## The number of values waiting to be received. Other threads may
    ## change it as soon as it returns.
    var count: ulong {
        get {
            _async_sys_mutex_lock(_lock);
            var queued = _state[1];
            _async_sys_mutex_unlock(_lock);
            return queued;
        }
    }

    ## Returns an iterator that receives until the channel is closed and
    ## empty. A `for` loop over the channel calls it.
    ##
    ## Several threads may loop over one channel at once; each value goes to
    ## exactly one of them.
    ##
    ## @returns the iterator a `for` loop drives
    ## @example
    ##     for (var line in lines) {
    ##         print(line, "\n");
    ##     }   # ends once `lines` is closed and empty
    iterate(): ChannelIterator<T> {
        return ChannelIterator<T>(this);
    }

    # Queues `value` at the tail, growing an unbounded buffer when full; false
    # if closed, when `value` is dropped here, under the lock. The caller
    # holds the lock and has checked a bounded channel's capacity.
    _push([Move] value: T): bool {
        if (_state[3] != 0) {
            return false;
        }
        if (_state[1] == _state[2]) {
            this._grow();
        }
        __ptr<T> buffer = this._slots();
        buffer[(_state[0] + _state[1]) % _state[2]] = move(value);
        _state[1] = _state[1] + 1;
        _async_sys_condition_notify_one(_not_empty);
        _receivers._wake_one();
        return true;
    }

    # Takes the value at the head; an error if none is queued. The caller
    # holds the lock.
    _pop(): Result<T> {
        if (_state[1] == 0) {
            if (_state[3] != 0) {
                return Result<T>.err(Error("the channel is closed"));
            }
            return Result<T>.err(Error("no value is waiting"));
        }
        __ptr<T> buffer = this._slots();
        var head = _state[0];
        var received = Result<T>.ok(move(buffer[head]));
        _state[0] = (head + 1) % _state[2];
        _state[1] = _state[1] - 1;
        _async_sys_condition_notify_one(_not_full);
        _senders._wake_one();
        return received;
    }

    # Takes the value at the head if one is waiting: `(true, value)`, or
    # `(false, default)` when none is. For the scheduler, which polls
    # channels that are usually empty: unlike `try_receive`, a miss
    # allocates nothing (no `Result`, `Error` or message).
    _try_take(): (bool, T) {
        _async_sys_mutex_lock(_lock);
        if (_state[1] == 0) {
            _async_sys_mutex_unlock(_lock);
            return (false, __default<T>());
        }
        __ptr<T> buffer = this._slots();
        var head = _state[0];
        T value = move(buffer[head]);
        _state[0] = (head + 1) % _state[2];
        _state[1] = _state[1] - 1;
        _async_sys_condition_notify_one(_not_full);
        _senders._wake_one();
        _async_sys_mutex_unlock(_lock);
        return (true, value);
    }

    # For `Select`: takes the value at the head if there is one, and
    # otherwise reports whether the channel is closed.
    _select_take(): _Polled<T> {
        _async_sys_mutex_lock(_lock);
        if (_state[1] != 0) {
            var received = this._pop();
            _async_sys_mutex_unlock(_lock);
            return _Polled<T>.Ready(received.value());
        }
        var closed = _state[3] != 0;
        _async_sys_mutex_unlock(_lock);
        if (closed) {
            return _Polled<T>.Closed;
        }
        return _Polled<T>.Empty;
    }

    # For `Select`: adds `waiter` to `_receivers` and returns
    # `_Joined.Empty`. Returns `_Joined.Ready` without adding it when a
    # value is waiting (the select should look again instead of sleeping),
    # and `_Joined.Closed` when the channel is closed and empty (nothing
    # will ever wake it).
    _select_join(waiter: _SyncWaiter): _Joined {
        _async_sys_mutex_lock(_lock);
        var found = _Joined.Empty;
        if (_state[1] != 0) {
            found = _Joined.Ready;
        } else if (_state[3] != 0) {
            found = _Joined.Closed;
        } else {
            _receivers._push(waiter);
        }
        _async_sys_mutex_unlock(_lock);
        return found;
    }

    # For `Select`: takes `waiter` out of `_receivers`, if it is there.
    _select_leave(waiter: _SyncWaiter) {
        _receivers._remove(waiter);
    }

    # Parks the running task in `queue` until a waker wakes it, `deadline`
    # passes (0 for none), or the task is cancelled or its `timeout` expires;
    # returns which (see `_async_sync_park`). The caller holds the lock,
    # which is released while the task waits and held again on return.
    _park_task(queue: _SyncQueue, deadline: ulong): _SyncWake {
        var waiter = _async_sync_waiter();
        queue._push(waiter);
        _async_sys_mutex_unlock(_lock);
        var woken = _async_sync_park(queue, waiter, deadline, true);
        _async_sys_mutex_lock(_lock);
        return woken;
    }

    # The ring buffer, as `T` slots.
    _slots(): __ptr<T> {
        __ptr<void> raw = _buffer[0];
        return raw;
    }

    # Moves the queued values, in order, into a buffer twice the size. The
    # caller holds the lock.
    _grow() {
        __ptr<T> old = this._slots();
        var slots = _state[2];
        __ptr<T> grown = _pep_malloc(2 * slots * sizeof<T>());
        var i: ulong = 0;
        while (i < _state[1]) {
            var from = (_state[0] + i) % slots;
            grown[i] = old[from];
            old[from] = __default<T>();
            i = i + 1;
        }
        _pep_free(old);
        _buffer[0] = grown;
        _state[0] = 0;
        _state[2] = 2 * slots;
    }
}

# What `Channel._select_join` found (and, in select.pep, what a case's
# last `_take` found).
enum _Joined {
    Ready,
    Empty,
    Closed,
}

# What `Channel._select_take` found: a value, nothing yet, or a closed and
# empty channel.
enum _Polled<T> {
    Ready(value: T),
    Empty,
    Closed,
}

## Receives from a `Channel<T>` in a `for` loop: `next()` waits for the next
## value and returns false once the channel is closed and empty.
##
## `Channel.iterate()` returns one; a `for` loop over a channel uses it
## without naming it. It belongs to the thread that runs the loop.
##
## @typeParam T the type of the values carried
## @example
##     var values = jobs.iterate();
##     while (values.next()) {
##         total = total + values.current();
##     }
[Value]
export struct ChannelIterator<T> {
    # The channel it receives from.
    const _source: Channel<T>;

    # The value the last successful `next()` received.
    T _current;

    ## Creates an iterator that receives from `source`. `source.iterate()`
    ## does the same.
    ##
    ## @param source the channel to receive from
    construct(source: Channel<T>) {
        _source = source;
    }

    ## Waits for the next value.
    ##
    ## @returns true if a value arrived (read it with `current()`), false once the channel is closed and empty
    next(): bool {
        var received = _source.receive();
        if (received.is_err()) {
            _current = __default<T>();
            return false;
        }
        _current = received.value();
        return true;
    }

    ## Returns the value the last successful `next()` received.
    ##
    ## @returns the current value
    current(): T {
        return _current;
    }
}

extend ChannelIterator<T> with Iterator<T>;
