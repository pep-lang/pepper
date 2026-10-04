<!-- Generated from runtime/async/coordination.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Semaphore, Barrier and Latch

Coordination between threads: `Semaphore` bounds how many threads do
something at once, `Barrier` makes a group of threads meet before any
goes on, and `Latch` lets threads wait until a count of events has
happened.

Source: `runtime/async/coordination.pep`

## Semaphore

```pepper
[Shared] struct Semaphore
```

A count of permits that threads take and give back, like Java's
`Semaphore` or C++20 `std::counting_semaphore`: at most `permits` threads
hold one at a time.

`acquire()` waits until a permit is free and takes it; `release()` gives
one back. The usual form is a `with` block, which gives the permit back
on every path out: `with (semaphore.permit()) { ... }`.

A Semaphore is `[Shared]`: keep it in a module-scope variable or pass it
to threads. Permits are not tied to a thread: any thread may release a
permit that another acquired, and `release()` may raise the count above
where it started.

In a task (see `run`), waiting for a permit parks the task, not its worker
thread.

**Example**
```pepper
import async;

# At most two downloads at once.
const downloads = async.Semaphore(2);

download(url: String) {
    with (downloads.permit()) {
        # ... fetch url ...
    }
}
```

### Constructor

#### Semaphore()

```pepper
construct(permits: ulong)
```

Creates a Semaphore with `permits` free permits.

**Parameters**
- `permits` — how many permits are free at first; 0 makes every `acquire()` wait for a `release()`

### Methods

#### acquire

```pepper
acquire()
```

Waits until a permit is free, and takes it.

Give it back with `release()`, or use `permit()` in a `with` block,
which gives it back for you.

#### try_acquire

```pepper
try_acquire(): bool
```

Takes a permit only if one is free right now, without waiting.

**Returns**
- true if the caller now holds a permit, false if none was free

#### release

```pepper
release()
```

Gives a permit back, waking one thread waiting in `acquire()` if any.

#### permit

```pepper
permit(): SemaphorePermit
```

Waits until a permit is free, takes it, and returns a guard that gives
it back when destroyed: at the end of `with (semaphore.permit()) { ... }`
by any path.

**Returns**
- the guard holding the permit

**Example**
```pepper
with (connections.permit()) {
    serve(client);
}   # the permit is given back here
```

## SemaphorePermit

```pepper
struct SemaphorePermit
```

A permit taken from a `Semaphore`, given back when the guard is destroyed.
Get one from `Semaphore.permit()` in a `with` header.

**Example**
```pepper
with (var permit = pool.permit()) {
    # holds one of the pool's permits
}
```

### Constructor

#### SemaphorePermit()

```pepper
construct(semaphore: Semaphore)
```

Waits for a permit from `semaphore` and holds it; the same as
`semaphore.permit()`.

**Parameters**
- `semaphore` — the Semaphore to take a permit from

### Methods

#### enter

```pepper
enter(): SemaphorePermit
```

Returns this guard, for the `with` header.

**Returns**
- this permit

#### exit

```pepper
exit()
```

Gives the permit back if it is still held. The destructor calls it;
calling it again does nothing.

## Barrier

```pepper
[Shared] struct Barrier
```

A meeting point for a fixed number of threads, like Rust's
`std::sync::Barrier`: each thread that calls `wait()` sleeps until `count`
threads have called it, then all of them go on together.

Exactly one thread of each group, the leader, gets true from `wait()`, so
it can do the work that must happen once per round. The barrier then
resets, and the next `count` calls make the next round.

A Barrier is `[Shared]`. In a task (see `run`), `wait()` parks the task,
not its worker thread; the other tasks of a round must then run on other
workers or later on the same one.

**Example**
```pepper
import async;

const step_done = async.Barrier(4);

work(id: long) {
    var step = 0;
    while (step < 10) {
        # ... this thread's share of the step ...
        if (step_done.wait()) {
            print($"step {step} done\n");   # once per step
        }
        step = step + 1;
    }
}
```

### Constructor

#### Barrier()

```pepper
construct(count: ulong)
```

Creates a barrier for groups of `count` threads.

**Parameters**
- `count` — how many threads each round waits for; 0 counts as 1, so every `wait()` returns at once as the leader

### Methods

#### wait

```pepper
wait(): bool
```

Waits until `count` threads, this one included, have called `wait()`
in this round.

**Returns**
- true on exactly one thread of each round, the last to arrive; false on the others

## Latch

```pepper
[Shared] struct Latch
```

A one-shot countdown, like C++20 `std::latch`: threads wait until
`count_down()` has been called `count` times. Once open it stays open.

Unlike a `Barrier`, the threads that count down need not wait, and the
threads that wait need not count down: a typical use is a thread that
starts workers and waits for each to report that it is ready.

A Latch is `[Shared]`. In a task (see `run`), `wait()` parks the task, not
its worker thread.

**Example**
```pepper
import async;

const ready = async.Latch(3);

worker() {
    # ... set up ...
    ready.count_down();
    # ... work ...
}

main(): int {
    var threads = Array<async.Thread>();
    var i = 0;
    while (i < 3) {
        threads.append(async.Thread.spawn(worker));
        i = i + 1;
    }
    ready.wait();   # every worker has set up
    for (var t in threads) {
        t.join();
    }
    return 0;
}
```

### Constructor

#### Latch()

```pepper
construct(count: ulong)
```

Creates a latch that opens after `count` calls to `count_down()`.

**Parameters**
- `count` — how many calls open it; 0 makes a latch that is open from the start

### Methods

#### count_down

```pepper
count_down()
```

Counts one event, and opens the latch, waking every waiter, if it was
the last one.

**Panics**
- if the latch is already open

#### wait

```pepper
wait()
```

Waits until the latch is open. Returns at once if it already is.

#### is_ready

```pepper
is_ready(): bool
```

Reports whether the latch is open, without waiting.

**Returns**
- true once `count_down()` has been called `count` times
