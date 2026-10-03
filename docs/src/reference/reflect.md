# The reflect module (compile time)

`reflect` is built into the compiler, not written in the runtime, so this
page is written by hand; the test `reflect_reference_names_every_function`
in `tools/docgen` fails when the compiler gains a `reflect` function or a
property this page does not name.

`reflect` exists only inside a [`static` block](../language/reflection.md),
which runs while compiling. It needs no import. Everything here is
evaluated by the compiler: the values are compile-time numbers, `bool`s,
strings, lists, and the members, cases, functions and attributes below. The
[Reflection and attributes](../language/reflection.md) chapter explains how
a block mixes them with the code it emits.

## reflect.name

```pepper
reflect.name<T>(): String
```

The name of type `T` as it is written in source, with its type arguments
(`"Box<int>"`, `"Array<String>"`).

**Type parameters**
- `T` — the type to name

**Returns** the type's name

## reflect.properties

```pepper
reflect.properties<T>(): list of member
```

The public fields and [properties](../language/properties.md) of struct `T`,
in declaration order, as [members](#member).

**Type parameters**
- `T` — a struct

**Returns** one member per public field or property

## reflect.fields

```pepper
reflect.fields<T>(): list of member
```

Every field of struct `T`, private ones and a property's storage included,
in declaration order, as [members](#member). It is meant for code a struct's
author writes, such as a field-by-field `==`, so it is available only in the
file that declares `T`; anywhere else it is an error that points at
`properties`.

**Type parameters**
- `T` — a struct declared in this file

**Returns** one member per field

## reflect.cases

```pepper
reflect.cases<E>(): list of case
```

The cases of enum `E`, in declaration order, as [cases](#case).

**Type parameters**
- `E` — an enum

**Returns** one case per enum case

## reflect.functions_with

```pepper
reflect.functions_with<A>(): list of function
```

Every free function in the program that carries attribute `A`, as
[functions](#function).

**Type parameters**
- `A` — an [attribute struct](../language/reflection.md#attributes)

**Returns** one function per function marked `[A]`

## reflect.is_struct, reflect.is_enum, reflect.is_trait

```pepper
reflect.is_struct<T>(): bool
reflect.is_enum<T>(): bool
reflect.is_trait<T>(): bool
```

What kind of type `T` is. A number, `bool` or `char` is none of them.

**Type parameters**
- `T` — the type to test

**Returns** whether `T` is a struct, an enum, or a trait

## reflect.is_reference

```pepper
reflect.is_reference<T>(): bool
```

Whether `T` is a reference type, whose slots can be null: a struct, or an
enum whose cases carry values, unless it is `[Value]`.

**Type parameters**
- `T` — the type to test

**Returns** whether `T` is a reference type

## reflect.is_same

```pepper
reflect.is_same<A, B>(): bool
```

Whether `A` and `B` are the same type, after aliases (`int` and `i32` are).
A member's `Type` can be either argument:
`reflect.is_same<field.Type, String>()`.

**Type parameters**
- `A` — the first type
- `B` — the second type

**Returns** whether they are the same type

## reflect.has_attribute, reflect.attribute

```pepper
reflect.has_attribute<T, A>(): bool
reflect.attribute<T, A>(): attribute
```

Attribute `A` on struct or enum `T`. A member, case or function has the
same two as methods with one type argument (`field.has_attribute<A>()`).

**Type parameters**
- `T` — the struct or enum
- `A` — the attribute struct

**Returns** `has_attribute`: whether `T` carries `A`; `attribute`: its
[value](#attribute)

**Errors** `attribute` when `T` does not carry `A`

## reflect.has_build_option

```pepper
reflect.has_build_option(name: String): bool
```

Whether the build defines [build option](../language/build-options.md)
`name` (`-D NAME` or `-D NAME=value`).

**Parameters**
- `name` — the option's name: a letter or `_`, then letters, digits and `_`

**Returns** whether it is defined

## reflect.build_option

```pepper
reflect.build_option(name: String): String
reflect.build_option(name: String, default: String): String
```

The value of [build option](../language/build-options.md) `name`, as a
string (`-D NAME` alone is `"1"`).

**Parameters**
- `name` — the option's name
- `default` — the value when the build does not define it

**Returns** the option's value, else `default`

**Errors** without `default`, when the build does not define the option

## reflect.print

```pepper
reflect.print(value)
```

Writes `value` as a note each time the compiler runs the call, on every
compile, including one that succeeds; in an unrolled loop the note says
which pass printed it. See
[Seeing what a block does](../language/reflection.md#seeing-what-a-block-does).

**Parameters**
- `value` — any compile-time value

## reflect.error

```pepper
reflect.error(message: String)
```

Stops the compile with an error at the call.

**Parameters**
- `message` — the error's text; an interpolated string can show the values
  that matter

## reflect.assert

```pepper
reflect.assert(condition: bool, message: String)
```

Stops the compile with an error at `condition` when it is false.

**Parameters**
- `condition` — a compile-time condition
- `message` — the error's text

## Compile-time values

### member

A field or property, from `properties` or `fields`.

| | |
|---|---|
| `name` | its name |
| `index` | its position in the list, from 0 |
| `is_last` | whether it is the last in the list |
| `type_name` | its type, as a string |
| `Type` | its type, usable wherever a type is written (`var copy: field.Type = ...`) |
| `is_const` | whether it is a `const` field |
| `is_property` | whether it is a property rather than a field |
| `has_attribute<A>()`, `attribute<A>()` | attribute `A` on it |
| `get(value)` | emits `value.name` |
| `set(value, x)` | emits `value.name = x` |

### case

An enum case, from `cases`.

| | |
|---|---|
| `name` | its name |
| `value` | its integer value, or the tag of a case that carries values |
| `index` | its position, from 0 |
| `is_last` | whether it is the last case |
| `values` | the values it carries, as members, in order; empty when it carries none. A value's `get(v)` reads it from `v`, which must hold this case |
| `has_attribute<A>()`, `attribute<A>()` | attribute `A` on it |
| `matches(v)` | emits a test of whether `v` holds this case |
| `get(values...)` | emits the case made with those values (`case.get()` for one that carries none); at module scope, the case itself |

### function

A function, from `functions_with`.

| | |
|---|---|
| `name` | its name |
| `has_attribute<A>()`, `attribute<A>()` | attribute `A` on it |
| `call(arguments...)` | emits a direct call |

### attribute

The value of an attribute, from `attribute<A>()`: each field of attribute
struct `A` by name (`function.attribute<Deprecated>().message`).

### list

What `properties`, `fields`, `cases`, `functions_with` and a case's `values`
return. A compile-time `for` unrolls over it.

| | |
|---|---|
| `count` | how many items it holds |
| `is_empty` | whether it holds none |
| `list[i]` | the item at index `i` |

### String

A compile-time string has `length`, `is_empty`, `starts_with(s)`,
`ends_with(s)` and `contains(s)`, and joins with `+` and interpolation.
