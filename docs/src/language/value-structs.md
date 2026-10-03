# Value structs

A struct is normally a [reference](memory.md#values-and-references) to an
object on the heap. A struct marked `[Value]` is a *value* instead, like a
number or a [tuple](tuples.md): it is stored inline in whatever holds it (a
local, a field, an array element), and assigning it, passing it, or
returning it copies it. Creating one allocates nothing.

```pepper
{{#include ../../examples/value-structs-basics.pep}}
```

Use a value struct for small types that describe a value rather than an
identity: a span, a point, a color. An enum can be a value too (see
[Value enums](enums.md#value-enums)); `Optional` and `Result` are. Keep a
reference struct for anything that is shared and changed through several
names, or that is large.

## Declaring one

Put `[Value]` on its own line above the struct. Everything else is written
as for any struct: fields, constructors, methods, operators, generic
parameters, and [extensions](traits-and-extensions.md).

```pepper
[Value]
struct Point {
    var x: int;
    var y: int;

    construct(this.x = 0, this.y = 0) {}
}
```

A variable or field of a value struct type that is not given a value holds
the zero value: every field zero, `false`, or null.

## Copies

- `var b = a;` makes `b` an independent copy. Changing `b` leaves `a` as it
  was.
- A parameter is a copy of the argument. A function can change its
  parameter without the caller seeing it; return the changed value instead.
- A field of a value struct is part of whatever holds it. In a reference
  struct, `line.span.grow(5)` changes the span inside `line`'s object, and
  every reference to that object sees it.
- Reading an element of an array, or the result of any call, gives a copy.
  To change an element, read it into a variable, change it, and store it
  back (`spans[0] = first;`).

A field that is itself a reference (a `String`, an `Array`) is copied as a
reference, so both copies share that object, as two variables holding the
same `String` do. Its count is kept like any other reference's: copying the
value acquires it, and the copy going out of scope releases it. Use
[`copy`](memory.md#copying-a-value-with-copy) for a deep copy.

## Methods that change `this`

In a method, `this` is the value the method was called on, not a copy, so
a method that assigns a field (`end = end + by;`), or calls another method
that does, changes that value. The compiler works out which methods change
`this` from their bodies. Calling one on something that would only change a
copy is an error, because the change would be lost:

```text
main.pep:9:12: error: cannot call mutating method 'grow' on a temporary 'Span'
    9 |     make().grow(1);
      |            ^~~~
main.pep:9:5: note: 'make' returns a copy; store it in a variable, change it, and assign it back
    9 |     make().grow(1);
      |     ^~~~
```

The same holds for assigning a field of a call's result (`spans[0].end = 3;`)
and for changing a `const` variable's value. A [closure](function-types.md)
made in a method holds a copy of `this`, so it cannot change `this` either.

## Comparing and hashing

`==` and `!=` compare two values field by field, and `hash` combines the
fields' hashes, unless the struct declares its own `==` or `hash` (declare
both together; see [Hashing and equality](hashing.md)). A value
has no identity, so `===` and `!==` are errors on it, and it is never null:
comparing one with `__null` is an error too.

## What a value struct cannot do

Each of these is an error at the code to change:

- `===`, `!==`, or `__null` on a value.
- `__weak<T>` or `__refcount` of a value: there is no object to count.
- A `destruct` block: nothing destroys a value. Its reference fields are
  still released.
- `[Shared]`: a value struct is thread-safe when its fields are, and needs
  no atomic counts.
- A field whose type is the struct itself, directly or through other value
  structs: the value would be infinitely large. Hold it through a reference
  struct or an `Array` instead.
- A parameter or result of an [`extern`](c-interop.md) function: pass a
  pointer to C instead.

## Value structs as trait values

A value struct can declare [traits](traits-and-extensions.md) like any
struct. Where it flows into a slot of a trait type, such as an argument of
type `Iterator<int>`, it is *boxed*: copied into a new object that the trait
value refers to. The box is a copy, so a mutating method called through the
trait value changes the box and not the original, and two conversions of
one value make two boxes. Copying the trait value shares the box, as for
any trait value.

The runtime's iterators (`ArrayIterator`, `StringIterator`, the map and
set iterators, `ChannelIterator`, and the `map`, `filter`, `enumerate` and
`zip` adapters) are value structs, so a `for` loop over an `Array`, a
`String` or any map or set allocates no iterator.

## Current limitations

- A [value enum](enums.md#value-enums) stores the values of all its cases
  side by side, so it is as large as all of them together; the cases do not
  share storage yet.
