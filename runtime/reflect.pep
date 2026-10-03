## `reflect` exists only inside a [`static` block](../language/reflection.md),
## which runs while compiling. It needs no import. Everything here is
## evaluated by the compiler: the values are compile-time numbers, `bool`s,
## strings, lists, and the members, cases, functions and attributes below.
## The [Reflection and attributes](../language/reflection.md) chapter
## explains how a block mixes them with the code it emits.
##
## The compiler provides `reflect` itself; this file only declares it, with
## `[__BuiltIn]`, for this reference and the editor.

## The name of type `T` as it is written in source, with its type arguments
## (`"Box<int>"`, `"Array<String>"`).
##
## @typeParam T the type to name
## @returns the type's name
[__BuiltIn("reflect.name")]
export name<T>(): String;

## The public fields and [properties](../language/properties.md) of struct
## `T`, in declaration order, as members.
##
## @typeParam T a struct
## @returns one member per public field or property
[__BuiltIn("reflect.properties")]
export properties<T>(): List<Member>;

## Every field of struct `T`, private ones and a property's storage included,
## in declaration order, as members. It is meant for code a struct's author
## writes, such as a field-by-field `==`, so it is available only in the
## file that declares `T`; anywhere else it is an error that points at
## `properties`.
##
## @typeParam T a struct declared in this file
## @returns one member per field
[__BuiltIn("reflect.fields")]
export fields<T>(): List<Member>;

## The cases of enum `E`, in declaration order.
##
## @typeParam E an enum
## @returns one case per enum case
[__BuiltIn("reflect.cases")]
export cases<E>(): List<Case>;

## Every free function in the program that carries attribute `A`.
##
## @typeParam A an [attribute struct](../language/reflection.md#attributes)
## @returns one function per function marked `[A]`
[__BuiltIn("reflect.functions_with")]
export functions_with<A>(): List<Function>;

## Whether `T` is a struct. A number, `bool` or `char` is not, nor is an
## enum or a trait.
##
## @typeParam T the type to test
## @returns whether `T` is a struct
[__BuiltIn("reflect.is_struct")]
export is_struct<T>(): bool;

## Whether `T` is an enum.
##
## @typeParam T the type to test
## @returns whether `T` is an enum
[__BuiltIn("reflect.is_enum")]
export is_enum<T>(): bool;

## Whether `T` is a trait.
##
## @typeParam T the type to test
## @returns whether `T` is a trait
[__BuiltIn("reflect.is_trait")]
export is_trait<T>(): bool;

## Whether `T` is a reference type, whose slots can be null: a struct, or an
## enum whose cases carry values, unless it is `[Value]`.
##
## @typeParam T the type to test
## @returns whether `T` is a reference type
[__BuiltIn("reflect.is_reference")]
export is_reference<T>(): bool;

## Whether `A` and `B` are the same type, after aliases (`int` and `i32`
## are). A member's `Type` can be either argument:
## `reflect.is_same<field.Type, String>()`.
##
## @typeParam A the first type
## @typeParam B the second type
## @returns whether they are the same type
[__BuiltIn("reflect.is_same")]
export is_same<A, B>(): bool;

## Whether struct or enum `T` carries attribute `A`. A member, case or
## function has the same test as a method with one type argument
## (`field.has_attribute<A>()`).
##
## @typeParam T the struct or enum
## @typeParam A the attribute struct
## @returns whether `T` carries `A`
[__BuiltIn("reflect.has_attribute")]
export has_attribute<T, A>(): bool;

## The value of attribute `A` on struct or enum `T`: each field of attribute
## struct `A` by name (`reflect.attribute<T, Deprecated>().message`). It is
## an error when `T` does not carry `A`. A member, case or function has the
## same as a method with one type argument (`field.attribute<A>()`).
##
## @typeParam T the struct or enum
## @typeParam A the attribute struct
## @returns the attribute's value
[__BuiltIn("reflect.attribute")]
export attribute<T, A>(): A;

## Whether the build defines [build option](../language/build-options.md)
## `name` (`-D NAME` or `-D NAME=value`).
##
## @param name the option's name: a letter or `_`, then letters, digits and
##   `_`
## @returns whether it is defined
[__BuiltIn("reflect.has_build_option")]
export has_build_option(name: String): bool;

## The value of [build option](../language/build-options.md) `name`, as a
## string (`-D NAME` alone is `"1"`). It is an error when the build does not
## define the option.
##
## @param name the option's name
## @returns the option's value
[__BuiltIn("reflect.build_option")]
export build_option(name: String): String;

## The value of [build option](../language/build-options.md) `name`, as a
## string, or `default` when the build does not define it.
##
## @param name the option's name
## @param default the value when the build does not define it
## @returns the option's value, else `default`
[__BuiltIn("reflect.build_option")]
export build_option(name: String, default: String): String;

## Writes `value` as a note each time the compiler runs the call, on every
## compile, including one that succeeds; in an unrolled loop the note says
## which pass printed it. See
## [Seeing what a block does](../language/reflection.md#seeing-what-a-block-does).
##
## @typeParam T the value's compile-time kind
## @param value any compile-time value
[__BuiltIn("reflect.print")]
export print<T>(value: T);

## Stops the compile with an error at the call.
##
## @param message the error's text; an interpolated string can show the
##   values that matter
[__BuiltIn("reflect.error")]
export error(message: String);

## Stops the compile with an error at `condition` when it is false.
##
## @param condition a compile-time condition
## @param message the error's text
[__BuiltIn("reflect.assert")]
export assert(condition: bool, message: String);

## A field or property, from `properties` or `fields`. A compile-time value:
## no program can name its type.
[__BuiltIn("reflect.Member")]
export struct Member {
    ## Its name.
    const name: String;
    ## Its position in the list, from 0.
    const index: int;
    ## Whether it is the last in the list.
    const is_last: bool;
    ## Its type, as a string.
    const type_name: String;
    ## Its type, usable wherever a type is written
    ## (`var copy: field.Type = ...`).
    const Type: Type;
    ## Whether it is a `const` field.
    const is_const: bool;
    ## Whether it is a property rather than a field.
    const is_property: bool;

    ## Whether it carries attribute `A`.
    ##
    ## @typeParam A the attribute struct
    ## @returns whether it carries `A`
    has_attribute<A>(): bool;

    ## The value of attribute `A` on it; an error when it does not carry `A`.
    ##
    ## @typeParam A the attribute struct
    ## @returns the attribute's value
    attribute<A>(): A;

    ## Emits `value.name`, a read of this member of `value`.
    ##
    ## @typeParam T the struct
    ## @param value the struct to read from
    ## @returns the member's value
    get<T>(value: T): Type;

    ## Emits `value.name = x`, a store to this member of `value`.
    ##
    ## @typeParam T the struct
    ## @param value the struct to store into
    ## @param x the value to store
    set<T>(value: T, x: Type);
}

## An enum case, from `cases`. A compile-time value: no program can name its
## type.
[__BuiltIn("reflect.Case")]
export struct Case {
    ## Its name.
    const name: String;
    ## Its integer value, or the tag of a case that carries values.
    const value: int;
    ## Its position, from 0.
    const index: int;
    ## Whether it is the last case.
    const is_last: bool;
    ## The values it carries, as members, in order; empty when it carries
    ## none. A value's `get(v)` reads it from `v`, which must hold this case.
    const values: List<Member>;

    ## Whether it carries attribute `A`.
    ##
    ## @typeParam A the attribute struct
    ## @returns whether it carries `A`
    has_attribute<A>(): bool;

    ## The value of attribute `A` on it; an error when it does not carry `A`.
    ##
    ## @typeParam A the attribute struct
    ## @returns the attribute's value
    attribute<A>(): A;

    ## Emits a test of whether `v` holds this case.
    ##
    ## @typeParam E the enum
    ## @param v the enum value to test
    ## @returns whether `v` holds this case
    matches<E>(v: E): bool;

    ## Emits the case made with `values` (`case.get()` for one that carries
    ## none); at module scope, the case itself.
    ##
    ## @typeParam E the enum
    ## @typeParam TValues the types of the values
    ## @param values the values the case carries, one argument each
    ## @returns the enum value
    get<E, TValues>(values: TValues): E;
}

## A function, from `functions_with`. A compile-time value: no program can
## name its type.
[__BuiltIn("reflect.Function")]
export struct Function {
    ## Its name.
    const name: String;

    ## Whether it carries attribute `A`.
    ##
    ## @typeParam A the attribute struct
    ## @returns whether it carries `A`
    has_attribute<A>(): bool;

    ## The value of attribute `A` on it; an error when it does not carry `A`.
    ##
    ## @typeParam A the attribute struct
    ## @returns the attribute's value
    attribute<A>(): A;

    ## Emits a direct call of the function with `arguments`.
    ##
    ## @typeParam R what the function returns
    ## @typeParam TArguments the types of the arguments
    ## @param arguments the call's arguments, one argument each
    ## @returns what the call returns
    call<R, TArguments>(arguments: TArguments): R;
}

## What `properties`, `fields`, `cases`, `functions_with` and a case's
## `values` return. A compile-time `for` unrolls over it.
##
## @typeParam T a member, case or function
[__BuiltIn("reflect.List")]
export struct List<T> {
    ## How many items it holds.
    const count: int;
    ## Whether it holds none.
    const is_empty: bool;

    ## The item at index `i`.
    ##
    ## @param i its position, from 0
    ## @returns the item
    [](i: int): T;
}

## A compile-time string: a literal, a member's `name`, or the result of
## `name`, `+` or interpolation. It joins with `+` and interpolation.
[__BuiltIn("reflect.String")]
export struct String {
    ## How many characters it holds.
    const length: int;
    ## Whether it holds none.
    const is_empty: bool;

    ## Whether it starts with `s`.
    ##
    ## @param s the prefix
    ## @returns whether it starts with `s`
    starts_with(s: String): bool;

    ## Whether it ends with `s`.
    ##
    ## @param s the suffix
    ## @returns whether it ends with `s`
    ends_with(s: String): bool;

    ## Whether `s` occurs in it.
    ##
    ## @param s the text to find
    ## @returns whether it contains `s`
    contains(s: String): bool;

    ## A new compile-time string: this one followed by `rhs`.
    ##
    ## @param rhs the string to append
    ## @returns the joined string
    +(rhs: String): String;
}
