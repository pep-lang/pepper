<!-- Generated from runtime/async/once.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# async/once.pep

One-time initialization: `Once` runs a function exactly once however many
threads ask, and `Lazy<T>` builds a value on first use.

Source: `runtime/async/once.pep`

## Once

```pepper
[Shared] struct Once
```

Runs a function exactly once, however many threads ask, like C++
`std::call_once` or Rust's `std::sync::Once`.

The first `call` runs its body. Callers that arrive while it runs wait for
it to finish, and later callers return right away. Every caller sees
everything the body did once `call` returns.

A Once is `[Shared]`: keep it in a module-scope variable or pass it to
threads.

**Example**
```pepper
    import async;

    const setup = async.Once();
    const setups = Atomic<long>(0);

    initialize() {
        setups.fetch_add(1);
    }

    work() {
        setup.call(initialize);   # only the first caller runs it
    }
```

### Fields

#### State

```pepper
const State: Atomic<int>
```

0 before any call, 1 while a body runs, 2 once it has finished.

#### Runner

```pepper
const Runner: Atomic<ulong>
```

The operating-system id of the thread running the body, or 0.

#### Lock

```pepper
const Lock: __ptr<void>
```

The platform mutex that guards the move from 0 to 1 and the wait.

#### Finished

```pepper
const Finished: __ptr<void>
```

The platform condition variable that waiting callers sleep on.

### Constructor

#### Once()

```pepper
construct()
```

Creates a Once whose body has not run.

**Panics**
- if the operating system cannot create a mutex or condition variable

### Methods

#### call

```pepper
void call(ThreadBody body)
```

Runs `body` if no call has run a body yet; otherwise waits until that
run has finished. Everything the body did is visible to the caller
when this returns.

Only one body ever runs, even if later calls pass different ones.

**Parameters**
- `body` — the function to run once

**Panics**
- if `body` itself calls `call` on the same Once (it would wait for itself forever)

**Example**
```pepper
    config_once.call(load_config);
```

#### is_done

```pepper
bool is_done()
```

Reports whether a body has finished running.

**Returns**
- true once a `call` has completed its body on some thread

## Lazy

```pepper
[Shared] struct Lazy<T>
```

A value built on first use by whichever thread asks first, like Rust's
`LazyLock`. The usual way to give a module-scope variable a value that is
expensive to build, or that cannot be built before `main` runs.

The first `get()` runs the initializer; threads that call `get()` while it
runs wait for it, and every later call returns the same value.

`T` must be thread-safe (a number, a `[Shared]` struct, a `shared` function
type), because every thread gets the same value; `Lazy<String>` is a
compile error.

**Type parameters**
- `T` — the value's type, which must be thread-safe

**Example**
```pepper
    import async;

    [Shared]
    struct Settings {
        const Workers: long;
        construct(this.Workers = 1) {}
    }

    load_settings(): Settings {
        return Settings(async.logical_cpus() as long);
    }

    const settings = async.Lazy<Settings>(load_settings);

    main(): int {
        var workers = settings.get().Workers;   # built here, on first use
        return 0;
    }
```

### Fields

#### Initializer

```pepper
const Initializer: shared () => T
```

The function that builds the value.

#### Value

```pepper
const Value: __ptr<T>
```

A heap slot holding the value once it is built: `sizeof<T>()` bytes,
one reference for a struct `T`.

#### Built

```pepper
const Built: Once
```

Runs the initializer once.

### Constructor

#### Lazy()

```pepper
construct(shared () => T initializer)
```

Creates a Lazy whose value `initializer` builds on the first `get()`.
Nothing runs yet.

**Parameters**
- `initializer` — builds the value; runs at most once, on the thread that first calls `get()`

**Panics**
- if the operating system cannot create a mutex or condition variable

### Methods

#### get

```pepper
T get()
```

Returns the value, building it with the initializer on the first call.

For a struct `T` the caller gets its own reference.

**Returns**
- the value the initializer built

**Panics**
- if the initializer itself calls `get()` on the same Lazy

#### is_built

```pepper
bool is_built()
```

Reports whether the value has been built.

**Returns**
- true once a `get()` has finished running the initializer
