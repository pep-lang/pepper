<!-- Generated from runtime/reflect.pep by `pep-doc reference`. Do not edit. -->

# The reflect module (compile time)

`reflect` exists only inside a [`static` block](../language/reflection.md),
which runs while compiling. It needs no import. Everything here is
evaluated by the compiler: the values are compile-time numbers, `bool`s,
strings, lists, and the members, cases, functions and attributes below.
The [Reflection and attributes](../language/reflection.md) chapter
explains how a block mixes them with the code it emits.

The compiler provides `reflect` itself; this file only declares it, with
`[__BuiltIn]`, for this reference and the editor.

Source: `runtime/reflect.pep`

## reflect.name

```pepper
reflect.name<T>(): String
```

The name of type `T` as it is written in source, with its type arguments
(`"Box<int>"`, `"Array<String>"`).

**Type parameters**
- `T` — the type to name

**Returns**
- the type's name

## reflect.properties

```pepper
reflect.properties<T>(): List<Member>
```

The public fields and [properties](../language/properties.md) of struct
`T`, in declaration order, as members.

**Type parameters**
- `T` — a struct

**Returns**
- one member per public field or property

## reflect.fields

```pepper
reflect.fields<T>(): List<Member>
```

Every field of struct `T`, private ones and a property's storage included,
in declaration order, as members. It is meant for code a struct's author
writes, such as a field-by-field `==`, so it is available only in the
file that declares `T`; anywhere else it is an error that points at
`properties`.

**Type parameters**
- `T` — a struct declared in this file

**Returns**
- one member per field

## reflect.cases

```pepper
reflect.cases<E>(): List<Case>
```

The cases of enum `E`, in declaration order.

**Type parameters**
- `E` — an enum

**Returns**
- one case per enum case

## reflect.functions_with

```pepper
reflect.functions_with<A>(): List<Function>
```

Every free function in the program that carries attribute `A`.

**Type parameters**
- `A` — an [attribute struct](../language/reflection.md#attributes)

**Returns**
- one function per function marked `[A]`

## reflect.is_struct

```pepper
reflect.is_struct<T>(): bool
```

Whether `T` is a struct. A number, `bool` or `char` is not, nor is an
enum or a trait.

**Type parameters**
- `T` — the type to test

**Returns**
- whether `T` is a struct

## reflect.is_enum

```pepper
reflect.is_enum<T>(): bool
```

Whether `T` is an enum.

**Type parameters**
- `T` — the type to test

**Returns**
- whether `T` is an enum

## reflect.is_trait

```pepper
reflect.is_trait<T>(): bool
```

Whether `T` is a trait.

**Type parameters**
- `T` — the type to test

**Returns**
- whether `T` is a trait

## reflect.is_reference

```pepper
reflect.is_reference<T>(): bool
```

Whether `T` is a reference type, whose slots can be null: a struct, or an
enum whose cases carry values, unless it is `[Value]`.

**Type parameters**
- `T` — the type to test

**Returns**
- whether `T` is a reference type

## reflect.is_same

```pepper
reflect.is_same<A, B>(): bool
```

Whether `A` and `B` are the same type, after aliases (`int` and `i32`
are). A member's `Type` can be either argument:
`reflect.is_same<field.Type, String>()`.

**Type parameters**
- `A` — the first type
- `B` — the second type

**Returns**
- whether they are the same type

## reflect.has_attribute

```pepper
reflect.has_attribute<T, A>(): bool
```

Whether struct or enum `T` carries attribute `A`. A member, case or
function has the same test as a method with one type argument
(`field.has_attribute<A>()`).

**Type parameters**
- `T` — the struct or enum
- `A` — the attribute struct

**Returns**
- whether `T` carries `A`

## reflect.attribute

```pepper
reflect.attribute<T, A>(): A
```

The value of attribute `A` on struct or enum `T`: each field of attribute
struct `A` by name (`reflect.attribute<T, Deprecated>().message`). It is
an error when `T` does not carry `A`. A member, case or function has the
same as a method with one type argument (`field.attribute<A>()`).

**Type parameters**
- `T` — the struct or enum
- `A` — the attribute struct

**Returns**
- the attribute's value

## reflect.has_build_option

```pepper
reflect.has_build_option(name: String): bool
```

Whether the build defines [build option](../language/build-options.md)
`name` (`-D NAME` or `-D NAME=value`).

**Parameters**
- `name` — the option's name: a letter or `_`, then letters, digits and `_`

**Returns**
- whether it is defined

## reflect.build_option

```pepper
reflect.build_option(name: String): String
```

The value of [build option](../language/build-options.md) `name`, as a
string (`-D NAME` alone is `"1"`). It is an error when the build does not
define the option.

**Parameters**
- `name` — the option's name

**Returns**
- the option's value

## reflect.build_option

```pepper
reflect.build_option(name: String, default: String): String
```

The value of [build option](../language/build-options.md) `name`, as a
string, or `default` when the build does not define it.

**Parameters**
- `name` — the option's name
- `default` — the value when the build does not define it

**Returns**
- the option's value, else `default`

## reflect.print

```pepper
reflect.print<T>(value: T)
```

Writes `value` as a note each time the compiler runs the call, on every
compile, including one that succeeds; in an unrolled loop the note says
which pass printed it. See
[Seeing what a block does](../language/reflection.md#seeing-what-a-block-does).

**Type parameters**
- `T` — the value's compile-time kind

**Parameters**
- `value` — any compile-time value

## reflect.error

```pepper
reflect.error(message: String)
```

Stops the compile with an error at the call.

**Parameters**
- `message` — the error's text; an interpolated string can show the values that matter

## reflect.assert

```pepper
reflect.assert(condition: bool, message: String)
```

Stops the compile with an error at `condition` when it is false.

**Parameters**
- `condition` — a compile-time condition
- `message` — the error's text

## reflect.Member

```pepper
struct reflect.Member
```

A field or property, from `properties` or `fields`. A compile-time value:
no program can name its type.

### Fields

#### name

```pepper
const name: String
```

Its name.

#### index

```pepper
const index: int
```

Its position in the list, from 0.

#### is_last

```pepper
const is_last: bool
```

Whether it is the last in the list.

#### type_name

```pepper
const type_name: String
```

Its type, as a string.

#### Type

```pepper
const Type: Type
```

Its type, usable wherever a type is written
(`var copy: field.Type = ...`).

#### is_const

```pepper
const is_const: bool
```

Whether it is a `const` field.

#### is_property

```pepper
const is_property: bool
```

Whether it is a property rather than a field.

### Methods

#### has_attribute

```pepper
has_attribute<A>(): bool
```

Whether it carries attribute `A`.

**Type parameters**
- `A` — the attribute struct

**Returns**
- whether it carries `A`

#### attribute

```pepper
attribute<A>(): A
```

The value of attribute `A` on it; an error when it does not carry `A`.

**Type parameters**
- `A` — the attribute struct

**Returns**
- the attribute's value

#### get

```pepper
get<T>(value: T): Type
```

Emits `value.name`, a read of this member of `value`.

**Type parameters**
- `T` — the struct

**Parameters**
- `value` — the struct to read from

**Returns**
- the member's value

#### set

```pepper
set<T>(value: T, x: Type)
```

Emits `value.name = x`, a store to this member of `value`.

**Type parameters**
- `T` — the struct

**Parameters**
- `value` — the struct to store into
- `x` — the value to store

## reflect.Case

```pepper
struct reflect.Case
```

An enum case, from `cases`. A compile-time value: no program can name its
type.

### Fields

#### name

```pepper
const name: String
```

Its name.

#### value

```pepper
const value: int
```

Its integer value, or the tag of a case that carries values.

#### index

```pepper
const index: int
```

Its position, from 0.

#### is_last

```pepper
const is_last: bool
```

Whether it is the last case.

#### values

```pepper
const values: List<Member>
```

The values it carries, as members, in order; empty when it carries
none. A value's `get(v)` reads it from `v`, which must hold this case.

### Methods

#### has_attribute

```pepper
has_attribute<A>(): bool
```

Whether it carries attribute `A`.

**Type parameters**
- `A` — the attribute struct

**Returns**
- whether it carries `A`

#### attribute

```pepper
attribute<A>(): A
```

The value of attribute `A` on it; an error when it does not carry `A`.

**Type parameters**
- `A` — the attribute struct

**Returns**
- the attribute's value

#### matches

```pepper
matches<E>(v: E): bool
```

Emits a test of whether `v` holds this case.

**Type parameters**
- `E` — the enum

**Parameters**
- `v` — the enum value to test

**Returns**
- whether `v` holds this case

#### get

```pepper
get<E, TValues>(values: TValues): E
```

Emits the case made with `values` (`case.get()` for one that carries
none); at module scope, the case itself.

**Type parameters**
- `E` — the enum
- `TValues` — the types of the values

**Parameters**
- `values` — the values the case carries, one argument each

**Returns**
- the enum value

## reflect.Function

```pepper
struct reflect.Function
```

A function, from `functions_with`. A compile-time value: no program can
name its type.

### Fields

#### name

```pepper
const name: String
```

Its name.

### Methods

#### has_attribute

```pepper
has_attribute<A>(): bool
```

Whether it carries attribute `A`.

**Type parameters**
- `A` — the attribute struct

**Returns**
- whether it carries `A`

#### attribute

```pepper
attribute<A>(): A
```

The value of attribute `A` on it; an error when it does not carry `A`.

**Type parameters**
- `A` — the attribute struct

**Returns**
- the attribute's value

#### call

```pepper
call<R, TArguments>(arguments: TArguments): R
```

Emits a direct call of the function with `arguments`.

**Type parameters**
- `R` — what the function returns
- `TArguments` — the types of the arguments

**Parameters**
- `arguments` — the call's arguments, one argument each

**Returns**
- what the call returns

## reflect.List

```pepper
struct reflect.List<T>
```

What `properties`, `fields`, `cases`, `functions_with` and a case's
`values` return. A compile-time `for` unrolls over it.

**Type parameters**
- `T` — a member, case or function

### Fields

#### count

```pepper
const count: int
```

How many items it holds.

#### is_empty

```pepper
const is_empty: bool
```

Whether it holds none.

### Methods

#### operator []

```pepper
[](i: int): T
```

The item at index `i`.

**Parameters**
- `i` — its position, from 0

**Returns**
- the item

## reflect.String

```pepper
struct reflect.String
```

A compile-time string: a literal, a member's `name`, or the result of
`name`, `+` or interpolation. It joins with `+` and interpolation.

### Fields

#### length

```pepper
const length: int
```

How many characters it holds.

#### is_empty

```pepper
const is_empty: bool
```

Whether it holds none.

### Methods

#### starts_with

```pepper
starts_with(s: String): bool
```

Whether it starts with `s`.

**Parameters**
- `s` — the prefix

**Returns**
- whether it starts with `s`

#### ends_with

```pepper
ends_with(s: String): bool
```

Whether it ends with `s`.

**Parameters**
- `s` — the suffix

**Returns**
- whether it ends with `s`

#### contains

```pepper
contains(s: String): bool
```

Whether `s` occurs in it.

**Parameters**
- `s` — the text to find

**Returns**
- whether it contains `s`

#### operator +

```pepper
+(rhs: String): String
```

A new compile-time string: this one followed by `rhs`.

**Parameters**
- `rhs` — the string to append

**Returns**
- the joined string
