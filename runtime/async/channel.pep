## Channels: `Channel<T>` carries values from threads that send to threads
## that receive, and `ChannelIterator<T>` receives in a `for` loop.

# A Channel is `[Shared]`, so its fields are const. Its changing state lives
# in raw heap blocks that are read and written only under `Lock`:
#
# - `State`: four `ulong`s: the head index, the number of queued values, the
#   number of slots in the buffer, and 1 once closed.
# - `Buffer`: one pointer to the ring buffer of `T` slots (one reference each
#   for a struct `T`). An unbounded channel replaces the buffer with one
#   twice the size when it fills.
#
# `Buffer` is a `__ptr<__ptr<T>>`: a `[Shared]` struct's pointer field must
# point at a thread-safe type, so `check_shared_types` accepts only a
# thread-safe `T` (`Channel<String>` is a compile error). A thread-safe
# value's counts are atomic, so the sender and the receiver may both hold
# references to it. A later phase copies other values on `send`.
#
# Senders wait on `NotFull` (bounded channels only) and receivers on
# `NotEmpty`; `close` wakes both.

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
## `T` must be thread-safe (a number, a `[Shared]` struct, a `shared` function
## type such as `ThreadBody`), and is passed by reference; `Channel<String>` is
## a compile error.
##
## A Channel is `[Shared]`: keep it in a module-scope variable or pass it to
## threads.
##
## @typeParam T the type of the values carried, which must be thread-safe
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
    ## The most values that may wait before `send` blocks, or 0 for no limit.
    const Capacity: ulong;

    ## The platform mutex that guards `State` and `Buffer`.
    const Lock: __ptr<void>;

    ## The platform condition variable receivers wait on.
    const NotEmpty: __ptr<void>;

    ## The platform condition variable senders wait on while a bounded
    ## channel is full.
    const NotFull: __ptr<void>;

    ## The head index, the number of queued values, the number of slots in
    ## the buffer, and 1 once closed. Read and written only under `Lock`.
    const State: __ptr<ulong>;

    ## Holds the ring buffer of values. Read and written only under `Lock`.
    const Buffer: __ptr<__ptr<T>>;

    ## Creates an open, empty channel.
    ##
    ## @param capacity how many values may wait before `send` blocks; 0 (the default) for no limit
    ## @panics if the operating system cannot create a mutex or condition variable
    ## @example
    ##     var bounded = async.Channel<long>(16);
    ##     var unbounded = async.Channel<long>();
    construct(ulong capacity = 0) {
        Capacity = capacity;
        Lock = _async_sys_mutex_create();
        NotEmpty = _async_sys_condition_create();
        NotFull = _async_sys_condition_create();
        State = _pep_malloc(4 * sizeof<ulong>());
        var slots = capacity > 0 ? capacity : 16;
        State[2] = slots;
        Buffer = _pep_malloc(sizeof<__ptr<T>>());
        Buffer[0] = _pep_malloc(slots * sizeof<T>());
    }

    destruct {
        # Release the values still queued.
        __ptr<T> buffer = Buffer[0];
        var i: ulong = 0;
        while (i < State[1]) {
            buffer[(State[0] + i) % State[2]] = __default<T>();
            i = i + 1;
        }
        _pep_free(buffer);
        _pep_free(Buffer);
        _pep_free(State);
        _async_sys_condition_destroy(NotFull);
        _async_sys_condition_destroy(NotEmpty);
        _async_sys_mutex_destroy(Lock);
    }

    ## Queues `value`, first waiting while a bounded channel is full.
    ##
    ## @param value the value to send
    ## @returns true if the value was queued, false if the channel is closed (the value is dropped)
    ## @example
    ##     if (!results.send(42)) {
    ##         print("nobody is listening any more\n");
    ##     }
    bool send(T value) {
        _async_sys_mutex_lock(Lock);
        while (Capacity > 0 && State[1] == Capacity && State[3] == 0) {
            _async_sys_condition_wait(NotFull, Lock);
        }
        var queued = this._push(value);
        _async_sys_mutex_unlock(Lock);
        return queued;
    }

    ## Queues `value` only if there is room right now, without waiting.
    ##
    ## @param value the value to send
    ## @returns true if the value was queued, false if the channel is full or closed
    bool try_send(T value) {
        _async_sys_mutex_lock(Lock);
        var queued = false;
        if (Capacity == 0 || State[1] < Capacity) {
            queued = this._push(value);
        }
        _async_sys_mutex_unlock(Lock);
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
        _async_sys_mutex_lock(Lock);
        while (State[1] == 0 && State[3] == 0) {
            _async_sys_condition_wait(NotEmpty, Lock);
        }
        var received = this._pop();
        _async_sys_mutex_unlock(Lock);
        return received;
    }

    ## Takes the next value if one is waiting, without waiting.
    ##
    ## @returns the value, or an error if none is waiting (see `is_closed()` to tell an empty channel from a closed one)
    Result<T> try_receive() {
        _async_sys_mutex_lock(Lock);
        var received = this._pop();
        _async_sys_mutex_unlock(Lock);
        return received;
    }

    ## Like `receive()`, but gives up after about `milliseconds` milliseconds.
    ##
    ## @param milliseconds the longest time to wait
    ## @returns the value, or an error if the time ran out or once the channel is closed and empty
    Result<T> receive_for(ulong milliseconds) {
        var deadline = _async_sys_monotonic_milliseconds() + milliseconds;
        _async_sys_mutex_lock(Lock);
        while (State[1] == 0 && State[3] == 0) {
            var now = _async_sys_monotonic_milliseconds();
            if (now >= deadline) {
                break;
            }
            _async_sys_condition_wait_for(NotEmpty, Lock, deadline - now);
        }
        var received = this._pop();
        _async_sys_mutex_unlock(Lock);
        return received;
    }

    ## Closes the channel and wakes every waiting sender and receiver.
    ##
    ## Later sends fail. Values already queued stay, and receivers still get
    ## them; after the last one, `receive()` returns an error and `for` loops
    ## end. Closing a closed channel does nothing.
    void close() {
        _async_sys_mutex_lock(Lock);
        State[3] = 1;
        _async_sys_condition_notify_all(NotEmpty);
        _async_sys_condition_notify_all(NotFull);
        _async_sys_mutex_unlock(Lock);
    }

    ## Reports whether `close()` has been called.
    ##
    ## @returns true once the channel is closed, even while values are still queued
    bool is_closed() {
        _async_sys_mutex_lock(Lock);
        var closed = State[3] != 0;
        _async_sys_mutex_unlock(Lock);
        return closed;
    }

    ## Returns the number of values waiting to be received. Other threads may
    ## change it as soon as it returns.
    ##
    ## @returns the number of queued values
    ulong count() {
        _async_sys_mutex_lock(Lock);
        var queued = State[1];
        _async_sys_mutex_unlock(Lock);
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
        if (State[3] != 0) {
            return false;
        }
        if (State[1] == State[2]) {
            this._grow();
        }
        __ptr<T> buffer = Buffer[0];
        buffer[(State[0] + State[1]) % State[2]] = value;
        State[1] = State[1] + 1;
        _async_sys_condition_notify_one(NotEmpty);
        return true;
    }

    # Takes the value at the head; an error if none is queued. The caller
    # holds the lock.
    Result<T> _pop() {
        if (State[1] == 0) {
            if (State[3] != 0) {
                return Result<T>.err(Error("the channel is closed"));
            }
            return Result<T>.err(Error("no value is waiting"));
        }
        __ptr<T> buffer = Buffer[0];
        var head = State[0];
        var received = Result<T>.ok(buffer[head]);
        buffer[head] = __default<T>();
        State[0] = (head + 1) % State[2];
        State[1] = State[1] - 1;
        _async_sys_condition_notify_one(NotFull);
        return received;
    }

    # Moves the queued values, in order, into a buffer twice the size. The
    # caller holds the lock.
    void _grow() {
        __ptr<T> old = Buffer[0];
        var slots = State[2];
        __ptr<T> grown = _pep_malloc(2 * slots * sizeof<T>());
        var i: ulong = 0;
        while (i < State[1]) {
            var from = (State[0] + i) % slots;
            grown[i] = old[from];
            old[from] = __default<T>();
            i = i + 1;
        }
        _pep_free(old);
        Buffer[0] = grown;
        State[0] = 0;
        State[2] = 2 * slots;
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
    ## The channel it receives from.
    const Source: Channel<T>;

    ## The value the last successful `next()` received.
    T Current;

    ## Creates an iterator that receives from `source`. `source.iterate()`
    ## does the same.
    ##
    ## @param source the channel to receive from
    construct(Channel<T> source) {
        Source = source;
    }

    ## Waits for the next value.
    ##
    ## @returns true if a value arrived (read it with `current()`), false once the channel is closed and empty
    bool next() {
        var received = Source.receive();
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
