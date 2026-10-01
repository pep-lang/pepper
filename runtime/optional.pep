# A value that may be absent, like Rust's `Option<T>` and Swift's
# `Optional`. Pepper has no enums with payloads yet, so this is a struct with
# a flag and a slot; once payload enums land it becomes
# `enum Optional<T> { None, Some(value: T) }` with the same
# methods. The fields are private so that move changes no caller.

import "internals";

## A value of type `T` that may be absent: either Some, holding a `T`, or
## None, holding nothing, like Rust's `Option<T>` and Swift's `Optional`.
##
## Use it instead of a null reference or a sentinel (`-1`, `""`) wherever a
## value may be missing: the type says so, and reading the value goes through
## `value()`, which checks, or `value_or()`, which cannot fail. It works for
## every type, including those that have no null, such as `int`.
##
## `T?` is shorthand for `Optional<T>`, and a variable or field of an
## optional type that is not given a value starts as None.
##
## Build one with the static `some` or `none` functions, or `Optional<T>()`
## for None, and test it with `is_some()` or `is_none()`, or as a condition
## by itself (`if (found)`).
##
## An optional is a [value struct](../language/value-structs.md): it is
## stored inline in whatever holds it, with no allocation, and copying one
## gives an independent optional. It is never null, and has no identity, so
## compare optionals with `==`, not `===`.
##
## @typeParam T the type of the value a Some optional holds
## @example
##     find_even(values: Array<int>): int? {
##         for (var v in values) {
##             if (v % 2 == 0) { return Optional<int>.some(v); }
##         }
##         return Optional<int>.none();
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
export struct Optional<T> {
    # Whether `_value` holds the value.
    bool _has_value;
    # The value when `_has_value`, otherwise the default of `T` (zero for a
    # POD type, null for a struct type).
    T _value;

    ## Creates a None optional, one holding no value.
    ##
    ## @example
    ##     var nothing = Optional<int>();   # nothing.is_none() == true
    construct() {
        this._has_value = false;
    }

    ## Returns a Some optional holding `value`.
    ##
    ## For a struct `T` the optional acquires a reference to `value`.
    ##
    ## @param value the value to hold
    ## @returns a Some optional whose value is `value`
    ## @example
    ##     var answer = Optional<int>.some(42);
    static some(value: T): Optional<T> {
        var result = Optional<T>();
        result._has_value = true;
        result._value = value;
        return result;
    }

    ## Returns a None optional, one holding no value; the same as
    ## `Optional<T>()`.
    ##
    ## @returns a None optional
    ## @example
    ##     var nothing = Optional<String>.none();
    static none(): Optional<T> {
        return Optional<T>();
    }

    ## Reports whether this optional holds a value.
    ##
    ## @returns true when the optional is Some
    is_some(): bool {
        return this._has_value;
    }

    ## Reports whether this optional holds no value.
    ##
    ## @returns true when the optional is None
    is_none(): bool {
        return !this._has_value;
    }

    ## Reports whether this optional holds a value: the truth test, so an
    ## optional can stand as a condition by itself.
    ##
    ## `if (found)` means `if (found.is_some())`, `!found` means
    ## `found.is_none()`, and the same holds in `while`, `&&`, `||` and
    ## `?:`.
    ##
    ## @returns true when the optional is Some
    ## @example
    ##     var found = Optional<int>.some(7);
    ##     if (found) { print(found.value()); }   # prints 7
    !!(): bool {
        return this._has_value;
    }

    ## Returns the value, panicking if this optional is None.
    ##
    ## For a struct `T` the caller gets its own reference; the optional keeps
    ## its reference too.
    ##
    ## @returns the value of a Some optional
    ## @panics if the optional is None ("Optional.value on a None value")
    ## @example
    ##     var n = Optional<int>.some(42).value();   # 42
    value(): T {
        assert(this._has_value, "Optional.value on a None value");
        return this._value;
    }

    ## Returns the value, or `fallback` if this optional is None.
    ##
    ## Never panics. `fallback` is evaluated by the caller whether or not it
    ## is used.
    ##
    ## @param fallback the value to return when the optional is None
    ## @returns the value when the optional is Some, otherwise `fallback`
    ## @example
    ##     var n = Optional<int>.none().value_or(-1);   # -1
    value_or(fallback: T): T {
        if (this._has_value) {
            return this._value;
        }
        return fallback;
    }
}
