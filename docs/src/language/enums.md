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
  name the case instead.
- A slot of an enum type that is not given a value (a field, or a local
  declared without one) holds the case whose value is 0, or the first case
  when no case is 0.
- `sizeof<Name>()` is the size of the representation.

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
- Enums cannot have methods, and cannot be generic, yet.
- `match` works only on enums, and only as a statement: it does not produce
  a value, and cannot match integers, characters or strings yet.
- There is no way to get a case's name as a string, or to turn an integer
  back into a case, yet.
