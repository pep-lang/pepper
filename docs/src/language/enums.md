# Enums and `match`

An **enum** is a type with a fixed set of named **cases**. A value of the
enum holds exactly one of them. Use an enum where you would otherwise pass an
integer code or a string, so the compiler checks that only the listed cases
flow through, and that a `match` handles each one.

There are two kinds:

- In an enum whose cases carry nothing (`Red`, `Green`), each case is an
  integer. Such an enum is a value type, like `int`.
- When a case carries values (`Circle(radius: int)`), the enum is a
  reference type, like a struct. See
  [Cases that carry values](#cases-that-carry-values).

```pepper
{{#include ../../examples/enums-basics.pep}}
```

## Declaring an enum

`enum Name { ... }` lists the cases, separated by commas; a comma after the
last case is optional. Case names are `PascalCase`, like types (see
[naming conventions](naming.md)). A case may share a type's name
(`String(value: String)`); a string literal in the enum's methods is still
a `String`, and `String(...)` there calls the case.

Each case is an integer. The first case is 0 and each case after it is one
more than the one before. A case can give its own value with `= value`, and
numbering continues from there:

```pepper
enum Status: u8 {
    Ok,             # 0
    NotFound = 44,  # 44
    Failed,         # 45
}
```

A value must be an integer constant: a literal such as `-1` or `0x20`, or a
character such as `'y'`. Two cases cannot have the same value.

The type after the colon is the **representation**, the integer type the
enum is stored as. It can be any integer type (`u8`, `short`, `int`, `long`,
and so on). Without one, the enum is stored as an `int`. Every case value
must fit in the representation.

A case can carry a [`[Target]`](platform-selection.md) attribute, so a
platform can have cases that others lack. A dropped case does not renumber
the others.

## Using enum values

This section is about enums whose cases carry nothing.

`Name.Case` is a value of the enum type. Such an enum is a value type, like `int`:
it is copied, not reference counted, and it can be stored in locals, fields,
arrays and module-scope constants, and passed to and returned from functions.

- `==` and `!=` compare two values of the same enum. No other operator
  applies to an enum.
- An enum does not mix with integers or with other enums: `int x = Color.Red`
  and `Color c = 0` are errors, and so is comparing a `Color` with a `Size`.
- `value as int` (or any integer type) gives a case's integer value. The
  reverse, `1 as Color`, is an error, since the integer may not name a case;
  name the case, or use [`from_value`](#built-in-methods).
- A slot of an enum type that is not given a value (a field, or a local
  declared without one) holds the case whose value is 0, or the first case
  when no case is 0.
- `sizeof<Name>()` is the size of the representation.
- An enum works wherever an integer does: as a `HashMap` key or `HashSet`
  element, in an `Atomic<Name>`, and in an `extern` function's signature,
  where C sees the representation (an `int` unless the enum names another).

## Cases that carry values

A case can carry values, declared like parameters: `Circle(radius: int)`.
An enum with such a case is a **reference type**: each value is an object,
reference counted like a [struct](structs.md).

```pepper
{{#include ../../examples/enums-values.pep}}
```

- `Name.Case(values...)` makes a new value, like a constructor call, and
  `Name.Case` alone is a case that carries nothing. An enum's values are
  made only by its cases: `Shape(...)` is an error.
- A case that carries values must be given them: `Shape.Circle` without
  `(radius)` is an error.
- The values are fixed once made. There is no way to change them, so a value
  can be shared freely. To change one, make a new value.
- Each case that carries nothing is a single object that every use shares.
  It is never freed and costs no allocation, however often it is used.
- A slot of the enum type that is not given a value holds null, as a struct
  slot does. `===` and `!==` compare identity.
- An enum can have type parameters (`enum List<T>`), and its cases can hold
  the enum itself, directly or through other types, so lists and trees are
  enums.
- The enum can be `[Shared]` when every value its cases carry is
  thread-safe (see [What threads can share](threads.md#what-threads-can-share)).
  An enum whose cases carry nothing is stored as an integer and is always
  thread-safe. It can conform to a trait with
  `extend Name with Trait`, like a struct, and its methods can come from an
  `extend` block too.
- Cases cannot have explicit values (`= 3`), and the enum has no
  representation type (`: u8`), since its values are not integers.

### Value enums

An enum whose cases carry values can be marked `[Value]`, like a
[value struct](value-structs.md). Each value is then stored inline in
whatever holds it, and copied when assigned, passed or returned, instead of
being an object. Making one allocates nothing, which suits small enums that
are made often, such as [`Optional`](optionals.md) and
[`Result`](results.md), which are both value enums.

```pepper
[Value]
enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Point,
}
```

- A value enum is never null. A slot that is not given a value holds the
  first case, with every value it carries zero, `false`, or null: an unset
  `Shape` is `Circle(0)`.
- `==` compares the cases and their values; `===`, `!==` and `__null` are
  errors.
- Its cases cannot hold the enum itself, since the value would be infinitely
  large. Use a reference enum for lists and trees.
- Everything else a [value struct cannot do](value-structs.md#what-a-value-struct-cannot-do)
  applies too, and so does [boxing](value-structs.md#value-structs-as-trait-values)
  when it flows into a trait value.

## Methods

An enum can declare methods after its cases. Inside a method, `this` is the
value the method was called on, and a bare call of another method of the
enum (`next()`) calls it on `this`. A `static` method is called on the enum
itself (`Light.first()`).

```pepper
{{#include ../../examples/enums-methods.pep}}
```

For an enum whose cases carry nothing, `this` is passed by value, like an
`int`: a method cannot change the value it was called on. Return a new case
instead, as `next()` does. Such an enum can also declare a trait with
`extend Light with Describe { ... }`, which makes it meet the constraint
`T: Describe` (see
[numbers, `bool` and enums](traits-and-extensions.md#numbers-bool-and-enums));
it is still never a trait value. For an enum whose cases carry values, `this` is
the object, as in a struct's method; its values still cannot change.

### Built-in methods

Every enum has these methods without declaring them, and cannot declare
methods of the same names:

| Method | What it does |
|---|---|
| `value.name()` | Returns the case's name as written (`"Red"`), a `String`. Every enum has it. |
| `Name.from_value(n)` | Returns a `Result<Name>`: Ok with the case whose value is `n`, or an Err when no case has it. `n` has the enum's representation type. Only enums whose cases carry nothing have it. |

`from_value` is the checked way back from an integer (from a file, a C
library or the network) to a case, since `as` only goes the other way.

## `match`

`match (value) { ... }` runs the arm for the case that `value` holds:

```pepper
{{#include ../../examples/enums-match.pep}}
```

- Each arm is one or more patterns, separated by commas, then `=>` and a
  block. A pattern is a case name (`Red`) or the case qualified by its enum
  (`Light.Red`).
- A pattern for a case that carries values can **bind** them:
  `Rect(w, h)` declares `w` and `h` in its arm, holding the case's values in
  order. The bindings are `const`. `_` skips a value. A pattern binds all of
  its case's values or, written without parentheses (`Rect`), none.
- Patterns that share an arm must bind the same names, with the same types
  (`Rect(w, _), Square(w)`).
- An `else => { ... }` arm, last, handles every case the other arms do not.
- The arms must handle **every case**. A missing case is an error that names
  it, located at `match`; the language server offers a quick fix that adds an
  empty arm for each missing case. An `else` that can never run, because the
  other arms handle every case, is a warning.
- Handling a case twice is an error.
- In a `match` statement, `break`, `continue` and `return` inside an arm act
  on the enclosing loop or function, as they would inside an `if`.

The value is evaluated once, before any arm runs. A `match` on a null value
of an enum whose cases carry values panics with `match on a null 'Name'`; a
[value enum](#value-enums) is never null.

## `match` expressions, `is`, and literal patterns

```pepper
{{#include ../../examples/enums-match-values.pep}}
```

- **A `match` that produces a value** can go wherever a value can: after
  `var x =`, `return`, in an argument. Each arm is `patterns => value`, and
  arms are separated by commas (one after the last is allowed). It follows
  the rules above: a pattern binds names for its arm's value, and the arms
  must handle every case unless there is an `else`. The value has the first
  arm's type, and every other arm's value must convert to it. When the arms
  are numbers of different types, the value has their common type, as C's
  `? :` does (`int` and `long` give `long`), and converts from it wherever
  it goes (`0` or a `long` `length`, returned as an `int`). A closure in
  an arm's value cannot use a name the arm binds; use a `match` statement
  there.
- **`value is Pattern`** is a `bool`: whether `value` holds that case
  (`d is Line`, `!(d is Text)`). It takes any one pattern. When it is the
  whole condition of an `if` or `while`, its bindings are declared in that
  block only: `if (d is Text(t)) { ... }` reads `t` inside the braces, and
  `while (list is Cons(head, tail)) { ... }` examines `list` again on every
  iteration. Anywhere else, `is` cannot bind names. `is` is a keyword only
  between a value and a pattern, so it stays usable as a name
  (`token.is(text)`).
- **Literal patterns**: a `match` on an integer, a character, a `bool` or a
  `String` compares with literals (`1`, `-1`, `'a'`, `true`, `"import"`),
  using `==`. Literals cannot list every value, so such a `match` needs an
  `else` arm, except on a `bool` that handles both `true` and `false`.
  Matching the same literal twice is an error. A match on an enum takes its
  case names, not literals, and a match on `int` takes literals, not names.

## Current limits

- An enum whose cases carry nothing cannot be generic. The methods of any
  enum cannot be generic yet. An enum cannot declare operators or indexers
  yet; `==` and `!=` are built in for enums whose cases carry nothing.
- A case's values bind names only: a pattern cannot nest inside a case
  (`Some(Text(t))`) or compare its values (`Text("")`) yet. Patterns nest
  inside [tuple patterns](tuples.md#matching-tuples) (`(Text(t), 0)`).
  Patterns cannot match ranges (`1..9`) or have guards yet. A literal
  pattern is a literal, not a named constant.
- A `match` cannot examine floating-point values.
- An enum whose cases carry nothing cannot be extended
  (`extend Color { ... }`); declare its methods inside it. So it cannot
  conform to a trait either, and a trait value is a reference to an object,
  which such an enum's value is not.
