# Threads and shared data

The `async` module starts and manages operating-system threads. Pepper keeps
threads safe by controlling what they can share: only **thread-safe** values
can be reached from more than one thread, and the compiler checks the types
that claim to be.

## Starting and joining threads

```pepper
{{#include ../../examples/threads-basics.pep}}
```

- `Thread.spawn(body, name)` starts a new thread that runs `body`, a function
  of type `ThreadBody` (an alias for `shared () => void`), and returns its
  `Thread`. The name is optional.
- `join()` waits for the body to return. After `join()`, the joining thread
  sees everything the other thread did. A thread can be joined once.
- `Thread.current()` returns the calling thread's `Thread`. For a spawned
  thread it is the same object that `spawn` returned. The main thread's is
  named `main`.
- `id()` returns the thread's `ThreadId`, a number that no other thread in
  the program has. Ids come from the runtime, starting at 1, and are not the
  operating system's thread ids. A `ThreadId` can be compared and used as a
  `HashMap` key.
- `is_finished()` reports whether the body has returned. `is_joinable()`
  reports whether `join()` may be called.
- `Thread.sleep(milliseconds)` pauses the calling thread.
- Dropping every reference to a `Thread` without joining it **detaches** the
  thread. It keeps running, and its resources are freed when it finishes.
- A `panic` or failed `assert` on any thread ends the whole program.

The body can be a named function or a [closure](function-types.md). A
closure passes data to the thread through its captures:

```pepper
var total = Atomic<long>(0);
var step: long = 5;
var worker = async.Thread.spawn(() => { total.fetch_add(step); });
worker.join();
```

The body is a [`shared` function value](function-types.md#sharing-function-values-between-threads),
so the closure may capture only thread-safe values (numbers, `Atomic<T>`,
`[Shared]` structs, `shared` function values). The compiler checks each
capture and reports one that is not thread-safe where the closure uses it:

```text
main.pep:5:46: error: closure passed as 'shared () => void' captures 'name' of type 'String', which is not thread-safe
    5 |     var t = async.Thread.spawn(() => { print(name); });
      |                                              ^~~~
main.pep:4:9: note: capture a thread-safe value instead, such as an 'Atomic<T>' or a '[Shared]' struct
    4 |     var name = "worker";
      |         ^~~~
```

Every module-scope variable is `const` and thread-safe, so any thread may
use one (see [below](#module-scope-variables)).

The [Thread reference](../reference/async-thread.md) documents every method.

## Processor counts

- `async.logical_cpus()` returns how many threads the machine can run at the
  same moment. A core with hyperthreading (SMT) counts two or more times.
  This is a good default size for a pool of CPU-bound worker threads.
- `async.physical_cpus()` counts each physical core once. On Linux it reads
  the kernel's CPU topology, on macOS `hw.physicalcpu`, and on Windows
  `GetLogicalProcessorInformationEx`. Inside a virtual machine it counts the
  cores the hypervisor presents, because the guest cannot see the host's
  hardware.

## Per-thread values with ThreadLocal

`ThreadLocal<T>` is a variable with a separate value on every thread:

```pepper
{{#include ../../examples/threads-local.pep}}
```

- `get()` returns the calling thread's value, or the default of `T` (zero, or
  null for a struct) until that thread calls `set`.
- `set(value)` replaces only the calling thread's value.
- `is_set()` and `clear()` test for and remove the calling thread's value.
- When a thread exits, its value is released.

A `ThreadLocal` is usually a module-scope variable. Its `T` does not need to
be thread-safe, because each value stays on the thread that stored it. The
[ThreadLocal reference](../reference/async-thread_local.md) has the details.

## What threads can share

Every struct value is a counted reference (see
[Memory and reference counting](memory.md)). Updating a count from two
threads at once can free an object too early or never, so by default a
struct's counts are plain, fast increments, and its objects must stay on one
thread.

A struct declared `[Shared]` has **atomic** reference counts, so references
to one object can be copied and dropped on any thread:

```pepper
{{#include ../../examples/threads-shared.pep}}
```

The compiler checks every `[Shared]` struct:

- **Every field must be `const`.** It is set once, by the constructor, and
  never assigned again, so threads cannot race on it. To change shared state,
  give the struct a thread-safe member such as an `Atomic<T>`.
- **Every field must have a thread-safe type.** These are the thread-safe
  types:
  - numbers and `bool`;
  - raw pointers (`__ptr<T>`) to thread-safe types;
  - `shared` function types, such as `shared () => void` (see
    [Function types](function-types.md#sharing-function-values-between-threads));
  - `[Shared]` structs, and weak references to them.

  `String`, `Array` and other structs that are not `[Shared]` are not
  thread-safe, and neither is a plain function type such as `() => void`:

  ```text
  main.pep:3:14: error: field 'F' of shared struct 'H' has type '() => void', which is not thread-safe
      3 |     const F: () => void;
        |              ^~~~~~~~~~
  note: declare the function type 'shared () => void' to share it between threads
  ```

A generic `[Shared]` struct is checked for each set of type arguments.
`Atomic<T>` is `[Shared]`, so `Atomic<int>` and `Atomic<Settings>` are fine,
and `Atomic<String>` is an error that points at the code that names it:

```text
main.pep:2:13: error: shared struct 'Atomic<String>' requires thread-safe type arguments; 'String' is not thread-safe
    2 |     var a = Atomic<String>();
      |             ^~~~~~~~~~~~~~
runtime/atomic.pep:40:17: note: required by field 'Data' declared here
runtime/string.pep:33:15: note: 'String' is not declared [Shared]
```

A field that is not `const`, or that has a type that is not thread-safe, is
reported at the field:

```text
main.pep:3:9: error: field 'Count' of shared struct 'Counter' must be 'const'
    3 |     int Count;
      |         ^~~~~
note: threads change a shared struct's state through a thread-safe member such as 'Atomic<T>'
```

`Thread`, `ThreadLocal<T>` and `Atomic<T>` are `[Shared]` themselves.

### Module-scope variables

Every module-scope variable is implicitly shared, exported or not: any
function can use it, and any function can run on any thread. So it follows
the same two rules as a field of a `[Shared]` struct:

- **It must be `const`.** To change the value, give it a thread-safe type such
  as `Atomic<T>`, or a `ThreadLocal<T>` for a value per thread.
- **It must have a thread-safe type** from the list above. A `String`, an
  `Array`, a struct that is not `[Shared]`, a trait value, or a plain function
  value cannot be a module-scope variable; keep it in a local, or in a
  `ThreadLocal<T>`.

```pepper
const max_workers = 8;                  # a number
const jobs_done = Atomic<long>(0);      # changed with fetch_add
const settings = Settings(8080, 3);     # a [Shared] struct
const scratch = ThreadLocal<String>();  # a String per thread
const double: shared (int) => int = (x: int) => x * 2;  # a shared function
```

A variable that breaks a rule is reported at its name or type:

```text
main.pep:1:5: error: module-scope variable 'hits' must be 'const'
    1 | var hits = 0;
      |     ^~~~
note: every thread can reach a module-scope variable; change its state through a thread-safe type such as 'Atomic<T>' or 'ThreadLocal<T>'
```

```text
main.pep:2:15: error: module-scope variable 'origin' has type 'Plain', which is not thread-safe
    2 | const origin: Plain = Plain();
      |               ^~~~~
main.pep:1:8: note: 'Plain' is not declared [Shared]
    1 | struct Plain { var x: int; }
      |        ^~~~~
```

Module-scope variables are initialized before `main` runs, in the order they
are declared, and each file's after those of the files it imports and of the
runtime. So an initializer may use the variables of the files it imports.

## Limitations

- There are no mutexes, condition variables or channels yet. Coordinate
  threads with `Atomic<T>` and `join()`.
