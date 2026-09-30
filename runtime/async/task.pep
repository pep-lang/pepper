## Tasks: functions that run concurrently on one thread, each on its own
## small stack, switching only where they wait.
##
## `run(body)` turns the calling thread into a worker and runs `body` as its
## first task. A task starts others with `Task<T>.spawn_local`, and gives
## the thread to the others whenever it waits: `sleep`, `yield_now`, and
## `Task.join`, and whenever a socket call would block. Nothing preempts a task, so a task that computes for a long
## time without waiting keeps every other task on its worker waiting too.
##
## A task is a green thread (a fiber): an ordinary function with its own
## stack, so code that waits looks the same as code that does not, and a
## function called in a task can wait without being marked in any way.

# Implementation notes.
#
# One `_Worker` per thread inside `run`: its ready queue, its timer heap,
# the task it is running, and a pool of idle fibers. The worker lives in
# `run`'s frame; `_async_worker_key` (a thread-local key whose value is a
# malloc'd slot holding one reference to it) lets code in tasks find it.
#
# Every fiber runs `_async_fiber_main`, a loop that runs whichever task the
# worker assigned it (`_current`) and then switches back to the scheduler.
# A fiber therefore outlives its task and is reused for the next one, which
# also means no fiber's entry function ever returns (a Windows fiber whose
# start routine returns ends its thread). The loop body calls a function
# that returns, so every reference a task's frame held is released before
# the fiber switches away for the last time.
#
# A task is parked (`_parked`) while it waits on a timer, a join, or a
# socket. Waking puts a parked task back on the ready queue once, however
# many things try to wake it; a woken task re-checks what it waited for. A
# timer carries the sequence number of the wait that set it, so a timer that
# outlives its wait (the task was woken some other way) wakes nothing.
#
# Sockets: the worker is the thread's `io._IoWaiter` (see io/wait.pep). A
# socket call that would block parks its task in `_wait_ready` until the
# worker's `_Driver` (driver.pep: epoll, kqueue, IOCP or poll, chosen when
# `run` starts) reports the socket ready. The driver watches a socket from
# the first time a task waits on it, and `_waits` maps it to the tasks
# waiting on it. When no task is ready the loop blocks in the driver until
# the next timer; while tasks run it polls the driver without blocking every
# `_POLL_INTERVAL` tasks, so waiting sockets are not starved.
#
# A timeout (`Deadline`) sets the task's `_deadline`, and every wait inside
# it also sets a timer for the deadline.

import io;
import "driver";
import "fiber_posix";
import "fiber_windows";
import "sys_posix";
import "sys_windows";

# How many tasks run between two non-blocking polls of the driver.
const _POLL_INTERVAL = 61;

## Why `Task.join` did not return the task's value.
export struct TaskError {
    ## A description of what went wrong.
    const message: String;
    # A timeout ended the wait, rather than cancellation.
    var _timed_out: bool;

    ## Creates a task error.
    ##
    ## @param message a description of what went wrong
    construct(message: String) {
        this.message = message;
    }

    ## Returns whether the task was cancelled, or the task waiting for it was.
    ##
    ## @returns true when cancellation ended the wait
    is_cancelled(): bool {
        return !this._timed_out;
    }

    ## Returns whether a `timeout` around the `join` expired before the task
    ## finished. The task itself carries on.
    ##
    ## @returns true when a timeout ended the wait
    is_timed_out(): bool {
        return this._timed_out;
    }
}

# The error `join` returns when a timeout expires.
_async_timed_out_error(): TaskError {
    var error = TaskError("the wait for the task timed out");
    error._timed_out = true;
    return error;
}

## Settings for `run_with`, built by chaining: `RuntimeOptions().stack_size(65536)`.
export struct RuntimeOptions {
    # Bytes of stack reserved for each task.
    var _stack_size: ulong;
    # The I/O backend asked for.
    var _backend: Backend;

    ## Creates the default options: 256 KiB of stack per task, and the
    ## system's best I/O backend.
    construct() {
        this._stack_size = 262144;
        this._backend = Backend.Automatic;
    }

    ## Sets which I/O backend the runtime waits on sockets with. The default,
    ## `Backend.Automatic`, picks the system's best (or the one the
    ## `PEPPER_IO_BACKEND` environment variable names).
    ##
    ## @param kind the backend
    ## @returns these options
    ## @note `run_with` panics if the system does not have the backend
    backend(kind: Backend): RuntimeOptions {
        this._backend = kind;
        return this;
    }

    ## Sets how much stack each task reserves. Only the pages a task touches
    ## use memory; the rest is address space. A task that uses more than this
    ## crashes the program, as a thread that overflows its stack does.
    ##
    ## @param bytes the stack size in bytes (rounded up to whole pages)
    ## @returns these options
    ## @panics if `bytes` is less than 16 KiB
    stack_size(bytes: ulong): RuntimeOptions {
        assert(bytes >= 16384, "RuntimeOptions.stack_size: less than 16 KiB");
        this._stack_size = bytes;
        return this;
    }
}

# What the scheduler knows about a task, whatever its result type.
struct _TaskCore {
    # A number unique within the worker, for identity checks.
    var _id: ulong;
    # Runs the task's body and stores its result; cleared once it has run.
    var _body: () => void;
    # The fiber the task runs on, once started.
    var _fiber: __ptr<void>;
    var _started: bool;
    var _finished: bool;
    var _cancelled: bool;
    # Waiting to be woken (sleeping or joining), and not on the ready queue.
    var _parked: bool;
    # The sequence number of the timer the task's wait set, or 0.
    var _wait_sequence: ulong;
    # When the innermost `timeout` around the running code expires (monotonic
    # milliseconds), or 0.
    var _deadline: ulong;
    # Tasks parked in `join` on this one.
    var _joiners: Array<_TaskCore>;
    # The task's position in the worker's `_tasks`.
    var _index: ulong;

    construct(id: ulong, body: () => void) {
        this._id = id;
        this._body = body;
        this._joiners = Array<_TaskCore>();
    }
}

# When to wake a waiting task.
struct _Timer {
    var _deadline: ulong;
    var _sequence: ulong;
    var _task: _TaskCore;

    construct(deadline: ulong, sequence: ulong, task: _TaskCore) {
        this._deadline = deadline;
        this._sequence = sequence;
        this._task = task;
    }
}

# The scheduler state of a thread inside `run`.
struct _Worker {
    # The thread's own context, which runs the scheduler loop.
    var _scheduler: __ptr<void>;
    # Tasks ready to run, first at `_ready_head`.
    var _ready: Array<_TaskCore>;
    var _ready_head: ulong;
    # Sleeping tasks: a binary min-heap on `_deadline`.
    var _timers: Array<_Timer>;
    var _timer_sequence: ulong;
    # Every task that has not finished, in no order.
    var _tasks: Array<_TaskCore>;
    var _next_id: ulong;
    # The running task, while one runs.
    var _current: _TaskCore;
    var _running: bool;
    # Fibers whose tasks finished, for the next tasks.
    var _idle: Array<__ptr<void>>;
    var _stack_size: ulong;
    # The I/O driver and the backend it is.
    var _driver: _Driver;
    var _backend: Backend;
    # Sockets the driver found ready in the last poll, and for what.
    var _ready_handles: Array<ulong>;
    var _ready_interests: Array<int>;
    # The tasks waiting on each registered socket.
    var _waits: HashMap<ulong, _SocketWaits>;
    # How many tasks are parked on sockets.
    var _io_waiting: ulong;
    # Tasks run since the driver was last polled.
    var _since_poll: ulong;

    construct(stack_size: ulong, backend: Backend) {
        this._scheduler = _async_fiber_thread_context();
        var (driver, chosen) = _async_open_driver(backend);
        this._driver = driver;
        this._backend = chosen;
        this._ready_handles = Array<ulong>();
        this._ready_interests = Array<int>();
        this._waits = HashMap<ulong, _SocketWaits>();
        this._ready = Array<_TaskCore>();
        this._timers = Array<_Timer>();
        this._tasks = Array<_TaskCore>();
        this._idle = Array<__ptr<void>>();
        this._stack_size = stack_size;
        this._next_id = 1;
        this._timer_sequence = 1;
    }

    _spawn(body: () => void): _TaskCore {
        var core = _TaskCore(this._next_id, body);
        this._next_id = this._next_id + 1;
        core._index = this._tasks.count();
        this._tasks.append(core);
        this._ready.append(core);
        return core;
    }

    # Puts a parked task back on the ready queue.
    _wake(core: _TaskCore) {
        if (core._parked) {
            core._parked = false;
            this._ready.append(core);
        }
    }

    _has_ready(): bool {
        return this._ready_head < this._ready.count();
    }

    _pop_ready(): _TaskCore {
        var core = this._ready[this._ready_head];
        this._ready_head = this._ready_head + 1;
        if (this._ready_head == this._ready.count()) {
            this._ready.clear();
            this._ready_head = 0;
        }
        return core;
    }

    _add_timer(timer: _Timer) {
        this._timers.append(timer);
        var i = this._timers.count() - 1;
        while (i > 0) {
            var parent = (i - 1) / 2;
            if (this._timers[parent]._deadline <= this._timers[i]._deadline) {
                return;
            }
            this._timers.swap(parent, i);
            i = parent;
        }
    }

    _remove_first_timer(): _Timer {
        var first = this._timers[0];
        var last = this._timers.pop();
        var count = this._timers.count();
        if (count == 0) {
            return first;
        }
        this._timers[0] = last;
        var i: ulong = 0;
        while (true) {
            var smallest = i;
            var left = 2 * i + 1;
            var right = left + 1;
            if (left < count) {
                if (this._timers[left]._deadline < this._timers[smallest]._deadline) {
                    smallest = left;
                }
            }
            if (right < count) {
                if (this._timers[right]._deadline < this._timers[smallest]._deadline) {
                    smallest = right;
                }
            }
            if (smallest == i) {
                return first;
            }
            this._timers.swap(i, smallest);
            i = smallest;
        }
        return first;
    }

    # Sets a timer that wakes `core` at `deadline` unless its current wait
    # ends first.
    _set_timer(core: _TaskCore, deadline: ulong) {
        var sequence = this._timer_sequence;
        this._timer_sequence = sequence + 1;
        core._wait_sequence = sequence;
        this._add_timer(_Timer(deadline, sequence, core));
    }

    # Parks the running task until something wakes it, or its deadline
    # passes.
    _park() {
        var me = this._current;
        if (me._deadline != 0) {
            this._set_timer(me, me._deadline);
        }
        me._parked = true;
        _async_suspend(this);
        me._wait_sequence = 0;
    }

    # Wakes every task whose timer has expired.
    _fire_timers() {
        var now = _async_sys_monotonic_milliseconds();
        while (this._timers.count() > 0) {
            if (this._timers[0]._deadline > now) {
                return;
            }
            var timer = this._remove_first_timer();
            if (timer._task._wait_sequence == timer._sequence) {
                timer._task._wait_sequence = 0;
                this._wake(timer._task);
            }
        }
    }

    # Waits up to `timeout` milliseconds (forever when negative) for socket
    # events, and wakes the tasks they let continue.
    _poll(timeout: long) {
        this._since_poll = 0;
        this._driver._poll(this._waits, timeout, this._ready_handles, this._ready_interests);
        var i: ulong = 0;
        while (i < this._ready_handles.count()) {
            var key = this._ready_handles[i];
            if (this._waits.contains(key)) {
                var waits = this._waits.get(key);
                var interest = this._ready_interests[i];
                if ((interest & io._IO_READABLE) != 0) {
                    this._wake_all(waits._readers);
                }
                if ((interest & io._IO_WRITABLE) != 0) {
                    this._wake_all(waits._writers);
                }
            }
            i = i + 1;
        }
        this._ready_handles.clear();
        this._ready_interests.clear();
    }

    # Wakes every task in `tasks` and empties it.
    _wake_all(tasks: Array<_TaskCore>) {
        for (var core in tasks) {
            this._wake(core);
        }
        tasks.clear();
    }

    # Runs one ready task until it waits or finishes.
    _run_one() {
        var core = this._pop_ready();
        if (core._finished) {
            return;
        }
        if (!core._started) {
            core._started = true;
            if (this._idle.count() > 0) {
                core._fiber = this._idle.pop();
            } else {
                core._fiber = _async_fiber_create(this._stack_size, __function_pointer(_async_fiber_main));
                assert(core._fiber != __null, "async: out of memory for a task's stack");
            }
        }
        this._current = core;
        this._running = true;
        _async_fiber_switch(this._scheduler, core._fiber);
        this._running = false;
        this._current = __default<_TaskCore>();
        if (core._finished) {
            this._idle.append(core._fiber);
            core._fiber = __null;
            this._retire(core);
        }
    }

    # Removes a finished task from `_tasks`.
    _retire(core: _TaskCore) {
        var last = this._tasks.pop();
        if (last._id != core._id) {
            this._tasks[core._index] = last;
            last._index = core._index;
        }
    }

    # Runs tasks until `until` finishes; then cancels the rest and runs them
    # until they finish too.
    _run_until(until: _TaskCore) {
        var cancelled_rest = false;
        while (true) {
            if (until._finished) {
                if (this._tasks.count() == 0) {
                    return;
                }
                if (!cancelled_rest) {
                    cancelled_rest = true;
                    for (var core in this._tasks) {
                        _async_cancel(this, core);
                    }
                }
            }
            this._fire_timers();
            if (this._has_ready()) {
                this._run_one();
                this._since_poll = this._since_poll + 1;
                if (this._io_waiting > 0 && this._since_poll >= _POLL_INTERVAL) {
                    this._poll(0);
                }
            } else if (this._timers.count() > 0 || this._io_waiting > 0) {
                var timeout: long = -1;
                if (this._timers.count() > 0) {
                    var now = _async_sys_monotonic_milliseconds();
                    var deadline = this._timers[0]._deadline;
                    timeout = 0;
                    if (deadline > now) {
                        timeout = (deadline - now) as long;
                    }
                }
                if (this._io_waiting > 0) {
                    this._poll(timeout);
                } else if (timeout > 0) {
                    _async_sys_sleep(timeout as ulong);
                }
            } else {
                panic("async.run: every task is waiting for another task and none can continue");
            }
        }
    }

    # Frees the fibers, the driver and the thread context.
    _close() {
        for (var fiber in this._idle) {
            _async_fiber_destroy(fiber);
        }
        this._idle.clear();
        this._waits.clear();
        this._driver._close();
        _async_fiber_release_thread_context(this._scheduler);
    }
}

# The tasks waiting on one socket.
export struct _SocketWaits {
    var _readers: Array<_TaskCore>;
    var _writers: Array<_TaskCore>;

    construct() {
        this._readers = Array<_TaskCore>();
        this._writers = Array<_TaskCore>();
    }
}

# Removes `core` from `tasks`, if it is there.
_async_remove_task(tasks: Array<_TaskCore>, core: _TaskCore) {
    var i: ulong = 0;
    while (i < tasks.count()) {
        if (tasks[i]._id == core._id) {
            tasks.remove_at(i);
            return;
        }
        i = i + 1;
    }
}

# How the sockets in io wait (see io/wait.pep).
extend _Worker with io._IoWaiter {
    _in_task(): bool {
        return this._running;
    }

    _wait_ready(handle: io.SocketHandle, interest: int): int {
        var me = this._current;
        if (me._cancelled) {
            return io._IO_WAIT_CANCELLED;
        }
        if (me._deadline != 0 && _async_sys_monotonic_milliseconds() >= me._deadline) {
            return io._IO_WAIT_TIMED_OUT;
        }
        var key = handle as ulong;
        if (!this._waits.contains(key)) {
            if (!this._driver._watch(handle)) {
                return io._IO_WAIT_UNWATCHED;
            }
            this._waits.insert(key, _SocketWaits());
        }
        var waits = this._waits.get(key);
        var queue = waits._readers;
        if (interest == io._IO_WRITABLE) {
            queue = waits._writers;
        }
        if (!this._driver._want(handle, interest)) {
            return io._IO_WAIT_UNWATCHED;
        }
        queue.append(me);
        this._io_waiting = this._io_waiting + 1;
        this._park();
        this._io_waiting = this._io_waiting - 1;
        _async_remove_task(queue, me);
        if (me._cancelled) {
            return io._IO_WAIT_CANCELLED;
        }
        if (me._deadline != 0 && _async_sys_monotonic_milliseconds() >= me._deadline) {
            return io._IO_WAIT_TIMED_OUT;
        }
        return io._IO_WAIT_READY;
    }

    _forget(handle: io.SocketHandle) {
        this._driver._forget(handle);
        var key = handle as ulong;
        if (this._waits.contains(key)) {
            var waits = this._waits.get(key);
            this._wake_all(waits._readers);
            this._wake_all(waits._writers);
            this._waits.remove(key);
        }
    }
}

# The thread-local key whose value is the current thread's worker: a
# malloc'd slot holding one reference to it, or null outside `run`.
const _async_worker_key = _async_fiber_key_create();

export _async_on_worker(): bool {
    return _async_fiber_key_get(_async_worker_key) != __null;
}

export _async_worker(): _Worker {
    __ptr<_Worker> slot = _async_fiber_key_get(_async_worker_key);
    assert(slot != __null, "async: not inside async.run");
    return slot[0];
}

# Marks `core` cancelled and wakes it if it waits.
_async_cancel(worker: _Worker, core: _TaskCore) {
    if (core._finished) {
        return;
    }
    core._cancelled = true;
    core._wait_sequence = 0;
    worker._wake(core);
}

# Switches from the running task to the scheduler; returns when the task
# is resumed.
_async_suspend(worker: _Worker) {
    _async_fiber_switch(worker._current._fiber, worker._scheduler);
}

# Runs the task the worker assigned to this fiber, and marks it finished.
_async_run_current() {
    var worker = _async_worker();
    var core = worker._current;
    var body = core._body;
    core._body = () => {};
    body();
    core._finished = true;
    for (var joiner in core._joiners) {
        worker._wake(joiner);
    }
    core._joiners.clear();
}

# The entry point of every fiber (see the notes at the top of this file).
_async_fiber_main(unused: __ptr<void>) {
    while (true) {
        _async_run_current();
        _async_return_to_scheduler();
    }
}

# Switches to the scheduler for good, holding no reference in this frame.
_async_return_to_scheduler() {
    _async_fiber_switch(_async_current_fiber(), _async_scheduler_context());
}

_async_current_fiber(): __ptr<void> {
    return _async_worker()._current._fiber;
}

_async_scheduler_context(): __ptr<void> {
    return _async_worker()._scheduler;
}

## A task started with `spawn_local`, and the value its body returns.
##
## @typeParam T the type of the body's result; `void` when there is none
## @example
##     import async;
##
##     main(): int {
##         async.run(() => {
##             var a = async.Task<int>.spawn_local(() => { return 20; });
##             var b = async.Task<int>.spawn_local(() => { return 22; });
##             print(a.join().value() + b.join().value());   # 42
##         });
##         return 0;
##     }
export struct Task<T> {
    # What the scheduler knows about the task (set once, by `spawn_local`).
    var _core: _TaskCore;
    # The body's result, once it has finished.
    var _value: T;

    ## Wraps the scheduler's record of a task. Only `spawn_local` has one;
    ## start tasks with `spawn_local`.
    ##
    ## @param core the scheduler's record of the task
    construct(core: _TaskCore) {
        this._core = core;
    }

    ## Starts a task on the current worker that runs `body`. It runs the
    ## next time the running task waits, and may use anything the running
    ## task can, since it stays on this thread.
    ##
    ## @param body the task's code
    ## @returns the task
    ## @panics outside `run`
    static spawn_local(body: () => T): Task<T> {
        assert(_async_on_worker(), "Task.spawn_local: not inside async.run");
        var worker = _async_worker();
        var task = Task<T>(__default<_TaskCore>());
        var core = worker._spawn(() => {
            task._run(body);
        });
        task._core = core;
        return task;
    }

    _run(body: () => T) {
        this._value = body();
    }

    ## Waits for the task to finish and returns its value. Other tasks run
    ## meanwhile.
    ##
    ## @returns the body's result, or a `TaskError` if the task was cancelled
    ##   before it finished, the task calling `join` was cancelled while it
    ##   waited, or a `timeout` around the `join` expired first
    ## @panics if a task joins itself, or if called outside `run` on a task
    ##   that has not finished
    join(): Result<T, TaskError> {
        if (!this._core._finished) {
            assert(_async_on_worker(), "Task.join: not inside async.run");
            var worker = _async_worker();
            var me = worker._current;
            assert(worker._running, "Task.join: not called from a task");
            assert(me._id != this._core._id, "Task.join: a task cannot join itself");
            this._core._joiners.append(me);
            while (!this._core._finished) {
                if (me._cancelled) {
                    _async_remove_task(this._core._joiners, me);
                    return Result<T, TaskError>.err(TaskError("the waiting task was cancelled"));
                }
                if (me._deadline != 0 && _async_sys_monotonic_milliseconds() >= me._deadline) {
                    _async_remove_task(this._core._joiners, me);
                    return Result<T, TaskError>.err(_async_timed_out_error());
                }
                worker._park();
            }
        }
        if (this._core._cancelled) {
            return Result<T, TaskError>.err(TaskError("the task was cancelled"));
        }
        return Result<T, TaskError>.ok(this._value);
    }

    ## Asks the task to stop: from now on `is_cancelled()` is true inside it,
    ## `sleep` returns at once, and its `join` calls fail. A task is never
    ## stopped by force; it finishes when its body returns.
    cancel() {
        if (_async_on_worker()) {
            _async_cancel(_async_worker(), this._core);
        } else {
            this._core._cancelled = true;
        }
    }

    ## Returns whether the task's body has returned.
    ##
    ## @returns true once the task has finished
    is_finished(): bool {
        return this._core._finished;
    }
}

## Runs `body` as the first task of a new runtime on the calling thread, and
## returns once `body` has returned and every task it started has finished.
## When `body` returns, the tasks still running are cancelled (see
## `Task.cancel`), and `run` waits for them to finish.
##
## @param body the first task
## @panics if called inside a task, or if every remaining task is waiting on
##   another and none can continue
## @example
##     import async;
##
##     main(): int {
##         async.run(() => {
##             var t = async.Task<void>.spawn_local(() => {
##                 async.sleep(10);
##                 print("second");
##             });
##             print("first");
##             t.join();
##         });
##         return 0;
##     }
export run(body: () => void) {
    run_with(RuntimeOptions(), body);
}

## Runs `body` like `run`, with the given settings.
##
## @param options the runtime's settings
## @param body the first task
## @panics if called inside a task, if every remaining task is waiting on
##   another and none can continue, or if the system does not have the
##   backend `options` asks for
export run_with(options: RuntimeOptions, body: () => void) {
    assert(!_async_on_worker(), "async.run: already inside async.run");
    var worker = _Worker(options._stack_size, options._backend);
    __ptr<_Worker> slot = _pep_malloc(8);
    slot[0] = worker;
    _async_fiber_key_set(_async_worker_key, slot);
    io._io_set_waiter(worker);
    var first = worker._spawn(body);
    worker._run_until(first);
    io._io_clear_waiter();
    _async_fiber_key_set(_async_worker_key, __null);
    slot[0] = __default<_Worker>();
    _pep_free(slot);
    worker._close();
}

## Lets every other ready task run before the calling task continues. Does
## nothing outside a task.
export yield_now() {
    if (!_async_on_worker()) {
        return;
    }
    var worker = _async_worker();
    if (!worker._running) {
        return;
    }
    worker._ready.append(worker._current);
    _async_suspend(worker);
}

## Waits at least `milliseconds`. In a task, other tasks run meanwhile, and
## a cancelled task returns at once, as does one whose `timeout` expires
## first; outside a task, the thread sleeps.
##
## @param milliseconds how long to wait
export sleep(milliseconds: ulong) {
    if (!_async_on_worker()) {
        _async_sys_sleep(milliseconds);
        return;
    }
    var worker = _async_worker();
    if (!worker._running) {
        _async_sys_sleep(milliseconds);
        return;
    }
    var me = worker._current;
    if (me._cancelled) {
        return;
    }
    var until = _async_sys_monotonic_milliseconds() + milliseconds;
    if (me._deadline != 0 && me._deadline < until) {
        until = me._deadline;
    }
    worker._set_timer(me, until);
    me._parked = true;
    _async_suspend(worker);
    me._wait_sequence = 0;
}

## Returns whether the running task has been cancelled (see `Task.cancel`),
## so a long computation can stop early. False outside a task.
##
## @returns true when the running task was asked to stop
export is_cancelled(): bool {
    if (!_async_on_worker()) {
        return false;
    }
    var worker = _async_worker();
    if (!worker._running) {
        return false;
    }
    return worker._current._cancelled;
}

## A time limit on the waits inside a `with` block, made by `timeout`.
##
## While the block runs, a socket call that has to wait fails with an
## `IoError` for which `is_timed_out()` holds once the limit passes,
## `Task.join` fails with a `TaskError` for which `is_timed_out()` holds,
## and `sleep` returns early. Code that does not wait is never interrupted.
## Timeouts nest: an inner one cannot extend an outer one.
export struct Deadline {
    # When the limit passes, in monotonic milliseconds.
    var _at: ulong;
    # The task the block runs in, and its deadline before the block.
    var _core: _TaskCore;
    var _previous: ulong;
    var _entered: bool;

    ## Creates a limit `milliseconds` from now. Use `timeout` instead.
    ##
    ## @param milliseconds how long from now the limit passes
    construct(milliseconds: ulong) {
        this._at = _async_sys_monotonic_milliseconds() + milliseconds;
    }

    destruct {
        this.exit();
    }

    ## Starts applying the limit to the running task; a `with` block calls
    ## it.
    ##
    ## @returns this deadline
    ## @panics outside a task
    enter(): Deadline {
        assert(_async_on_worker() && _async_worker()._running, "async.timeout: not called from a task");
        var core = _async_worker()._current;
        this._core = core;
        this._previous = core._deadline;
        if (core._deadline == 0 || this._at < core._deadline) {
            core._deadline = this._at;
        }
        this._entered = true;
        return this;
    }

    ## Stops applying the limit; the end of the `with` block calls it.
    exit() {
        if (this._entered) {
            this._entered = false;
            this._core._deadline = this._previous;
        }
    }

    ## Returns whether the limit has passed.
    ##
    ## @returns true once the time is up
    is_expired(): bool {
        return _async_sys_monotonic_milliseconds() >= this._at;
    }
}

extend Deadline with Scoped<Deadline> {}

## Returns a time limit for a `with` block: the waits inside it give up
## `milliseconds` from now (see `Deadline`).
##
## @param milliseconds how long the block's waits may take in all
## @returns the limit, for a `with` header
## @example
##     import async;
##     import io;
##
##     main(): int {
##         async.run(() => {
##             var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
##             with (var deadline = async.timeout(50)) {
##                 var accepted = listener.accept();   # nobody connects
##                 assert(accepted.error().is_timed_out(), "timed out");
##             }
##         });
##         return 0;
##     }
export timeout(milliseconds: ulong): Deadline {
    return Deadline(milliseconds);
}

## Returns the I/O backend the running runtime waits on sockets with (see
## `RuntimeOptions.backend`).
##
## @returns the backend; never `Backend.Automatic`
## @panics outside `run`
export current_backend(): Backend {
    assert(_async_on_worker(), "async.current_backend: not inside async.run");
    return _async_worker()._backend;
}
