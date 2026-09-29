# Rust-analogous Result type. Pepper has no unions: both `Value` and
# `Error` always exist, and `IsOk` selects the live one (the dead field
# stays at its default/null value).

import "internals";

## The default error type of `Result`: a human-readable message.
##
## @example
##     var r = Result<int>.err(Error("boom"));
##     var n = r.Error.Message.length();   # 4
export struct Error {
    ## The description of what went wrong; empty when none was given.
    String Message;

    ## Creates an Error carrying `message`.
    ##
    ## @param message the description of the failure; defaults to the empty string
    construct(String message = "") {
        this.Message = message;
    }
}

## The outcome of an operation that can fail: either Ok, holding a `TValue`,
## or Err, holding a `TError`, like Rust's `Result<T, E>`.
##
## Build one with the static `ok` or `err` functions and test it with
## `is_ok()` or `is_err()`. Pepper has no unions, so both the `Value` and
## the `Error` fields always exist; only the one matching `IsOk` is
## meaningful, and the other keeps its default (zero for a POD type, null for
## a struct type, so do not read through it). `TError` defaults to `Error`,
## so `Result<int>` is `Result<int, Error>`.
##
## `Result<void>` is the result of an operation that returns nothing on
## success, like Rust's `Result<(), E>`. A `void` type argument erases what
## it types: that instance has no `Value` field, `ok()` takes no argument,
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
    ## Whether this result is Ok (`Value` is live) rather than Err (`Error` is live).
    bool IsOk;
    ## The success value; meaningful only when `IsOk` is true, otherwise the default of `TValue`.
    TValue Value;
    ## The failure value; meaningful only when `IsOk` is false, otherwise the default of `TError`.
    TError Error;

    ## Creates an Err result whose `Error` and `Value` both hold their
    ## type's default (zero for a POD type, null for a struct type).
    ##
    ## Prefer `ok` or `err`, which set the live field.
    ##
    ## @example
    ##     var e = Result<int>();   # e.is_ok() == false
    construct() {
        this.IsOk = false;
    }

    ## Returns an Ok result holding `v`.
    ##
    ## For a struct `TValue` the result acquires a reference to `v`.
    ##
    ## For `Result<void>`, `ok()` takes no argument.
    ##
    ## @param v the success value
    ## @returns an Ok result whose `Value` is `v`
    ## @example
    ##     var r = Result<int>.ok(42);
    ##     var done = Result<void>.ok();
    static Result<TValue, TError> ok(TValue v) {
        var r = Result<TValue, TError>();
        r.IsOk = true;
        r.Value = v;
        return r;
    }

    ## Returns an Err result holding `e`.
    ##
    ## For a struct `TError` the result acquires a reference to `e`.
    ##
    ## @param e the failure value
    ## @returns an Err result whose `Error` is `e`
    ## @example
    ##     var r = Result<int>.err(Error("boom"));
    static Result<TValue, TError> err(TError e) {
        var r = Result<TValue, TError>();
        r.IsOk = false;
        r.Error = e;
        return r;
    }

    ## Reports whether this result is Ok.
    ##
    ## @returns true when `Value` holds the outcome
    bool is_ok() {
        return this.IsOk;
    }

    ## Reports whether this result is Err.
    ##
    ## @returns true when `Error` holds the outcome
    bool is_err() {
        return !this.IsOk;
    }

    ## Returns the success value, panicking if this result is Err.
    ##
    ## For a struct `TValue` the caller gets its own reference; the result
    ## keeps its reference too.
    ##
    ## For `Result<void>` it returns nothing: calling it only checks that the
    ## result is Ok.
    ##
    ## @returns the `Value` of an Ok result
    ## @panics if `this.IsOk` does not hold, that is, the result is Err ("Result.value on an Err value")
    ## @example
    ##     var n = Result<int>.ok(42).value();   # 42
    TValue value() {
        assert(this.IsOk, "Result.value on an Err value");
        return this.Value;
    }

    ## Returns the success value, or `fallback` if this result is Err.
    ##
    ## Never panics. `fallback` is evaluated by the caller whether or not it
    ## is used.
    ##
    ## @param fallback the value to return when the result is Err
    ## @returns `Value` when the result is Ok, otherwise `fallback`
    ## @example
    ##     var n = Result<int>.err(Error("e")).ok_or(-1);   # -1
    TValue ok_or(TValue fallback) {
        if (this.IsOk) {
            return this.Value;
        }
        return fallback;
    }
}
