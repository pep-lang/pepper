# Equality, hashing and ordering

`HashMap<K, V>` and `HashSet<K>` find a key by hashing it with `hash<K>`
and comparing it with `==`. What those two mean for a type decides which keys
count as the same.
`OrderedMap<K, V>` finds keys the same way. For maps that keep their keys
in order, see [Maps and sets](maps.md); what `<` and sorting mean for a
type is [Ordering with Comparable](#ordering-with-comparable), below.

| Key type | `==` | `hash<K>` |
| --- | --- | --- |
| Numbers, `bool`, `char`, pointers | the value | the value's bits |
| `String` | the content | the content |
| An `Array` | element by element | the elements' hashes, combined |
| A tuple | element by element | the elements' hashes, combined |
| A [value struct](value-structs.md) | field by field | the fields' hashes, combined |
| An [`[Equatable]`](#deriving-both-with-equatable) struct or enum | field by field | the fields' hashes, combined |
| Any other struct | identity (`===`) | the object's address |

The standard library's structs that compare by value also hash by it:
`BitSet` by its members, `io.Path` by its text, and `io.IpAddress` and
`io.SocketAddress` by their address and port.

## Struct keys use identity by default

A struct is a [reference](memory.md#values-and-references). Unless it says
otherwise, two references are the same key only when they refer to the same
object. Another object with equal fields is a different key:

```pepper
{{#include ../../examples/hashing-identity.pep}}
```

Identity is right for objects that stand for one thing: a connection, a
node in a graph, a task. It is wrong for a struct that describes a value,
such as a point or a record looked up by its fields.

## Deriving both with `[Equatable]`

Mark the struct `[Equatable]`, and the compiler writes both halves from its
fields, so they cannot drift apart. It compares and hashes like a tuple of
its fields: a field of a struct type uses that struct's `==` and `hash`, a
`String` its content, and a null field equals only null. Mark a field
`[Equatable(exclude = true)]`, or `[Equatable(include = false)]`, to leave it
out of both; a field with neither takes part:

```pepper
{{#include ../../examples/hashing-equatable.pep}}
```

- An [enum whose cases carry values](enums.md#cases-that-carry-values) can
  be `[Equatable]` too: two values are equal when they hold the same case
  and its values are equal.
- A generic struct derives both for each specialization, from the fields
  its type arguments give it.
- `include` and `exclude` are `bool`s, and saying both in a way that
  contradicts (`include = true, exclude = true`) is an error. On the struct
  itself, `[Equatable]` takes no arguments.
- An `[Equatable]` struct cannot also declare `==` or override `hash<T>`;
  either is an error. To compare some other way, drop the attribute and
  declare both by hand (below).
- An `Array` field compares and hashes by its elements, as an `Array` key
  does, and so does an `Array` in a tuple. Its hash takes O(count).
- `[Equatable]` does not apply to a [value struct](value-structs.md) or an
  enum whose cases carry nothing: they already compare and hash by content.

## Keying a struct by its content

To decide yourself what counts as equal, give the struct both halves of the
pair:

- an `==` [operator](structs.md#operators) that says when two keys are the
  same, and
- an override of `hash<T>` for the struct (see
  [Overriding a generic function for one type](generics.md#overriding-a-generic-function-for-one-type)),
  `hash<Point>(value: Point): u64`.

```pepper
{{#include ../../examples/hashing-custom.pep}}
```

The two must agree: **keys that are `==` must have the same hash.** The
simplest way to keep that promise is to hash exactly the fields that `==`
compares, by hashing a tuple of them: `hash<(int, int)>((value.x,
value.y))`. A tuple's hash combines its elements' hashes, and each element
uses its own type's `hash`, so a `String` field contributes its content.
Unequal keys may share a hash. That costs speed, not correctness.

With `==` declared, `!=` is its negation, as for any struct. The struct may
also [overload](overloading.md) `==` for other types (`==(rhs: int)`); the map
and set compare keys with the `==` that takes the struct itself.

Keep these rules in mind:

- **Declare both or neither.** With `==` but no `hash<T>`, two equal keys
  usually hash differently, so a lookup would miss an entry that is there.
  With `hash<T>` but no `==`, keys would still compare by identity, so an
  equal object would never find another's entry. Either is a compile error
  when the struct is used as a `HashMap` or `HashSet` key:

  ```text
  main.pep:5:5: error: 'Point' declares '==' but no 'hash<Point>', so as a HashMap or HashSet key, equal values will not find each other
      5 |     ==(other: Point): bool {
        |     ^~
  note: declare 'hash<Point>(value: Point): u64' hashing the fields '==' compares, or remove '==' and mark 'Point' '[Equatable]' to derive both
  ```

  The runtime's own structs are not checked. An `Array` key matches an
  equal `Array`: both its `==` and its hash go by its elements.
- **Don't change a key's fields while it is in a map or set.** The entry
  stays where its old hash put it, so lookups by its new or its old fields
  both miss it. Remove it, change it, then insert it again. The same goes
  for an `Array` key's elements.
- **One override per program.** `hash<Point>` replaces `hash<T>` for
  `Point` everywhere, including inside `HashMap`, so it may be declared in
  only one file, and that file must declare `Point` or be in its module
  (see [overriding a generic function](generics.md#overriding-a-generic-function-for-one-type)).
- The hash is not keyed, so it does not resist keys chosen by an attacker to
  collide.

## Value structs compare and hash by their fields

A [value struct](value-structs.md) has no identity, so `==` and `hash`
already compare and hash it field by field. Declare your own pair only to
change what counts as equal, here to ignore case:

```pepper
{{#include ../../examples/hashing-values.pep}}
```

## Ordering with Comparable

A type whose values sort in one order declares the `Comparable` trait. It
asks for one method, `compare(other)`, which returns a negative number, zero
or a positive number as the value sorts before, with or after `other`, and
gives the type the rest:

- the operators `<`, `<=`, `>` and `>=`;
- `min(other)`, `max(other)` and `clamp(low, high)` (which panics when `low`
  sorts after `high`);
- a place as a [`Map` key or `Set` element](maps.md#how-keys-are-ordered),
  in that order;
- the constraint `T: Comparable` in a [generic](generics.md#constraints)
  function, whose body can then use all of the above on a `T`.

```pepper
{{#include ../../examples/ordering-comparable.pep}}
```

A type that declares its own `<` (or `min`, or any of the others) keeps it;
the trait's version fills in only what the type leaves out.

`compare` must give a total, consistent order: the same two values always
compare the same way, `a.compare(b)` has the opposite sign of
`b.compare(a)`, and if `a` sorts before `b` and `b` before `c`, `a` sorts
before `c`. `Map`, `Set` and sorting depend on it.

### Sorting

An array of `Comparable` elements sorts in their own order with `sort()`,
stably, as `sort((a, b) => a.compare(b))` would. Floats sort in the total
order, NaN last. Any other order still takes a comparer:
`items.sort((a, b) => b.compare(a))` sorts in reverse.

### Numbers, `char` and `String`

Every number type and `char` is `Comparable` by value, and `String` by
content, the order of `String.compare`. Their `compare` returns -1, 0 or 1
(`String.compare` any negative or positive number).

`float` and `double` compare in a total order: NaN sorts after every number
and with every other NaN, and `-0.0` sorts with `0.0`. Their `<`, `<=`, `>`
and `>=` keep IEEE behavior, false whenever a NaN takes part, while
`compare`, `clamp` and `Map` keys follow the total order, so a NaN key
cannot break a map.

### Not yet

- Tuples and `Optional` are not `Comparable`, and `Comparable` is not
  derived from a struct's fields: a struct writes its `compare`, as
  `Version` does above.
