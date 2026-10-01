# Error handling with Result

An operation that can fail returns a `Result`: either **Ok**, holding the value
you asked for, or **Err**, holding an error that says what went wrong. The
caller checks which one it got before using the value. Pepper has no
exceptions, so `Result` is how a function reports a failure the caller is
expected to handle. For a failure that should stop the program, such as a
broken invariant, use `assert` or `panic` instead.

`Result` and `Error` are part of the runtime, so you can use them
without an import. The [Result reference](../reference/result.md) lists every
member.

## Creating and checking results

`Result<TValue, TError>` works like Rust's `Result<T, E>`. It is an
[enum](enums.md) with two cases, `Ok(value: TValue)` and `Err(error: TError)`.
You build one with a case or with the static functions `ok` and `err`, and
read it with [`match`](enums.md#match), [`is`](enums.md#match-expressions-is-and-literal-patterns),
or its methods:

```pepper
{{#include ../../examples/results-basics.pep}}
```

The pieces:

| Member | What it does |
|---|---|
| `Result<T>.Ok(value)`, `Result<T>.ok(value)` | Creates an Ok result holding `value`. |
| `Result<T>.Err(error)`, `Result<T>.err(error)` | Creates an Err result holding `error`. |
| `is_ok()`, `is_err()` | Report which kind the result is. |
| `value()` | Returns the value; panics with `Result.value on an Err value` if the result is an Err. |
| `error()` | Returns the error; panics with `Result.error on an Ok value` if the result is Ok. |
| `ok_or(fallback)` | Returns the value, or `fallback` if the result is an Err. Never panics. |

`TError` defaults to `Error`, so `Result<int>` means `Result<int, Error>`, and
values of the two spellings can be assigned to each other freely (the compiler
does generate a separate specialization for each spelling). `Error` is a struct
with one field, `String message`: `Error("boom").message` is `"boom"`.

Use `value()` when an Err would be a bug in your program, since it stops the
program. When an Err is an expected outcome, `match` on the result, test it
with `is` (`if (r is Err(e)) { ... }`) or `is_ok()`, or supply a fallback with
`ok_or`.

### Check before you read

A `Result` holds either its value or its error, never both. A `match` or an
`is` test reads the one it holds, so it cannot pick the wrong one. `value()`
and `error()` panic on the wrong one, so call `value()` only after checking
`is_ok()`, and `error()` only after checking `is_err()`.

A slot of type `Result` that is never given a value holds null, as for any
enum whose cases carry values: `Result<int>()` is an error, since only the
cases make values.

### Results with no value

An operation that has nothing to return on success, such as deleting a file,
uses `void` as its value type, like `Result<(), E>` in Rust. A `void` type
argument erases what it types, so in `Result<void>` the case `Ok` carries
nothing, `ok()` takes no argument, and `value()` returns nothing: calling it
only checks that the result is Ok. Using that call as a value, as in
`var x = done.value();`, is a compile error, as it is for any function that
returns `void`.

```pepper
var done = Result<void>.Ok;   # or Result<void>.ok()
var failed = Result<void>.err(Error("disk full"));
done.value();   # panics if `done` is an Err
match (failed) {
    Ok => {}
    Err(e) => { print(e.message); }
}
```

## Custom error types and propagation

Any type can be the error type. A struct lets you carry details the caller can
act on, not just a message. To pass an error up to your own caller, check the
result and return early with its error; to change the error's type on the way,
build a new error from the old one:

```pepper
{{#include ../../examples/results-propagate.pep}}
```

Pepper does not yet have a shorthand for propagation (such as Rust's `?`
operator), so each fallible call is checked with `if`, `is` or `match` as
shown above.

## Results from the io module

The [io module](../reference/io-module.md) is a good model of a library built
on `Result`. Every operation that can fail returns an `IoResult<T>`, a type
alias for `Result<T, IoError>`, and operations with nothing to return use
`IoResult<void>`. `IoError` holds the platform's error `code` and a `message`.
To decide what to do about the failure, `kind()` returns the code's portable
`ErrorKind` (`NotFound`, `PermissionDenied`, `AlreadyExists`, ...,
`Other`), an [enum](enums.md) to `match` on, and a predicate per kind, such as
`is_not_found()` and `is_permission_denied()`, tests for one of them:

```pepper
{{#include ../../examples/results-io.pep}}
```

See [io: errors and platform types](../reference/io-types.md) for the full list
of kinds and the platform codes each one covers.
