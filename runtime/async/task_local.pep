## Per-task values: `TaskLocal<T>` gives every task its own copy of a
## variable.

# A task's values live in its `_TaskCore._locals` (task.pep), one malloc'd
# slot per variable it has set, found by the variable's `_id` and released
# when the task's body returns. Code outside any task (before `async.run`,
# or on a plain `Thread`) uses `_outside`, a `ThreadLocal<T>`, so it gets
# one value per thread, as with a `ThreadLocal`.
#
# The confinement rules are ThreadLocal's (see thread_local.pep): for a `T`
# that is not thread-safe, `get()` is a compile error and the value is
# reached through `with (var value = local.enter())`.

import "atomic";
import "sys_posix";
import "sys_windows";
import "task";
import "thread_local";

# Gives every TaskLocal its own id.
const _async_task_local_ids = Atomic<ulong>(1);

## A variable with a separate value in every task, the task counterpart of
## `ThreadLocal<T>`.
##
## Each task that calls `set` stores its own value, which is released when
## the task finishes. A task starts with no value, including one started by
## a task that has one: values are not inherited. Tasks that take turns on
## one worker thread each see their own value, which a `ThreadLocal` cannot
## give them.
##
## Code that does not run in a task (before `async.run`, or on a plain
## `Thread`) has one value per thread, as with a `ThreadLocal`.
##
## For a thread-safe `T` (a number, a `[Shared]` struct), `get` returns the
## calling task's value (the default of `T`, zero or null, until it sets
## one). For any other `T`, such as a `String`, the value is reached through
## a `with` block, `with (var value = local.enter()) { ... }`, and `get` is a
## compile error; `set` then takes a new value (a constructor call, a string
## literal, `copy(x)`).
##
## A `TaskLocal` is `[Shared]`, so one object can be used from every task
## and thread; it is usually a module-scope variable. Destroying one
## releases only the caller's value, so destroy it only after the tasks that
## used it have finished.
##
## @typeParam T the type of the per-task value
## @example
##     import async;
##
##     const request_id = async.TaskLocal<long>();
##
##     handle(id: long) {
##         request_id.set(id);
##         async.yield_now();   # the other tasks run meanwhile
##         assert(request_id.get() == id, "still this task's id");
##     }
##
##     main(): int {
##         async.run(() => {
##             var tasks = Array<async.Task<void>>();
##             for (var id in [1, 2, 3]) {
##                 tasks.append(async.spawn<void>(() => {
##                     handle(id);
##                 }));
##             }
##             for (var task in tasks) {
##                 task.join();
##             }
##         });
##         return 0;
##     }
## @see ThreadLocal
[Shared]
export struct TaskLocal<T> {
    # Identifies the variable in each task's list of values.
    const _id: ulong;
    # The value of code that does not run in a task, one per thread.
    const _outside: ThreadLocal<T>;

    ## Creates a task-local variable. No task has a value yet.
    ##
    ## @panics if the operating system has no thread-local keys left
    construct() {
        _id = _async_task_local_ids.fetch_add(1);
        _outside = ThreadLocal<T>();
    }

    destruct {
        if (_async_in_task()) {
            _async_task_local_clear(_id);
        }
    }

    # Releases the value in `slot` and frees it.
    static _release_slot(slot: __ptr<void>) {
        __ptr<T> value = slot;
        value[0] = __default<T>();
        _pep_free(slot);
    }

    # The caller's slot: the running task's, or the thread's outside a task;
    # null when it has no value.
    _slot(): __ptr<void> {
        if (_async_in_task()) {
            return _async_task_local_slot(_id);
        }
        return _async_sys_key_get(_outside._key);
    }

    ## Returns the calling task's value.
    ##
    ## For a struct `T` the caller gets its own reference. Only for a
    ## thread-safe `T`: for any other `T`, use `with (var value =
    ## local.enter())`.
    ##
    ## @returns the value this task last stored, or the default of `T` (zero or null) if it has not stored one
    get(): T {
        __ptr<T> slot = this._slot();
        if (slot == __null) {
            return __default<T>();
        }
        return slot[0];
    }

    ## Stores `value` as the calling task's value, replacing (and, for a
    ## struct `T`, releasing) the one it held. Other tasks' values are not
    ## affected.
    ##
    ## For a `T` that is not thread-safe, `value` must be a new value (a
    ## constructor call, a string literal, `copy(x)`), which the compiler
    ## checks.
    ##
    ## @param value the new value for this task
    set([Move] value: T) {
        __ptr<T> slot = this._slot();
        if (slot == __null) {
            # One stored T: see ThreadLocal.set.
            slot = _pep_malloc(sizeof<T>());
            __ptr<void> raw = slot;
            if (_async_in_task()) {
                _async_task_local_add(_id, raw, () => {
                    TaskLocal<T>._release_slot(raw);
                });
            } else {
                _async_sys_key_set(_outside._key, raw);
            }
        }
        slot[0] = value;
    }

    ## Returns the guard that a `with` block enters to reach the calling
    ## task's value: `with (var value = local.enter()) { ... }`. The body
    ## runs with the value bound; the `else` block runs when this task has
    ## no value (for a struct `T`).
    ##
    ## @returns the guard; its `enter()` returns this task's value
    ## @example
    ##     const trail = async.TaskLocal<Array<String>>();
    ##
    ##     note(step: String) {
    ##         if (!trail.is_set()) {
    ##             trail.set(Array<String>());
    ##         }
    ##         with (var steps = trail.enter()) {
    ##             steps.append(step.copy());
    ##         }
    ##     }
    enter(): TaskLocalGuard<T> {
        return TaskLocalGuard<T>(this);
    }

    ## Reports whether the calling task has stored a value since it started
    ## or last called `clear()`.
    ##
    ## @returns true if this task has a value
    is_set(): bool {
        return this._slot() != __null;
    }

    ## Removes the calling task's value, releasing it for a struct `T`.
    ## `get()` returns the default of `T` afterwards.
    clear() {
        if (_async_in_task()) {
            _async_task_local_clear(_id);
        } else {
            _outside.clear();
        }
    }
}

## The access to a task's `TaskLocal<T>` value that a `with` block holds:
## `enter()` returns the value. Get one from `TaskLocal.enter()`.
##
## A guard is `[Isolated]`: it can only be the scope of a `with` header, and
## the compiler checks the block with the confinement rule (see `Mutex`).
##
## @typeParam T the type of the per-task value
[Isolated]
export struct TaskLocalGuard<T> {
    # The task-local variable.
    const _local: TaskLocal<T>;

    ## Creates the guard for the calling task's value of `local`; the same as
    ## `local.enter()`.
    ##
    ## @param local the task-local variable
    construct(local: TaskLocal<T>) {
        _local = local;
    }

    ## Returns the calling task's value, for the `with` header to bind.
    ##
    ## @returns this task's value, or the default of `T` (null for a struct) when it has none
    enter(): T {
        __ptr<T> slot = _local._slot();
        if (slot == __null) {
            return __default<T>();
        }
        return slot[0];
    }

    ## Does nothing: the value stays with the task.
    exit() {}
}

extend TaskLocalGuard<T> with Scoped<T> {}
