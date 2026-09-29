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
- `a === b` is true when `a` and `b` refer to the same object. See
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
- Ordinary parameters are written C-style, `Type name`, with an optional
  default: `float fahrenheit = 32.0`. The `name: Type` form that functions
  use is not accepted in a constructor yet.
- Inside the body, fields are in scope by name. Use `this.name` when a
  parameter has the same name as a field.
- A struct has at most one constructor. Pepper has no constructor
  overloading: use default arguments, or a [static method](#static-methods)
  for each alternative way to build the object.

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
is the operator, with the return type written first:

```pepper
{{#include ../../examples/structs-operators.pep}}
```

When the left operand is a struct that declares the operator, `a + b` becomes
the call `a.+(b)`. The right operand is the method's single parameter, and it
can be any type. These binary operators can be defined:

| Kind | Operators |
|---|---|
| Arithmetic | `+` `-` `*` `/` `%` `**` |
| Bitwise | `&` `|` `^` `>>` |
| Comparison and logical | `==` `!=` `>` `>=` `&&` `||` |
| Compound assignment | `+=` `-=` `*=` `/=` `%=` `>>=` `&=` `^=` |

Keep these rules in mind:

- Each operator is its own method. `!=` is not derived from `==`, and `+=` is
  not rewritten to `a = a + b`; define each one you want to use.
- Comparison and logical operators should return `bool`. Arithmetic, bitwise
  and compound assignment operators should return the struct's own type; a
  compound assignment usually changes `this` and returns it.
- The left operand decides: `a + b` uses the method on `a`'s type. An
  expression with a number on the left and a struct on the right, such as
  `2 * v`, is not supported.
- Operators that start with `<` (`<`, `<=`, `<<`, `<<=`) cannot be declared
  yet, because the parser reads the `<` as the start of generic arguments.
  `|=` cannot be overloaded yet either.
- Unary operators (`-a`, `!a`, `~a`) cannot be overloaded yet.

> **Note:** `var r = a - b;` currently assumes that an arithmetic operator
> returns the struct's own type. If yours returns something else, such as an
> `int`, give the variable its type explicitly: `int r = a - b;`.

### Comparing structs

Without an `==` method, `a == b` on two structs compares identity: it is true
only when both refer to the same object, exactly like `a === b`. The same goes
for `!=`. Define `==` and `!=` when two distinct objects with the same
contents should count as equal, as `String` and `Array` do. `===` always
compares identity, whatever methods the struct declares.

### Indexers

An indexer lets you write `object[index]`. Declare it with the element type,
`[]`, and parameters, but no name:

- With one parameter, `String [](int index)`, it handles reads: `shelf[i]`.
- With two parameters, `String [](int index, String value)`, it handles
  writes: `shelf[i] = value`. The second parameter is the value being stored.

A struct can have both. With both, compound assignment through an index
(`counts[i] += 1`) reads with the first and writes with the second.
[`Array`](../reference/array.md) and [`String`](../reference/string.md) are
indexed this way.
