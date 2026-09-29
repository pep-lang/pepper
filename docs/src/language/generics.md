# Generics

Generics let you write a struct or a function once and use it with many types.
Add type parameters in angle brackets after the name, then use them like any
other type name. The standard library's [`Array<T>`](../reference/array.md),
[`HashMap<K, V>`](../reference/hash.md), and
[`Result<TValue, TError>`](../reference/result.md) are all ordinary generic
structs written this way.

Pepper generics work like C++ templates: each distinct set of type arguments,
such as `Stack<int>` or `Stack<String>`, produces its own copy of the code,
compiled for those exact types. There is no runtime cost for using them.

## Generic structs

```pepper
{{#include ../../examples/generics-structs.pep}}
```

- Name the type parameters after the struct's name: `struct Stack<T>`,
  `struct Entry<K, V>`. Inside the struct, fields, parameters, return types,
  and locals can all use them.
- Name the type arguments whenever you use the struct: `Stack<int>()`,
  `var s: Stack<String>;`.
- `Stack<int>` and `Stack<String>` are different types.

> **Note:** Inside a generic struct, `var top = items.last();` cannot infer a
> type that involves a type parameter yet, and fails with
> `unknown type name 'T'`. Write the type out: `var top: T = items.last();`.

## Generic functions

A free function takes type parameters the same way:

```pepper
{{#include ../../examples/generics-functions.pep}}
```

Write the type arguments at every call, `larger<int>(3, 9)`. Pepper does not
infer them from the arguments yet; leaving them out is reported as a call to
an unknown function:

```text
main.pep:7:12: error: call to undeclared function 'larger'
    7 |     return larger(3, 9);
      |            ^~~~~~
```

Because each use is compiled for its concrete types, the body may use any
operator, field, or method that the type arguments provide. `total_area<T>`
calls `shape.area()`, so it works with any `T` that has an `area()` method
returning a number, and using it with a type that lacks one is a compile
error. Pepper does not yet let you state such requirements up front with a
[trait](traits-and-extensions.md#traits).

Methods cannot have type parameters of their own yet; only structs and free
functions can.

## Default type arguments

A type parameter can have a default, written `Name=Type`. When a use leaves
that argument out, the default fills it in:

```pepper
{{#include ../../examples/generics-defaults.pep}}
```

Arguments are matched to parameters in order, so put the parameters that have
defaults last. The standard library declares `struct Result<TValue, TError=Error>`, so
`Result<int>` means `Result<int, Error>`. See
[Error handling with Result](results.md).

## Overriding a generic function for one type

You can give a generic function a separate definition for a specific type
argument. Write the concrete type where the type parameter would go:

```pepper
{{#include ../../examples/generics-overrides.pep}}
```

A call whose type argument matches an override, such as `describe<int>(7)`,
uses the override; every other call uses the generic version. The standard
library uses this to give [`hash<String>`](../reference/hash.md) a
content-based hash, while `hash<T>` hashes other structs by identity.

An override can name a built-in type (`int`, `bool`, `String`, and so on) or
one of your own structs, such as `describe<Point>`. An override for a struct
must be in the same file as the generic function: in another file it is
reported as a duplicate declaration (see
[Visibility](visibility.md#one-namespace-for-the-whole-program)).

To add methods to a generic struct from outside its declaration, use an
[extension](traits-and-extensions.md#extending-generic-structs).
