# Rust-analogous Result type. Pepper has no unions: both `_value` and
# `_error` always exist, and `_is_ok` selects the live one (the dead field
# stays at its default/null value).

import "internals";

## The default error type of `Result`: a human-readable message.
##
## @example
##     var r = Result<int>.err(Error("boom"));
##     var n = r.error().message.length();   # 4
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
    construct(String message = "") {
        this.message = message;
    }
}

## The outcome of an operation that can fail: either Ok, holding a `TValue`,
## or Err, holding a `TError`, like Rust's `Result<T, E>`.
##
## Build one with the static `ok` or `err` functions and test it with
## `is_ok()` or `is_err()`, then read the outcome with `value()` or
## `error()`, each of which panics on the wrong kind of result. `TError`
## defaults to `Error`, so `Result<int>` is `Result<int, Error>`.
##
## `Result<void>` is the result of an operation that returns nothing on
## success, like Rust's `Result<(), E>`. A `void` type argument erases what
## it types: that instance holds no value, `ok()` takes no argument,
## and `value()` returns nothing, so it only checks that the result is Ok.
##
## @typeParam TValue the type of the value an Ok result carries; `void` when there is none
## @typeParam TError the type of the error an Err result carries; defaults to `Error`
## @example
##     main(): int {
##         var a = Result<int>.ok(42);
##         if (a.value() != 42) { return 1; }
##         var b = Result<int>.err(Error("boom"));
##         if (!b.is_err()) { return 2; }
##         return b.ok_or(0);   # 0
##     }
export struct Result<TValue, TError=Error> {
    # Whether this result is Ok (`_value` is live) rather than Err (`_error` is live).
    bool _is_ok;
    # The success value; meaningful only when `_is_ok`, otherwise the default of `TValue`.
    TValue _value;
    # The failure value; meaningful only when not `_is_ok`, otherwise the default of `TError`.
    TError _error;

    ## Creates an Err result whose error and value both hold their type's
    ## default (zero for a POD type, null for a struct type).
    ##
    ## Prefer `ok` or `err`, which set the live field.
    ##
    ## @example
    ##     var e = Result<int>();   # e.is_ok() == false
    construct() {
        this._is_ok = false;
    }

    ## Returns an Ok result holding `v`.
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
    static Result<TValue, TError> ok(TValue v) {
        var r = Result<TValue, TError>();
        r._is_ok = true;
        r._value = v;
        return r;
    }

    ## Returns an Err result holding `e`.
    ##
    ## For a struct `TError` the result acquires a reference to `e`.
    ##
    ## @param e the failure value
    ## @returns an Err result whose `error()` is `e`
    ## @example
    ##     var r = Result<int>.err(Error("boom"));
    static Result<TValue, TError> err(TError e) {
        var r = Result<TValue, TError>();
        r._is_ok = false;
        r._error = e;
        return r;
    }

    ## Reports whether this result is Ok.
    ##
    ## @returns true when the result holds a value
    bool is_ok() {
        return this._is_ok;
    }

    ## Reports whether this result is Err.
    ##
    ## @returns true when the result holds an error
    bool is_err() {
        return !this._is_ok;
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
    TValue value() {
        assert(this._is_ok, "Result.value on an Err value");
        return this._value;
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
    TError error() {
        assert(!this._is_ok, "Result.error on an Ok value");
        return this._error;
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
    TValue ok_or(TValue fallback) {
        if (this._is_ok) {
            return this._value;
        }
        return fallback;
    }
}
