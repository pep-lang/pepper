# Optional values

A value that may be missing has the type `Optional<T>`: either **Some**,
holding a `T`, or **None**, holding nothing. It plays the role of Rust's
`Option<T>` and Swift's `Optional`. Use it instead of a null reference or a
sentinel such as `-1` or `""`: the type tells the caller that the value can be
absent, and reading it goes through a method that checks.

`Optional` is part of the runtime, so you can use it without an import. The
[Optional reference](../reference/optional.md) lists every member.

```pepper
{{#include ../../examples/optionals-basics.pep}}
```

## Creating and checking optionals

| Member | What it does |
|---|---|
| `Optional<T>.some(value)` | Creates a Some optional holding `value`. |
| `Optional<T>.none()`, `Optional<T>()` | Create a None optional. |
| `is_some()`, `is_none()` | Report which kind the optional is. |
| `value()` | Returns the value; panics with `Optional.value on a None value` if the optional is None. |
| `value_or(fallback)` | Returns the value, or `fallback` if the optional is None. Never panics. |

Use `value()` when a None would be a bug in your program, since it stops the
program. When a missing value is an expected outcome, test with `is_some()` or
`is_none()` first, or supply a fallback with `value_or`.

`Optional<T>` works for every `T`, including types that have no null at all,
such as `int` or `ulong`. For a struct type, a Some optional holds a
reference to the object, like any other struct slot (see
[Memory and reference counting](memory.md)).

## Optional or Result

An `Optional<T>` says only that a value is missing. When the caller needs to
know *why*, return a [`Result`](results.md) instead, whose Err carries an
error.

## Current limits

- There is no `T?` shorthand yet: write `Optional<T>`.
- An optional is checked with `is_some()` or `is_none()` and read with
  `value()` or `value_or`; `match` does not work on it yet. `Optional` will
  become an [enum](enums.md) with `None` and `Some(value)` cases once enum
  cases can carry values; its methods stay the same.
- The runtime's own APIs still use null references or default values for
  "missing" (a `HashMap` returns the default value for a missing key, for
  example).
