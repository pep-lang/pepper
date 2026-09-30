# Structs

A struct groups related values into one named type, and gives that type
behavior through methods. Pepper has no classes and no inheritance: a struct
holds data, methods and [extensions](traits-and-extensions.md) add behavior,
and [traits](traits-and-extensions.md#traits) describe what a type can do.

Every struct value is a reference to an object, so assigning a struct or
passing it to a function shares the object rather than copying it. The
[memory chapter](memory.md) explains exactly when objects are created and
destroyed.

## Declaring a struct

Declare a struct with `struct`, a name, and its fields in braces. Struct
names are PascalCase by convention.

```pepper
{{#include ../../examples/structs-basics.pep}}
```

Things to notice:

- A field is declared like a variable: `var x: int = 0;` or, C-style,
  `int x = 0;`. The initializer is optional.
- A field without an initializer starts at its type's default: zero for
  numbers, `false` for `bool`, and null for a struct type such as `String` or
  another struct. Reading a field through a null reference crashes the
  program, so give struct-typed fields a value before you use them.
- A struct with no constructor can be created with its name and empty
  parentheses, `Point()`. There is no `new` keyword at the call site.
- `p.x` reads a field and `p.x = 3` writes it.
- `a === b` is true when `a` and `b` refer to the same object, and `a !== b`
  when they do not. See
  [Comparing structs](#comparing-structs) for `==`.

A struct can have a field whose type is a struct declared later in the file.
A struct cannot yet have a field of its own type, or of a struct type whose
fields lead back to it (such as `Parent` holding a `Child` that holds a
`Parent`): the compiler rejects both with `GEP index out of range`. Hold such
references in an `Array` instead, as in the
[cycles example](memory.md#cycles-leak).

## Constructors

A constructor sets up a new object. Declare it with `construct`, followed by
its parameters and a body. Callers create the object by calling the struct's
name like a function.

```pepper
{{#include ../../examples/structs-constructors.pep}}
```

- A parameter written `this.width = 1` stores its argument directly into the
  field `width`, before the body runs. The `= 1` is required: it is the value
  used when the caller omits that argument.
- Ordinary parameters are written as in a function, `name: Type`, with an
  optional default: `fahrenheit: float = 32.0`. The C-style form,
  `float fahrenheit = 32.0`, is accepted too.
- Inside the body, fields are in scope by name. Use `this.name` when a
  parameter has the same name as a field.
- A struct has at most one constructor, and declaring a second is an error
  (`redefinition of the constructor of 'S'`). Constructors do not
  [overload](overloading.md) yet: use default arguments, or a [static method](#static-methods)
  for each alternative way to build the object. Likewise, a struct has at
  most one destructor.

A `this.field` parameter must have a default. Leaving it out is an error:

```pepper
struct Point {
    var x: int;
    construct(this.x) {}
}
```

```text
main.pep:3:21: error: expected '='
    3 |     construct(this.x) {}
      |                     ^
```

A struct without a constructor accepts no arguments:

```text
main.pep:7:13: error: too many arguments to 'Point': expected 0, have 2
    7 |     var p = Point(1, 2);
      |             ^~~~~
```

> **Note:** `new` is the older, deprecated spelling of `construct`. It still
> compiles, with a warning that offers the fix (see
> [Deprecations](compiler-errors.md#deprecations)).

### Implicit conversions

A constructor marked `[Implicit]` also converts. Wherever a value flows into a
place whose type is the struct, and the value has the constructor's parameter
type, the compiler calls the constructor for you:

```pepper
{{#include ../../examples/structs-implicit.pep}}
```

The standard library uses this for [`io.Path`](../reference/io-path.md),
which converts from a `String`, so `dir.join("logs")` and
`io.File.open("notes.txt")` work without writing `io.Path(...)`, and for
[`Error`](../reference/result.md), so `Result<int>.err("bad input")` works.

- **Where it applies**: a variable's initializer when the variable's type is
  written, an assignment, a function, method or constructor argument
  (operators and `a[i] = value` included), a call through a function value,
  and a `return` from a function with a declared return type.
- **Where it does not**: the receiver of a method call (`"docs".join("x")`
  does not turn `"docs"` into a `Path`), a `var` whose type is inferred
  (`var n = 12.0;` stays a `double`), and `__null`, which stays a null
  reference.
- **One conversion per value.** The value must already have the
  constructor's parameter type, or reach it by a widening that loses nothing:
  a smaller integer to a larger one, an integer literal that fits, `float` to
  `double`, or a struct to a [trait it declares](traits-and-extensions.md#traits-as-types).
  Conversions never chain: if `Tag` converts from `Name` and `Name` from
  `String`, a `String` does not become a `Tag`.
- **Overloads prefer anything else.** Among [overloads](overloading.md),
  a member that takes the value as it is, or by any other conversion, beats
  one that needs an `[Implicit]` constructor.
- **Each conversion is a constructor call**, so it allocates a new object.
  The VS Code extension shows the call as an inlay hint around the converted
  value, and hovering the value names the constructor.
  The converted value is a temporary like any constructor call's result: it
  is released after the call it was passed to (see
  [Memory and reference counting](memory.md)).
- Only a constructor that can be called with one argument may be
  `[Implicit]`: one parameter, or a first parameter followed by parameters
  that all have defaults. It may not convert from the struct itself or, in a
  generic struct, from a bare type parameter (`construct(T value)`):

```text
main.pep:2:5: error: 'Implicit' constructor of 'Span' must be callable with one argument
    2 |     [Implicit]
      |     ^~~~~~~~~~
```

Conversions are opt-in: a constructor without `[Implicit]` never runs on its
own. When a value would fit such a constructor, the type error says so:

```text
main.pep:6:27: error: cannot pass a value of type 'String' as argument 1 of 'show', which has type 'Label'
    6 | main(): int { return show("x"); }
      |                           ^~~
main.pep:3:5: note: 'Label' has a constructor from 'String': call 'Label(...)', or mark the constructor [Implicit]
    3 |     construct(String text) { this.text = text; }
      |     ^~~~~~~~~
```

## Destructors

A destructor runs when an object is destroyed, which happens when the last
reference to it goes away. Declare it with `destruct` and a body, with no
parentheses. Use it to release something the object holds that Pepper does not
manage for you, such as a file handle from C.

```pepper
{{#include ../../examples/structs-destructors.pep}}
```

You never call a destructor yourself. After it runs, Pepper releases the
object's fields, so a destructor can still read them. The
[memory chapter](memory.md) lists every point where an object can be
destroyed.

## Methods

A method is a function declared inside a struct. You call it on an object with
a dot, `v.length_squared()`, and inside it `this` refers to that object.

```pepper
{{#include ../../examples/structs-methods.pep}}
```

- Methods are written like [functions](functions.md): `name(parameters):
  ReturnType { ... }`. Leave out the return type for a method that returns
  nothing. The C-style form, `bool is_zero() { ... }`, works too.
- Inside a method, the object's fields and other methods can be named
  directly (`x`, `length_squared()`), or through `this` (`this.x`). A
  parameter or local with the same name as a field hides the field; use
  `this.` to reach the field.
- A method can change the fields of its object. Because struct values are
  references, the caller sees the change.
- Calling a method does not copy the object or add a reference to it. The
  result of a method call is a new reference, like any function result.

### Static methods

A method marked `static` belongs to the type rather than to one object. It has
no `this`, and you call it on the type name: `Vector.unit_x()`. Static methods
are the usual way to offer named constructors, such as the standard library's
`Result<int>.ok(42)`.

## Operators

A struct can define what the operators do for it. Declare a method whose name
is the operator, written like any other method: `==(other: Money): bool`.
The C-style form with the return type first, `bool ==(Money other)`, is
accepted too.

```pepper
{{#include ../../examples/structs-operators.pep}}
```

When the left operand is a struct that declares the operator, `a + b` becomes
the call `a.+(b)`. The right operand is the method's single parameter, and it
can be any type. These binary operators can be defined:

| Kind | Operators |
|---|---|
| Arithmetic | `+` `-` `*` `/` `%` `**` |
| Bitwise | `&` `\|` `^` `>>` |
| Bitwise shifts | `<<` `>>` |
| Comparison and logical | `==` `!=` `<` `<=` `>` `>=` `&&` `\|\|` |
| Compound assignment | `+=` `-=` `*=` `/=` `%=` `<<=` `>>=` `&=` `\|=` `^=` |

Keep these rules in mind:

- Each operator is its own method, with one exception: when a struct defines
  `==` but not `!=`, `a != b` means `!(a == b)`. `+=` is not rewritten to
  `a = a + b`; define each one you want to use.
- Comparison operators must return `bool`; any other return type is an error
  (`comparison operator '==' must return 'bool', not 'String'`). Logical
  operators should return `bool` too. Arithmetic, bitwise and compound
  assignment operators usually return the struct's own type; a compound
  assignment usually changes `this` and returns it.
- The left operand decides: `a + b` uses the method on `a`'s type. An
  expression with a number on the left and a struct on the right, such as
  `2 * v`, is not supported.
- Operators that start with `<` (`<`, `<=`, `<<`, `<<=`) can only be declared
  in the `name: Type` form, `<(other: V): bool`: in the C-style form the
  parser reads `bool <` as the start of generic arguments.
- Unary operators (`-a`, `!a`, `~a`) cannot be overloaded yet.

The result of an operator has the type its method returns, so with
`-(other: V): int`, `var r = a - b;` is an `int`.

### Comparing structs

Without an `==` method, `a == b` on two structs compares identity: it is true
only when both refer to the same object, exactly like `a === b`. The same goes
for `!=`. Define `==` when two distinct objects with the same contents should
count as equal, as `String` and `Array` do; `!=` then follows from it. `===` and
`!==` always compare identity, whatever methods the struct declares, so
`"a" + "b" == "ab"` is true while `"a" + "b" === "ab"` is false.

### Indexers

An indexer lets you write `object[index]`. Declare it as a method named `[]`:

- With one parameter, `[](index: int): String`, it handles reads: `shelf[i]`.
- With two parameters, `[](index: int, value: String): String`, it handles
  writes: `shelf[i] = value`. The second parameter is the value being stored.

The C-style form, `String [](int index)`, is accepted too.

A struct can have both. With both, compound assignment through an index
(`counts[i] += 1`) reads with the first and writes with the second.
[`Array`](../reference/array.md) and [`String`](../reference/string.md) are
indexed this way.
