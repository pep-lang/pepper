# Tuples and multiple return values

A *tuple* groups a fixed number of values, each of its own type, into one
value. Its main use is returning several values from a function:

```pepper
{{#include ../../examples/tuples-basics.pep}}
```

## Tuple types and values

- A tuple type lists its element types in parentheses: `(int, String)`,
  `(bool, (int, int))`. A tuple has at least two elements.
- A tuple value lists its elements the same way: `(a / b, a % b)`. The
  compiler infers its type from the elements, so `(1, "x")` is an
  `(int, String)`.
- Where a tuple type is expected (a declared variable, a parameter, a return
  value), each element converts to its element type, as it would on its own:
  `var wide: (long, double) = (1, 2);`.
- `t.0`, `t.1`, … read an element by position, counting from 0. `t.1.0` is
  element 0 of element 1. An element that does not exist is a compile error.
- Elements are read-only. `t.0 = 3` is a compile error; build a new tuple
  instead: `t = (3, t.1);`.
- `Tuple<A, B>` is another spelling of `(A, B)`, for places where a type in
  angle brackets reads better.
- `(int, String)?` is an optional tuple, `Optional<(int, String)>` (see
  [Optional values](optionals.md)), and `(int, String)[]` is an array of
  tuples, `Array<(int, String)>`.

## Labels

A tuple type can name its elements: `(line: int, column: int)`, and so can a
tuple value: `(line: 3, column: 7)`. A label is another name for a position,
so `p.line` and `p.0` read the same element:

```pepper
{{#include ../../examples/tuples-labels.pep}}
```

- Labels belong to the type you write, not to the value. A labeled tuple and
  an unlabeled one with the same element types are the same type, so each
  converts to the other freely.
- Either every element has a label or none does, and labels in one tuple must
  differ.
- Labels pass through a type argument: an element of an
  `Array<(word: String, count: int)>`, a `HashMap` value or the `value()` of a
  `(line: int, column: int)?` answers to its labels, and so does what a static
  method or an enum case called on the labeled type gives
  (`var p = Optional<(line: int, column: int)>.Value(at);`), though
  `Optional<(line: int, column: int)>` is the same type as
  `Optional<(int, int)>`. A member takes back only the labels its declaration
  writes as a type parameter: a method of `Box<(a: int, b: int)>` declared to
  return `(int, int)` returns an unlabeled tuple. A generic function's result
  takes none: `identity<(a: int, b: int)>(p)` is unlabeled, so declare the
  variable's type to name its elements.
- `var p = (line: 3, column: 7);` gives `p` the labeled type
  `(line: int, column: int)`. A labeled value takes at least two elements.
- A labeled value initializing or returned as a labeled type must use its
  labels in order: `(column: 7, line: 3)` where a `(line: int, column: int)`
  is expected is an error, not a swap. An unlabeled value, or a labeled one
  going to an unlabeled type, converts by position.
- A destructuring assignment lists places alone: `(a, b) = (b, a);`, never
  `(x: a, y: b) = ...`.

## Destructuring

`var (a, b) = value;` declares one variable for each element of a tuple:

```pepper
{{#include ../../examples/tuples-destructuring.pep}}
```

- The number of names must match the number of elements.
- `_` skips an element.
- A name may state its type, `var (_, top: long) = …`; the element converts
  to it. Without one, the variable takes the element's type.
- `const (a, b) = …` declares constants.
- Patterns nest: `var (id, (name, age)) = …` takes an element that is itself
  a tuple apart.
- A `for` loop destructures each element: `for (var (name, count) in pairs)`.
- `(a, b) = value;` assigns to places that already exist: variables, fields
  (`p.x`) and array elements. The whole right side is evaluated before any
  assignment, so `(a, b) = (b, a)` swaps.

## Tuples and references

A tuple is a value, like a number. It is not an object on the heap, and
copying it copies its elements. An element that is a
[reference](memory.md#values-and-references) is shared, not copied, exactly as
if you had assigned it to a variable:

- Building a tuple from a variable adds a reference to the object; building
  it from a function result takes over that result's reference.
- A tuple holds its references until it goes out of scope or is replaced,
  then releases them.
- Destructuring moves each element into its variable. After
  `var (a, b) = pair();`, `a` holds the only reference to its object, just as
  it would after `var a = make();`.

A tuple is thread-safe when all its elements are, so a module-scope
`const origin: (int, long) = (0, 0);` is allowed.

## Collections, comparing and printing

A tuple works anywhere a type does, including as a type argument:
`Array<(int, String)>`, `HashMap<(int, int), String>`. Iterating a `HashMap`
yields `(key, value)` tuples:

```pepper
{{#include ../../examples/tuples-collections.pep}}
```

- `==` and `!=` compare element by element. Each element compares the way it
  would on its own: a type with an `==` operator (such as `String`) uses it,
  and any other struct compares by identity (the same object).
- A tuple can be a `HashMap` key or a `HashSet` member. Its hash combines the
  hashes of its elements, so equal tuples hash equally.
- `to_string((1, "two"))` is `(1, two)`, so a tuple of up to eight
  values that each have a `to_string` can be
  [interpolated](interpolation.md) and printed: `print($"{t}")`.
- `copy(t)` (see [Copying a value](memory.md#copying-a-value-with-copy)) copies each element: a struct
  element as `copy` would copy it on its own, anything thread-safe as is.

## Matching tuples

A [`match`](enums.md#match) over a tuple tests all of its elements at once.
A tuple pattern lists a pattern for each element: `(Rock, Scissors)`,
`(Number(v), 1)`, `(4, column)`. Write the tuple in the `match` itself with
double parentheses, `match ((a, b))`, or match a tuple value, `match (at)`.

```pepper
{{#include ../../examples/tuples-match.pep}}
```

- Each element takes a case of its enum (`Rock`, `Word(text)`), a literal
  (`1`, `"x"`, `true`), a [range or a constant](enums.md#ranges-and-constants)
  (`0..9`, `LIMIT`), another tuple pattern, `_` for any value, or a name.
- A name binds its element, unless it names a module-scope constant, which
  the element is compared with, or the element is an enum with a case of
  that name, which it then matches. So in `(Circle, other)` over two shapes,
  `Circle` is a case and `other` holds the second shape.
- An arm's patterns bind the same names, each at the same element: `(x, 0),
  (0, x)` is an error, since `x` would mean a different element depending
  on which pattern matched.
- The arms must handle every value unless there is an `else`. A missing
  value is named with an example: ``match on '(Shape, int)' does not handle
  '(Line, _)'``. Only enum cases and `true`/`false` can be listed in full;
  other literals and ranges need a pattern with `_` or a name at that
  element.
- A pattern that the arms before it already cover is an error, and an
  `else` after arms that cover everything is a warning.
- `value is (4, column)` tests one tuple pattern, and binds its names as
  the whole condition of an `if` or `while`, as for enums.
