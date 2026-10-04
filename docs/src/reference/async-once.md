<!-- Generated from runtime/async/once.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Once and Lazy

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

### Constructor

#### Once()

```pepper
construct()
```

Creates a Once whose body has not run.

### Methods

#### call

```pepper
call(body: ThreadBody)
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
is_done(): bool
```

Reports whether a body has finished running.

**Returns**
- true once a `call` has completed its body on some thread

## Lazy

```pepper
[Shared] struct Lazy<T: Shared>
```

A value built on first use by whichever thread asks first, like Rust's
`LazyLock`. The usual way to give a module-scope variable a value that is
expensive to build, or that cannot be built before `main` runs.

The first `get()` runs the initializer; threads that call `get()` while it
runs wait for it, and every later call returns the same value.

`T` is constrained `Shared` (a thread-safe type such as a number, a
`[Shared]` struct, or a `shared` function type), because every thread
gets the same value; `Lazy<String>` is a compile error.

**Type parameters**
- `T` — the value's type, which must be thread-safe (`T: Shared`)

**Example**
```pepper
import async;

[Shared]
struct Settings {
    const workers: long;
    construct(this.workers = 1) {}
}

load_settings(): Settings {
    return Settings(async.logical_cpus() as long);
}

const settings = async.Lazy<Settings>(load_settings);

main(): int {
    var workers = settings.get().workers;   # built here, on first use
    return 0;
}
```

### Constructor

#### Lazy()

```pepper
construct(initializer: shared () => T)
```

Creates a Lazy whose value `initializer` builds on the first `get()`.
Nothing runs yet.

**Parameters**
- `initializer` — builds the value; runs at most once, on the thread that first calls `get()`

### Methods

#### get

```pepper
get(): T
```

Returns the value, building it with the initializer on the first call.

For a struct `T` the caller gets its own reference.

**Returns**
- the value the initializer built

**Panics**
- if the initializer itself calls `get()` on the same Lazy

#### is_built

```pepper
is_built(): bool
```

Reports whether the value has been built.

**Returns**
- true once a `get()` has finished running the initializer
