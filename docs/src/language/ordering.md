# Ordering with Comparable

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

## Sorting

An array of `Comparable` elements sorts in their own order with `sort()`,
stably, as `sort((a, b) => a.compare(b))` would. Floats sort in the total
order, NaN last. Any other order still takes a comparer:
`items.sort((a, b) => b.compare(a))` sorts in reverse.

## Numbers, `char` and `String`

Every number type and `char` is `Comparable` by value, and `String` by
content, the order of `String.compare`. Their `compare` returns -1, 0 or 1
(`String.compare` any negative or positive number).

`float` and `double` compare in a total order: NaN sorts after every number
and with every other NaN, and `-0.0` sorts with `0.0`. Their `<`, `<=`, `>`
and `>=` keep IEEE behavior, false whenever a NaN takes part, while
`compare`, `clamp` and `Map` keys follow the total order, so a NaN key
cannot break a map.

## Not yet

- Tuples and `Optional` are not `Comparable`, and `Comparable` is not
  derived from a struct's fields: a struct writes its `compare`, as
  `Version` does above.
