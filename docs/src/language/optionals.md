# Optional values

A value that may be missing has the type `Optional<T>`, written `T?` for
short: either **Some**,
holding a `T`, or **None**, holding nothing. It plays the role of Rust's
`Option<T>` and Swift's `Optional`. Use it instead of a null reference or a
sentinel such as `-1` or `""`: the type tells the caller that the value can be
absent, and reading it goes through a method that checks.

`Optional` is part of the runtime, so you can use it without an import. The
[Optional reference](../reference/optional.md) lists every member.

```pepper
{{#include ../../examples/optionals-basics.pep}}
```

## The `T?` shorthand

`T?` means `Optional<T>` wherever a type is written: `x: int?`,
`find(key: String): Node?`, `Array<Node?>`, a field `Token? leaf;`. The `?`
applies to everything before it, so `int[]?` is an optional array, and
`Array<int?>` is an array of optional values.

A C-style declaration inside a function body, such as `Node? n = m;`, is read
as a declaration only when a name follows the `?` and then `=`, `;` or the end
of the line; `a ? b : c` stays a conditional expression.

## Optional slots start as None

A variable or field of an optional type that is not given a value starts as
None, not null:

```pepper
struct Node {
    Token? leaf;   # None until assigned
}
var count: int?;   # None
```

## Creating and checking optionals

| Member | What it does |
|---|---|
| `Optional<T>.some(value)` | Creates a Some optional holding `value`. |
| `Optional<T>.none()`, `Optional<T>()` | Create a None optional. |
| `is_some()`, `is_none()` | Report which kind the optional is. |
| `!!` (truth test) | An optional is a condition by itself: `if (found)` is `if (found.is_some())`, and `!found` is `found.is_none()`. |
| `value()` | Returns the value; panics with `Optional.value on a None value` if the optional is None. |
| `value_or(fallback)` | Returns the value, or `fallback` if the optional is None. Never panics. |

Use `value()` when a None would be a bug in your program, since it stops the
program. When a missing value is an expected outcome, test it first (`if
(found)`, `is_some()` or `is_none()`), or supply a fallback with `value_or`.
Testing the optional itself works because `Optional` declares the truth-test
operator `!!` (see [Truth tests](structs.md#truth-tests-and-conditions)).

`Optional<T>` works for every `T`, including types that have no null at all,
such as `int` or `ulong`. For a struct type, a Some optional holds a
reference to the object, like any other struct slot (see
[Memory and reference counting](memory.md)).

## Optional or Result

An `Optional<T>` says only that a value is missing. When the caller needs to
know *why*, return a [`Result`](results.md) instead, whose Err carries an
error.

## Current limits

- An optional is checked as a condition (or with `is_some()` or
  `is_none()`) and read with `value()` or `value_or`; `match` does not work
  on it yet. `Optional` will become an [enum](enums.md) with `None` and
  `Some(value)` cases once enum cases can carry values; its methods stay the
  same.
- The runtime's own APIs still use null references or default values for
  "missing" (a `HashMap` returns the default value for a missing key, for
  example).
