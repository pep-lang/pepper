## `Result<T, E>`: the value of an operation that can fail, either `Ok`
## holding its value or `Err` holding its error, like Rust's `Result`.

import "internals";

## The default error type of `Result`: a human-readable message.
##
## @example
##     var r = Result<int>.err(Error("boom"));
##     var n = r.error().message.length;   # 4
export struct Error {
    ## The description of what went wrong; empty when none was given.
    String message;

    ## Creates an Error carrying `message`.
    ##
    ## The constructor is `[Implicit]`: a `String` converts to an `Error`
    ## wherever an `Error` is expected, as in `Result<int>.err("bad input")`.
    ##
    ## @param message the description of the failure; defaults to the empty string
    [Implicit]
    construct(message: String = "") {
        this.message = message;
    }
}

## The outcome of an operation that can fail: either Ok, holding a `TValue`,
## or Err, holding a `TError`, like Rust's `Result<T, E>`.
##
## An enum with the cases `Ok(value)` and `Err(error)`. Build one with a
## case (`Result<int>.Ok(42)`) or the static `ok` or `err` functions, and
## read it with `match` or `is` (`if (r is Err(e)) { ... }`), or with
## `is_ok()`, `is_err()`, `value()` and `error()`; `value()` and `error()`
## panic on the wrong kind of result. `TError` defaults to `Error`, so
## `Result<int>` is `Result<int, Error>`.
##
## `Result<void>` is the result of an operation that returns nothing on
## success, like Rust's `Result<(), E>`. A `void` type argument erases what
## it types: that instance's `Ok` carries nothing (`Result<void>.Ok`, and
## the pattern `Ok`), `ok()` takes no argument, and `value()` returns
## nothing, so it only checks that the result is Ok.
##
## @typeParam TValue the type of the value an Ok result carries; `void` when there is none
## @typeParam TError the type of the error an Err result carries; defaults to `Error`
## @example
##     main(): int {
##         var a = Result<int>.ok(42);
##         if (a.value() != 42) { return 1; }
##         var b = Result<int>.err(Error("boom"));
##         if (!b.is_err()) { return 2; }
##         var n = match (b) { Ok(v) => v, Err(e) => e.message.length };   # 4
##         return b.ok_or(0);   # 0
##     }
[Value]
export enum Result<TValue, TError=Error> {
    ## The operation succeeded with `value`.
    ##
    ## @param value the success value
    Ok(value: TValue),
    ## The operation failed with `error`.
    ##
    ## @param error the failure value
    Err(error: TError),

    ## Returns an Ok result holding `v`; the same as `Result.Ok(v)`.
    ##
    ## For a struct `TValue` the result acquires a reference to `v`.
    ##
    ## For `Result<void>`, `ok()` takes no argument.
    ##
    ## @param v the success value
    ## @returns an Ok result whose `value()` is `v`
    ## @example
    ##     var r = Result<int>.ok(42);
    ##     var done = Result<void>.ok();
    static ok(v: TValue): Result<TValue, TError> {
        return Result<TValue, TError>.Ok(v);
    }

    ## Returns an Err result holding `e`; the same as `Result.Err(e)`.
    ##
    ## For a struct `TError` the result acquires a reference to `e`.
    ##
    ## @param e the failure value
    ## @returns an Err result whose `error()` is `e`
    ## @example
    ##     var r = Result<int>.err(Error("boom"));
    static err(e: TError): Result<TValue, TError> {
        return Result<TValue, TError>.Err(e);
    }

    ## Reports whether this result is Ok.
    ##
    ## @returns true when the result holds a value
    is_ok(): bool {
        return this is Ok;
    }

    ## Reports whether this result is Err.
    ##
    ## @returns true when the result holds an error
    is_err(): bool {
        return this is Err;
    }

    ## Returns the success value, panicking if this result is Err.
    ##
    ## For a struct `TValue` the caller gets its own reference; the result
    ## keeps its reference too.
    ##
    ## For `Result<void>` it returns nothing: calling it only checks that the
    ## result is Ok.
    ##
    ## @returns the value of an Ok result
    ## @panics if the result is Err ("Result.value on an Err value")
    ## @example
    ##     var n = Result<int>.ok(42).value();   # 42
    value(location: __ptr<char> = __caller_location()): TValue {
        if (this is Ok(value)) {
            return value;
        }
        panic("Result.value on an Err value", location);
    }

    ## Returns the failure value, panicking if this result is Ok.
    ##
    ## For a struct `TError` the caller gets its own reference; the result
    ## keeps its reference too.
    ##
    ## @returns the error of an Err result
    ## @panics if the result is Ok ("Result.error on an Ok value")
    ## @example
    ##     var e = Result<int>.err(Error("boom")).error();   # e.message == "boom"
    error(location: __ptr<char> = __caller_location()): TError {
        if (this is Err(error)) {
            return error;
        }
        panic("Result.error on an Ok value", location);
    }

    # What `e?` lowers to (the builder's `lift_tries`): it returns early when
    # `_propagates()`, with the enclosing function's
    # `_from_residual(e._residual())`. An error of another type converts to
    # this `TError` as the argument, through an `[Implicit]` constructor.
    _propagates(): bool {
        return this is Err;
    }

    _residual(): TError {
        return this.error();
    }

    static _from_residual(error: TError): Result<TValue, TError> {
        return Result<TValue, TError>.Err(error);
    }

    ## Returns the success value, or `fallback` if this result is Err.
    ##
    ## Never panics. `fallback` is evaluated by the caller whether or not it
    ## is used.
    ##
    ## @param fallback the value to return when the result is Err
    ## @returns the value when the result is Ok, otherwise `fallback`
    ## @example
    ##     var n = Result<int>.err(Error("e")).ok_or(-1);   # -1
    ok_or(fallback: TValue): TValue {
        if (this is Ok(value)) {
            return value;
        }
        return fallback;
    }
}
