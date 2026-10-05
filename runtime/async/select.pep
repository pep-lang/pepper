## Waiting on several channels at once: `Select<E>` takes the first value
## any of them receives, or sends a value to the first that has room, and
## turns what happened into a case of your own enum, which a `match` then
## handles.

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
#
# A send arm (`_SendCase`) works the same way on the sending side: it keeps
# its value in a raw slot until a look finds room (`Channel._select_put`,
# which moves the value in under the channel's lock), joins the channel's
# `_senders` queue while it is full, and leaves the select once it fires.

import "channel";
import "sync_wait";
import "sys_posix";
import "sys_wasi";
import "sys_windows";
import "task";

# One arm of a `Select`, whatever its channel's value type: firing it
# (receiving or sending, and turning that into an `E`), and joining and
# leaving its channel's wait queue (`_join` returns what the channel
# found). `_finished` is true for an arm that has fired and leaves the
# select.
trait _SelectCase<E> {
    _take(): _Polled<E>;
    _join(waiter: _SyncWaiter): _Joined;
    _leave(waiter: _SyncWaiter);
    _finished(): bool;
}

# A channel of `T` values and how to turn one into an `E`.
struct _ReceiveCase<T, E> {
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

    _join(waiter: _SyncWaiter): _Joined {
        return _channel._select_join(waiter);
    }

    _leave(waiter: _SyncWaiter) {
        _channel._select_leave(waiter);
    }

    # A receive arm stays until the select is dropped.
    _finished(): bool {
        return false;
    }
}

# A value waiting to be sent to a channel of `T` values, and what to return
# once it is. The value is held in `_slot`, raw memory the compiler cannot
# follow: `send` took it as a `[Move]` value, so the slot holds the only
# reference, and `Channel._select_put` moves it out of the slot only when
# the channel has room.
struct _SendCase<T, E> {
    const _channel: Channel<T>;
    const _sent: () => E;
    # One `T` slot; it holds the value until the arm fires.
    const _slot: __ptr<T>;
    # True once the value is in the channel.
    var _done: bool;

    construct(channel: Channel<T>, [Move] value: T, sent: () => E) {
        _channel = channel;
        _sent = sent;
        _slot = _pep_malloc(sizeof<T>());
        _slot[0] = move(value);
        _done = false;
    }

    destruct {
        # A value never sent is dropped with the select.
        _slot[0] = __default<T>();
        _pep_free(_slot);
    }
}

extend _SendCase<T, E> with _SelectCase<E> {
    # Sends the value if the channel has room, and returns what `_sent`
    # makes of that.
    _take(): _Polled<E> {
        if (_done) {
            return _Polled<E>.Closed;
        }
        var found = _channel._select_put(_slot);
        if (found == _Joined.Ready) {
            _done = true;
            return _Polled<E>.Ready(_sent());
        }
        if (found == _Joined.Closed) {
            return _Polled<E>.Closed;
        }
        return _Polled<E>.Empty;
    }

    _join(waiter: _SyncWaiter): _Joined {
        if (_done) {
            return _Joined.Closed;
        }
        return _channel._select_join_send(waiter);
    }

    _leave(waiter: _SyncWaiter) {
        _channel._select_leave_send(waiter);
    }

    _finished(): bool {
        return _done;
    }
}

## Waits on several channels at once and takes the first value any of them
## receives, or sends to the first that has room, like Go's `select`.
##
## Each channel to receive from is added with `receive(channel, wrap)`,
## where `wrap` turns one of its values into an `E`, usually a case of an
## enum of your own that carries it. A value to send is added with
## `send(channel, value, sent)`, where `sent` returns the `E` that says it
## was sent. `wait()` then fires whichever arm is ready first and returns
## its `E`, for a `match` to handle. The channels may carry different types.
##
## - The value is taken under the channel's own lock, so no other receiver
##   can take it between "ready" and "take".
## - A send arm's value goes into its channel only when that arm fires;
##   until then the select holds it. Once sent, the arm leaves the select,
##   so the next `wait()` does not send it again. A value never sent is
##   dropped with the select.
## - When several channels have values, each wait starts after the channel
##   that fired last, so a busy channel cannot starve the others.
## - A channel that is closed and empty is skipped, and so is a send arm
##   whose channel is closed. Once every arm is, `wait()` returns an error.
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

    ## Adds a send arm: `wait()` sends `value` to `channel` once the channel
    ## has room (a bounded channel that is full waits), and returns what
    ## `sent` returns.
    ##
    ## `value` must be a new value, as for `Channel.send`: the select holds
    ## it and moves it into the channel only when this arm fires, so it is
    ## never sent if another arm fires first. Once sent, the arm leaves the
    ## select. A send arm whose channel is closed never fires, and its value
    ## is dropped with the select.
    ##
    ## @typeParam T the type of the channel's values
    ## @param channel the channel to send to
    ## @param value the value to send; a new value, which the compiler checks
    ## @param sent returns the `E` that `wait()` returns once the value is sent; it runs on the waiting thread
    ## @example
    ##     select.send(results, copy(line), (): Event => Event.Sent);
    send<T>(channel: Channel<T>, [Move] value: T, sent: () => E) {
        _cases.append(_SendCase<T, E>(channel, move(value), sent));
    }

    ## Fires the first arm that is ready, waiting until one is: takes the
    ## next value any of the channels receives, or sends a send arm's value
    ## to a channel with room.
    ##
    ## @returns the arm's `E` (the value received, turned into an `E`, or what a send arm's `sent` returned); or an error once every channel is closed (and empty, for a receive arm), when the select has no arms, or when the task's wait was cancelled or timed out
    wait(): Result<E> {
        return this._wait(0);
    }

    ## Like `wait()`, but gives up after about `milliseconds` milliseconds.
    ##
    ## @param milliseconds the longest time to wait
    ## @returns the arm's `E`, as for `wait()`; or an error if the time ran out, once every channel is closed (and empty, for a receive arm), or when the task's wait was cancelled
    wait_for(milliseconds: ulong): Result<E> {
        return this._wait(_async_sys_monotonic_milliseconds() + milliseconds);
    }

    ## Fires an arm if one is ready now, without waiting: takes a value if a
    ## channel has one waiting, or sends a send arm's value if its channel
    ## has room.
    ##
    ## @returns the arm's `E`, as for `wait()`; or an error if no arm is ready, or once every channel is closed (and empty, for a receive arm)
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

    # Looks at each arm once, starting at `_next`: the first that fires
    # (Ready), else Empty if any channel is still open, else Closed. A send
    # arm that fires leaves the select.
    _poll(): _Polled<E> {
        var count = _cases.count;
        var closed: ulong = 0;
        var i: ulong = 0;
        while (i < count) {
            var index = (_next + i) % count;
            var entry: _SelectCase<E> = _cases[index];
            match (entry._take()) {
                Ready(event) => {
                    if (entry._finished()) {
                        _cases.remove_at(index);
                        _next = count > 1 ? index % (count - 1) : 0;
                    } else {
                        _next = (index + 1) % count;
                    }
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
        if (_cases.count == 0) {
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
            if (woken == _SyncWake.Cancelled) {
                return Result<E>.err(Error("the task was cancelled"));
            }
            if (woken == _SyncWake.TimedOut) {
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
    _sleep(deadline: ulong): _SyncWake {
        var in_task = _async_in_task();
        var waiter = in_task ? _async_sync_waiter() : _SyncWaiter(_ThreadWake());
        var count = _cases.count;
        var joined: ulong = 0;
        var closed: ulong = 0;
        var ready = false;
        while (joined < count && !ready) {
            var entry: _SelectCase<E> = _cases[joined];
            var found = entry._join(waiter);
            if (found == _Joined.Ready) {
                ready = true;
            } else {
                if (found == _Joined.Closed) {
                    closed = closed + 1;
                }
                joined = joined + 1;
            }
        }
        var woken = _SyncWake.Woken;
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
