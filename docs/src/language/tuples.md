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

## Current limitations

These come in later phases:

- Tuples cannot be generic type arguments yet (`Array<(int, String)>`,
  `HashMap<String, (int, int)>`), and there is no `Tuple<A, B>` spelling.
- Tuples cannot be compared with `==`, hashed, or passed to `print`.
- Elements cannot be named (`(line: int, column: int)`).
- Destructuring does not nest (`var (a, (b, c)) = …`) and does not work in a
  `for` loop (`for (var (k, v) in map)`).
- `match` cannot match tuple patterns.
