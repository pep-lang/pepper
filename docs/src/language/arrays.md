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
- `split_off(index)` moves the elements from `index` on into a new array,
  and `drain(start, end)` moves out the elements in between.
- `remove_if(remove)` is the opposite of `retain`.
- `rotate(count)` moves the first `count` elements to the end.
- `extend_from(slice)` appends the elements of a slice, which may be a
  slice of the same array.

Each counts as modifying the array, so a `for` loop over it panics on its
next step.

## Ordering

- `sort_unstable()` sorts with pattern-defeating quicksort: no scratch
  buffer, and O(count) on input that is already sorted or all equal, but
  equal elements may change places. `sort()` is the stable sort.
- `select_nth(nth)` puts the element a sort would put at `nth` there, with
  smaller elements before it and larger ones after (C++'s `nth_element`),
  in O(count) on average: the median without a full sort.
- `partial_sort(count)` sorts only the `count` smallest elements into the
  front.
- `a.compare(b)` orders two arrays lexicographically: by the first
  elements that differ, else the shorter first. `==` compares element by
  element.

Each takes a comparer too (`sort_unstable((a, b) => b - a)`) for an order
other than the elements' own, or for elements that are not `Comparable`.

## Slices

`a.slice(start, end)` is an `ArrayView<T>` (formerly `ArraySlice<T>`, a
name that still works, with a deprecation warning): a read-only view of the
elements from `start` up to but not including `end`. It has `count`,
`is_empty`, indexing, `for` loops, `slice`, `to_array`, `find`, `contains`
and the searches above, plus:

- `split_at(index)`, which returns two slices: the elements before
  `index`, and those from it on.
- `chunks(size)`, which visits runs of `size` elements side by side, as
  slices; the last run is shorter when `size` does not divide the count.
- `windows(size)`, which visits every run of `size` neighbors, each
  starting one element after the one before.
- `==` and, for `Comparable` elements, the lexicographic `compare`, which
  compare the elements, not where they are.

`Array` has `chunks` and `windows` too, over all its elements. Neither
copies an element: each run is a slice of the same array.

```pepper
var rises = 0;
for (var pair in [1, 3, 2, 5].windows(2)) {
    if (pair[1] > pair[0]) {
        rises = rises + 1;   # 2 in all
    }
}
```

A slice is safe by construction:

- It holds a reference to its array, so the array lives as long as the
  slice does.
- It is fail-fast, like an iterator. Once the array changes (any store,
  `append`, `remove_at`, `sort`, ...), every later use of the slice panics
  with `Array modified while a slice of it is in use`, so it can never read
  an element that moved or a buffer that was freed. Make a new slice after
  changing the array.
- It never holds a pointer into the array's buffer, only the array and a
  range, so even growing the array (which moves the buffer) cannot leave
  it pointing at freed memory. The runs `chunks` and `windows` give are
  slices too, and follow the same rules.

## Not yet

- Slices are read-only; there is no slice that writes through to its
  array, and no `a[1..4]` syntax: write `a.slice(1, 4)`.
- An `Array` is not itself `Comparable` (there are no conditional trait
  implementations yet), so `<` between arrays and `sort()` on an array of
  arrays need `compare`: `rows.sort((a, b) => a.compare(b))`.
- `String` has no slice type; `substr` copies.
