# Maps and sets

The standard library has three kinds of map, which differ in the order they
keep their keys in:

| Type | Order | Lookup, insert, remove | Keys need |
| --- | --- | --- | --- |
| `HashMap<K, V>`, `HashSet<K>` | none | expected O(1) | `hash<K>` and `==` ([Hashing and equality](hashing.md)) |
| `Map<K, V>`, `Set<K>` | sorted by key | O(log n) | `compare<K>` (below) |
| `OrderedMap<K, V>` | the order keys were first inserted | expected O(1) | `hash<K>` and `==` |

All of them share one API: `m[key]` reads (a missing key reads as the
default of `V`, and is not inserted) and `m[key] = value` writes; `insert`,
`get`, `try_get` (an [optional](optionals.md), none when the key is absent),
`contains`, `remove`, `count`, `is_empty` and `clear`. A `for` loop visits a
map's entries as `(key, value)` [tuples](tuples.md) and a set's members one
by one. Adding or removing an entry while a loop iterates the map panics
("Map modified during iteration"), as it does for `Array` and `HashMap`;
changing the value of a key that is present is allowed.

## Sorted: `Map` and `Set`

`Map<K, V>` keeps its entries sorted by key, on a red-black tree. Besides
iterating in order, it answers questions about the order:

- `first()` and `last()`: the entries with the smallest and largest key.
- `lower_bound(key)`: the first entry whose key is at least `key`;
  `upper_bound(key)`: the first whose key is greater.
- `reversed()`: iterates from the largest key down.
- `range(from, to)`: iterates the keys from `from` up to, not including,
  `to`.

Each of the four queries returns an optional `(key, value)` tuple, none when
there is no such entry. `Set<K>` is the same tree without values, and its
queries return an optional member. An array converts to a `Set`, so an array
literal can initialize one.

```pepper
{{#include ../../examples/maps-sorted.pep}}
```

### How keys are ordered

`Map` and `Set` order keys with the generic function `compare<K>(a, b)`,
which returns a negative number, zero or a positive number as `a` sorts
before, equal to or after `b`. Two keys that compare equal are the same key.

- Numbers and `char` compare by value, and `String` by content (the same
  order as `String.compare`).
- A struct that declares a `<` [operator](structs.md#operators) sorts by it:
  the generic `compare` asks `a < b` and `b < a`.
- Any other struct overrides `compare<T>` for itself, as a hashed key
  overrides `hash<T>` (see
  [Overriding a generic function for one type](generics.md#overriding-a-generic-function-for-one-type)).

```pepper
{{#include ../../examples/maps-custom-order.pep}}
```

The order must be consistent: the same two keys must always compare the
same way, and if `a` sorts before `b` and `b` before `c`, `a` sorts before
`c`. A struct key whose fields change while it is in a map breaks that
promise.

## Insertion order: `OrderedMap`

`OrderedMap<K, V>` hashes its keys like `HashMap`, and iterates its entries
in the order their keys were first inserted, like a Python `dict`. Setting
the value of a key that is present keeps its place; removing a key and
inserting it again moves it to the end. The other entries keep their order
when one is removed.

```pepper
{{#include ../../examples/maps-ordered.pep}}
```

Use it where the order of the input matters, such as the keys of a
configuration file that should be written back as they were read.
