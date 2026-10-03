# A value that may be absent, like Rust's `Option<T>` and Swift's
# `Optional`: a value enum with an Empty and a Value case.

import "internals";

## A value of type `T` that may be absent: either Value, holding a `T`, or
## Empty, holding nothing, like Rust's `Option<T>` and Swift's `Optional`.
##
## Use it instead of a null reference or a sentinel (`-1`, `""`) wherever a
## value may be missing: the type says so, and reading the value goes through
## `value()`, which checks, or `value_or()`, which cannot fail. It works for
## every type, including those that have no null, such as `int`.
##
## `T?` is shorthand for `Optional<T>`, and a variable or field of an
## optional type that is not given a value starts as Empty.
##
## Build one with its cases (`Optional<int>.Value(1)`, `Optional<int>.Empty`).
## Test it with `is_value()` or `is_empty()`, as a condition by itself (`if (found)`), or with `match`
## and `is` on its cases (`if (found is Value(v))`).
##
## An optional is a [value enum](../language/value-structs.md): it is stored
## inline in whatever holds it, with no allocation, and copying one gives an
## independent optional. It is never null, and has no identity, so compare
## optionals with `==`, not `===`.
##
## @typeParam T the type of the value a Value optional holds
## @example
##     find_even(values: Array<int>): int? {
##         for (var v in values) {
##             if (v % 2 == 0) { return Optional<int>.Value(v); }
##         }
##         return Optional<int>.Empty;
##     }
##
##     main(): int {
##         var values = Array<int>();
##         values.append(3);
##         values.append(4);
##         var found = find_even(values);
##         if (!found) { return 1; }
##         return found.value() - 4;   # 0
##     }
[Value]
export enum Optional<T> {
    ## Holds no value. It is the first case, so an optional that is never
    ## given a value is Empty.
    Empty,
    ## Holds a value.
    ##
    ## @param value the value held
    Value(value: T),

    ## Deprecated: use the `Value` case, `Optional<T>.Value(value)`,
    ## instead.
    ##
    ## Returns a Value optional holding `value`.
    ##
    ## @param value the value to hold
    ## @returns a Value optional whose value is `value`
    [Deprecated("use the case 'Value' instead", "Value")]
    static some(value: T): Optional<T> {
        return Optional<T>.Value(value);
    }

    ## Deprecated: use the `Empty` case, `Optional<T>.Empty`, instead.
    ##
    ## Returns an Empty optional, one holding no value.
    ##
    ## @returns an Empty optional
    [Deprecated("use the case 'Optional<T>.Empty' instead")]
    static none(): Optional<T> {
        return Optional<T>.Empty;
    }

    ## Reports whether this optional holds a value.
    ##
    ## @returns true when the optional is Value
    ## @example
    ##     var found = Optional<int>.Value(7);
    ##     if (found.is_value()) { print(found.value()); }   # prints 7
    is_value(): bool {
        return this is Value;
    }

    ## Reports whether this optional holds no value.
    ##
    ## @returns true when the optional is Empty
    ## @example
    ##     var missing = Optional<int>.Empty;
    ##     if (missing.is_empty()) { print("missing"); }
    is_empty(): bool {
        return this is Empty;
    }

    ## Deprecated: use `is_value` instead.
    ##
    ## Reports whether this optional holds a value.
    ##
    ## @returns true when the optional is Value
    [Deprecated("use 'is_value' instead", "is_value")]
    is_some(): bool {
        return this is Value;
    }

    ## Deprecated: use `is_empty` instead.
    ##
    ## Reports whether this optional holds no value.
    ##
    ## @returns true when the optional is Empty
    [Deprecated("use 'is_empty' instead", "is_empty")]
    is_none(): bool {
        return this is Empty;
    }

    ## Reports whether this optional holds a value: the truth test, so an
    ## optional can stand as a condition by itself.
    ##
    ## `if (found)` means `if (found.is_value())`, `!found` means
    ## `found.is_empty()`, and the same holds in `while`, `&&`, `||` and
    ## `?:`.
    ##
    ## @returns true when the optional is Value
    ## @example
    ##     var found = Optional<int>.Value(7);
    ##     if (found) { print(found.value()); }   # prints 7
    !!(): bool {
        return this is Value;
    }

    ## Returns the value, panicking if this optional is Empty.
    ##
    ## For a struct `T` the caller gets its own reference; the optional keeps
    ## its reference too.
    ##
    ## @returns the value of a Value optional
    ## @panics if the optional is Empty ("Optional.value on an Empty optional")
    ## @example
    ##     var n = Optional<int>.Value(42).value();   # 42
    value(location: __ptr<char> = __caller_location()): T {
        if (this is Value(value)) {
            return value;
        }
        panic("Optional.value on an Empty optional", location);
    }

    # What `e?` lowers to (the builder's `lift_tries`): it returns early when
    # `_propagates()`, with the enclosing function's
    # `_from_residual(e._residual())`, an Empty optional.
    _propagates(): bool {
        return this is Empty;
    }

    _residual(): bool {
        return false;
    }

    static _from_residual(empty: bool): Optional<T> {
        return Optional<T>.Empty;
    }

    ## Returns the value, or `fallback` if this optional is Empty.
    ##
    ## Never panics. `fallback` is evaluated by the caller whether or not it
    ## is used.
    ##
    ## @param fallback the value to return when the optional is Empty
    ## @returns the value when the optional is Value, otherwise `fallback`
    ## @example
    ##     var n = Optional<int>.Empty.value_or(-1);   # -1
    value_or(fallback: T): T {
        if (this is Value(value)) {
            return value;
        }
        return fallback;
    }
}
