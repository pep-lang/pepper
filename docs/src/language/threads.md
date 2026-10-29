# Threads and shared data

The `async` module starts and manages operating-system threads. Pepper keeps
threads safe by controlling what they can share: only **thread-safe** values
can be reached from more than one thread, and the compiler checks the types
that claim to be.

On WebAssembly (`--target wasm32-wasip1`) a program has one thread:
`Thread.spawn` panics. Mutexes, channels and atomics still work, as long as
nothing waits for another thread (see [WebAssembly](platform-selection.md#webassembly)).

## Starting and joining threads

```pepper
{{#include ../../examples/threads-basics.pep}}
```

- `Thread.spawn(body, name)` starts a new thread that runs `body`, a function
  of type `ThreadBody` (an alias for `shared () => void`), and returns its
  `Thread`. The name is optional.
- `Thread.spawn(body, name, stack_size)` gives the thread `stack_size` bytes
  of stack. Without it a thread gets the system's default: usually 8 MiB on
  Linux (`ulimit -s`), 1 MiB on Windows and 512 KiB on macOS. A thread that
  recurses deeply, such as one walking a deeply nested tree, passes a size so
  it has the same room everywhere. The stack is reserved address space: memory is used only as
  the thread reaches it.
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
- `Thread.sleep(milliseconds)` pauses the calling thread (in a task, only
  the task: see [Tasks](tasks.md#waiting)).
- Dropping every reference to a `Thread` without joining it **detaches** the
  thread. It keeps running, and its resources are freed when it finishes.
- A `panic` or failed `assert` on any thread ends the whole program.

The body can be a named function or a [closure](function-types.md). A
closure passes data to the thread through its captures:

```pepper
var total = async.Atomic<long>(0);
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
main.pep:4:9: note: capture a thread-safe value instead, such as an 'async.Atomic<T>' or a '[Shared]' struct
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
  In a Linux container with a CPU quota (`docker run --cpus`), it is the
  quota rounded up, when that is fewer (see [Containers](os.md#containers)).
- `async.physical_cpus()` counts each physical core once. On Linux it reads
  the kernel's CPU topology, on macOS `hw.physicalcpu`, and on Windows
  `GetLogicalProcessorInformationEx`. Inside a virtual machine it counts the
  cores the hypervisor presents, because the guest cannot see the host's
  hardware.

## Thread-local variables

A module-scope `var` marked `[ThreadLocal]` has a separate copy on every
thread, like C++ `thread_local` or a Rust `#[thread_local]` static:

```pepper
{{#include ../../examples/threads-thread-local.pep}}
```

- Every thread's copy starts from the initializer, which must be a
  constant: a number, `bool` or `char` literal (negated, or cast), an enum
  case, or nothing, for the type's default (zero, or null for a struct).
  To start from anything else, leave the initializer out and set the value
  on the thread's first use.
- Reading or assigning one touches only the calling thread's copy, so it is
  a plain `var`: it need not be `const` like other module-scope variables,
  and needs no atomics or locks. A read is a single load from the thread's
  storage (a `%fs`-relative load on x86-64 Linux), not a call.
- Its type must be thread-safe (see [What threads can share](#what-threads-can-share)):
  a number, a raw pointer, a `[Shared]` struct, a `shared` function type, or
  a tuple or `[Value]` struct of them. A value of any other type, such as a
  `String`, goes in a [`ThreadLocal<T>`](#per-thread-values-with-threadlocal).
- When a thread started with `Thread.spawn` exits (the `async` runtime's
  workers and blocking threads included), each of its thread-locals is set to
  its default and the struct it held is released, last declared first. The
  main thread's are never released, like every other module-scope variable,
  and a thread started by C code does not release its own.
- A task sees the thread-locals of the worker thread it runs on, as with a
  `ThreadLocal<T>`.

`[ThreadLocal]` applies only to a module-scope variable. A variable whose
type is not thread-safe, or whose initializer is not a constant, is
reported at the type or the initializer:

```text
main.pep:3:14: error: thread-local variable 'scratch' has type 'Plain', which is not thread-safe
    3 | var scratch: Plain;
      |              ^~~~~
note: a per-thread value of any type is an 'async.ThreadLocal<T>' (after 'import async')
main.pep:1:8: note: 'Plain' is not declared [Shared]
    1 | struct Plain { var x: int; }
      |        ^~~~~
```

```text
main.pep:3:18: error: thread-local variable 'depth' must start from a constant
    3 | var depth: int = start();
      |                  ^~~~~
note: every thread starts from this value; leave it out and assign the value on the thread's first use instead
```

## Per-thread values with ThreadLocal

`ThreadLocal<T>` is a variable with a separate value on every thread, of
any type:

```pepper
{{#include ../../examples/threads-local.pep}}
```

- `get()` returns the calling thread's value, or the default of `T` (zero, or
  null for a struct) until that thread calls `set`.
- `set(value)` replaces only the calling thread's value.
- `is_set()` and `clear()` test for and remove the calling thread's value.
- When a thread started with `Thread.spawn` exits, its value is released,
  even if the `ThreadLocal` itself was destroyed first. As with
  `[ThreadLocal]` variables, the main thread's value is released only by
  `clear()`, and a thread started by C code leaks the values it did not
  clear.
- Each thread keeps its values in a table of its own, held in
  `[ThreadLocal]` variables, so `get()` costs a few loads and no call, and a
  program can have any number of `ThreadLocal`s.

A `ThreadLocal` is usually a module-scope variable. Its `T` does not need to
be thread-safe, because each value stays on the thread that stored it. For a
`T` that is not thread-safe, such as a `String`, the value is reached like a
Mutex's (see [What a lock body may do](#what-a-lock-body-may-do)):

- `with (var value = local.enter()) { ... }` binds this thread's value; the
  `else` block runs when the thread has none;
- `get()` is a compile error;
- `set(value)` takes a new value: a constructor call, a string literal,
  `copy(x)`, or `move(x)`.

Otherwise a function called while a Mutex is locked could keep part of the
locked value in a thread-local, and a later `get()` would hand it out after
the lock was released. The
[ThreadLocal reference](../reference/async-thread_local.md) has the details.

Tasks that take turns on one worker thread share its `ThreadLocal` values;
a [`TaskLocal<T>`](tasks.md#task-local-values) gives each task its own.

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
- **Every field must have a thread-safe type.** These are all the
  thread-safe types, the same ones the constraint
  [`T: Shared`](generics.md#the-shared-constraint) accepts:
  - every number type (`int`, `long`, `byte`, `char`, `short`, `float`,
    `double` and the rest), `bool`, and `void`;
  - [enums](enums.md) whose cases carry no values, which are stored as
    integers;
  - `[Shared]` structs, and enums whose cases carry values that are declared
    `[Shared]`;
  - weak references to thread-safe types;
  - raw pointers (`__ptr<T>`, and `void*`) to thread-safe types;
  - `shared` function types, such as `shared () => void` (see
    [Function types](function-types.md#sharing-function-values-between-threads)),
    and C function pointer types (`extern (int) => int`);
  - [tuples](tuples.md) whose elements are all thread-safe;
  - inside a generic, a type parameter constrained `T: Shared`.

  Nothing else is. A struct is never thread-safe on its own, even when all
  its fields are numbers: a struct value is a reference to a
  reference-counted object, and only a `[Shared]` struct counts those
  references atomically. So `String`, `Array` and other structs that are not
  `[Shared]` are not thread-safe, and neither is a plain function type such
  as `() => void`:

  ```text
  main.pep:3:14: error: field 'F' of shared struct 'H' has type '() => void', which is not thread-safe
      3 |     const F: () => void;
        |              ^~~~~~~~~~
  note: declare the function type 'shared () => void' to share it between threads
  ```

A generic `[Shared]` struct whose parameter has no constraint is checked
for each set of type arguments, and the error points at the code that asked
for the specialization:

```pepper
[Shared]
struct Cell<T> {
    const value: T;
}

make<T>(): Cell<T> { return Cell<T>(); }

main(): int {
    var c = make<String>();
    return 0;
}
```

```text
main.pep:9:13: error: 'make<String>' requires thread-safe type arguments; 'String' is not thread-safe
    9 |     var c = make<String>();
      |             ^~~~~~~~~~~~
main.pep:6:29: note: 'Cell<String>' is required here, in 'make<String>'
    6 | make<T>(): Cell<T> { return Cell<T>(); }
      |                             ^~~~~~~
main.pep:3:18: note: required by field 'value' declared here
    3 |     const value: T;
      |                  ^
runtime/string.pep:54:15: note: 'String' is not declared [Shared]
```

A generic can state the rule up front with the built-in constraint
[`T: Shared`](generics.md#the-shared-constraint): `[Shared] struct
Cell<T: Shared>` accepts exactly the type arguments above, and a wrong one
is reported where it is written (`'String' does not conform to 'Shared',
required by 'T' in 'Cell'`). The standard library's `Atomic<T>`, `spawn`,
`run_blocking` and `Lazy<T>` do this, so `Atomic<String>` is reported at
`String`.

A field that is not `const`, or that has a type that is not thread-safe, is
reported at the field:

```text
main.pep:3:9: error: field 'Count' of shared struct 'Counter' must be 'const'
    3 |     int Count;
      |         ^~~~~
note: threads change a shared struct's state through a thread-safe member such as 'async.Atomic<T>' (after 'import async')
```

`Thread`, `ThreadLocal<T>` and `Atomic<T>` are `[Shared]` themselves, and so
are the synchronization types below: `Channel<T>`, `Mutex<T>`,
`Condition<T>`, `RwLock<T>`, `Semaphore`, `Barrier`, `Latch`, `Once` and
`Lazy<T>`.

### Module-scope variables

Every module-scope variable is implicitly shared, exported or not: any
function can use it, and any function can run on any thread. So it follows
the same two rules as a field of a `[Shared]` struct:

- **It must be `const`.** To change the value, give it a thread-safe type such
  as `Atomic<T>`, or a `ThreadLocal<T>` for a value per thread. The one
  exception is a [`[ThreadLocal]` variable](#thread-local-variables), which
  every thread has its own copy of.
- **It must have a thread-safe type** from the list above. A `String`, an
  `Array`, a struct that is not `[Shared]`, a trait value, or a plain function
  value cannot be a module-scope variable; keep it in a local, or in a
  `ThreadLocal<T>`.

```pepper
const MAX_WORKERS = 8;                  # a number
const jobs_done = async.Atomic<long>(0);  # changed with fetch_add
const settings = Settings(8080, 3);     # a [Shared] struct
const scratch = ThreadLocal<String>();  # a String per thread
const double: shared (int) => int = (x: int) => x * 2;  # a shared function
[ThreadLocal]
var depth: int = 0;                     # a copy per thread
```

A variable that breaks a rule is reported at its name or type:

```text
main.pep:1:5: error: module-scope variable 'hits' must be 'const'
    1 | var hits = 0;
      |     ^~~~
note: every thread can reach a module-scope variable; change its state through a thread-safe type such as 'async.Atomic<T>' (after 'import async'), or declare it '[ThreadLocal]' to give each thread its own copy
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

## Channels

A `Channel<T>` carries values from threads that send to threads that
receive, with any number of each, like a Go channel. (In a
[task](tasks.md#mutexes-channels-and-conditions), a wait parks only the
task, and so do the waits of `Mutex` and `Condition` below.)

```pepper
{{#include ../../examples/threads-channel.pep}}
```

- `Channel<T>(capacity)` makes a channel that holds at most `capacity`
  values; `send` waits while it is full. `Channel<T>()` (capacity 0) is
  unbounded, and `send` never waits.
- `send(value)` queues a value and returns `true`, or returns `false` if the
  channel is closed. `try_send(value)` does not wait: it also returns
  `false` when a bounded channel is full.
- `receive()` waits for the next value and returns a `Result<T>`: the
  value, or an error once the channel is closed and empty.
  `try_receive()` returns an error right away when nothing is waiting, and
  `receive_for(milliseconds)` when the time runs out.
- `close()` ends the stream and wakes every waiting sender and receiver.
  Values already queued are still received. Only `close()` closes a
  channel: dropping it, or ending the threads that use it, does not.
- `for (var v in channel)` receives until the channel is closed and empty.
  Several threads can loop over one channel; each value goes to one of them.
- Values from one sender arrive in the order they were sent.
- The `count` property and `is_closed()` report the channel's state, which other
  threads may change right after.

`send` and `try_send` take a **new** value, which nothing on the sending
thread references, and hand it to the receiver without copying it: a
constructor call, a literal, a call that returns a fresh value (through a
`shared` function value too, when its arguments are new: it reaches nothing
else that is not thread-safe),
[`move(x)`](memory.md#handing-a-reference-over-with-move) (a variable that
holds the only reference) or [`copy(x)`](memory.md#copying-a-value-with-copy)
(when the sender keeps using `x`). A `String`, an `Array` or a struct of them
can be sent, and changing the original after sending a copy does not change
what was sent:

```pepper
{{#include ../../examples/threads-copy.pep}}
```

Sending a variable that something else may still reference is an error, and
the editor offers both fixes:

```text
main.pep:7:16: error: 'line' is not a new value, but parameter 'value' takes a value that nothing else references
    7 |     lines.send(line);
      |                ^~~~
      |                move(line)
runtime/async/channel.pep:173:17: note: 'value' is declared [Move] here
  173 |     send([Move] value: T): bool {
      |                 ^~~~~
note: hand it over with 'move(line)', or pass a new value, such as 'copy(line)'
```

A thread-safe value (a number, a `[Shared]` struct, a `shared` function value
such as a `ThreadBody`) passes freely, which makes a channel of `ThreadBody`
values a work queue. Since nothing is copied, a channel can carry any type,
trait values and values that cannot be copied (an `io.File`) included.

The [Channel reference](../reference/async-channel.md) documents every
method.

### Waiting on several channels with Select

A `Select<E>` waits on several channels at once and takes the first value
any of them receives (or, with a send arm, sends to the first with room),
like Go's `select`. Each channel is added with a
function that turns its values into an `E`, usually a case of an
[enum](enums.md) of your own that carries the value, so the channels may
carry different types and a `match` handles the result:

```pepper
{{#include ../../examples/threads-select.pep}}
```

- `receive(channel, wrap)` adds a channel. `wrap` runs on the waiting
  thread, with the value received.
- `wait()` waits until a channel has a value and returns it as an `E`, in a
  `Result<E>`. `wait_for(milliseconds)` gives up after that long, and
  `try_wait()` does not wait at all.
- The value is taken under that channel's own lock, so no other receiver
  can take it between "ready" and "take".
- When several channels have values, each wait starts just after the
  channel that fired last, so one busy channel cannot starve the others.
- A channel that is closed and empty is skipped. Once every channel is,
  `wait()` returns an error (`every channel is closed`). A timeout's error
  is `the time ran out`.
- A `Select` belongs to the thread (or [task](tasks.md)) that made it; it
  is not `[Shared]`. In a task, waiting parks the task, and a cancel or the
  task's `timeout` ends the wait.

A `Select` can also wait to send, like a `case ch <- v` in Go's `select`.
`send(channel, value, sent)` adds a send arm: `wait()` fires it once
`channel` has room (a bounded channel that is full waits), and returns what
`sent` returns. Here a loop keeps receiving jobs while each result waits for
room in a bounded channel:

```pepper
{{#include ../../examples/threads-select-send.pep}}
```

- `value` must be a new value, as for `Channel.send` (`move(x)`, `copy(x)`,
  a constructor call, ...). The select holds it and moves it into the
  channel only when that arm fires, under the channel's lock, so it is never
  sent when another arm fires first.
- A send arm fires once: after its value is sent it leaves the select, so
  the next `wait()` does not send it again. Add another with `send` for the
  next value.
- A send arm whose channel is closed is skipped like a closed receive
  channel, and its value is dropped with the select.

The [Select reference](../reference/async-select.md) documents every method.

## Mutexes and conditions

A `Mutex<T>` owns a value that one thread at a time can use. The way to
reach the value is a [`with` block](scopes.md):

```pepper
{{#include ../../examples/threads-mutex.pep}}
```

- `with (var v = mutex.lock()) { ... }` waits until no other thread holds
  the lock, binds the value, and unlocks when the block ends by any path:
  the end of the body, `return`, `break` or `continue`. Everything a thread
  did while it held the lock is visible to the next thread that takes it.
- `try_lock()` does not wait. With `with (var v = mutex.try_lock()) { ... }
  else { ... }`, the body runs if the lock was free and the `else` block runs
  if it was not.
- A Mutex is not re-entrant: calling `lock()` again on the thread that holds
  it panics instead of deadlocking. `is_held()` reports whether the calling
  thread holds it.
- A `panic` while a Mutex is held ends the program, so a Mutex is never left
  "poisoned".
- Taking a free lock is one atomic instruction, and a thread that finds it
  held spins briefly before it sleeps. Locks sleep on the operating system's
  wait-on-address call (`futex` on Linux, `__ulock_wait` on macOS,
  `WaitOnAddress` on Windows), as Rust's do.

`T` is a struct type: a struct of your own, an `Array<String>`, or a
`[Shared]` struct whose `Atomic` fields must change as a unit.
`Mutex<int>` is an error (use `async.Atomic<int>`). A Mutex of values that are not
thread-safe is kept apart from the rest of the program by the compiler; see
[What a lock body may do](#what-a-lock-body-may-do).

- `Mutex<T>(value)` and `replace(value)` take a **new** value: a constructor
  call, a string literal, a call that returns a fresh value, `copy(x)`, or
  `move(x)`, never a variable something else still references. The caller
  hands its reference over, so nothing is copied.
- `replace(value)` swaps the whole value under the lock and returns the old
  one, which the caller then owns outright.

A value built in a local variable goes in with
[`move`](memory.md#handing-a-reference-over-with-move), which hands over the
variable's reference instead of copying the value:

```pepper
{{#include ../../examples/threads-move.pep}}
```

A `Condition<T>` lets a thread that holds a Mutex sleep until another thread
changes the value. Get one with `mutex.condition()`:

```pepper
{{#include ../../examples/threads-condition.pep}}
```

- `wait()` must run while the caller holds the Mutex, normally
  inside its `with` block. It unlocks, sleeps until notified, and locks again
  before returning. It panics if the caller does not hold the Mutex.
- A thread can wake without a notification (a spurious wakeup), and another
  thread may get to the value first, so always wait in a loop that re-checks
  what it waits for.
- `wait_for(milliseconds)` gives up after that long and returns `false`.
- `notify_one()` wakes one waiting thread, and `notify_all()` wakes them all.

`wait_while(predicate)` writes that loop for you: it waits while
`predicate` returns true for the locked value, asking again after every
wakeup, and returns with the Mutex still locked. `wait_while_for(milliseconds,
predicate)` gives up after that long and returns `false`:

```pepper
{{#include ../../examples/threads-wait-while.pep}}
```

The predicate is given the locked value as its parameter, since a closure
cannot capture part of a locked value. It must be a closure written at the
call, and the compiler checks its body as it checks a lock body (see
[What a lock body may do](#what-a-lock-body-may-do)): it cannot keep any
part of the value, or bring in a value from outside.

```text
main.pep:10:26: error: 'queue[0]' is part of the value locked by 'queue' and cannot outlive the lock
   10 |             saved.append(queue[0]);
      |                          ^~~~~~~~
main.pep:9:27: note: locked here
    9 |         ready.wait_while((queue: Array<String>): bool => {
      |                           ^~~~~
note: 'String' is not thread-safe, so no part of the locked value may be kept outside the block; take 'copy(queue[0])'
```

The [Mutex reference](../reference/async-mutex.md) documents `Mutex`,
`MutexGuard` and `Condition`.

## What a lock body may do

A value that is not thread-safe counts its references plainly, so no thread
may hold a reference into a Mutex's value while the Mutex is unlocked. The
compiler checks each `with` block over a lock so that none can:

```pepper
{{#include ../../examples/threads-lock-body.pep}}
```

Inside the block, every value that is not thread-safe is either **part of
the locked value** (the binding, its fields and elements, and what calls on
them return), from **outside** (a parameter, `this`, or a variable declared
before the block), or **new**. A new value may join either side; the other
two must never meet:

- **Moving in.** A call, constructor or assignment that would link an
  outside value with the locked one is an error. Pass a new value instead:
  `copy(line)`, a literal, or the result of a call that returns a fresh
  value. A variable that holds the only reference to its value can hand it
  over with `move(line)`.

  ```text
  main.pep:8:21: error: 'line' cannot move into the value locked by 'names'
      8 |         list.append(line);
        |                     ^~~~
  main.pep:7:28: note: locked here
      7 |     with (var list = names.lock()) {
        |                            ^~~~
  note: 'String' is not thread-safe, so the locked value cannot share it with the rest of the program; pass 'copy(line)'
  ```

- **Moving out.** Storing part of the locked value outside the block, or
  returning it from the block, is an error; take a copy
  (`copy(list[0])`, or `list[0].copy()`, which returns a fresh value).

  ```text
  main.pep:8:17: error: 'list[0]' is part of the value locked by 'names' and cannot outlive the lock
      8 |         first = list[0];
        |                 ^~~~~~~
  ```

  A value that [cannot be copied](memory.md#copying-a-value-with-copy)
  cannot leave the block at all. The note then says why instead of
  suggesting `copy(...)`, naming the field that blocks the copy:

  ```text
  note: 'Reply' cannot be copied: field 'callback' of 'Reply' holds '() => void', which is a plain function value
  ```

- **Closures.** A closure written in the block cannot capture part of the
  locked value, since a function value could carry it out.
- **Two locks.** Values locked by two nested blocks stay apart as well.
  A variable declared in the outer block, before the inner one, is from
  outside to the inner block: it outlives the inner lock, so it may hold the
  outer block's value but no part of the inner one's, whether it would hold
  it directly, in a field, through a closure, or from one pass of a loop to
  the next.
- **Numbers pass freely**, as do every thread-safe value and every new one.

Which calls link which values comes from what the called function does: the
compiler works out, for every function, whether it keeps an argument (as
`append` keeps its element) and whether its result shares anything with its
arguments. A result that shares nothing, such as that of `+`, `substr`,
`copy()` or a constructor, is **fresh**, and may cross in either direction.
The language server shows "Returns a fresh value" when hovering over such a
function. A call through a function value links its result with its
arguments and with what the function value captured, so it is fresh only
when the function value and its arguments are new. A value an `extern`
function hands back, and a value read through raw memory that a `[Shared]`
struct holds, are never fresh: something else may reference them. The runtime takes
the few values it hands out that nothing else references out of raw memory
with `move(p[i])`, a promise the compiler cannot check and allows only in the
runtime: a channel's `receive()` (the value `send` handed over) and a Mutex's
`replace()`.

A function that returns a [tuple](tuples.md) has one such fact per element:
after `var (fresh, same) = split(line);`, `fresh` may move into a locked value
while `same`, which `split` returned from its argument, may not.

The guard a `lock()` returns can only be the scope of a `with` header: storing
it in a variable or field is an error, so no lock outlives its block.

Two attributes carry these rules, and code outside the runtime may use them
too:

- `[Isolated]` on a struct makes it a guard: it can only be the scope of a
  `with` header, and the block is checked as above. `MutexGuard<T>` and
  `ThreadLocalGuard<T>` are `[Isolated]`.
- `[Move]` on a parameter (`construct([Move] T value)`) requires a new
  value for it at every call: a constructor call, a literal, a fresh result,
  `copy(x)`, `move(x)`, or any thread-safe value. The caller hands its
  reference over, so the function receives it without a count step.

### Checking confinement at run time

Raw memory (`__ptr<T>`) and `extern` code are promises the compiler cannot
check, so a program that uses them can still keep a reference into a locked
value. Set the environment variable `PEP_CHECK_SYNC` when running a program
to check at every unlock that nothing outside the locked value refers into
it:

```text
$ PEP_CHECK_SYNC=1 ./main
PEP_CHECK_SYNC: an object in the value locked by a 'Mutex<Box>' is still referenced from outside it
```

The check copies the locked value to count the references inside it, so it
costs time and memory in proportion to the value's size at each unlock; it
is off unless the variable is set. It checks a `Mutex<T>` whose `T` is not
thread-safe and can be [copied](memory.md#copying-a-value-with-copy).

## Reader/writer locks

An `RwLock<T>` lets many threads read a value at once, or one thread
write it:

```pepper
{{#include ../../examples/threads-rwlock.pep}}
```

- `with (var v = lock.read()) { ... }` waits until no writer holds or waits
  for the lock; any number of threads may read at the same time.
- `with (var v = lock.write()) { ... }` waits until no other thread holds
  the lock at all.
- `try_read()` and `try_write()` do not wait: the `else` block runs when the
  lock is not free.
- `replace(value)` swaps the whole value under the write lock and returns
  the old one.
- Writers come first: while a writer waits, new readers wait behind it, so
  readers cannot keep it out forever. A thread that reads must therefore not
  ask to read again before its block ends, and asking to write while holding
  the lock panics instead of deadlocking.

`T` must be thread-safe, as for `Atomic<T>`: typically a `[Shared]` struct
whose `Atomic` fields a writer changes together. Readers that hold the
value at once each copy a reference to it, so a value that is not
thread-safe, such as an `Array<String>`, would have its reference counts
changed by several threads at a time; it is a compile error at the type
argument. Put such a value in a `Mutex<T>`. When readers only need the
latest value and writers replace it whole, an `Atomic<T>` holding a
`[Shared]` struct does the same job without a lock.

## Semaphores, barriers and latches

Three types coordinate threads by counting. Each is `[Shared]`, so keep it
in a module-scope variable or pass it to threads:

- A `Semaphore(permits)` lets at most `permits` threads hold a permit at
  once. `acquire()` waits for a free permit and takes it, `try_acquire()`
  takes one only if one is free, and `release()` gives one back.
  `with (semaphore.permit()) { ... }` holds a permit for the block and gives
  it back on every path out.
- A `Barrier(count)` makes groups of `count` threads meet: `wait()` sleeps
  until `count` threads have called it, then all go on together. It returns
  `true` on exactly one of them, the leader, and resets for the next round.
- A `Latch(count)` opens once `count_down()` has been called `count` times.
  `wait()` sleeps until it is open, and `is_ready()` asks without waiting.
  It is one-shot: counting down an open latch panics.

```pepper
{{#include ../../examples/threads-coordination.pep}}
```

Each is a `Mutex` over its counts with a `Condition` to sleep on, so in a
[task](tasks.md#mutexes-channels-and-conditions) their waits park the task,
not its worker.

## Once and Lazy

`Once` runs a function exactly once, however many threads ask, and `Lazy<T>`
builds a value the first time a thread asks for it:

```pepper
{{#include ../../examples/threads-lazy.pep}}
```

- `once.call(body)` runs `body` if no call has run one yet. Threads that
  call it while the body runs wait for it, and every caller sees what the
  body did. `is_done()` reports whether it has run.
- `Lazy<T>(initializer)` takes a `shared () => T` function. The first
  `get()` runs it; later calls, from any thread, return the same value.
  `is_built()` reports whether it has run.
- A `Lazy<T>` is the usual way to give a module-scope variable a value that
  is expensive to build, or that cannot be built before `main` runs. Its `T`
  must be thread-safe, since every thread gets the same value.

The [Once reference](../reference/async-once.md) has the details.

## Limitations

- `Lazy<T>` holds only thread-safe values.
- A value received from a channel moves into a locked value directly
  (`list.append(jobs.receive().value())`), but not through a variable
  declared outside the block: such a variable is an outside value, whatever
  it holds, so it needs `copy`, or `move` when it holds the only reference
  (`list.append(move(job))`).
- A Mutex is not re-entrant, and neither is an `RwLock`.
- The value a `Select`'s `wait()` returns is not a new value for a lock
  body, since it comes from `wrap`, a function value the `Select` keeps,
  and may share what `wrap` captured; `copy` it to move it into a locked
  value.
- Deadlocks are not detected, except locking a Mutex twice on one thread,
  or asking to write an `RwLock` the thread holds, which panic.
