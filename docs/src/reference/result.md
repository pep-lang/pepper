<!-- Generated from runtime/result.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Result

Source: `runtime/result.pep`

## Error

```pepper
struct Error
```

The default error type of `Result`: a human-readable message.

**Example**
```pepper
    var r = Result<int>.err(Error("boom"));
    var n = r.error().message.length();   # 4
```

### Fields

#### message

```pepper
String message
```

The description of what went wrong; empty when none was given.

### Constructor

#### Error()

```pepper
[Implicit] construct(String message = "")
```

Creates an Error carrying `message`.

The constructor is `[Implicit]`: a `String` converts to an `Error`
wherever an `Error` is expected, as in `Result<int>.err("bad input")`.

**Parameters**
- `message` — the description of the failure; defaults to the empty string

## Result

```pepper
enum Result<TValue, TError=Error>
```

The outcome of an operation that can fail: either Ok, holding a `TValue`,
or Err, holding a `TError`, like Rust's `Result<T, E>`.

An enum with the cases `Ok(value)` and `Err(error)`. Build one with a
case (`Result<int>.Ok(42)`) or the static `ok` or `err` functions, and
read it with `match` or `is` (`if (r is Err(e)) { ... }`), or with
`is_ok()`, `is_err()`, `value()` and `error()`; `value()` and `error()`
panic on the wrong kind of result. `TError` defaults to `Error`, so
`Result<int>` is `Result<int, Error>`.

`Result<void>` is the result of an operation that returns nothing on
success, like Rust's `Result<(), E>`. A `void` type argument erases what
it types: that instance's `Ok` carries nothing (`Result<void>.Ok`, and
the pattern `Ok`), `ok()` takes no argument, and `value()` returns
nothing, so it only checks that the result is Ok.

**Type parameters**
- `TValue` — the type of the value an Ok result carries; `void` when there is none
- `TError` — the type of the error an Err result carries; defaults to `Error`

**Example**
```pepper
    main(): int {
        var a = Result<int>.ok(42);
        if (a.value() != 42) { return 1; }
        var b = Result<int>.err(Error("boom"));
        if (!b.is_err()) { return 2; }
        var n = match (b) { Ok(v) => v, Err(e) => e.message.length() };   # 4
        return b.ok_or(0);   # 0
    }
```

### Cases

#### Ok

```pepper
Ok(value: TValue)
```

The operation succeeded with `value`.

**Parameters**
- `value` — the success value

#### Err

```pepper
Err(error: TError)
```

The operation failed with `error`.

**Parameters**
- `error` — the failure value

### Static methods

#### ok

```pepper
static ok(v: TValue): Result<TValue, TError>
```

Returns an Ok result holding `v`; the same as `Result.Ok(v)`.

For a struct `TValue` the result acquires a reference to `v`.

For `Result<void>`, `ok()` takes no argument.

**Parameters**
- `v` — the success value

**Returns**
- an Ok result whose `value()` is `v`

**Example**
```pepper
    var r = Result<int>.ok(42);
    var done = Result<void>.ok();
```

#### err

```pepper
static err(e: TError): Result<TValue, TError>
```

Returns an Err result holding `e`; the same as `Result.Err(e)`.

For a struct `TError` the result acquires a reference to `e`.

**Parameters**
- `e` — the failure value

**Returns**
- an Err result whose `error()` is `e`

**Example**
```pepper
    var r = Result<int>.err(Error("boom"));
```

### Methods

#### is_ok

```pepper
is_ok(): bool
```

Reports whether this result is Ok.

**Returns**
- true when the result holds a value

#### is_err

```pepper
is_err(): bool
```

Reports whether this result is Err.

**Returns**
- true when the result holds an error

#### value

```pepper
value(): TValue
```

Returns the success value, panicking if this result is Err.

For a struct `TValue` the caller gets its own reference; the result
keeps its reference too.

For `Result<void>` it returns nothing: calling it only checks that the
result is Ok.

**Returns**
- the value of an Ok result

**Panics**
- if the result is Err ("Result.value on an Err value")

**Example**
```pepper
    var n = Result<int>.ok(42).value();   # 42
```

#### error

```pepper
error(): TError
```

Returns the failure value, panicking if this result is Ok.

For a struct `TError` the caller gets its own reference; the result
keeps its reference too.

**Returns**
- the error of an Err result

**Panics**
- if the result is Ok ("Result.error on an Ok value")

**Example**
```pepper
    var e = Result<int>.err(Error("boom")).error();   # e.message == "boom"
```

#### ok_or

```pepper
ok_or(fallback: TValue): TValue
```

Returns the success value, or `fallback` if this result is Err.

Never panics. `fallback` is evaluated by the caller whether or not it
is used.

**Parameters**
- `fallback` — the value to return when the result is Err

**Returns**
- the value when the result is Ok, otherwise `fallback`

**Example**
```pepper
    var n = Result<int>.err(Error("e")).ok_or(-1);   # -1
```
