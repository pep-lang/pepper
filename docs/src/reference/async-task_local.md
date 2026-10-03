<!-- Generated from runtime/async/task_local.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# TaskLocal

Per-task values: `TaskLocal<T>` gives every task its own copy of a
variable.

Source: `runtime/async/task_local.pep`

## TaskLocal

```pepper
[Shared] struct TaskLocal<T>
```

A variable with a separate value in every task, the task counterpart of
`ThreadLocal<T>`.

Each task that calls `set` stores its own value, which is released when
the task finishes. A task starts with no value, including one started by
a task that has one: values are not inherited. Tasks that take turns on
one worker thread each see their own value, which a `ThreadLocal` cannot
give them.

Code that does not run in a task (before `async.run`, or on a plain
`Thread`) has one value per thread, as with a `ThreadLocal`.

For a thread-safe `T` (a number, a `[Shared]` struct), `get` returns the
calling task's value (the default of `T`, zero or null, until it sets
one). For any other `T`, such as a `String`, the value is reached through
a `with` block, `with (var value = local.enter()) { ... }`, and `get` is a
compile error; `set` then takes a new value (a constructor call, a string
literal, `copy(x)`).

A `TaskLocal` is `[Shared]`, so one object can be used from every task
and thread; it is usually a module-scope variable. Destroying one
releases only the caller's value, so destroy it only after the tasks that
used it have finished.

**Type parameters**
- `T` — the type of the per-task value

**See also**
- `ThreadLocal`

**Example**
```pepper
    import async;

    const request_id = async.TaskLocal<long>();

    handle(id: long) {
        request_id.set(id);
        async.yield_now();   # the other tasks run meanwhile
        assert(request_id.get() == id, "still this task's id");
    }

    main(): int {
        async.run(() => {
            var tasks = Array<async.Task<void>>();
            for (var id in [1, 2, 3]) {
                tasks.append(async.spawn<void>(() => {
                    handle(id);
                }));
            }
            for (var task in tasks) {
                task.join();
            }
        });
        return 0;
    }
```

### Constructor

#### TaskLocal()

```pepper
construct()
```

Creates a task-local variable. No task has a value yet.

**Panics**
- if the operating system has no thread-local keys left

### Methods

#### get

```pepper
get(): T
```

Returns the calling task's value.

For a struct `T` the caller gets its own reference. Only for a
thread-safe `T`: for any other `T`, use `with (var value =
local.enter())`.

**Returns**
- the value this task last stored, or the default of `T` (zero or null) if it has not stored one

#### set

```pepper
set([Move] value: T)
```

Stores `value` as the calling task's value, replacing (and, for a
struct `T`, releasing) the one it held. Other tasks' values are not
affected.

For a `T` that is not thread-safe, `value` must be a new value (a
constructor call, a string literal, `copy(x)`), which the compiler
checks.

**Parameters**
- `value` — the new value for this task

#### enter

```pepper
enter(): TaskLocalGuard<T>
```

Returns the guard that a `with` block enters to reach the calling
task's value: `with (var value = local.enter()) { ... }`. The body
runs with the value bound; the `else` block runs when this task has
no value (for a struct `T`).

**Returns**
- the guard; its `enter()` returns this task's value

**Example**
```pepper
    const trail = async.TaskLocal<Array<String>>();

    note(step: String) {
        if (!trail.is_set()) {
            trail.set(Array<String>());
        }
        with (var steps = trail.enter()) {
            steps.append(step.copy());
        }
    }
```

#### is_set

```pepper
is_set(): bool
```

Reports whether the calling task has stored a value since it started
or last called `clear()`.

**Returns**
- true if this task has a value

#### clear

```pepper
clear()
```

Removes the calling task's value, releasing it for a struct `T`.
`get()` returns the default of `T` afterwards.

## TaskLocalGuard

```pepper
[Isolated] struct TaskLocalGuard<T>
```

The access to a task's `TaskLocal<T>` value that a `with` block holds:
`enter()` returns the value. Get one from `TaskLocal.enter()`.

A guard is `[Isolated]`: it can only be the scope of a `with` header, and
the compiler checks the block with the confinement rule (see `Mutex`).

**Type parameters**
- `T` — the type of the per-task value

### Constructor

#### TaskLocalGuard()

```pepper
construct(local: TaskLocal<T>)
```

Creates the guard for the calling task's value of `local`; the same as
`local.enter()`.

**Parameters**
- `local` — the task-local variable

### Methods

#### enter

```pepper
enter(): T
```

Returns the calling task's value, for the `with` header to bind.

**Returns**
- this task's value, or the default of `T` (null for a struct) when it has none

#### exit

```pepper
exit()
```

Does nothing: the value stays with the task.
