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

Pepper infers the type arguments from the arguments, so `larger(3, 9)` calls
`larger<int>`. You can always write them out, `larger<float>(2.5, 1.5)`, and
must when the arguments do not determine every type parameter, for example one
that appears only in the return type:

```text
main.pep:4:13: error: cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)
    4 |     var b = make();
      |             ^~~~
main.pep:1:1: note: declared here
    1 | make<T>(): Box<T> { return Box<T>(); }
      | ^~~~
```

Inference works through closures in both directions. In
`transform(words, (w) => w.size())`, where `transform<T, U>(items: Array<T>,
f: (T) => U)`, `words` gives `T`, which types the closure's parameter `w`, and
the closure's result gives `U`.

Because each use is compiled for its concrete types, the body may use any
operator, field, or method that the type arguments provide. `total_area<T>`
calls `shape.area()`, so it works with any `T` that has an `area()` method
returning a number, and using it with a type that lacks one is a compile
error. Pepper does not yet let you state such requirements up front with a
[trait](traits-and-extensions.md#traits).

## Generic methods

A method can have type parameters of its own, in a struct, a generic struct,
an extension, or a trait's default method. They are inferred at each call like
a function's, or written after the method name:

```pepper
{{#include ../../examples/generics-methods.pep}}
```

- Write the type arguments with no space before `<` or after `>`:
  `b.map<long>(f)`. With a space, `a.b < c` is a comparison.
- A generic method cannot be called through a [trait value](traits-and-extensions.md#traits-as-types),
  since each of its uses is compiled separately. Call it on the concrete type.
- The iterator adapters `map` and `filter` are generic default methods of
  `Iterator<T>`; see [Iteration](iteration.md#adapters).

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
a struct, such as `describe<Point>`. It may be declared in any file that can
see both the generic function and the struct: here `main.pep` overrides
`shapes.pep`'s `describe<T>` for its own `Point`, and the generic code in
`shapes.pep` uses the override too:

```pepper
{{#include ../../examples/generics-struct-override/shapes.pep}}
```

```pepper
{{#include ../../examples/generics-struct-override/main.pep}}
```

A function whose type parameters all name types the file can see (its own,
the ones it imports, under any name such as `P` after
`import [Point as P] from geo`, and the standard library's) is an override
when the file can also see a generic function of that name and number of
type parameters (its own, an imported one, or the standard library's);
otherwise a struct's name is just the name of a type parameter. The generic
may be spelled by any name the file has for it (`show<Point>` after
`import [describe as show]`). A type argument must name a struct, not a type
alias or a trait. A generic and another function of the same name in one
file are [overloads](overloading.md#generic-members), unless they have the
same parameters, or the generic's type parameters all name structs the file
can see without a generic of that name to override: either is an error,
since it usually means an override whose type argument the file cannot see,
or of a generic the file's own function of that name hides.

To add methods to a generic struct from outside its declaration, use an
[extension](traits-and-extensions.md#extending-generic-structs).
