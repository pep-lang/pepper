# Collection literals

A collection literal writes an array, a map or a set in one expression:

```pepper
{{#include ../../examples/collection-literals.pep}}
```

## Arrays

- `[a, b, c]` is a new [`Array<T>`](../reference/array.md) holding the
  elements in order. A trailing comma is allowed: `[a, b, c,]`.
- With no other type to go by, `T` is the first element's type, and every
  later element converts to it the way an argument converts to a parameter:
  `[1, 2]` is an `Array<int>`, and `[1, "a"]` is an error.
- Where an array type is expected (a declared variable, a parameter, a
  return value, an assignment), `T` is that type's element type instead, and
  every element converts to it: `long[] a = [1, 2];`,
  `Shape[] s = [square, circle];`.
- Nested literals are typed the same way: `long[][] grid = [[1], [2, 3]];`.
- `[]` is an empty array. It needs a declared type (`long[] none = [];`),
  since it has no element to take a type from:

```text
main.pep:2:13: error: empty array literal has no element type; declare the variable's type or write 'Array<T>()'
    2 |     var a = [];
      |             ^~
```

## Maps

- `[k1: v1, k2: v2]` is a new [`HashMap<K, V>`](../reference/hash.md) holding
  the entries. `K` and `V` come from the first entry, or from the
  `HashMap<K, V>` a declared variable, parameter or return type expects.
- A key written twice keeps its last value, as two `insert` calls would.
- `[:]` is an empty map, and needs a declared type:
  `HashMap<String, int> none = [:];`.

## Sets

There is no separate set literal. An array literal where a
[`HashSet<K>`](../reference/hash.md#hashset) or a
[`Set<K>`](maps.md#sorted-map-and-set) is expected converts to one through
the set's [implicit constructor](structs.md#implicit-conversions),
which keeps each element once: `HashSet<String> keywords = ["if", "else"];`.

## Types of specializations

A literal never changes a collection's type after it is built:
`Array<int>` and `Array<long>` are different types, and neither converts to
the other.

```text
main.pep:2:21: error: cannot initialize variable 'a' of type 'Array<long>' with a value of type 'Array<int>'
    2 |     Array<long> a = Array<int>();
      |                     ^~~~~~~~~~
```
