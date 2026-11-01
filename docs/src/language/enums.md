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

- `==` and `!=` compare two values of the same enum. Other operators apply
  only when the enum declares them (see
  [Operators and indexers](#operators-and-indexers)).
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
  element, in an `Atomic<Name>`, and in the signature of an `extern` or
  [`[Export]`](c-interop.md#what-crosses-to-c) function, where C sees the
  representation (an `int` unless the enum names another).

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
  slot does. `===` and `!==` compare identity, and so does `==`, unless the
  enum is `[Equatable]`.
- Mark the enum [`[Equatable]`](hashing.md#deriving-both-with-equatable) to
  derive `==` and `hash` from its cases: two values are equal when they hold
  the same case with equal values, so they work as `HashMap` and `HashSet`
  keys.
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
{{#include ../../examples/enums-value.pep}}
```

- A value holds the tag that says which case it holds, then the values of
  every case, each in a field of its own: cases do not share storage. So
  `sizeof<Shape>()` is 16, the tag and `radius`, `width` and `height`.
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
itself (`Light.first()`). A method can be generic (`choose<T>`), with its
type arguments inferred or written out (`light.choose<String>(...)`).

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

### Operators and indexers

An enum can declare [operators](structs.md#operators) and an
[indexer](structs.md#indexers) the way a struct does: a method named after
the operator (`<(other: Level): bool`) or `[]`. For an enum whose cases
carry nothing, `a < b` calls `Level.<` with `a` as `this`.

```pepper
{{#include ../../examples/enums-operators.pep}}
```

Its values never change and it already compares with `==` and `!=`, so
such an enum cannot declare `==`, `!=`, a compound assignment (`+=`), an
indexer that assigns (`[](index, value)`) or the truth test `!!`, and its
operators are not `static`.

### Properties

An enum can also declare computed [properties](properties.md) after its
cases, `var name: T { get { ... } }`, which are read like fields
(`size.ounces`). Inside the enum, a bare property name reads it on `this`.

```pepper
{{#include ../../examples/enums-properties.pep}}
```

An enum value has nowhere to keep anything and never changes, so an enum's
property has a `get` with a body that does not use `field`, and no `set`:

```text
main.pep:6:9: error: property 'n' of enum 'E' must be computed: give 'get' a body that does not use 'field'
main.pep:6:38: error: property 'n' of enum 'E' cannot have a 'set' accessor: enum values are immutable
```

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
  order. The bindings are `const`. `_` skips a value. A pattern lists all of
  its case's values or, written without parentheses (`Rect`), none.
  Each value can also be a pattern of its own (see
  [Nested patterns](#nested-patterns)).
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
  it goes (`0` or a `ulong` `length`, returned as an `int`). A closure in
  an arm's value captures the names the arm binds, as it captures a
  `const` local, and keeps them after the `match`.
- **`value is Pattern`** is a `bool`: whether `value` holds that case
  (`d is Line`, `!(d is Text)`). It takes any one pattern. When it is the
  whole condition of an `if` or `while`, its bindings are declared in that
  block only: `if (d is Text(t)) { ... }` reads `t` inside the braces, and
  `while (list is Cons(head, tail)) { ... }` examines `list` again on every
  iteration. Anywhere else, `is` cannot bind names. `is` is a keyword only
  between a value and a pattern, so it stays usable as a name
  (`token.is(text)`).
- **A trait value** is matched by type rather than by case: `Circle(c)`
  tests for the struct `Circle` and binds the value as one. See
  [Converting a trait value back](traits-and-extensions.md#converting-a-trait-value-back).
- **Literal patterns**: a `match` on an integer, a character, a `bool` or a
  `String` compares with literals (`1`, `-1`, `'a'`, `true`, `"import"`),
  using `==`. Literals cannot list every value, so such a `match` needs an
  `else` arm, except on a `bool` that handles both `true` and `false`.
  Matching the same literal twice is an error. A match on an enum takes its
  case names, not literals, and a match on `int` takes literals, not names
  (except [constants](#ranges-and-constants)).

## Nested patterns

The values in a case's parentheses are patterns, as a tuple pattern's
elements are, so patterns nest to any depth:

```pepper
{{#include ../../examples/enums-nested.pep}}
```

- Each value takes `_`, a name, a case of its enum (with patterns of its
  own values: `Value(Pair(Line, _))`), a literal, a
  [range or constant](#ranges-and-constants), or a
  [tuple pattern](tuples.md#matching-tuples).
- A bare name binds the value, unless the value's enum has a case of that
  name, which it then matches (`Value(Empty)`), or it names a module-scope
  constant. A name repeated in one pattern (`Pair(x, x)`) must be a case.
- A nested pattern handles part of its case: the arms must still handle
  every value. A case that only nested patterns handle is reported with the
  value they miss (``match on 'Optional<Doc>' does not handle
  'Value(Line)'``), and a pattern whose values the earlier arms already
  match is an error.
- Patterns that share an arm bind the same names, each at the same place:
  `Pair(Text(t), Line), Pair(Text(t), Pair)` binds `t` from either, but
  `Pair(Text(t), _), Pair(_, Text(t))` is an error.
- A nested test reads a value only once the case around it matched, so the
  tests stop at the first part that does not match.

## Ranges and constants

A `match` on an integer or a character can compare with a **range** of
values, and a `match` on an integer, a character or a `bool` with a
module-scope **constant**:

```pepper
{{#include ../../examples/enums-ranges.pep}}
```

- `start..end` matches from `start` up to but not including `end`, and
  `start..>end` includes `end`, as [ranges](iteration.md) do elsewhere.
  Each bound is a literal (`-1`, `'z'`) or a constant (`MIN..MAX`).
  Ranges match integers and characters only, not `bool` or `String`.
- A name that is a module-scope constant (`const LIMIT = 100;`, declared in
  the file or imported, or `limits.MAX` through a module) compares the value
  with it, like a literal. A local variable is not a pattern; compare with
  it in a [guard](#guards) instead (`n if n == limit`).
- Inside a [tuple pattern](tuples.md#matching-tuples), a range or a
  constant compares its element (`(0..LIMIT, _)`), and any other bare name
  binds it, as before.
- When every bound is a literal, the compiler knows which values a pattern
  matches: a pattern whose values the earlier arms already match is an
  error (`2..>5` after `1..9`), and a `match` whose ranges and literals
  cover every value of its type (`0..128` and `128..>255` for a `u8`) needs
  no `else`. A pattern with a constant bound covers nothing for this check.
- A `match` on an enum takes its cases, not ranges or constants, even a
  constant holding one of its cases.

## Guards

An arm can add a **guard** after its patterns, `if condition`: the arm runs
only when one of its patterns matches and the condition holds. Otherwise
the next arm is tried, as if this one had not matched.

```pepper
{{#include ../../examples/enums-guards.pep}}
```

- The guard reads the names the arm's patterns bind (`Circle(r) if r > 10`).
  With several patterns (`Word(s), Quoted(s) if s.length == 0`), it applies
  to the arm, whichever pattern matched.
- Guards work in `match` statements and `match` expressions, over enums,
  literals and tuples. `is` takes no guard: write `x is P && condition`, or
  test the condition inside the `if`.
- A guarded arm handles nothing when the compiler checks that every case is
  handled, since its guard may fail: a `match` whose only arm for `Circle`
  has a guard does not handle `Circle`, and a later unguarded arm (or
  `else`) must. An `else` after guarded arms is not unreachable.
- A guarded arm for a case an earlier unguarded arm already handles is an
  error, like any case handled twice. Two guarded arms may name the same
  case.
- A closure in a guard captures the names the arm binds, as one in the
  arm's body does.

## Current limits

- An enum whose cases carry nothing cannot be generic, by design: its value
  is a plain integer, so a type parameter would have nothing to describe.
  An enum whose cases carry values can be (`enum List<T>`).
- An enum whose cases carry values compares by identity with `==`, as a
  struct does, unless it is a [`[Value]` enum](#value-enums), is
  [`[Equatable]`](hashing.md#deriving-both-with-equatable), or declares
  `==` (with a matching `hash<T>` to be a key).
- A constant is a pattern only when it is declared at module scope.
- A `match` cannot examine floating-point values.
- The methods of an enum whose cases carry nothing have no value form:
  `c.name` without the call is an error ("'name' is a method of 'Color':
  call it as 'name()'"), where a struct's `p.norm` is a
  [bound method](function-types.md). Wrap the call in a closure instead,
  `() => c.name()`.
- An enum whose cases carry nothing is extended only with a trait
  (`extend Color with Describe { ... }`); declare its other methods inside
  it. It is never a trait value, since a trait value is a reference to an
  object, which such an enum's value is not.
