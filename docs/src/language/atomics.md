# Atomics and concurrency

An **atomic** value can be read and updated by several threads at once without
a data race: every operation on it happens as one indivisible step. Pepper
provides this through `Atomic<T>`, the equivalent of C++ `std::atomic<T>`.

This chapter also describes what concurrency support Pepper has today, which
is limited: there is no way to start a thread from Pepper yet.

## Atomic&lt;T&gt;

`Atomic<T>` is part of the runtime, so you can use it without an import. The
[Atomic reference](../reference/atomic.md) documents every method.

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
- **Sharing an Atomic.** `Atomic` is a struct, so copying one copies a
  reference: every copy shares the same slot. To share a value, pass the
  `Atomic` around or keep it in a module-scope variable.
- **Atomic struct references.** An `Atomic<T>` whose `T` is a struct type
  holds a counted reference, and follows the same rules as any other reference
  (see [Memory and reference counting](memory.md)): `store` and a successful
  `compare_exchange` take a reference to the new value and release the one they
  replace, and `load` and `exchange` give you your own reference. The swap in
  the slot is itself atomic, so concurrent stores never leak or release a value
  twice.

## Concurrency today

Pepper does not have threads yet. The language and the runtime have no way to
start a thread, no mutexes or other locks, and no thread-safety checks.

What works today:

- `Atomic<T>` operations are real atomic instructions. When threads are
  created outside Pepper, for example by a host program in another language
  that calls into Pepper functions, those threads can safely share
  `Atomic<T>` values of number types. Pepper's own test suite does exactly
  that, calling a Pepper function that uses `fetch_add` from several threads.

What does not:

- **Reference counts are not atomic.** Copying or releasing a struct
  reference updates its count with ordinary, non-atomic instructions. Two
  threads that copy or release references to the same object at the same time
  can corrupt its count, freeing it too early or never. Until this changes, do
  not share struct values, including `String` and `Array`, between threads.
  This also applies to `Atomic<T>` with a struct `T`: the slot's own swap is
  atomic, but the object's count is not.
- Ordinary variables and struct fields have no protection against data races.

## Where Pepper is heading

The goal is for Pepper to make concurrent code safe by construction: code
that shares data between threads without synchronization should be a compile
error, not a bug found in production. The current design plans point toward:

- a thread API that accepts only values that are safe to send to another
  thread, such as number types, `Atomic<T>`, and types the compiler can prove
  are immutable or internally synchronized, with an error that names the
  offending value;
- atomic reference counting for values that cross threads.

None of this is implemented yet, and the details may change.
