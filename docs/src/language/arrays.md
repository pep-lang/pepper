# Arrays and slices

[`Array<T>`](../reference/array.md) is Pepper's growable list. Beyond
`append`, indexing and `sort`, it has the everyday algorithms, and
`slice` gives a function "some of the elements" without copying them:

```pepper
{{#include ../../examples/arrays-algorithms.pep}}
```

## Searching a sorted array

- `binary_search(item)` returns the index of the first element equal to
  `item` as a `ulong?`, in O(log count). The element type must be
  [`Comparable`](ordering.md) (every number, `char` and `String` is), and
  the array sorted in its `compare` order.
- `binary_search_by(order)` searches with a function that says whether an
  element sorts before (negative), at (0) or after (positive) the target.
- `lower_bound(item)` and `upper_bound(item)` are the first and last places
  `item` could be inserted to keep the array sorted; the elements between
  them equal `item`.
- `is_sorted()` reports whether the array is in that order.

## Changing elements in place

- `fill(value)` sets every element to `value`.
- `retain(keep)` removes each element `keep` returns false for, keeping the
  order of the rest. `keep` must not change the array; if it does, `retain`
  panics with `Array modified during retain`.
- `dedup()` removes each element equal (`==`) to the one before it; on a
  sorted array that removes every duplicate.
- `resize(count, value)` shortens the array, or appends copies of `value`.
- `split_off(index)` moves the elements from `index` on into a new array.

Each counts as modifying the array, so a `for` loop over it panics on its
next step.

## Slices

`a.slice(start, end)` is an `ArraySlice<T>`: a read-only view of the
elements from `start` up to but not including `end`. It has `count`,
`is_empty`, indexing, `for` loops, `slice`, `to_array`, `find`, `contains`
and the searches above.

A slice is safe by construction:

- It holds a reference to its array, so the array lives as long as the
  slice does.
- It is fail-fast, like an iterator. Once the array changes (any store,
  `append`, `remove_at`, `sort`, ...), every later use of the slice panics
  with `Array modified while a slice of it is in use`, so it can never read
  an element that moved or a buffer that was freed. Make a new slice after
  changing the array.

## Not yet

- Slices are read-only; there is no slice that writes through to its
  array, and no `a[1..4]` syntax: write `a.slice(1, 4)`.
- `sort_unstable`, `rotate`, `drain`, `chunks` and `windows` are not
  there yet.
- `String` has no slice type; `substr` copies.
