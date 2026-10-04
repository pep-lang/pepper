## Coordination between threads: `Semaphore` bounds how many threads do
## something at once, `Barrier` makes a group of threads meet before any
## goes on, and `Latch` lets threads wait until a count of events has
## happened.

# Each type is a Mutex over a small struct of counts, with a Condition that
# its waiters sleep on. The counts are plain numbers, read and written only
# inside `with` blocks over the Mutex, so the types are `[Shared]` with no
# confinement concerns, and in a task their waits park the task (see
# mutex.pep).

import "mutex";

## A count of permits that threads take and give back, like Java's
## `Semaphore` or C++20 `std::counting_semaphore`: at most `permits` threads
## hold one at a time.
##
## `acquire()` waits until a permit is free and takes it; `release()` gives
## one back. The usual form is a `with` block, which gives the permit back
## on every path out: `with (semaphore.permit()) { ... }`.
##
## A Semaphore is `[Shared]`: keep it in a module-scope variable or pass it
## to threads. Permits are not tied to a thread: any thread may release a
## permit that another acquired, and `release()` may raise the count above
## where it started.
##
## In a task (see `run`), waiting for a permit parks the task, not its worker
## thread.
##
## @example
##     import async;
##
##     # At most two downloads at once.
##     const downloads = async.Semaphore(2);
##
##     download(url: String) {
##         with (downloads.permit()) {
##             # ... fetch url ...
##         }
##     }
[Shared]
export struct Semaphore {
    # The free permits.
    const _state: Mutex<_Permits>;

    # Signalled when a permit is given back.
    const _released: Condition<_Permits>;

    ## Creates a Semaphore with `permits` free permits.
    ##
    ## @param permits how many permits are free at first; 0 makes every `acquire()` wait for a `release()`
    construct(permits: ulong) {
        _state = Mutex<_Permits>(_Permits(permits));
        _released = _state.condition();
    }

    ## Waits until a permit is free, and takes it.
    ##
    ## Give it back with `release()`, or use `permit()` in a `with` block,
    ## which gives it back for you.
    acquire() {
        with (var permits = _state.lock()) {
            while (permits.free == 0) {
                _released.wait();
            }
            permits.free = permits.free - 1;
        }
    }

    ## Takes a permit only if one is free right now, without waiting.
    ##
    ## @returns true if the caller now holds a permit, false if none was free
    try_acquire(): bool {
        with (var permits = _state.lock()) {
            if (permits.free == 0) {
                return false;
            }
            permits.free = permits.free - 1;
        }
        return true;
    }

    ## Gives a permit back, waking one thread waiting in `acquire()` if any.
    release() {
        with (var permits = _state.lock()) {
            permits.free = permits.free + 1;
            _released.notify_one();
        }
    }

    ## Waits until a permit is free, takes it, and returns a guard that gives
    ## it back when destroyed: at the end of `with (semaphore.permit()) { ... }`
    ## by any path.
    ##
    ## @returns the guard holding the permit
    ## @example
    ##     with (connections.permit()) {
    ##         serve(client);
    ##     }   # the permit is given back here
    permit(): SemaphorePermit {
        return SemaphorePermit(this);
    }
}

## A permit taken from a `Semaphore`, given back when the guard is destroyed.
## Get one from `Semaphore.permit()` in a `with` header.
##
## @example
##     with (var permit = pool.permit()) {
##         # holds one of the pool's permits
##     }
export struct SemaphorePermit {
    # The Semaphore the permit came from.
    const _semaphore: Semaphore;

    # Whether the permit is still held: false once `exit()` gave it back.
    var _held: bool;

    ## Waits for a permit from `semaphore` and holds it; the same as
    ## `semaphore.permit()`.
    ##
    ## @param semaphore the Semaphore to take a permit from
    construct(semaphore: Semaphore) {
        _semaphore = semaphore;
        semaphore.acquire();
        _held = true;
    }

    destruct {
        this.exit();
    }

    ## Returns this guard, for the `with` header.
    ##
    ## @returns this permit
    enter(): SemaphorePermit {
        return this;
    }

    ## Gives the permit back if it is still held. The destructor calls it;
    ## calling it again does nothing.
    exit() {
        if (_held) {
            _held = false;
            _semaphore.release();
        }
    }
}

extend SemaphorePermit with Scoped<SemaphorePermit>;

## A meeting point for a fixed number of threads, like Rust's
## `std::sync::Barrier`: each thread that calls `wait()` sleeps until `count`
## threads have called it, then all of them go on together.
##
## Exactly one thread of each group, the leader, gets true from `wait()`, so
## it can do the work that must happen once per round. The barrier then
## resets, and the next `count` calls make the next round.
##
## A Barrier is `[Shared]`. In a task (see `run`), `wait()` parks the task,
## not its worker thread; the other tasks of a round must then run on other
## workers or later on the same one.
##
## @example
##     import async;
##
##     const step_done = async.Barrier(4);
##
##     work(id: long) {
##         var step = 0;
##         while (step < 10) {
##             # ... this thread's share of the step ...
##             if (step_done.wait()) {
##                 print($"step {step} done\n");   # once per step
##             }
##             step = step + 1;
##         }
##     }
[Shared]
export struct Barrier {
    # How many threads make a round.
    const _count: ulong;

    # The round in progress and how many have arrived at it.
    const _state: Mutex<_BarrierState>;

    # Signalled when a round completes.
    const _round_done: Condition<_BarrierState>;

    ## Creates a barrier for groups of `count` threads.
    ##
    ## @param count how many threads each round waits for; 0 counts as 1, so every `wait()` returns at once as the leader
    construct(count: ulong) {
        _count = count == 0 ? 1 : count;
        _state = Mutex<_BarrierState>(_BarrierState());
        _round_done = _state.condition();
    }

    ## Waits until `count` threads, this one included, have called `wait()`
    ## in this round.
    ##
    ## @returns true on exactly one thread of each round, the last to arrive; false on the others
    wait(): bool {
        with (var state = _state.lock()) {
            var round = state.round;
            state.arrived = state.arrived + 1;
            if (state.arrived < _count) {
                while (state.round == round) {
                    _round_done.wait();
                }
                return false;
            }
            state.arrived = 0;
            state.round = state.round + 1;
            _round_done.notify_all();
        }
        return true;
    }
}

## A one-shot countdown, like C++20 `std::latch`: threads wait until
## `count_down()` has been called `count` times. Once open it stays open.
##
## Unlike a `Barrier`, the threads that count down need not wait, and the
## threads that wait need not count down: a typical use is a thread that
## starts workers and waits for each to report that it is ready.
##
## A Latch is `[Shared]`. In a task (see `run`), `wait()` parks the task, not
## its worker thread.
##
## @example
##     import async;
##
##     const ready = async.Latch(3);
##
##     worker() {
##         # ... set up ...
##         ready.count_down();
##         # ... work ...
##     }
##
##     main(): int {
##         var threads = Array<async.Thread>();
##         var i = 0;
##         while (i < 3) {
##             threads.append(async.Thread.spawn(worker));
##             i = i + 1;
##         }
##         ready.wait();   # every worker has set up
##         for (var t in threads) {
##             t.join();
##         }
##         return 0;
##     }
[Shared]
export struct Latch {
    # How many `count_down()` calls are still to come.
    const _state: Mutex<_LatchState>;

    # Signalled when the count reaches zero.
    const _opened: Condition<_LatchState>;

    ## Creates a latch that opens after `count` calls to `count_down()`.
    ##
    ## @param count how many calls open it; 0 makes a latch that is open from the start
    construct(count: ulong) {
        _state = Mutex<_LatchState>(_LatchState(count));
        _opened = _state.condition();
    }

    ## Counts one event, and opens the latch, waking every waiter, if it was
    ## the last one.
    ##
    ## @panics if the latch is already open
    count_down() {
        with (var state = _state.lock()) {
            if (state.remaining == 0) {
                panic("Latch.count_down: the latch is already open");
            }
            state.remaining = state.remaining - 1;
            if (state.remaining == 0) {
                _opened.notify_all();
            }
        }
    }

    ## Waits until the latch is open. Returns at once if it already is.
    wait() {
        with (var state = _state.lock()) {
            while (state.remaining != 0) {
                _opened.wait();
            }
        }
    }

    ## Reports whether the latch is open, without waiting.
    ##
    ## @returns true once `count_down()` has been called `count` times
    is_ready(): bool {
        with (var state = _state.lock()) {
            return state.remaining == 0;
        }
        return false;
    }
}

# A Semaphore's count.
struct _Permits {
    var free: ulong;
    construct(this.free = 0) {}
}

# A Barrier's round number and how many threads have arrived at it.
struct _BarrierState {
    var round: ulong;
    var arrived: ulong;
}

# How many `count_down()` calls a Latch still waits for.
struct _LatchState {
    var remaining: ulong;
    construct(this.remaining = 0) {}
}
