# Optional values

A value that may be missing has the type `Optional<T>`, written `T?` for
short: either **Value**,
holding a `T`, or **Empty**, holding nothing. It plays the role of Rust's
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

## Returning early with `?`

In a function that returns an optional, `?` after an optional is its value,
or, when it is Empty, returns Empty from the function at once, as `?` does
with an error for [`Result`](results.md#propagating-errors-with-):

```pepper
middle_name(person: Person): String? {
    var names = person.full_name?.split(" ");
    if (names.count < 3) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(names[1]);
}
```

Using `?` on an optional in a function that does not return an optional is
an error (`'?' requires the enclosing function to return an Optional`).

## Optional slots start as Empty

A variable or field of an optional type that is not given a value starts as
Empty, not null:

```pepper
struct Node {
    Token? leaf;   # Empty until assigned
}
var count: int?;   # Empty
```

## Creating and checking optionals

| Member | What it does |
|---|---|
| `Optional<T>.Value(value)` | Creates a Value optional holding `value`. |
| `Optional<T>.Empty` | An Empty optional. |
| `is_value()`, `is_empty()` | Report which case the optional is. |
| `!!` (truth test) | An optional is a condition by itself: `if (found)` is `if (found.is_value())`, and `!found` is `found.is_empty()`. |
| `value()` | Returns the value; panics with `Optional.value on an Empty optional` if the optional is Empty. |
| `value_or(fallback)` | Returns the value, or `fallback` if the optional is Empty. Never panics. |

Use `value()` when an Empty optional would be a bug in your program, since it stops the
program. When a missing value is an expected outcome, test it first (`if
(found)`, `is_value()` or `is_empty()`), or supply a fallback with `value_or`.
Testing the optional itself works because `Optional` declares the truth-test
operator `!!` (see [Truth tests](structs.md#truth-tests-and-conditions)).

`Optional<T>` works for every `T`, including types that have no null at all,
such as `int` or `ulong`. For a struct type, a Value optional holds a
reference to the object, like any other struct slot (see
[Memory and reference counting](memory.md)).

`Optional<T>` is an [enum](enums.md) with the cases `Empty` and
`Value(value)`, so `match` and `is` work on it too:

```pepper
var shown = match (name) {
    Empty => "nobody",
    Value(text) => text,
};
if (name is Value(text)) { print(text); }
```

An optional is a [value enum](enums.md#value-enums): it lives inline in the
variable, field or array element that holds it, so creating one allocates
nothing, and copying one gives an independent optional. It is never null,
and has no identity: compare two optionals with `==`, which compares
whether each holds a value and, if both do, their values; `===` on an optional
is an error.

## Optionals in the standard library

Standard library lookups that can come up empty return an optional rather
than a sentinel value:

| API | Returns | Empty when |
|---|---|---|
| `Array<T>.find(item)` | `ulong?` | no element equals `item` |
| `io.Path.parent()` | `Path?` | the path is a root (`/`, `C:\`), a bare name with no root (`a`, `.`, `..`), or empty |
| `io.Path.file_name()` | `String?` | the path is a root or empty, or its last component is `.` or `..` |
| `io.Path.file_stem()` | `String?` | there is no file name |
| `io.Path.extension()` | `String?` | there is no file name, or the name has no dot after its first character (`Makefile`, `.bashrc`); `foo.` has the empty extension `""` |
| `io.Path.dot_index(name)` | `ulong?` | `name` has no dot after its first character |
| `http.Headers.get(name)` | `String?` | no field has that name |
| `HashMap<K, V>.try_get(key)` (and `Map`, `OrderedMap`) | `V?` | `key` is absent |

```pepper
{{#include ../../examples/optionals-library.pep}}
```

**Breaking change.** `Array.find` used to return a `long` that was `-1` for
"not found", and the `Path` methods above returned an empty `Path` or
`String` (or `name.size` for `dot_index`). Code written against the old
API must test the optional instead: `a.find(x) >= 0` becomes
`a.find(x).is_value()`, `p.parent().is_empty` becomes
`p.parent().is_empty()`, and a value is read with `value()` or `value_or`.
A comparison such as `a.find(x) == -1` still compiles but compares the
optional object rather than an index, so search for these and rewrite them.
`String.find` is unchanged and still returns `-1`.

## Optional or Result

An `Optional<T>` says only that a value is missing. When the caller needs to
know *why*, return a [`Result`](results.md) instead, whose Err carries an
error.

## Current limits

- Some runtime APIs still use null references, default values or sentinels
  for "missing": a `HashMap`'s `get` (and indexer) returns the default value
  for a missing key (use `try_get` for an optional), and `String.find`
  returns `-1`, for example.
