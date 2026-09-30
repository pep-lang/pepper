# Several workers: what the worker threads of one `run` share.
#
# `run` starts `RuntimeOptions.workers` workers: the calling thread and one
# `Thread` for each of the rest. Each worker is a `_Worker` (task.pep) on its
# own thread, with its own tasks, timers and driver. A started task never
# leaves its worker, so tasks on one worker still share values with plain
# reference counts. What crosses threads is only thread-safe:
#
# - `_Runtime`, shared by every worker: the inbox of each, the queue of
#   tasks from `spawn` that no worker has started yet, and the stop flag.
# - `_Inbox`, one per worker: messages from other workers (a
#   `Channel<ulong>` of `id * 4 + kind`: a task spawned here finished
#   elsewhere, a task running here was cancelled elsewhere, or a task
#   parked here on a sync object was woken elsewhere), tasks from
#   `spawn_on_each_worker` that must run on this worker, and the worker's
#   doorbell, which ends its wait in the driver.
# - `_SharedTask`, one per `spawn`: the body, where to report when it
#   finishes (the spawning worker and the stand-in task there that `join`
#   waits on), which worker runs it once one does, and its cancel flag.
# - `_TaskResult<T>`, the result of a spawned task, which the running worker
#   stores and the spawning worker takes. It is `[Shared]` so that `T` must
#   be thread-safe.
#
# Any idle worker takes the next task from the shared queue, so an idle
# worker takes on unstarted work from a busy one; a task, once started,
# stays where it started.
#
# Waking a sleeping worker: a worker about to block in its driver sets
# `_sleeping`, clears `_notified`, and looks at its inbox, the shared queue
# and the stop flag once more before it blocks. A sender puts the message in
# the inbox first and then rings the doorbell unless `_notified` was already
# set; a ring is remembered until the next wait. So a message is either seen
# by that last look or ends the wait.
#
# Blocking calls: `run_blocking` hands its body to a pool of plain threads
# that the runtime starts as needed, up to `RuntimeOptions.blocking_threads`,
# and parks the calling task. A pool thread runs the body and sends the
# calling worker a `_MESSAGE_COMPLETE` for the task's stand-in, as a worker
# running a spawned task does. Pool threads wait for more work until the
# runtime ends.
#
# Stopping: when the first task returns, its worker sets `_stopping` and
# rings every worker. Each worker cancels its tasks, keeps running until
# none remain (tasks started from then on start cancelled), and then waits
# until every worker is done before it closes its driver, so no ring ever
# reaches a closed handle.

import "channel";
import "driver";
import "sys_posix";
import "sys_windows";
import "task";

# What a message tells a worker about one of its tasks.
export const _MESSAGE_COMPLETE: ulong = 0;
export const _MESSAGE_CANCEL: ulong = 1;
# A task parked on a `Mutex`, `Condition` or `Channel` here was woken (see
# sync_wait.pep).
export const _MESSAGE_WAKE: ulong = 2;

# Gives every inbox its own id.
const _async_inbox_ids = Atomic<ulong>(1);

# Messages to one worker, and its doorbell.
[Shared]
export struct _Inbox {
    # Unique among inboxes, so a waker can tell whether a task waits on its
    # own worker.
    const _id: ulong;
    # `id * 4 + kind` (a `_MESSAGE_*` kind) for each message.
    const _messages: Channel<ulong>;
    # Spawned tasks that must run on this worker.
    const _pinned: Channel<_SharedTask>;
    # 1 once the doorbell was rung since the worker last prepared to block.
    const _notified: Atomic<int>;
    # 1 while the worker is about to block or blocks in its driver.
    const _sleeping: Atomic<int>;
    const _doorbell: _Doorbell;

    construct(doorbell: _Doorbell) {
        _id = _async_inbox_ids.fetch_add(1);
        _messages = Channel<ulong>();
        _pinned = Channel<_SharedTask>();
        _notified = Atomic<int>(0);
        _sleeping = Atomic<int>(0);
        _doorbell = doorbell;
    }

    # Sends the worker `kind` about its task `id`.
    _send(id: ulong, kind: ulong) {
        _messages.send(id * 4 + kind);
        _ring();
    }

    # Ends the worker's wait, unless a ring is already pending.
    _ring() {
        if (_notified.exchange(1) == 0) {
            _doorbell._ring();
        }
    }
}

# A task from `spawn`, which any worker may run.
[Shared]
export struct _SharedTask {
    # Runs the body and stores its result.
    const _body: shared () => void;
    # The worker that spawned it, and the id there of the stand-in task that
    # finishes when this one does.
    const _owner: ulong;
    const _proxy: ulong;
    # The worker running it plus 1 (0 until one starts it), and the task's
    # id there. The id is stored first.
    const _runner_worker: Atomic<ulong>;
    const _runner_id: Atomic<ulong>;
    # 1 once cancelled.
    const _cancelled: Atomic<int>;

    construct(body: shared () => void, owner: ulong, proxy: ulong) {
        _body = body;
        _owner = owner;
        _proxy = proxy;
        _runner_worker = Atomic<ulong>(0);
        _runner_id = Atomic<ulong>(0);
        _cancelled = Atomic<int>(0);
    }

    # Asks the task to stop, telling the worker running it if one is.
    _cancel(runtime: _Runtime) {
        _cancelled.store(1);
        var worker = _runner_worker.load();
        if (worker != 0) {
            runtime._inbox(worker - 1)._send(_runner_id.load(), _MESSAGE_CANCEL);
        }
    }
}

# The result of a spawned task: stored on the worker that runs it, taken on
# the worker that spawned it.
[Shared]
export struct _TaskResult<T> {
    # A heap slot for the value (one reference for a struct `T`).
    const _value: __ptr<T>;

    construct() {
        _value = _pep_malloc(sizeof<T>() + 8);
        _async_zero(_value, sizeof<T>() + 8);
    }

    destruct {
        _value[0] = __default<T>();
        _pep_free(_value);
    }

    # Runs `body` and stores what it returns.
    _run(body: shared () => T) {
        _value[0] = body();
    }

    # Takes the stored value out.
    _take(): T {
        var value = _value[0];
        _value[0] = __default<T>();
        return value;
    }
}

# What the workers of one `run` share.
[Shared]
export struct _Runtime {
    # How many workers.
    const _count: ulong;
    # Each worker's inbox, stored by the worker when it starts.
    const _inboxes: __ptr<_Inbox>;
    # How many workers have stored their inbox.
    const _started: Atomic<ulong>;
    # Tasks from `spawn` that no worker has started.
    const _queue: Channel<_SharedTask>;
    # 1 once the first task has returned.
    const _stopping: Atomic<int>;
    # How many workers are still running tasks.
    const _active: Atomic<ulong>;
    # Bodies from `run_blocking` for the pool threads.
    const _blocking: Channel<_SharedTask>;
    # How many pool threads are waiting for a body, and how many there are,
    # at most `_blocking_limit`.
    const _blocking_idle: Atomic<ulong>;
    const _blocking_threads: Atomic<ulong>;
    const _blocking_limit: ulong;

    construct(count: ulong, blocking_limit: ulong) {
        _count = count;
        _inboxes = _pep_malloc(count * 8);
        _async_zero(_inboxes, count * 8);
        _started = Atomic<ulong>(0);
        _queue = Channel<_SharedTask>();
        _stopping = Atomic<int>(0);
        _active = Atomic<ulong>(count);
        _blocking = Channel<_SharedTask>();
        _blocking_idle = Atomic<ulong>(0);
        _blocking_threads = Atomic<ulong>(0);
        _blocking_limit = blocking_limit;
    }

    destruct {
        var i: ulong = 0;
        while (i < _count) {
            _inboxes[i] = __default<_Inbox>();
            i = i + 1;
        }
        _pep_free(_inboxes);
    }

    # Worker `index` stores its inbox, then waits until every worker has.
    _join(index: ulong, inbox: _Inbox) {
        _inboxes[index] = inbox;
        _started.fetch_add(1);
        while (_started.load() < _count) {
            _async_sys_sleep(1);
        }
    }

    _inbox(index: ulong): _Inbox {
        return _inboxes[index];
    }

    # Queues a spawned task and wakes one sleeping worker to take it (one
    # not already woken).
    _push(task: _SharedTask) {
        _queue.send(task);
        var i: ulong = 0;
        while (i < _count) {
            var inbox = _inboxes[i];
            if (inbox._sleeping.load() != 0 && inbox._notified.load() == 0) {
                inbox._ring();
                return;
            }
            i = i + 1;
        }
    }

    # Queues a spawned task that must run on worker `index`, and wakes it.
    _push_to(index: ulong, task: _SharedTask) {
        var inbox = _inboxes[index];
        inbox._pinned.send(task);
        inbox._ring();
    }

    # Tells every worker to stop.
    _stop() {
        _stopping.store(1);
        var i: ulong = 0;
        while (i < _count) {
            _inboxes[i]._ring();
            i = i + 1;
        }
    }

    # Queues a body from `run_blocking` for the pool. Returns true when no
    # pool thread is idle and there is room for another, which the caller
    # then starts (see `_async_blocking_main`).
    _block(job: _SharedTask): bool {
        _blocking.send(job);
        while (true) {
            var idle = _blocking_idle.load();
            if (idle == 0) {
                break;
            }
            if (_blocking_idle.compare_exchange(idle, idle - 1)) {
                return false;
            }
        }
        while (true) {
            var started = _blocking_threads.load();
            if (started >= _blocking_limit) {
                return false;
            }
            if (_blocking_threads.compare_exchange(started, started + 1)) {
                return true;
            }
        }
        return false;
    }

    # A worker has run its last task: waits until every worker has. A task
    # pinned to it meanwhile (by a worker still running) goes to the shared
    # queue, where a running worker takes it.
    _leave(inbox: _Inbox) {
        _active.fetch_sub(1);
        while (_active.load() > 0) {
            var late = inbox._pinned.try_receive();
            if (late.is_ok()) {
                _push(late.value());
            } else {
                _async_sys_sleep(1);
            }
        }
    }
}

# The loop of a pool thread: runs bodies from `run_blocking` and reports
# each to the worker that queued it, until the runtime closes the queue.
export _async_blocking_main(runtime: _Runtime) {
    while (true) {
        var next = runtime._blocking.receive();
        if (next.is_err()) {
            return;
        }
        var job = next.value();
        job._body();
        runtime._inbox(job._owner)._send(job._proxy, _MESSAGE_COMPLETE);
        runtime._blocking_idle.fetch_add(1);
    }
}

extern void memset(void* p, int c, ulong n);

# Zeroes `size` bytes at `memory`.
export _async_zero(memory: __ptr<void>, size: ulong) {
    memset(memory, 0, size);
}
