## Waiting on several channels at once: `Select<E>` takes the first value
## any of them receives and turns it into a case of your own enum, which a
## `match` then handles.

# A select tries each channel in turn (`_poll`), starting after the one that
# fired last so a busy channel cannot starve the others. When none has a
# value it makes one `_SyncWaiter` and joins every open channel's
# `_receivers` queue with it (`Channel._select_join`, which declines when a
# value is already there, so a value that arrives while joining is never
# missed). A send or close on any of them wakes the waiter once; the select
# then leaves every queue and looks again. A closed channel is not joined,
# since nothing will wake it: when every channel is closed, or one has a
# value, the select does not sleep at all (a task that slept on nothing
# would never wake, and one that looped without sleeping would starve the
# tasks it waits for). A task parks as it does for
# `receive`; a plain thread sleeps on the waiter's `_ThreadWake` instead of
# a channel's condition variable (see sync_wait.pep).

import "channel";
import "sync_wait";
import "sys_posix";
import "sys_windows";
import "task";

# One channel of a `Select`, whatever its value type: taking a value (as an
# `E`), and joining and leaving its wait queue (`_join` returns what
# `Channel._select_join` found).
export trait _SelectCase<E> {
    _take(): _Polled<E>;
    _join(waiter: _SyncWaiter): int;
    _leave(waiter: _SyncWaiter);
}

# A channel of `T` values and how to turn one into an `E`.
export struct _ReceiveCase<T, E> {
    const _channel: Channel<T>;
    const _wrap: (T) => E;

    construct(channel: Channel<T>, wrap: (T) => E) {
        _channel = channel;
        _wrap = wrap;
    }
}

extend _ReceiveCase<T, E> with _SelectCase<E> {
    # The value the channel had, turned into an `E`.
    _take(): _Polled<E> {
        match (_channel._select_take()) {
            Ready(value) => {
                return _Polled<E>.Ready(_wrap(value));
            }
            Empty => {
                return _Polled<E>.Empty;
            }
            Closed => {
                return _Polled<E>.Closed;
            }
        }
        return _Polled<E>.Empty;
    }

    _join(waiter: _SyncWaiter): int {
        return _channel._select_join(waiter);
    }

    _leave(waiter: _SyncWaiter) {
        _channel._select_leave(waiter);
    }
}

## Waits on several channels at once and takes the first value any of them
## receives, like Go's `select`.
##
## Each channel is added with `receive(channel, wrap)`, where `wrap` turns
## one of its values into an `E`, usually a case of an enum of your own that
## carries it. `wait()` then returns the next value from whichever channel
## has one, as an `E`, for a `match` to handle. The channels may carry
## different types.
##
## - The value is taken under the channel's own lock, so no other receiver
##   can take it between "ready" and "take".
## - When several channels have values, each wait starts after the channel
##   that fired last, so a busy channel cannot starve the others.
## - A channel that is closed and empty is skipped. Once every channel is,
##   `wait()` returns an error.
## - In a task (see `run`), waiting parks the task and its worker runs other
##   tasks; a cancel or the task's `timeout` ends the wait.
##
## A Select is not `[Shared]`: use it from the thread (or task) that made it.
##
## @typeParam E the type every channel's values are turned into
## @example
##     enum Event {
##         Job(job: Job),
##         Tick(count: long),
##         Stop,
##     }
##
##     var select = async.Select<Event>();
##     select.receive(jobs, (job: Job): Event => Event.Job(job));
##     select.receive(ticks, (count: long): Event => Event.Tick(count));
##     select.receive(quit, (stop: bool): Event => Event.Stop);
##     var running = true;
##     while (running) {
##         match (select.wait()) {
##             Ok(event) => {
##                 match (event) {
##                     Job(job) => { run(job); }
##                     Tick(count) => { report(count); }
##                     Stop => { running = false; }
##                 }
##             }
##             Err(error) => { running = false; }   # every channel closed
##         }
##     }
export struct Select<E> {
    # The channels, in the order they were added.
    var _cases: Array<_SelectCase<E>>;
    # Where the next look starts: just after the case that fired last.
    var _next: ulong;
    # An empty queue for `_async_sync_park`, which takes a waiter out of one
    # queue when it gives up; a select leaves every channel's queue itself.
    const _no_queue: _SyncQueue;

    ## Creates a select with no channels yet.
    construct() {
        _cases = Array<_SelectCase<E>>();
        _next = 0;
        _no_queue = _SyncQueue();
    }

    ## Adds `channel`: its values, turned into an `E` by `wrap`, are among
    ## those `wait()` returns.
    ##
    ## @typeParam T the type of the channel's values
    ## @param channel the channel to receive from
    ## @param wrap turns a value received from `channel` into an `E`; it runs on the waiting thread
    ## @example
    ##     select.receive(lines, (line: String): Event => Event.Line(line));
    receive<T>(channel: Channel<T>, wrap: (T) => E) {
        _cases.append(_ReceiveCase<T, E>(channel, wrap));
    }

    ## Takes the next value any of the channels receives, waiting until one
    ## arrives.
    ##
    ## @returns the value, turned into an `E`; or an error once every channel is closed and empty, when the select has no channels, or when the task's wait was cancelled or timed out
    wait(): Result<E> {
        return this._wait(0);
    }

    ## Like `wait()`, but gives up after about `milliseconds` milliseconds.
    ##
    ## @param milliseconds the longest time to wait
    ## @returns the value, turned into an `E`; or an error if the time ran out, once every channel is closed and empty, or when the task's wait was cancelled
    wait_for(milliseconds: ulong): Result<E> {
        return this._wait(_async_sys_monotonic_milliseconds() + milliseconds);
    }

    ## Takes a value if any channel has one waiting, without waiting.
    ##
    ## @returns the value, turned into an `E`; or an error if none is waiting, or once every channel is closed and empty
    try_wait(): Result<E> {
        match (this._poll()) {
            Ready(event) => {
                return Result<E>.ok(event);
            }
            Empty => {
                return Result<E>.err(Error("no value is waiting"));
            }
            Closed => {
                return Result<E>.err(Error("every channel is closed"));
            }
        }
    }

    # Looks at each channel once, starting at `_next`: the first value found
    # (Ready), else Empty if any channel is still open, else Closed.
    _poll(): _Polled<E> {
        var count = _cases.count();
        var closed: ulong = 0;
        var i: ulong = 0;
        while (i < count) {
            var index = (_next + i) % count;
            var entry: _SelectCase<E> = _cases[index];
            match (entry._take()) {
                Ready(event) => {
                    _next = (index + 1) % count;
                    return _Polled<E>.Ready(event);
                }
                Empty => {}
                Closed => {
                    closed = closed + 1;
                }
            }
            i = i + 1;
        }
        if (closed == count) {
            return _Polled<E>.Closed;
        }
        return _Polled<E>.Empty;
    }

    # `wait` until `deadline` (monotonic milliseconds, 0 for none).
    _wait(deadline: ulong): Result<E> {
        if (_cases.count() == 0) {
            return Result<E>.err(Error("the select has no channels"));
        }
        while (true) {
            match (this._poll()) {
                Ready(event) => {
                    return Result<E>.ok(event);
                }
                Empty => {}
                Closed => {
                    return Result<E>.err(Error("every channel is closed"));
                }
            }
            if (deadline != 0 && _async_sys_monotonic_milliseconds() >= deadline) {
                return Result<E>.err(Error("the time ran out"));
            }
            var woken = this._sleep(deadline);
            if (woken == _SYNC_CANCELLED) {
                return Result<E>.err(Error("the task was cancelled"));
            }
            if (woken == _SYNC_TIMED_OUT) {
                # The task's `timeout`, or `deadline`: one last look.
                match (this._poll()) {
                    Ready(event) => {
                        return Result<E>.ok(event);
                    }
                    Empty => {}
                    Closed => {}
                }
                return Result<E>.err(Error("the time ran out"));
            }
        }
        return Result<E>.err(Error("the time ran out"));
    }

    # Joins every open channel's queue with one waiter and sleeps until a
    # channel wakes it, `deadline` passes, or (in a task) the wait is
    # cancelled; returns which, as `_async_sync_park` does. Returns at once,
    # as woken, when a channel already has a value or every channel is
    # closed: the next look finds which.
    _sleep(deadline: ulong): int {
        var in_task = _async_in_task();
        var waiter = in_task ? _async_sync_waiter() : _SyncWaiter(_ThreadWake());
        var count = _cases.count();
        var joined: ulong = 0;
        var closed: ulong = 0;
        var ready = false;
        while (joined < count && !ready) {
            var entry: _SelectCase<E> = _cases[joined];
            var found = entry._join(waiter);
            if (found == _SELECT_READY) {
                ready = true;
            } else {
                if (found == _SELECT_CLOSED) {
                    closed = closed + 1;
                }
                joined = joined + 1;
            }
        }
        var woken = _SYNC_WOKEN;
        if (ready || closed == count) {
            # Nothing to sleep for: stop waiting before sleeping at all.
            waiter._state.compare_exchange(_WAITER_WAITING, _WAITER_ABANDONED);
        } else if (in_task) {
            woken = _async_sync_park(_no_queue, waiter, deadline, true);
        } else {
            woken = _async_thread_park(waiter, deadline);
        }
        var i: ulong = 0;
        while (i < joined) {
            _cases[i]._leave(waiter);
            i = i + 1;
        }
        return woken;
    }
}
