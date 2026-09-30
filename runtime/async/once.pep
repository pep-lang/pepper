## One-time initialization: `Once` runs a function exactly once however many
## threads ask, and `Lazy<T>` builds a value on first use.

# A Once moves through three states in an `Atomic<int>`: 0 (nothing has run),
# 1 (a thread is running the body) and 2 (done). The fast path, once done, is
# one acquire load. The first caller moves 0 -> 1 under a platform mutex,
# runs the body without holding it, then stores 2 and wakes the callers that
# arrived meanwhile, which sleep on a platform condition variable. The done
# store is a release, so a caller that sees 2 also sees what the body did.

import "thread";
import "sys_posix";
import "sys_windows";

## Runs a function exactly once, however many threads ask, like C++
## `std::call_once` or Rust's `std::sync::Once`.
##
## The first `call` runs its body. Callers that arrive while it runs wait for
## it to finish, and later callers return right away. Every caller sees
## everything the body did once `call` returns.
##
## A Once is `[Shared]`: keep it in a module-scope variable or pass it to
## threads.
##
## @example
##     import async;
##
##     const setup = async.Once();
##     const setups = Atomic<long>(0);
##
##     initialize() {
##         setups.fetch_add(1);
##     }
##
##     work() {
##         setup.call(initialize);   # only the first caller runs it
##     }
[Shared]
export struct Once {
    ## 0 before any call, 1 while a body runs, 2 once it has finished.
    const State: Atomic<int>;

    ## The operating-system id of the thread running the body, or 0.
    const Runner: Atomic<ulong>;

    ## The platform mutex that guards the move from 0 to 1 and the wait.
    const Lock: __ptr<void>;

    ## The platform condition variable that waiting callers sleep on.
    const Finished: __ptr<void>;

    ## Creates a Once whose body has not run.
    ##
    ## @panics if the operating system cannot create a mutex or condition variable
    construct() {
        State = Atomic<int>(0);
        Runner = Atomic<ulong>(0);
        Lock = _async_sys_mutex_create();
        Finished = _async_sys_condition_create();
    }

    destruct {
        _async_sys_condition_destroy(Finished);
        _async_sys_mutex_destroy(Lock);
    }

    ## Runs `body` if no call has run a body yet; otherwise waits until that
    ## run has finished. Everything the body did is visible to the caller
    ## when this returns.
    ##
    ## Only one body ever runs, even if later calls pass different ones.
    ##
    ## @param body the function to run once
    ## @panics if `body` itself calls `call` on the same Once (it would wait for itself forever)
    ## @example
    ##     config_once.call(load_config);
    void call(ThreadBody body) {
        if (this._start()) {
            body();
            this._finish();
        }
    }

    ## Reports whether a body has finished running.
    ##
    ## @returns true once a `call` has completed its body on some thread
    bool is_done() {
        return State.load() == 2;
    }

    # True if the caller must run the body (and then call `_finish`); false
    # once another thread's run has finished.
    bool _start() {
        if (State.load() == 2) {
            return false;
        }
        var me = _async_sys_os_thread();
        _async_sys_mutex_lock(Lock);
        if (State.load() == 0) {
            State.store(1);
            Runner.store(me);
            _async_sys_mutex_unlock(Lock);
            return true;
        }
        if (Runner.load() == me) {
            _async_sys_mutex_unlock(Lock);
            panic("Once.call: the body called 'call' on the Once that is running it");
        }
        while (State.load() != 2) {
            _async_sys_condition_wait(Finished, Lock);
        }
        _async_sys_mutex_unlock(Lock);
        return false;
    }

    # Marks the body finished and wakes every waiting caller.
    void _finish() {
        _async_sys_mutex_lock(Lock);
        Runner.store(0);
        State.store(2);
        _async_sys_condition_notify_all(Finished);
        _async_sys_mutex_unlock(Lock);
    }
}

## A value built on first use by whichever thread asks first, like Rust's
## `LazyLock`. The usual way to give a module-scope variable a value that is
## expensive to build, or that cannot be built before `main` runs.
##
## The first `get()` runs the initializer; threads that call `get()` while it
## runs wait for it, and every later call returns the same value.
##
## `T` must be thread-safe (a number, a `[Shared]` struct, a `shared` function
## type), because every thread gets the same value; `Lazy<String>` is a
## compile error.
##
## @typeParam T the value's type, which must be thread-safe
## @example
##     import async;
##
##     [Shared]
##     struct Settings {
##         const Workers: long;
##         construct(this.Workers = 1) {}
##     }
##
##     load_settings(): Settings {
##         return Settings(async.logical_cpus() as long);
##     }
##
##     const settings = async.Lazy<Settings>(load_settings);
##
##     main(): int {
##         var workers = settings.get().Workers;   # built here, on first use
##         return 0;
##     }
[Shared]
export struct Lazy<T> {
    ## The function that builds the value.
    const Initializer: shared () => T;

    ## A heap slot holding the value once it is built: `sizeof<T>()` bytes,
    ## one reference for a struct `T`.
    const Value: __ptr<T>;

    ## Runs the initializer once.
    const Built: Once;

    ## Creates a Lazy whose value `initializer` builds on the first `get()`.
    ## Nothing runs yet.
    ##
    ## @param initializer builds the value; runs at most once, on the thread that first calls `get()`
    ## @panics if the operating system cannot create a mutex or condition variable
    construct(shared () => T initializer) {
        Initializer = initializer;
        Value = _pep_malloc(sizeof<T>());
        Built = Once();
    }

    destruct {
        Value[0] = __default<T>();
        _pep_free(Value);
    }

    ## Returns the value, building it with the initializer on the first call.
    ##
    ## For a struct `T` the caller gets its own reference.
    ##
    ## @returns the value the initializer built
    ## @panics if the initializer itself calls `get()` on the same Lazy
    T get() {
        if (Built._start()) {
            Value[0] = Initializer();
            Built._finish();
        }
        return Value[0];
    }

    ## Reports whether the value has been built.
    ##
    ## @returns true once a `get()` has finished running the initializer
    bool is_built() {
        return Built.is_done();
    }
}
