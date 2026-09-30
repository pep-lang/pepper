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
# touch its counts. `send` therefore copies the value with `copy` first, on
# the sending thread and before locking, then, under the lock, stores the
# copy in its slot and drops its own reference to it, so after unlocking
# only the slot references the copy. `receive` takes the value out of its
# slot under the lock the same way. Every count step on a copy happens on
# the sender before it unlocks or on the receiver after it locks. A
# thread-safe value is not copied (`copy` returns it); its counts are atomic.
#
# Senders wait on `_not_full` (bounded channels only) and receivers on
# `_not_empty`; `close` wakes both.

import "sys_posix";
import "sys_windows";

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
## `send` copies each value with `copy`, so the receiver gets a value that
## nothing on the sending thread references: a `String` or an `Array` can be
## sent, and changing the original afterwards does not affect what was sent.
## A thread-safe value (a number, a `[Shared]` struct, a `shared` function
## value such as a `ThreadBody`) is not copied but passed by reference. A
## type that `copy` cannot copy (a struct with a destructor or a raw pointer
## field that does not implement `Copyable<T>`, a plain function value, a
## trait value) is a compile error where the `Channel` is named.
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

    ## Creates an open, empty channel.
    ##
    ## @param capacity how many values may wait before `send` blocks; 0 (the default) for no limit
    ## @panics if the operating system cannot create a mutex or condition variable
    ## @example
    ##     var bounded = async.Channel<long>(16);
    ##     var unbounded = async.Channel<long>();
    construct(ulong capacity = 0) {
        _capacity = capacity;
        _lock = _async_sys_mutex_create();
        _not_empty = _async_sys_condition_create();
        _not_full = _async_sys_condition_create();
        _state = _pep_malloc(4 * sizeof<ulong>());
        var slots = capacity > 0 ? capacity : 16;
        _state[2] = slots;
        _buffer = _pep_malloc(sizeof<__ptr<void>>());
        _buffer[0] = _pep_malloc(slots * sizeof<T>());
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

    ## Queues a copy of `value`, first waiting while a bounded channel is
    ## full.
    ##
    ## The copy is made with `copy` before waiting, so the value can be
    ## changed or dropped as soon as `send` returns; a thread-safe value is
    ## queued itself.
    ##
    ## @param value the value to send
    ## @returns true if the value was queued, false if the channel is closed (the copy is dropped)
    ## @example
    ##     var line = "hello";
    ##     lines.send(line);
    ##     line.append(" again");   # the receiver still gets "hello"
    bool send(T value) {
        var copied = copy<T>(value);
        _async_sys_mutex_lock(_lock);
        while (_capacity > 0 && _state[1] == _capacity && _state[3] == 0) {
            _async_sys_condition_wait(_not_full, _lock);
        }
        var queued = this._push(copied);
        # Drop this thread's reference before unlocking: the slot now holds
        # the only one.
        copied = __default<T>();
        _async_sys_mutex_unlock(_lock);
        return queued;
    }

    ## Queues a copy of `value` only if there is room right now, without
    ## waiting. The copy is made even when it is not queued.
    ##
    ## @param value the value to send
    ## @returns true if the value was queued, false if the channel is full or closed
    bool try_send(T value) {
        var copied = copy<T>(value);
        _async_sys_mutex_lock(_lock);
        var queued = false;
        if (_capacity == 0 || _state[1] < _capacity) {
            queued = this._push(copied);
        }
        copied = __default<T>();
        _async_sys_mutex_unlock(_lock);
        return queued;
    }

    ## Takes the next value, waiting until one arrives.
    ##
    ## @returns the value, or an error once the channel is closed and empty
    ## @example
    ##     var job = jobs.receive();
    ##     if (job.is_ok()) {
    ##         run(job.value());
    ##     }
    Result<T> receive() {
        _async_sys_mutex_lock(_lock);
        while (_state[1] == 0 && _state[3] == 0) {
            _async_sys_condition_wait(_not_empty, _lock);
        }
        var received = this._pop();
        _async_sys_mutex_unlock(_lock);
        return received;
    }

    ## Takes the next value if one is waiting, without waiting.
    ##
    ## @returns the value, or an error if none is waiting (see `is_closed()` to tell an empty channel from a closed one)
    Result<T> try_receive() {
        _async_sys_mutex_lock(_lock);
        var received = this._pop();
        _async_sys_mutex_unlock(_lock);
        return received;
    }

    ## Like `receive()`, but gives up after about `milliseconds` milliseconds.
    ##
    ## @param milliseconds the longest time to wait
    ## @returns the value, or an error if the time ran out or once the channel is closed and empty
    Result<T> receive_for(ulong milliseconds) {
        var deadline = _async_sys_monotonic_milliseconds() + milliseconds;
        _async_sys_mutex_lock(_lock);
        while (_state[1] == 0 && _state[3] == 0) {
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
    void close() {
        _async_sys_mutex_lock(_lock);
        _state[3] = 1;
        _async_sys_condition_notify_all(_not_empty);
        _async_sys_condition_notify_all(_not_full);
        _async_sys_mutex_unlock(_lock);
    }

    ## Reports whether `close()` has been called.
    ##
    ## @returns true once the channel is closed, even while values are still queued
    bool is_closed() {
        _async_sys_mutex_lock(_lock);
        var closed = _state[3] != 0;
        _async_sys_mutex_unlock(_lock);
        return closed;
    }

    ## Returns the number of values waiting to be received. Other threads may
    ## change it as soon as it returns.
    ##
    ## @returns the number of queued values
    ulong count() {
        _async_sys_mutex_lock(_lock);
        var queued = _state[1];
        _async_sys_mutex_unlock(_lock);
        return queued;
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
    ChannelIterator<T> iterate() {
        return ChannelIterator<T>(this);
    }

    # Queues `value` at the tail, growing an unbounded buffer when full; false
    # if closed. The caller holds the lock and has checked a bounded
    # channel's capacity.
    bool _push(T value) {
        if (_state[3] != 0) {
            return false;
        }
        if (_state[1] == _state[2]) {
            this._grow();
        }
        __ptr<T> buffer = this._slots();
        buffer[(_state[0] + _state[1]) % _state[2]] = value;
        _state[1] = _state[1] + 1;
        _async_sys_condition_notify_one(_not_empty);
        return true;
    }

    # Takes the value at the head; an error if none is queued. The caller
    # holds the lock.
    Result<T> _pop() {
        if (_state[1] == 0) {
            if (_state[3] != 0) {
                return Result<T>.err(Error("the channel is closed"));
            }
            return Result<T>.err(Error("no value is waiting"));
        }
        __ptr<T> buffer = this._slots();
        var head = _state[0];
        var received = Result<T>.ok(buffer[head]);
        buffer[head] = __default<T>();
        _state[0] = (head + 1) % _state[2];
        _state[1] = _state[1] - 1;
        _async_sys_condition_notify_one(_not_full);
        return received;
    }

    # The ring buffer, as `T` slots.
    __ptr<T> _slots() {
        __ptr<void> raw = _buffer[0];
        return raw;
    }

    # Moves the queued values, in order, into a buffer twice the size. The
    # caller holds the lock.
    void _grow() {
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
export struct ChannelIterator<T> {
    # The channel it receives from.
    const _source: Channel<T>;

    ## The value the last successful `next()` received.
    T Current;

    ## Creates an iterator that receives from `source`. `source.iterate()`
    ## does the same.
    ##
    ## @param source the channel to receive from
    construct(Channel<T> source) {
        _source = source;
    }

    ## Waits for the next value.
    ##
    ## @returns true if a value arrived (read it with `current()`), false once the channel is closed and empty
    bool next() {
        var received = _source.receive();
        if (received.is_err()) {
            Current = __default<T>();
            return false;
        }
        Current = received.value();
        return true;
    }

    ## Returns the value the last successful `next()` received.
    ##
    ## @returns the current value
    T current() {
        return Current;
    }
}

extend ChannelIterator<T> with Iterator<T> {}
