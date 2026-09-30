# Atomics

An **atomic** value can be read and updated by several threads at once without
a data race: every operation on it happens as one indivisible step. Pepper
provides this through `async.Atomic<T>`, the equivalent of C++
`std::atomic<T>`.

Threads themselves, and the rules for what they can share, are in
[Threads and shared data](threads.md).

## Atomic&lt;T&gt;

`Atomic<T>` belongs to the [`async` module](threads.md), with the other
types threads share: `import async` and write `async.Atomic<T>`, or bring
the name in with `import [Atomic] from async`. The
[Atomic reference](../reference/async-atomic.md) documents every method.

```pepper
{{#include ../../examples/atomics-basics.pep}}
```

| Method | What it does |
|---|---|
| `Atomic<T>(value)` | Creates an atomic holding `value` (zero, or null for a struct type, if you leave it out). |
| `load()` | Reads the value. |
| `store(v)` | Replaces the value with `v`. |
| `compare_exchange(expected, desired)` | Stores `desired` only if the value is currently `expected`; returns whether it did. |
| `exchange(v)` | Stores `v` and returns the value it replaced. |
| `fetch_add(v)`, `fetch_sub(v)` | Adds or subtracts `v`; returns the value from before. Overflow wraps around. |
| `fetch_and(v)`, `fetch_or(v)`, `fetch_xor(v)` | Combines the value bitwise with `v`; returns the value from before. |
| `is_lock_free()` | Reports whether the operations use native atomic instructions. |

Each operation compiles to a native atomic instruction. `load` has acquire
ordering, `store` has release ordering, and `compare_exchange` and the
`fetch_` operations are acquire-release. `exchange` is a `compare_exchange`
retry loop.

Some details differ from C++:

- **`compare_exchange` does not update `expected`** when it fails. Call
  `load()` to get the current value before you retry.
- **The comparison is bitwise.** For a floating-point `T`, `0.0` and `-0.0` are
  different values. For a struct `T`, it compares references (whether both are
  the same object), not the objects' contents.
- **The `fetch_` operations are for integer types.** Calling one on a
  floating-point or struct `T` compiles, but stops the program when it runs.
- **`is_lock_free()`** is true for any number type of 8 bytes or less, and for
  any struct type.
- **A struct `T` must be thread-safe.** `Atomic` is a `[Shared]` struct, so
  its `T` must be a `[Shared]` struct too (or a number, pointer or function
  type). `Atomic<String>` is a compile error. See
  [What threads can share](threads.md#what-threads-can-share).

## Common patterns

```pepper
{{#include ../../examples/atomics-patterns.pep}}
```

- **A shared counter.** `fetch_add(1)` hands out unique, increasing numbers,
  even when many threads call it at once.
- **A compare-and-swap loop.** To apply any update that the `fetch_`
  operations do not cover, load the current value, compute the new one, and
  `compare_exchange`; if another thread changed the value in between, the
  exchange fails and you try again with a fresh `load()`.
- **Sharing an Atomic.** `Atomic` is a `[Shared]` struct, so copying one
  copies a reference: every copy shares the same slot, on any thread. To
  share a value, pass the `Atomic` around or keep it in a module-scope
  variable.
- **Atomic struct references.** An `Atomic<T>` whose `T` is a `[Shared]`
  struct type holds a counted reference, and follows the same rules as any other reference
  (see [Memory and reference counting](memory.md)): `store` and a successful
  `compare_exchange` take a reference to the new value and release the one they
  replace, and `load` and `exchange` give you your own reference. The swap in
  the slot is itself atomic, so concurrent stores never leak or release a value
  twice. When the `Atomic` itself is destroyed, it releases the reference it
  holds.

## Atomics and threads

`Atomic<T>` is how threads share a value that changes. Keep it in a
module-scope variable, or in a `const` field of a `[Shared]` struct, and every
thread sees the same slot. [Threads and shared data](threads.md) shows it
together with `Thread.spawn`.
