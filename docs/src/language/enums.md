# Enums and `match`

An **enum** is a type with a fixed set of named **cases**. A value of the
enum holds exactly one of them. Use an enum where you would otherwise pass an
integer code or a string, so the compiler checks that only the listed cases
flow through, and that a `match` handles each one.

```pepper
{{#include ../../examples/enums-basics.pep}}
```

## Declaring an enum

`enum Name { ... }` lists the cases, separated by commas; a comma after the
last case is optional. Case names are `PascalCase`, like types (see
[naming conventions](naming.md)).

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

`Name.Case` is a value of the enum type. An enum is a value type, like `int`:
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

## Methods

An enum can declare methods after its cases. Inside a method, `this` is the
value the method was called on, and a bare call of another method of the
enum (`next()`) calls it on `this`. A `static` method is called on the enum
itself (`Light.first()`).

```pepper
{{#include ../../examples/enums-methods.pep}}
```

`this` is passed by value, like an `int`: a method cannot change the value it
was called on. Return a new case instead, as `next()` does.

### Built-in methods

Every enum has two methods without declaring them, and cannot declare
methods of the same names:

| Method | What it does |
|---|---|
| `value.name()` | Returns the case's name as written (`"Red"`), a `String`. |
| `Name.from_value(n)` | Returns a `Result<Name>`: Ok with the case whose value is `n`, or an Err when no case has it. `n` has the enum's representation type. |

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
- An `else => { ... }` arm, last, handles every case the other arms do not.
- The arms must handle **every case**. A missing case is an error that names
  it, located at `match`; the language server offers a quick fix that adds an
  empty arm for each missing case. An `else` that can never run, because the
  other arms handle every case, is a warning.
- Handling a case twice is an error.
- `match` is a statement. `break`, `continue` and `return` inside an arm act
  on the enclosing loop or function, as they would inside an `if`.

The value is evaluated once, before any arm runs.

## Current limits

- Cases cannot carry values yet (`Circle(radius: float)`); that is the next
  step, and it is what lets [`Optional`](optionals.md) and
  [`Result`](results.md) become enums.
- Enums cannot be generic yet, and neither can their methods. An enum
  cannot declare operators or indexers yet; `==` and `!=` are built in.
- `match` works only on enums, and only as a statement: it does not produce
  a value, and cannot match integers, characters or strings yet.
- An enum cannot be extended (`extend Color { ... }`); declare its methods
  inside it. So it cannot conform to a trait either, and a trait value is a
  reference to an object, which an enum value is not.
