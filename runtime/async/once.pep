## One-time initialization: `Once` runs a function exactly once however many
## threads ask, and `Lazy<T>` builds a value on first use.

# A Once moves through three states in an `Atomic<int>`: 0 (nothing has run),
# 1 (a thread is running the body) and 2 (done). The fast path, once done, is
# one acquire load. The first caller moves 0 -> 1 under a platform mutex,
# runs the body without holding it, then stores 2 and wakes the callers that
# arrived meanwhile, which sleep on a platform condition variable. The done
# store is a release, so a caller that sees 2 also sees what the body did.

import "atomic";
import "sys_posix";
import "sys_wasi";
import "sys_windows";
import "thread";

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
    # 0 before any call, 1 while a body runs, 2 once it has finished.
    const _state: Atomic<int>;

    # The operating-system id of the thread running the body, or 0.
    const _runner: Atomic<ulong>;

    # The platform mutex that guards the move from 0 to 1 and the wait.
    const _lock: __ptr<void>;

    # The platform condition variable that waiting callers sleep on.
    const _finished: __ptr<void>;

    ## Creates a Once whose body has not run.
    ##
    ## @panics if the operating system cannot create a mutex or condition variable
    construct() {
        _state = Atomic<int>(0);
        _runner = Atomic<ulong>(0);
        _lock = _async_sys_mutex_create();
        _finished = _async_sys_condition_create();
    }

    destruct {
        _async_sys_condition_destroy(_finished);
        _async_sys_mutex_destroy(_lock);
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
    call(body: ThreadBody) {
        if (this._start()) {
            body();
            this._finish();
        }
    }

    ## Reports whether a body has finished running.
    ##
    ## @returns true once a `call` has completed its body on some thread
    is_done(): bool {
        return _state.load() == 2;
    }

    # True if the caller must run the body (and then call `_finish`); false
    # once another thread's run has finished.
    _start(): bool {
        if (_state.load() == 2) {
            return false;
        }
        var me = _async_sys_os_thread();
        _async_sys_mutex_lock(_lock);
        if (_state.load() == 0) {
            _state.store(1);
            _runner.store(me);
            _async_sys_mutex_unlock(_lock);
            return true;
        }
        if (_runner.load() == me) {
            _async_sys_mutex_unlock(_lock);
            panic("Once.call: the body called 'call' on the Once that is running it");
        }
        while (_state.load() != 2) {
            _async_sys_condition_wait(_finished, _lock);
        }
        _async_sys_mutex_unlock(_lock);
        return false;
    }

    # Marks the body finished and wakes every waiting caller.
    _finish() {
        _async_sys_mutex_lock(_lock);
        _runner.store(0);
        _state.store(2);
        _async_sys_condition_notify_all(_finished);
        _async_sys_mutex_unlock(_lock);
    }
}

## A value built on first use by whichever thread asks first, like Rust's
## `LazyLock`. The usual way to give a module-scope variable a value that is
## expensive to build, or that cannot be built before `main` runs.
##
## The first `get()` runs the initializer; threads that call `get()` while it
## runs wait for it, and every later call returns the same value.
##
## `T` is constrained `Shared` (a thread-safe type such as a number, a
## `[Shared]` struct, or a `shared` function type), because every thread
## gets the same value; `Lazy<String>` is a compile error.
##
## @typeParam T the value's type, which must be thread-safe (`T: Shared`)
## @example
##     import async;
##
##     [Shared]
##     struct Settings {
##         const workers: long;
##         construct(this.workers = 1) {}
##     }
##
##     load_settings(): Settings {
##         return Settings(async.logical_cpus() as long);
##     }
##
##     const settings = async.Lazy<Settings>(load_settings);
##
##     main(): int {
##         var workers = settings.get().workers;   # built here, on first use
##         return 0;
##     }
[Shared]
export struct Lazy<T: Shared> {
    # The function that builds the value.
    const _initializer: shared () => T;

    # A heap slot holding the value once it is built: `sizeof<T>()` bytes,
    # one reference for a struct `T`.
    const _value: __ptr<T>;

    # Runs the initializer once.
    const _built: Once;

    ## Creates a Lazy whose value `initializer` builds on the first `get()`.
    ## Nothing runs yet.
    ##
    ## @param initializer builds the value; runs at most once, on the thread that first calls `get()`
    ## @panics if the operating system cannot create a mutex or condition variable
    construct(initializer: shared () => T) {
        _initializer = initializer;
        _value = _pep_malloc(sizeof<T>());
        _built = Once();
    }

    destruct {
        _value[0] = __default<T>();
        _pep_free(_value);
    }

    ## Returns the value, building it with the initializer on the first call.
    ##
    ## For a struct `T` the caller gets its own reference.
    ##
    ## @returns the value the initializer built
    ## @panics if the initializer itself calls `get()` on the same Lazy
    get(): T {
        if (_built._start()) {
            _value[0] = _initializer();
            _built._finish();
        }
        return _value[0];
    }

    ## Reports whether the value has been built.
    ##
    ## @returns true once a `get()` has finished running the initializer
    is_built(): bool {
        return _built.is_done();
    }
}
