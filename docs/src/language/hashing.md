# Hashing and equality

`HashMap<K, V>` and `HashSet<K>` find a key by hashing it with `hash<K>`
and comparing it with `==`. What those two mean for a type decides which keys
count as the same.

| Key type | `==` | `hash<K>` |
| --- | --- | --- |
| Numbers, `bool`, `char`, pointers | the value | the value's bits |
| `String` | the content | the content |
| A tuple | element by element | the elements' hashes, combined |
| A [value struct](value-structs.md) | field by field | the fields' hashes, combined |
| Any other struct | identity (`===`) | the object's address |

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

## Keying a struct by its content

Give the struct both halves of the pair:

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

With `==` declared, `!=` is its negation, as for any struct.

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
  note: declare 'hash<Point>(value: Point): u64' hashing the fields '==' compares
  ```

  The runtime's own structs are not checked. An `Array` key's `==` compares
  elements but its hash is its address, so find it with the same `Array`
  object, not an equal one.
- **Don't change a key's fields while it is in a map or set.** The entry
  stays where its old hash put it, so lookups by its new or its old fields
  both miss it. Remove it, change it, then insert it again.
- **One override per program.** `hash<Point>` replaces `hash<T>` for
  `Point` everywhere, including inside `HashMap`, so it may be declared in
  only one file. Declare it next to the struct.
- The hash is not keyed, so it does not resist keys chosen by an attacker to
  collide.

## Value structs compare and hash by their fields

A [value struct](value-structs.md) has no identity, so `==` and `hash`
already compare and hash it field by field. Declare your own pair only to
change what counts as equal, here to ignore case:

```pepper
{{#include ../../examples/hashing-values.pep}}
```
