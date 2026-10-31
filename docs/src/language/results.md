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

`Result` is a [value enum](enums.md#value-enums): it is stored inline in
whatever holds it, so making one allocates nothing, and it is never null. A
slot of type `Result` that is never given a value holds its first case,
`Ok`, carrying the zero value of `TValue` (`0`, or null for a struct), so give
every result slot a value. `Result<int>()` is an error, since only the cases
make values.

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

The `?` operator, below, writes each of these checks in one character.

## Propagating errors with `?`

`?` after a `Result` passes its error up, like Rust's `?`: on an Ok result
it is the value, and on an Err result it returns that error from the
enclosing function at once. `var x = parse(s)?;` does what the `if
(x.is_err()) { return ...err(x.error()); }` checks above do:

```pepper
{{#include ../../examples/results-question.pep}}
```

The rules:

- The enclosing function must declare that it returns a `Result`, or the
  compiler reports `'?' requires the enclosing function to return a
  Result`. A closure that uses `?` writes its return type out:
  `(s: String): Result<int> => Result<int>.ok(parse(s)? + 1)`.
- The error type must be the function's error type, or convert to it
  through an `[Implicit]` constructor (see [Implicit
  conversions](structs.md#implicit-conversions)), as `ConfigError` does above, like
  Rust's `From`. Otherwise the error is `cannot convert error type
  'ParseError' to 'ConfigError'`.
- On a `Result<void>`, `?` yields nothing, so it stands as a statement:
  `remove(path)?;`.
- On an `Optional`, `?` works the same way in a function that returns an
  optional: an Empty optional returns Empty (see [Optional
  values](optionals.md#returning-early-with-)).
- The early return is an ordinary `return`: locals are released and
  `with` blocks are exited as for any other.

A `?` can go anywhere in an expression, and runs where it is written, in
the order the expression is evaluated:

- What comes before it runs first, and what comes after it runs only when
  it does not return: in `f() + g()? + h()`, `f()` runs, then `g()`, and
  `h()` only if `g()` returned a value. Several `?`s run in the order
  written: `add(parse(a)?, parse(b)?)`. Reading a variable or field is not
  a call: `x.count + g()?` reads `x.count` once `g()` has returned.
- A `?` that is not reached does nothing: on the right of `&&` or `||` when
  the left operand decides, in the branch of `?:` not taken, or in a
  `match` arm that does not match. `ready && load()?` calls `load()` only
  when `ready` holds.
- The early return releases what the statement made before the `?`, like
  any other `return`.

A `?` in a `while` condition runs on every iteration, before the condition
is tested.

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

A library that reads a file format reports damaged data the same way:
`IoError.invalid_input(message)` makes an error whose `is_invalid_input()`
holds, as `compress` and `archive` return for corrupt input.

Reading a directory or a file line by line in a `for` loop yields one
`IoResult` per element, so each error is handled where it happens; see
[Iteration](iteration.md#reading-files-and-directories).
