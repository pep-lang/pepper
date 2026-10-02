## Tasks: functions that run concurrently on a few worker threads, each on
## its own small stack, switching only where they wait.
##
## `run(body)` turns the calling thread into the first worker, starts the
## others, and runs `body` as the first task. A task starts others with
## `Task<T>.spawn_local` (on its own worker) or `spawn` (on any worker), and
## gives its worker to the other tasks there whenever it waits: `sleep`,
## `yield_now`, and `Task.join`, whenever a socket call would block, and
## whenever it waits on a `Mutex`, `Condition` or `Channel`. Nothing
## preempts a task, so a task that computes for a long time without waiting
## keeps every other task on its worker waiting too.
##
## A task is a green thread (a fiber): an ordinary function with its own
## stack, so code that waits looks the same as code that does not, and a
## function called in a task can wait without being marked in any way.

# Implementation notes. (What the workers of one `run` share is described
# in workers.pep.)
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
# A task is parked (`_parked`) while it waits on a timer, a join, a
# socket, or a sync object (sync_wait.pep). Waking puts a parked task back
# on the ready queue once, however many things try to wake it; a woken task
# re-checks what it waited for. A timer carries the sequence number of the
# wait that set it, so a timer that outlives its wait (the task was woken
# some other way) wakes nothing.
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
import os;
import "atomic";
import "cpus";
import "driver";
import "fiber_posix";
import "fiber_wasi";
import "fiber_windows";
import "sync_wait";
import "sys_posix";
import "sys_wasi";
import "sys_windows";
import "thread";
import "workers";

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
    # How many workers, or 0 for one per logical CPU.
    var _workers: ulong;
    # The most threads `run_blocking` may start.
    var _blocking_threads: ulong;

    ## Creates the default options: one worker per logical CPU, 256 KiB of
    ## stack per task, the system's best I/O backend, and up to 64 threads
    ## for `run_blocking`.
    construct() {
        this._stack_size = 262144;
        this._backend = Backend.Automatic;
        this._workers = 0;
        this._blocking_threads = 64;
    }

    ## Sets how many workers (threads that run tasks) the runtime has. The
    ## thread that calls `run_with` is the first; the rest are new threads.
    ## Tasks from `spawn_local` run on the worker that started them; tasks
    ## from `spawn` run on whichever worker is free. The default is
    ## `logical_cpus()`.
    ##
    ## @param count the number of workers
    ## @returns these options
    ## @panics if `count` is 0
    workers(count: ulong): RuntimeOptions {
        assert(count > 0, "RuntimeOptions.workers: 0 workers");
        this._workers = count;
        return this;
    }

    ## Sets how many threads `run_blocking` may start. The runtime starts
    ## them one at a time, when a blocking call finds none idle, and keeps
    ## them until `run_with` returns. Once there are `count`, further calls
    ## wait for one of them to be free. The default is 64.
    ##
    ## @param count the most threads for blocking calls
    ## @returns these options
    ## @panics if `count` is 0
    blocking_threads(count: ulong): RuntimeOptions {
        assert(count > 0, "RuntimeOptions.blocking_threads: 0 threads");
        this._blocking_threads = count;
        return this;
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
    # For a task from `spawn`: what the workers share about it. The worker
    # that runs it has a core for it, and so does the worker that spawned
    # it: a stand-in (`_proxy`) that never runs, and finishes when the
    # other worker reports the task finished.
    var _shared: _SharedTask?;
    # The `_cancelled` flag of `_shared`, or null. `_is_cancelled` reads it
    # on every socket wait; reading it from `_shared` would copy the
    # `[Shared]` task out of the optional, two atomic count steps.
    var _shared_cancelled: Atomic<int>;
    var _proxy: bool;
    # A stand-in's step when its task finishes: takes the result.
    var _on_complete: () => void;
    # The id that marks the task as a `Mutex`'s holder, or 0 until it first
    # takes one (see `_async_holder_id`).
    var _token: ulong;
    # The task's `TaskLocal` values, released when its body returns.
    var _locals: Array<_TaskLocalValue>;

    construct(id: ulong, body: () => void) {
        this._id = id;
        this._body = body;
        this._joiners = Array<_TaskCore>();
        this._locals = Array<_TaskLocalValue>();
    }

    # Releases the task's `TaskLocal` values, newest first. A value's
    # destructor may store another, which is released in turn.
    _release_locals() {
        while (this._locals.count > 0) {
            var local = this._locals.pop();
            local._release();
        }
    }

    # Whether the task was cancelled, here or (for a task from `spawn`) on
    # another worker.
    _is_cancelled(): bool {
        if (!this._cancelled && this._shared_cancelled !== __null) {
            if (this._shared_cancelled.load() != 0) {
                this._cancelled = true;
            }
        }
        return this._cancelled;
    }
}

# One task's value of a `TaskLocal` (task_local.pep): the variable's id,
# the malloc'd slot holding the value, and how to release the slot.
struct _TaskLocalValue {
    var _id: ulong;
    var _slot: __ptr<void>;
    var _release: () => void;

    construct(id: ulong, slot: __ptr<void>, release: () => void) {
        this._id = id;
        this._slot = slot;
        this._release = release;
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
    # Which worker this is (0 for the thread that called `run`), what the
    # workers share, and this worker's inbox.
    var _index: ulong;
    var _runtime: _Runtime;
    var _inbox: _Inbox;
    # Stand-ins for tasks spawned here that run elsewhere, and tasks from
    # `spawn` that run here: the tasks messages can name, by id.
    var _remote: HashMap<ulong, _TaskCore>;
    # Set once this worker has seen the runtime stopping and cancelled its
    # tasks.
    var _stopping: bool;
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
    var _ready_sockets: Array<(handle: ulong, interest: int)>;
    # The tasks waiting on each registered socket.
    var _waits: HashMap<ulong, _SocketWaits>;
    # How many tasks are parked on sockets or file transfers.
    var _io_waiting: ulong;
    # Tasks parked on a file transfer the driver runs, by id, and the
    # results of finished transfers not yet taken.
    var _file_waits: HashMap<ulong, _TaskCore>;
    var _file_results: HashMap<ulong, long>;
    var _finished_files: Array<(task: ulong, result: long)>;
    # Tasks parked on a `Mutex`, `Condition` or `Channel`, by id (see
    # sync_wait.pep).
    var _sync_waits: HashMap<ulong, _TaskCore>;
    # Tasks run since the driver was last polled.
    var _since_poll: ulong;
    # The `run_blocking` threads this worker started, joined when the
    # runtime ends.
    var _pool: Array<Thread>;

    construct(runtime: _Runtime, index: ulong, stack_size: ulong, backend: Backend) {
        this._index = index;
        this._runtime = runtime;
        this._remote = HashMap<ulong, _TaskCore>();
        this._scheduler = _async_fiber_thread_context();
        var (driver, chosen) = _async_open_driver(backend);
        this._driver = driver;
        this._backend = chosen;
        this._inbox = _Inbox(driver._doorbell());
        this._ready_sockets = Array<(handle: ulong, interest: int)>();
        this._waits = HashMap<ulong, _SocketWaits>();
        this._sync_waits = HashMap<ulong, _TaskCore>();
        this._file_waits = HashMap<ulong, _TaskCore>();
        this._file_results = HashMap<ulong, long>();
        this._finished_files = Array<(task: ulong, result: long)>();
        this._ready = Array<_TaskCore>();
        this._timers = Array<_Timer>();
        this._tasks = Array<_TaskCore>();
        this._idle = Array<__ptr<void>>();
        this._pool = Array<Thread>();
        this._stack_size = stack_size;
        this._next_id = 1;
        this._timer_sequence = 1;
    }

    _spawn(body: () => void): _TaskCore {
        var core = _TaskCore(this._next_id, body);
        this._next_id = this._next_id + 1;
        core._index = this._tasks.count;
        this._tasks.append(core);
        this._ready.append(core);
        return core;
    }

    # A stand-in for a task spawned here that runs on any worker.
    _new_proxy(): _TaskCore {
        var core = _TaskCore(this._next_id, () => {});
        this._next_id = this._next_id + 1;
        core._proxy = true;
        core._finished = false;
        core._on_complete = () => {};
        this._remote.insert(core._id, core);
        return core;
    }

    # Hands a body from `run_blocking` to the pool, starting a pool thread
    # when none is idle.
    _start_blocking(job: _SharedTask) {
        var runtime = this._runtime;
        if (runtime._block(job)) {
            this._pool.append(Thread.spawn(() => {
                _async_blocking_main(runtime);
            }, "async blocking"));
        }
    }

    # Takes the next task pinned to this worker, or else the next task from
    # `spawn` off the shared queue, and makes it ready here; false if there
    # is none.
    _take_shared(): bool {
        var next = this._inbox._pinned._try_take();
        if (!next.0) {
            next = this._runtime._queue._try_take();
        }
        if (!next.0) {
            return false;
        }
        var shared = next.1;
        var core = this._spawn(() => {
            shared._body();
        });
        core._shared = Optional<_SharedTask>.Value(shared);
        core._shared_cancelled = shared._cancelled;
        this._remote.insert(core._id, core);
        shared._runner_id.store(core._id);
        shared._runner_worker.store(this._index + 1);
        if (this._stopping) {
            core._cancelled = true;
        }
        return true;
    }

    # A task from `spawn` that ran here has finished: tells the worker that
    # spawned it.
    _finish_shared(core: _TaskCore) {
        this._remote.remove(core._id);
        var shared = core._shared.value();
        this._runtime._inbox(shared._owner)._send(shared._proxy, _Message.Complete);
    }

    # Handles the messages other workers sent.
    _receive() {
        while (true) {
            var (found, message) = this._inbox._messages._try_take();
            if (!found) {
                return;
            }
            var (id, kind) = _async_unpack_message(message);
            match (kind) {
                Wake => {
                    if (this._sync_waits.contains(id)) {
                        this._wake(this._sync_waits.get(id));
                    }
                }
                Complete => {
                    if (this._remote.contains(id)) {
                        var core = this._remote.get(id);
                        this._remote.remove(id);
                        var complete = core._on_complete;
                        core._on_complete = () => {};
                        complete();
                        core._finished = true;
                        this._wake_all(core._joiners);
                    }
                }
                Cancel => {
                    if (this._remote.contains(id)) {
                        _async_cancel(this, this._remote.get(id));
                    }
                }
            }
        }
    }

    # Cancels every task here, once the runtime is stopping.
    _stop() {
        this._stopping = true;
        for (var core in this._tasks) {
            _async_cancel(this, core);
        }
    }

    # Waits in the driver up to `timeout` milliseconds (forever when
    # negative), unless something arrived meanwhile (see workers.pep).
    _sleep(timeout: long) {
        var wait = timeout;
        this._inbox._sleeping.store(1);
        this._inbox._notified.store(0);
        var pending = this._inbox._messages.count + this._inbox._pinned.count + this._runtime._queue.count;
        if (pending > 0) {
            wait = 0;
        }
        if (!this._stopping && this._runtime._stopping.load() != 0) {
            wait = 0;
        }
        this._poll(wait);
        this._inbox._sleeping.store(0);
    }

    # Puts a parked task back on the ready queue.
    _wake(core: _TaskCore) {
        if (core._parked) {
            core._parked = false;
            this._ready.append(core);
        }
    }

    _has_ready(): bool {
        return this._ready_head < this._ready.count;
    }

    _pop_ready(): _TaskCore {
        var core = this._ready[this._ready_head];
        this._ready_head = this._ready_head + 1;
        if (this._ready_head == this._ready.count) {
            this._ready.clear();
            this._ready_head = 0;
        }
        return core;
    }

    _add_timer(timer: _Timer) {
        this._timers.append(timer);
        var i = this._timers.count - 1;
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
        var count = this._timers.count;
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
        # Every scheduler pass comes here; with no timers, skip the clock
        # read (a system call and an allocation on POSIX).
        if (this._timers.count == 0) {
            return;
        }
        var now = _async_sys_monotonic_milliseconds();
        while (this._timers.count > 0) {
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
        this._driver._poll(this._waits, timeout, this._ready_sockets);
        var i: ulong = 0;
        while (i < this._ready_sockets.count) {
            var (key, interest) = this._ready_sockets[i];
            if (this._waits.contains(key)) {
                var waits = this._waits.get(key);
                if ((interest & io._IO_READABLE) != 0) {
                    this._wake_all(waits._readers);
                }
                if ((interest & io._IO_WRITABLE) != 0) {
                    this._wake_all(waits._writers);
                }
            }
            i = i + 1;
        }
        this._ready_sockets.clear();
        this._driver._finished_files(this._finished_files);
        i = 0;
        while (i < this._finished_files.count) {
            var (task, result) = this._finished_files[i];
            this._file_results.insert(task, result);
            if (this._file_waits.contains(task)) {
                this._wake(this._file_waits.get(task));
            }
            i = i + 1;
        }
        this._finished_files.clear();
    }

    # Wakes every task in `tasks` and empties it. An index loop: a `for`
    # would allocate an iterator on every call, and the list is usually
    # empty.
    _wake_all(tasks: Array<_TaskCore>) {
        ulong index = 0;
        while (index < tasks.count) {
            this._wake(tasks[index]);
            index = index + 1;
        }
        tasks.clear();
    }

    # Wakes the tasks waiting on `handle` and forgets them.
    _drop_waits(handle: io.SocketHandle) {
        var key = handle as ulong;
        if (this._waits.contains(key)) {
            var waits = this._waits.get(key);
            this._wake_all(waits._readers);
            this._wake_all(waits._writers);
            this._waits.remove(key);
        }
    }

    # Runs one ready task until it waits or finishes.
    _run_one() {
        var core = this._pop_ready();
        if (core._finished) {
            return;
        }
        if (!core._started) {
            core._started = true;
            if (this._idle.count > 0) {
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
            if (core._shared.is_value()) {
                this._finish_shared(core);
            }
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

    # Runs tasks until the runtime stops (see workers.pep) and none are
    # left here. On the first worker, `first` is the first task, whose end
    # stops the runtime.
    _run(first: _TaskCore?) {
        while (true) {
            if (!this._stopping) {
                if (first.is_value() && first.value()._finished) {
                    this._runtime._stop();
                }
                if (this._runtime._stopping.load() != 0) {
                    this._stop();
                }
            }
            if (this._stopping && this._tasks.count == 0 && this._remote.count == 0) {
                if (!this._take_shared()) {
                    return;
                }
            }
            this._fire_timers();
            if (this._has_ready()) {
                this._run_one();
                this._since_poll = this._since_poll + 1;
                if (this._since_poll >= _POLL_INTERVAL) {
                    this._receive();
                    this._take_shared();
                    this._poll(0);
                }
                continue;
            }
            this._receive();
            if (this._has_ready() || this._take_shared()) {
                continue;
            }
            if (this._stopping && this._tasks.count == 0 && this._remote.count == 0) {
                continue;
            }
            # With no tasks here, every timer left is stale.
            var timeout: long = -1;
            if (this._timers.count > 0 && this._tasks.count > 0) {
                var now = _async_sys_monotonic_milliseconds();
                var deadline = this._timers[0]._deadline;
                timeout = 0;
                if (deadline > now) {
                    timeout = (deadline - now) as long;
                }
            } else if (this._tasks.count > 0
                && this._io_waiting == 0
                && this._remote.count == 0
                && this._sync_waits.count == 0) {
                panic("async.run: every task is waiting for another task and none can continue");
            }
            this._sleep(timeout);
        }
    }

    # Frees the fibers, the driver and the thread context. Every worker has
    # stopped by now (see `_Runtime._leave`).
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
    while (i < tasks.count) {
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

    _wait_ready(handle: io.SocketHandle, interest: int): io._IoWait {
        var me = this._current;
        if (me._is_cancelled()) {
            return io._IoWait.Cancelled;
        }
        if (me._deadline != 0 && _async_sys_monotonic_milliseconds() >= me._deadline) {
            return io._IoWait.TimedOut;
        }
        var key = handle as ulong;
        if (!this._waits.contains(key)) {
            if (!this._driver._watch(handle)) {
                return io._IoWait.Unwatched;
            }
            this._waits.insert(key, _SocketWaits());
        }
        var waits = this._waits.get(key);
        var queue = waits._readers;
        if (interest == io._IO_WRITABLE) {
            queue = waits._writers;
        }
        if (!this._driver._want(handle, interest)) {
            return io._IoWait.Unwatched;
        }
        queue.append(me);
        this._io_waiting = this._io_waiting + 1;
        this._park();
        this._io_waiting = this._io_waiting - 1;
        _async_remove_task(queue, me);
        if (me._is_cancelled()) {
            return io._IoWait.Cancelled;
        }
        if (me._deadline != 0 && _async_sys_monotonic_milliseconds() >= me._deadline) {
            return io._IoWait.TimedOut;
        }
        return io._IoWait.Ready;
    }

    _forget(handle: io.SocketHandle) {
        this._driver._forget(handle);
        this._drop_waits(handle);
    }

    _release(handle: io.SocketHandle) {
        this._driver._release(handle);
        this._drop_waits(handle);
    }

    _release_idle(handle: io.SocketHandle) {
        var key = handle as ulong;
        if (this._waits.contains(key)) {
            var waits = this._waits.get(key);
            if (waits._readers.count == 0 && waits._writers.count == 0) {
                this._driver._release(handle);
                this._waits.remove(key);
            }
        }
    }

    _file_transfer(transfer: io._FileTransfer): long {
        var me = this._current;
        var descriptor = _async_file_descriptor(transfer._handle);
        if (!this._driver._start_file(descriptor, transfer._address(), transfer._count, transfer._write, me._id)) {
            return run_blocking<long>(() => {
                return transfer._run();
            });
        }
        # Neither a cancel nor a deadline ends the wait: the kernel is using
        # `buffer`.
        var deadline = me._deadline;
        me._deadline = 0;
        this._file_waits.insert(me._id, me);
        this._io_waiting = this._io_waiting + 1;
        while (!this._file_results.contains(me._id)) {
            this._park();
        }
        this._io_waiting = this._io_waiting - 1;
        this._file_waits.remove(me._id);
        var result = this._file_results.get(me._id);
        this._file_results.remove(me._id);
        me._deadline = deadline;
        return result;
    }
}

# A file handle as the drivers take it. Only io_uring (Linux) runs file
# transfers itself.
[Target(!OS(Windows))]
_async_file_descriptor(handle: io.FileHandle): long {
    return handle as long;
}

[Target(OS(Windows))]
_async_file_descriptor(handle: io.FileHandle): long {
    return -1;
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

# Whether the calling code runs in a task (on a worker inside `run`).
export _async_in_task(): bool {
    return _async_on_worker() && _async_worker()._running;
}

# The running task's slot for the `TaskLocal` numbered `id`, or null when
# it has no value. Only in a task.
export _async_task_local_slot(id: ulong): __ptr<void> {
    # An index loop: `TaskLocal.get` calls this, and a `for` would allocate
    # an iterator every time.
    var locals = _async_worker()._current._locals;
    ulong index = 0;
    while (index < locals.count) {
        if (locals[index]._id == id) {
            return locals[index]._slot;
        }
        index = index + 1;
    }
    return __null;
}

# Records `slot` as the running task's value of the `TaskLocal` numbered
# `id`; `release` frees it when the task ends. Only in a task.
export _async_task_local_add(id: ulong, slot: __ptr<void>, release: () => void) {
    _async_worker()._current._locals.append(_TaskLocalValue(id, slot, release));
}

# Removes and releases the running task's value of the `TaskLocal`
# numbered `id`, if it has one. Only in a task.
export _async_task_local_clear(id: ulong) {
    var locals = _async_worker()._current._locals;
    var i: ulong = 0;
    while (i < locals.count) {
        if (locals[i]._id == id) {
            var local = locals.remove_at(i);
            local._release();
            return;
        }
        i = i + 1;
    }
}

# Gives every task that takes a `Mutex` its own holder id, above any
# operating-system thread id.
const _async_task_tokens = Atomic<ulong>((1 as ulong) << 62);

# The id that marks the caller as a `Mutex`'s holder: the running task's
# own, or the thread's outside a task, since tasks on one worker share its
# thread.
export _async_holder_id(): ulong {
    if (!_async_in_task()) {
        return _async_sys_os_thread();
    }
    var me = _async_worker()._current;
    if (me._token == 0) {
        me._token = _async_task_tokens.fetch_add(1);
    }
    return me._token;
}

# A waiter for the running task to add to a `_SyncQueue`. The caller has
# checked `_async_in_task()`; no Optional is built, since every park takes
# this path.
export _async_sync_waiter(): _SyncWaiter {
    assert(_async_in_task(), "_async_sync_waiter outside a task");
    var worker = _async_worker();
    return _SyncWaiter(worker._inbox, worker._current._id);
}

# What `_async_sync_park` reports: woken by a waker, or why the wait ended
# without one.
export enum _SyncWake {
    Woken,
    Cancelled,
    TimedOut,
}

# Parks the running task until `waiter`, already in `queue`, is woken, or
# until `deadline` (monotonic milliseconds, 0 for none) passes. When
# `interruptible`, a cancel or the task's `timeout` also ends the wait.
#
# A wait that ends without a wake abandons the waiter and takes it out of
# `queue`, and the result says why; a waker that got there first wins, and
# the result is `_SyncWake.Woken`.
export _async_sync_park(queue: _SyncQueue, waiter: _SyncWaiter, deadline: ulong, interruptible: bool): _SyncWake {
    var worker = _async_worker();
    var me = worker._current;
    var saved = me._deadline;
    var until = deadline;
    if (interruptible && saved != 0 && (until == 0 || saved < until)) {
        until = saved;
    }
    me._deadline = until;
    worker._sync_waits.insert(me._id, me);
    var result = _SyncWake.Woken;
    while (waiter._state.load() == _WAITER_WAITING) {
        var reason = _SyncWake.Woken;
        if (interruptible && me._is_cancelled()) {
            reason = _SyncWake.Cancelled;
        } else if (until != 0 && _async_sys_monotonic_milliseconds() >= until) {
            reason = _SyncWake.TimedOut;
        }
        if (reason != _SyncWake.Woken) {
            if (waiter._state.compare_exchange(_WAITER_WAITING, _WAITER_ABANDONED)) {
                queue._remove(waiter);
                result = reason;
            }
            break;
        }
        worker._park();
    }
    worker._sync_waits.remove(me._id);
    me._deadline = saved;
    return result;
}

# Wakes the task `waiter` stands for: directly when it waits on the calling
# thread's worker, otherwise through that worker's inbox. A plain thread's
# waiter (in a `Select`) is signalled through its `_ThreadWake`.
export _async_sync_wake(waiter: _SyncWaiter) {
    if (waiter._thread !== __null) {
        waiter._thread._signal();
        return;
    }
    if (_async_on_worker()) {
        var worker = _async_worker();
        if (worker._inbox._id == waiter._inbox._id) {
            if (worker._sync_waits.contains(waiter._task)) {
                worker._wake(worker._sync_waits.get(waiter._task));
            }
            return;
        }
    }
    waiter._inbox._send(waiter._task, _Message.Wake);
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
    core._release_locals();
    core._finished = true;
    worker._wake_all(core._joiners);
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

## A task started with `spawn_local` or `spawn`, and the value its body
## returns.
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

    ## Wraps the scheduler's record of a task. Only `spawn_local` and `spawn`
    ## have one; start tasks with those.
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
                if (me._is_cancelled()) {
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
        if (this._core._proxy) {
            if (this._core._finished) {
                this._core._cancelled = true;
                return;
            }
            this._core._cancelled = true;
            if (_async_on_worker()) {
                this._core._shared.value()._cancel(_async_worker()._runtime);
            } else {
                this._core._shared.value()._cancelled.store(1);
            }
        } else if (_async_on_worker()) {
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

## Runs `body` as the first task of a new runtime, and returns once `body`
## has returned and every task it started has finished. The calling thread
## is the first worker; the runtime starts one more thread per logical CPU
## after it (see `RuntimeOptions.workers`). When `body` returns, the tasks
## still running are cancelled (see `Task.cancel`), on every worker, and
## `run` waits for them to finish.
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
    var count = options._workers;
    if (count == 0) {
        count = logical_cpus();
    }
    var runtime = _Runtime(count, options._blocking_threads);
    var stack_size = options._stack_size;
    var backend = options._backend;
    var threads = Array<Thread>();
    var i: ulong = 1;
    while (i < count) {
        var index = i;
        threads.append(Thread.spawn(() => {
            _async_worker_main(runtime, index, stack_size, backend, () => {});
        }, "async worker"));
        i = i + 1;
    }
    _async_worker_main(runtime, 0, stack_size, backend, body);
    for (var thread in threads) {
        thread.join();
    }
}

# Runs worker `index` of `runtime` on this thread until the runtime stops.
# The first worker's first task is `body`.
_async_worker_main(runtime: _Runtime, index: ulong, stack_size: ulong, backend: Backend, body: () => void) {
    var worker = _Worker(runtime, index, stack_size, backend);
    __ptr<_Worker> slot = _pep_malloc(8);
    slot[0] = worker;
    _async_fiber_key_set(_async_worker_key, slot);
    io._io_set_waiter(worker);
    runtime._join(index, worker._inbox);
    var first = Optional<_TaskCore>.Empty;
    if (index == 0) {
        first = Optional<_TaskCore>.Value(worker._spawn(body));
    }
    worker._run(first);
    runtime._leave(worker._inbox);
    # Every blocking call has returned: no task is left to wait for one.
    runtime._blocking.close();
    for (var thread in worker._pool) {
        thread.join();
    }
    worker._pool.clear();
    io._io_clear_waiter();
    _async_fiber_key_set(_async_worker_key, __null);
    slot[0] = __default<_Worker>();
    _pep_free(slot);
    worker._close();
}

## Starts a task that runs `body` on whichever worker is free first, and
## returns it. Unlike `Task<T>.spawn_local`, the task may run on another
## thread, in parallel with the calling task, so the body must be a
## `shared` function (it may capture only thread-safe values) and its result
## crosses threads, so `T` is constrained `Shared`: a thread-safe type such
## as a number, a `[Shared]` struct, or a `shared` function type
## (`spawn<String>` is a compile error at `String`).
##
## A task, once started, stays on the worker that started it. Joining and
## cancelling work as for `spawn_local`.
##
## @typeParam T the type of the body's result, which must be thread-safe
##   (`T: Shared`); `void` when there is none
## @param body the task's code
## @returns the task
## @panics outside `run`
## @example
##     import async;
##
##     sum(from: long, to: long): long {
##         var total: long = 0;
##         var i = from;
##         while (i < to) {
##             total = total + i;
##             i = i + 1;
##         }
##         return total;
##     }
##
##     main(): int {
##         async.run(() => {
##             var low = async.spawn<long>(() => { return sum(0, 500000); });
##             var high = async.spawn<long>(() => { return sum(500000, 1000000); });
##             print(low.join().value() + high.join().value());   # 499999500000
##         });
##         return 0;
##     }
export spawn<T: Shared>(body: shared () => T): Task<T> {
    assert(_async_on_worker(), "async.spawn: not inside async.run");
    var worker = _async_worker();
    var result = _TaskResult<T>();
    var proxy = worker._new_proxy();
    var task = Task<T>(proxy);
    proxy._on_complete = () => {
        task._run(() => {
            return result._take();
        });
    };
    _async_push(worker, proxy, () => {
        result._run(body);
    }, 0);
    return task;
}

# Queues `run` as the task that `proxy`, a stand-in on `worker`, stands for:
# on the shared queue (`worker_plus_one` 0) or pinned to the worker whose
# index is `worker_plus_one - 1`.
_async_push(worker: _Worker, proxy: _TaskCore, run: shared () => void, worker_plus_one: ulong) {
    var shared = _SharedTask(run, worker._index, proxy._id);
    proxy._shared = Optional<_SharedTask>.Value(shared);
    proxy._shared_cancelled = shared._cancelled;
    if (worker_plus_one == 0) {
        worker._runtime._push(shared);
    } else {
        worker._runtime._push_to(worker_plus_one - 1, shared);
    }
}

## Starts one task on every worker, each running `body`, and returns them in
## worker order. Use it to give each worker its own copy of a loop, such as
## a server's accept loop on an `io.SharedTcpListener`, so that every worker
## takes part. Each task runs on its own worker, the calling task's worker
## included; they are otherwise like tasks from `spawn`, and `body` must be
## a `shared` function.
##
## @param body the code each worker runs
## @returns one task per worker, the first on the first worker
## @panics outside `run`
## @example
##     import async;
##     import io;
##
##     main(): int {
##         async.run(() => {
##             var listener = io.SharedTcpListener.bind(io.SocketAddress.parse("0.0.0.0:7000").value()).value();
##             var loops = async.spawn_on_each_worker(() => {
##                 while (true) {
##                     var accepted = listener.accept();
##                     if (accepted.is_err()) {
##                         return;
##                     }
##                     var (stream, peer) = accepted.value();
##                     async.Task<void>.spawn_local(() => {
##                         stream.write_all("hello");
##                     });
##                 }
##             });
##             for (var loop in loops) {
##                 loop.join();
##             }
##         });
##         return 0;
##     }
export spawn_on_each_worker(body: shared () => void): Array<Task<void>> {
    assert(_async_on_worker(), "async.spawn_on_each_worker: not inside async.run");
    var worker = _async_worker();
    var tasks = Array<Task<void>>();
    var i: ulong = 0;
    while (i < worker._runtime._count) {
        var proxy = worker._new_proxy();
        tasks.append(Task<void>(proxy));
        _async_push(worker, proxy, body, i + 1);
        i = i + 1;
    }
    return tasks;
}

## Runs `body` on a separate thread and returns what it returns, parking
## the calling task meanwhile so the worker keeps running other tasks. Use it
## for work that would otherwise hold the worker up: a call that blocks in
## the operating system (reading a file, resolving a host name, a C library
## that waits) or a long computation.
##
## The runtime keeps a pool of threads for these calls, started as needed up
## to `RuntimeOptions.blocking_threads`. `body` runs on one of them, so it
## must be a `shared` function and `T` is constrained `Shared`, as for
## `spawn`.
## On a pool thread, sockets block the thread, and `sleep` and the other task
## functions behave as outside `run`.
##
## `body` always runs to the end: cancelling the calling task, or a `timeout`
## around the call expiring, takes effect once `run_blocking` has returned.
## Outside a task, `run_blocking` just calls `body`.
##
## @typeParam T the type of the body's result, which must be thread-safe
##   (`T: Shared`); `void` when there is none
## @param body the blocking code
## @returns what `body` returns
## @example
##     import async;
##
##     main(): int {
##         async.run(() => {
##             var ticker = async.Task<void>.spawn_local(() => {
##                 async.sleep(10);
##                 print("the worker kept running");
##             });
##             var answer = async.run_blocking<int>(() => {
##                 async.Thread.sleep(50);   # blocks a pool thread, not the worker
##                 return 42;
##             });
##             print(answer);
##             ticker.join();
##         });
##         return 0;
##     }
export run_blocking<T: Shared>(body: shared () => T): T {
    var result = _TaskResult<T>();
    if (!_async_on_worker() || !_async_worker()._running) {
        result._run(body);
        return result._value[0];
    }
    var worker = _async_worker();
    var me = worker._current;
    var proxy = worker._new_proxy();
    worker._start_blocking(_SharedTask(() => {
        result._run(body);
    }, worker._index, proxy._id));
    # Neither a cancel nor a deadline ends the wait: the body is running and
    # holds `result`.
    var deadline = me._deadline;
    me._deadline = 0;
    proxy._joiners.append(me);
    while (!proxy._finished) {
        worker._park();
    }
    me._deadline = deadline;
    # Read the slot rather than call `_take()`: `return` of a call is
    # rejected for `T = void`. The slot keeps its reference until `result`
    # goes, as a copy would.
    return result._value[0];
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
    _async_task_sleep(milliseconds);
}

## Waits at least `duration`, the same as `sleep(milliseconds)`. A duration
## that is not a whole number of milliseconds rounds up, so the wait is never
## shorter than asked.
##
## @param duration how long to wait
## @example
##     async.sleep(os.Duration.from_seconds(1));
export sleep(duration: os.Duration) {
    var milliseconds = duration.milliseconds();
    if (os.Duration.from_milliseconds(milliseconds) < duration) {
        milliseconds = milliseconds + 1;
    }
    _async_task_sleep(milliseconds);
}

# `sleep`, which `Thread.sleep` also calls in a task.
export _async_task_sleep(milliseconds: ulong) {
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
    if (me._is_cancelled()) {
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
    return worker._current._is_cancelled();
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

extend Deadline with Scoped<Deadline>;

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
