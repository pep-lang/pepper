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

A struct can have a field whose type is a struct declared later in the file,
a field of its own type, or fields that lead back to it through other
structs (a `Team` holding a `Player` that holds the `Team`). A struct-typed
field holds a reference, so a linked list or a tree is just a struct that
names itself:

```pepper
{{#include ../../examples/structs-recursive.pep}}
```

Objects that refer to each other in a loop keep each other alive, so make
back pointers such as a child's parent a `Weak<T>` (see
[Cycles leak](memory.md#cycles-leak)).

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
- A struct may declare several constructors with different parameter
  lists; a call picks one by its arguments, as for any
  [overloaded](overloading.md#constructors) function. At most one of them
  may be `[Implicit]`. A struct has at most one destructor.

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
- Several methods can share a name when their parameters differ; each call
  picks the best fit (see [Overloading](overloading.md#methods-and-operators)).

### Static methods

A method marked `static` belongs to the type rather than to one object. It has
no `this`, and you call it on the type name: `Vector.unit_x()`. Static methods
are the usual way to offer named constructors, such as the standard library's
`Result<int>.ok(42)`.

Inside the struct, any method, static or not, can call a static method by
its bare name: `unit_x()` in a method of `Vector` means `Vector.unit_x()`.

```pepper
{{#include ../../examples/structs-static.pep}}
```

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

- An operator can be declared once per right-operand type (`+(Money)` and
  `+(int)`), and `a + b` picks by `b`'s type, as for any
  [overloaded](overloading.md#methods-and-operators) method.
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

The result of an operator has the type its method returns, so with
`-(other: V): int`, `var r = a - b;` is an `int`.

### Unary operators

A unary operator is a method with no parameters; its operand is `this`.

| Operator | Declaration | `op x` calls |
|---|---|---|
| Negation | `-(): V` | `x.-()` |
| Bitwise complement | `~(): V` | `x.~()` |
| Logical not | `!(): bool` | `x.!()` |
| Truth test | `!!(): bool` | `x.!!()` (see below) |

The C-style form works here too: `V -()`, `bool !!()`. `!` and `!!` must
return `bool` (`truth-test operator '!!' must return 'bool', not 'int'`), and
`!`, `~` and `!!` take no parameters. `-a` on a number is unchanged. A struct
may declare both a unary `-()` and a binary `-(other: V)`: they
[overload](overloading.md) each other, told apart by their number of
parameters.

### Truth tests and conditions

A condition asks a value "true or false?". For `bool` the answer is the value,
for a number it is "not zero", and for a raw pointer (`__ptr<T>`) or a function
value it is "not null". A struct answers through its truth-test operator,
`!!(): bool`, like C++'s `operator bool`:

```pepper
{{#include ../../examples/structs-truth-test.pep}}
```

These are the boolean contexts. In each, a struct value `x` becomes `x.!!()`:

- the condition of `if`, `else if` and `while`;
- the condition of `condition ? a : b`;
- each operand of `&&`, `||`, `and` and `or` (unless the struct declares `&&`
  or `||` itself, which then takes the whole operation);
- the operand of `!`: without its own `!` method, `!x` is `!(x.!!())`.

`!!x` is the truth test itself: on a struct it calls `x.!!()`; on a `bool` or
a number it is still two negations. [`Optional`](optionals.md) declares `!!`,
so `if (found)` asks whether an optional holds a value.

A struct that does not declare `!!` cannot be used as a condition at all:

```text
main.pep:6:9: error: 'Node' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'
    6 |     if (node) {
      |         ^~~~
```

A struct value is a reference, but a condition never tests it for null. To ask
whether a reference is set, compare it with `__null` (`node !== __null`), or
better, use an [`Optional`](optionals.md) for a value that may be missing. A trait value is
treated the same way: it is a condition only when its trait declares `!!`.

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
