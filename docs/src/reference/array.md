<!-- Generated from runtime/array.pep by `pep-doc reference`. Do not edit. -->

# Array

Source: `runtime/array.pep`

## Array

```pepper
[__Lazy] struct Array<T>
```

A growable, contiguous, zero-indexed sequence of `T` values.

Elements live in one heap buffer that doubles when full (starting at 4
slots), so `append` is amortized O(1) and indexing is O(1). When `T` is a
struct type, each slot holds a counted reference, exactly like a
`std::vector<std::shared_ptr<T>>`: storing an element acquires it,
overwriting or removing one releases the old occupant, and destroying the
Array releases every element it still holds. Moving elements within the
Array (`insert`, `remove_at`, `swap`, `reverse`) does not change their
reference counts.

`Array` is itself a struct, so assigning it or passing it to a function
shares the same Array rather than copying its elements; use `clone()` for
an independent copy.

An empty Array allocates nothing: `Array<T>()` makes no object until the
Array is first written (`append`, `insert`, `reserve`, ...) or shared
(assigned, stored, passed or returned), and reading it (`count`,
`is_empty`, `capacity`, `find`, `contains`, iterating) allocates nothing.
Sharing allocates first, so every name for an Array sees the same
elements.

An Array is `Iterable<T>`: `for (var x in a)` visits each element in index
order. Every mutating operation (an element store through `[]`, `append`,
`insert`, `remove_at`, `pop`, `clear`, a shrinking `truncate`, `swap`,
`fill`, `retain`, `remove_if`, `resize`, `split_off`, `drain`,
`extend_from`, `rotate`, `select_nth`, `partial_sort`, and `reverse`,
`sort`, `sort_unstable` or `dedup` of two or more elements) invalidates
running iterators and slices
(`slice`), and the next step of such a loop panics with "Array modified
during iteration".

**Type parameters**
- `T` — the element type

**See also**
- `ArrayIterator`

**Example**
```pepper
main(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a[0] = 5;
    var total = 0;
    for (var x in a) {
        total = total + x;
    }
    return total;   # 7
}
```

### Properties

#### count

```pepper
var count: ulong { get; }
```

The number of elements in the Array.

#### capacity

```pepper
var capacity: ulong { get; }
```

The number of elements the Array can hold before its buffer
must be reallocated.

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the Array has no elements.

### Constructor

#### Array()

```pepper
construct(capacity: ulong = 0)
```

Creates an empty Array, optionally preallocating room for `capacity`
elements.

With the default `capacity` of 0, nothing is allocated, not even the
Array itself, until the Array is first written or shared (see `Array`).
Preallocating avoids the reallocations `append`
would otherwise perform while the Array grows to a known size.

**Parameters**
- `capacity` — the number of element slots to allocate up front; `count` is still 0

**Example**
```pepper
var a = Array<int>(16);   # a.count == 0, a.capacity == 16
```

### Methods

#### iterate

```pepper
[__Reads] iterate(): ArrayIterator<T>
```

Returns an iterator over the elements in index order; this is what
`for (var x in array)` calls (the `Iterable<T>` protocol).

The iterator holds a reference to the Array, so iterating a temporary
keeps it alive for the whole loop. Modifying the Array while the
iterator is in use makes the iterator's next `next()` or `current()`
panic, except when the Array was empty when the iterator was made:
the iterator then sees no elements and ends.

**Returns**
- a new iterator positioned before the first element

**Example**
```pepper
for (var x in a) {
    total = total + x;
}
```

#### reserve

```pepper
reserve(capacity: ulong)
```

Ensures the buffer has room for at least `capacity` elements,
reallocating it when it is smaller.

Never shrinks the buffer: a `capacity` at or below the current one does
nothing. Elements, their order, and their reference counts are
unchanged, and running iterators stay valid. Growing copies the
existing elements, which costs O(count).

**Parameters**
- `capacity` — the minimum number of element slots required

**Panics**
- if the buffer must grow while an I/O operation in a task is using it

**Example**
```pepper
var a = Array<int>();
a.reserve(8);   # a.capacity >= 8
a.reserve(2);   # no effect: capacity never shrinks
```

#### grow

```pepper
grow()
```

Makes room for one more element: when the buffer is full, doubles its
capacity (to at least 4); otherwise does nothing.

`append` and `insert` call this themselves; callers rarely need it.
Does not change the elements or invalidate iterators.

**Panics**
- if the buffer must grow while an I/O operation in a task is using it

#### operator []

```pepper
[__Reads] [](idx: ulong): T
```

Returns the element at `idx`; this is the indexer read `a[idx]`.

Runs in O(1). For a struct `T` the result is the stored reference
itself; binding it to a variable acquires it like any shared copy.

**Parameters**
- `idx` — the zero-based position to read

**Returns**
- the element at `idx`

**Panics**
- if `idx < count` does not hold ("Array index read out of bounds")

**Example**
```pepper
var first = a[0];
```

#### operator []

```pepper
[](idx: ulong, value: T): T
```

Replaces the element at `idx` with `value`; this is the indexer write
`a[idx] = value`.

For a struct `T` the slot acquires `value` and releases its previous
occupant; assigning an element to its own slot (`a[i] = a[i]`) leaves
counts unchanged. Only replaces an existing element: use `append` to
add one. Invalidates running iterators, even when the value is
unchanged.

**Parameters**
- `idx` — the zero-based position to overwrite
- `value` — the new element

**Returns**
- the element now stored at `idx` (that is, `value`)

**Panics**
- if `idx < count` does not hold ("Array index write out of bounds")

**Example**
```pepper
a[0] = 42;
```

#### append

```pepper
append(item: T)
```

Adds `item` to the end of the Array.

Amortized O(1): when the buffer is full it doubles (O(count) for that
call). For a struct `T` the Array acquires a reference to `item`.
Invalidates running iterators.

**Parameters**
- `item` — the element to add

**Panics**
- if the buffer must grow while an I/O operation in a task is using it

**Example**
```pepper
var a = Array<int>();
a.append(1);
a.append(2);   # a holds [1, 2]
```

#### insert

```pepper
insert(idx: ulong, item: T)
```

Inserts `item` at position `idx`, shifting the element there and every
later element up by one.

Runs in O(count - idx), plus a reallocation when the buffer is full.
`idx == count` appends. For a struct `T` the Array acquires a
reference to `item`; shifted elements keep their reference counts.
Invalidates running iterators.

**Parameters**
- `idx` — the position `item` will occupy; from 0 through `count`
- `item` — the element to insert

**Panics**
- if `idx <= count` does not hold ("Array insert index out of bounds")
- if the buffer must grow while an I/O operation in a task is using it

**Example**
```pepper
var a = Array<int>();
a.append(1);
a.append(3);
a.insert(1, 2);   # a holds [1, 2, 3]
```

#### remove_at

```pepper
remove_at(idx: ulong): T
```

Removes and returns the element at `idx`, shifting every later element
down by one.

Runs in O(count - idx). For a struct `T` the Array's reference is
transferred to the caller, so the element stays alive as long as the
result is held; shifted elements keep their reference counts. The
capacity is unchanged. Invalidates running iterators.

**Parameters**
- `idx` — the position of the element to remove

**Returns**
- the removed element

**Panics**
- if `idx < count` does not hold ("Array remove index out of bounds")

**Example**
```pepper
var a = Array<int>();
a.append(1);
a.append(2);
var x = a.remove_at(0);   # x == 1; a holds [2]
```

#### pop

```pepper
pop(): T
```

Removes and returns the last element.

Runs in O(1). For a struct `T` the Array's reference is transferred to
the caller. The capacity is unchanged. Invalidates running iterators.

**Returns**
- the element that was last

**Panics**
- if the Array is empty ("Array pop on empty Array")

**Example**
```pepper
var top = a.pop();
```

#### first

```pepper
[__Reads] first(): T
```

Returns the first element without removing it; the same as `a[0]`.

**Returns**
- the element at index 0

**Panics**
- if the Array is empty ("Array first on empty Array")

#### last

```pepper
[__Reads] last(): T
```

Returns the last element without removing it; the same as
`a[a.count - 1]`.

**Returns**
- the element at index `count - 1`

**Panics**
- if the Array is empty ("Array last on empty Array")

#### clear

```pepper
clear()
```

Removes every element, leaving the Array empty.

Runs in O(count) for a `T` holding references, each of which is
released, and in O(1) for a plain value `T` (`int`, `u8`, a tuple of
numbers). The capacity is kept, so refilling the Array does not
reallocate. Always invalidates running iterators, even on an empty
Array.

#### truncate

```pepper
truncate(count: ulong)
```

Shortens the Array to its first `count` elements, removing the rest.

Runs in O(removed elements). For a struct `T` each removed element's
reference is released. A `count` at or above the current `count`
does nothing (the Array never grows) and leaves iterators valid; an
actual shrink invalidates them. The capacity is kept.

**Parameters**
- `count` — the number of leading elements to keep

**Example**
```pepper
a.truncate(1);   # keeps only a[0]
a.truncate(5);   # no effect when a has fewer than 5 elements
```

#### swap

```pepper
swap(a: ulong, b: ulong)
```

Exchanges the elements at positions `a` and `b`.

Runs in O(1). Reference counts are unchanged: the two references just
trade slots. Swapping a position with itself is allowed and changes no
element, but still invalidates running iterators like every swap.

**Parameters**
- `a` — the position of the first element
- `b` — the position of the second element

**Panics**
- if `a < count` does not hold ("Array swap index out of bounds")
- if `b < count` does not hold ("Array swap index out of bounds")

#### reverse

```pepper
reverse()
```

Reverses the order of the elements in place.

Runs in O(count), exchanging elements pairwise, so reference counts
are unchanged. An Array of fewer than two elements is left untouched
and its iterators stay valid; otherwise running iterators are
invalidated.

**Example**
```pepper
a.reverse();   # [1, 2, 3] becomes [3, 2, 1]
```

#### rotate

```pepper
rotate(count: ulong)
```

Moves the first `count` elements to the end, keeping the order within
each part: the element at `count` becomes the first.

Runs in O(count of the Array), exchanging elements, so reference
counts are unchanged. Rotating by 0 or by the Array's `count` changes
nothing and leaves iterators valid; any other rotation invalidates
them.

**Parameters**
- `count` — the number of leading elements to move; from 0 through the Array's `count`

**Panics**
- if `count` is more than the Array's `count` ("Array rotate count out of bounds")

**Example**
```pepper
var a = [1, 2, 3, 4, 5];
a.rotate(2);   # [3, 4, 5, 1, 2]
```

#### sort

```pepper
sort(compare: (T, T) => int)
```

Sorts the elements in place into the order `compare` defines. The
sort is stable: elements that compare equal keep their relative
order.

`compare(a, b)` returns a negative number when `a` belongs before
`b`, 0 when their order does not matter, and a positive number when
`a` belongs after `b`, the convention `String.compare` follows. It is
a merge sort: O(count log count) calls to `compare`, plus a scratch
buffer of `count` slots. Elements move between the two buffers
without changing any reference count. Invalidates running iterators
when there are two or more elements.

`compare` must not modify the Array: its elements are spread over
the two buffers while the sort runs.

**Parameters**
- `compare` — returns the order of its two arguments, as above

**Panics**
- if `compare` modifies the Array ("Array modified during sort")

**Example**
```pepper
var names = Array<String>();
names.append("pear");
names.append("apple");
names.sort((a, b) => a.compare(b));   # ["apple", "pear"]
var numbers = Array<int>();
numbers.append(3);
numbers.append(1);
numbers.sort((a, b) => b - a);        # descending: [3, 1]
```

#### sort_unstable

```pepper
sort_unstable(compare: (T, T) => int)
```

Sorts the elements in place into the order `compare` defines, without
keeping equal elements in their original order.

`compare` follows the convention of `sort(compare)`. It is
pattern-defeating quicksort (pdqsort): O(count log count) calls to
`compare` in the worst case, O(count) on an Array that is already
sorted or all equal, and no scratch buffer, so it is the faster sort
when stability does not matter. Elements only trade slots, so no
reference count changes. Invalidates running iterators when there
are two or more elements.

**Parameters**
- `compare` — returns the order of its two arguments, as for `sort`

**Panics**
- if `compare` modifies the Array ("Array modified during sort")

**Example**
```pepper
var a = [5, 1, 4, 2, 3];
a.sort_unstable((x, y) => x - y);   # [1, 2, 3, 4, 5]
```

#### select_nth

```pepper
select_nth(nth: ulong, compare: (T, T) => int)
```

Reorders the elements so that the one at `nth` is the element a full
sort would put there, every element before it sorts before or with
it, and every element after it sorts after or with it (C++'s
`nth_element`). Each side is otherwise in no particular order.

`compare` follows the convention of `sort(compare)`. Runs in O(count)
calls to `compare` on average and O(count log count) in the worst
case, with no scratch buffer. Elements only trade slots, so no
reference count changes. Invalidates running iterators.

**Parameters**
- `nth` — the position to settle; less than `count`
- `compare` — returns the order of its two arguments, as for `sort`

**Panics**
- if `nth < count` does not hold ("Array select_nth index out of bounds")
- if `compare` modifies the Array ("Array modified during sort")

**Example**
```pepper
var a = [9, 1, 8, 2, 7, 3];
a.select_nth(2, (x, y) => x - y);   # a[2] == 3, the third smallest
```

#### partial_sort

```pepper
partial_sort(count: ulong, compare: (T, T) => int)
```

Puts the `count` elements that sort first into the first `count`
positions, in order, and leaves the rest after them in no particular
order: the start of a full sort, found faster.

`compare` follows the convention of `sort(compare)`. Runs in
O(count of the Array + `count` log `count`) calls to `compare` on
average, with no scratch buffer; it is not stable. Elements only
trade slots, so no reference count changes. Invalidates running
iterators.

**Parameters**
- `count` — the number of leading elements to sort; from 0 through the Array's `count`
- `compare` — returns the order of its two arguments, as for `sort`

**Panics**
- if `count` is more than the Array's `count` ("Array partial_sort count out of bounds")
- if `compare` modifies the Array ("Array modified during sort")

**Example**
```pepper
var scores = [40, 95, 12, 77, 63];
scores.partial_sort(3, (x, y) => y - x);   # starts [95, 77, 63]
```

#### find

```pepper
[__Reads] find(item: T): ulong?
```

Returns the position of the first element equal to `item`, or none
when no element matches.

Runs in O(count), scanning from the front. Elements are compared with
`==`: when `T` declares an `==` operator (as `String` does) that
operator decides; for any other struct `T` it compares references, so
only the very same object matches.

Breaking change: `find` used to return a `long` that was `-1` when
nothing matched. It now returns `ulong?`: test it with `is_some()` (or
as a condition) and read the index with `value()`.

**Parameters**
- `item` — the value to look for

**Returns**
- the index of the first match, or none when no element matches (always none for an empty Array)

**Example**
```pepper
var a = [3, 9, 4];
var i = a.find(9);         # i.value() == 1
var missing = a.find(7);   # missing.is_empty() == true
```

#### contains

```pepper
[__Reads] contains(item: T): bool
```

Reports whether any element equals `item`, compared as `find` does.

Runs in O(count).

**Parameters**
- `item` — the value to look for

**Returns**
- true when `find(item)` finds a match

#### slice

```pepper
[__Reads] slice(start: ulong, end: ulong): ArraySlice<T>
```

Returns a read-only view of the elements from `start` up to but not
including `end`, without copying them.

The slice holds a reference to this Array, so it cannot outlive it,
and it is fail-fast like an iterator: once the Array is modified (see
`Array` for which operations count), every later use of the slice
panics, so it never reads elements that moved or were freed.

**Parameters**
- `start` — the position of the first element in the slice
- `end` — the position one past the last element; from `start` through `count`

**Returns**
- a view of `end - start` elements

**Panics**
- if `start <= end` and `end <= count` do not both hold ("Array slice out of bounds")

**Example**
```pepper
var a = [1, 2, 3, 4, 5];
var middle = a.slice(1, 4);   # views [2, 3, 4]
var second = middle[1];       # 3
```

#### binary_search_by

```pepper
[__Reads] binary_search_by(order: (T) => int): ulong?
```

Returns the position of the element that `order` reports equal to the
target, searching an Array sorted in the order `order` follows, or
none when there is none.

Runs in O(log count) calls to `order`, which must not modify the
Array. When several elements match, the first of them is found.

**Parameters**
- `order` — returns a negative number when its argument sorts before the target, 0 when it matches, and a positive number when it sorts after

**Returns**
- the index of the first matching element, or none

**Panics**
- if `order` modifies the Array ("Array modified while a slice of it is in use")

**Example**
```pepper
var a = [10, 20, 30];
var i = a.binary_search_by((x) => x.compare(20));   # i.value() == 1
```

#### fill

```pepper
fill(value: T)
```

Replaces every element with `value`.

Runs in O(count). For a struct `T` every slot acquires `value` and
releases its previous occupant. Invalidates running iterators.

**Parameters**
- `value` — the value each element becomes

**Example**
```pepper
var a = [1, 2, 3];
a.fill(0);   # [0, 0, 0]
```

#### retain

```pepper
retain(keep: (T) => bool)
```

Removes every element for which `keep` returns false, keeping the
order of the rest.

Runs in O(count) calls to `keep`, which sees each element once, in
index order, and must not modify the Array. For a struct `T` each
removed element is released and kept elements keep their counts. The
capacity is unchanged. Invalidates running iterators.

**Parameters**
- `keep` — returns true for an element to keep

**Panics**
- if `keep` modifies the Array ("Array modified during retain")

**Example**
```pepper
var a = [1, 2, 3, 4];
a.retain((x) => x % 2 == 0);   # [2, 4]
```

#### remove_if

```pepper
remove_if(remove: (T) => bool)
```

Removes every element for which `remove` returns true, keeping the
order of the rest; the opposite of `retain`.

Runs in O(count) calls to `remove`, which sees each element once, in
index order, and must not modify the Array. For a struct `T` each
removed element is released. Invalidates running iterators.

**Parameters**
- `remove` — returns true for an element to remove

**Panics**
- if `remove` modifies the Array ("Array modified during retain")

**Example**
```pepper
var a = [1, 2, 3, 4];
a.remove_if((x) => x > 2);   # [1, 2]
```

#### dedup

```pepper
dedup()
```

Removes each element equal (`==`) to the one before it, so a run of
equal elements keeps only its first. On a sorted Array this removes
every duplicate.

Runs in O(count). Elements are compared as `find` does. For a struct
`T` each removed element is released. Invalidates running iterators
when there are two or more elements.

**Example**
```pepper
var a = [1, 1, 2, 3, 3, 3, 1];
a.dedup();   # [1, 2, 3, 1]
```

#### resize

```pepper
resize(count: ulong, value: T)
```

Changes the count to `count`: removes elements past it, as
`truncate` does, or appends copies of `value` until there are
`count` elements.

Runs in O(difference in count), plus at most one reallocation.
Invalidates running iterators when the count changes.

**Parameters**
- `count` — the number of elements the Array will hold
- `value` — the element to append when the Array grows

**Panics**
- if the buffer must grow while an I/O operation in a task is using it

**Example**
```pepper
var a = [1, 2];
a.resize(4, 0);   # [1, 2, 0, 0]
a.resize(1, 0);   # [1]
```

#### split_off

```pepper
split_off(index: ulong): Array<T>
```

Removes the elements from `index` on and returns them as a new Array,
leaving this Array with its first `index` elements.

Runs in O(count - index). The elements move without changing their
reference counts. This Array's capacity is unchanged. Invalidates
running iterators when any element moves.

**Parameters**
- `index` — the position of the first element to move; from 0 through `count`

**Returns**
- a new Array holding the elements that were at `index` and after

**Panics**
- if `index <= count` does not hold ("Array split_off index out of bounds")

**Example**
```pepper
var a = [1, 2, 3, 4];
var tail = a.split_off(1);   # a holds [1]; tail holds [2, 3, 4]
```

#### drain

```pepper
drain(start: ulong, end: ulong): Array<T>
```

Removes the elements from `start` up to but not including `end` and
returns them as a new Array, shifting the later elements down.

Runs in O(count - start). The elements move without changing their
reference counts. This Array's capacity is unchanged. Invalidates
running iterators when any element is removed.

**Parameters**
- `start` — the position of the first element to remove
- `end` — the position one past the last element to remove; from `start` through `count`

**Returns**
- a new Array holding the removed elements, in order

**Panics**
- if `start <= end` and `end <= count` do not both hold ("Array drain range out of bounds")

**Example**
```pepper
var a = [1, 2, 3, 4, 5];
var middle = a.drain(1, 3);   # a holds [1, 4, 5]; middle holds [2, 3]
```

#### append_all

```pepper
append_all(rhs: Array<T>)
```

Appends every element of `rhs`, in order, to the end of this Array.

Runs in O(count of `rhs`), growing the buffer at most once and copying
the elements in one block. `rhs` is unchanged, and it may be this same Array
(`a.append_all(a)` doubles `a`). For a struct `T` each appended element
is acquired once more, since both Arrays now hold it. Invalidates this
Array's running iterators when `rhs` is not empty.

**Parameters**
- `rhs` — the Array whose elements are copied

**Panics**
- if the buffer must grow while an I/O operation in a task is using it

**See also**
- `+=`

#### extend_from

```pepper
extend_from(items: ArraySlice<T>)
```

Appends every element of `items`, in order, to the end of this Array.

Runs in O(count of `items`), growing the buffer at most once. `items`
may view this same Array. For a struct `T` each appended element is
acquired once more. Invalidates this Array's running iterators and
slices (`items` among them, when it views this Array) when `items`
is not empty.

**Parameters**
- `items` — the elements to copy

**Panics**
- if the Array `items` views was modified since `items` was made ("Array modified while a slice of it is in use")
- if the buffer must grow while an I/O operation in a task is using it

**Example**
```pepper
var a = [1, 2];
var b = [7, 8, 9];
a.extend_from(b.slice(1, 3));   # [1, 2, 8, 9]
```

#### clone

```pepper
[__Reads] clone(): Array<T>
```

Returns a new Array holding the same elements in the same order.

Runs in O(count). The copy is shallow: for a struct `T` both Arrays
refer to the same element objects (each acquired once more), but adding
or removing elements in one does not affect the other. The new Array's
capacity equals this Array's `count`.

**Returns**
- an independent Array with the same elements

**Example**
```pepper
var b = a.clone();
b.append(7);   # a is unchanged
```

#### copy

```pepper
copy(): Array<T>
```

Returns a deep copy: a new Array holding a copy of each element, made
with `copy`. This is how `copy(value)` copies an Array (the
`Copyable<Array<T>>` implementation); call `copy(array)` rather than
this method.

Unlike `clone()`, which shares struct elements, the result shares no
element that is not thread-safe with this Array. An element that
appears twice is copied once. Runs in O(count) plus the cost of
copying the elements.

**Returns**
- the copy

**Example**
```pepper
var names = Array<String>();
names.append("ada");
var copied = copy(names);   # calls this method
```

#### operator ==

```pepper
[__Reads] ==(rhs: Array<T>): bool
```

Reports whether both Arrays have the same count and pairwise equal
elements, compared with `==` as `find` does.

Runs in O(count); stops at the first difference. Two empty Arrays are
equal. `capacity` is not compared.

**Parameters**
- `rhs` — the Array to compare with

**Returns**
- true when the Arrays are element-wise equal

#### operator !=

```pepper
[__Reads] !=(rhs: Array<T>): bool
```

Reports whether the Arrays differ in count or in any element; the
negation of `==`.

**Parameters**
- `rhs` — the Array to compare with

**Returns**
- true when the Arrays are not element-wise equal

#### operator +=

```pepper
+=(rhs: Array<T>): Array<T>
```

Appends every element of `rhs` to this Array in place (`a += b`); the
same as `append_all`.

`a += a` is allowed and doubles `a`.

**Parameters**
- `rhs` — the Array whose elements are appended

**Returns**
- this Array, after the append

**See also**
- `append_all`

**Example**
```pepper
a += b;   # a now ends with b's elements
```

#### operator +

```pepper
[__Reads] +(rhs: Array<T>): Array<T>
```

Returns a new Array holding this Array's elements followed by those of
`rhs` (`a + b`).

Runs in O(count + count of `rhs`). Neither operand is modified; like
`clone`, the result shares struct elements with its operands.

**Parameters**
- `rhs` — the Array whose elements come second

**Returns**
- the concatenation of this Array and `rhs`

**Example**
```pepper
var c = a + b;
```

## extend Array<T>

```pepper
extend Array<T: Comparable>
```

The searches of a sorted Array, for an element type with an order
(see `Comparable`).

**Type parameters**
- `T` — the element type, `Comparable`

### Methods

#### binary_search

```pepper
[__Reads] binary_search(item: T): ulong?
```

Returns the position of an element equal to `item` in this Array,
which must be sorted in `compare` order, or none when there is
none.

Runs in O(log count). When several elements equal `item`, the first
of them is found. On an Array that is not sorted the result is
unspecified (but never out of bounds).

**Parameters**
- `item` — the value to look for

**Returns**
- the index of the first element equal to `item`, or none

**Example**
```pepper
var a = [1, 3, 5, 7];
var i = a.binary_search(5);   # i.value() == 2
```

#### lower_bound

```pepper
[__Reads] lower_bound(item: T): ulong
```

Returns the first position at which `item` could be inserted while
keeping this sorted Array sorted: the index of the first element that
does not sort before `item` (in `compare` order), or `count` when
every element does.

Runs in O(log count).

**Parameters**
- `item` — the value to place

**Returns**
- the index of the first element at or after `item`

**Example**
```pepper
var a = [1, 3, 3, 5];
var i = a.lower_bound(3);   # 1
```

#### upper_bound

```pepper
[__Reads] upper_bound(item: T): ulong
```

Returns the last position at which `item` could be inserted while
keeping this sorted Array sorted: the index of the first element that
sorts after `item` (in `compare` order), or `count` when none does.

Runs in O(log count). `upper_bound(x) - lower_bound(x)` is the number
of elements equal to `x`.

**Parameters**
- `item` — the value to place

**Returns**
- the index of the first element after `item`

**Example**
```pepper
var a = [1, 3, 3, 5];
var i = a.upper_bound(3);   # 3
```

#### is_sorted

```pepper
[__Reads] is_sorted(): bool
```

Reports whether the elements are in `compare` order: no element
sorts after the one that follows it.

Runs in O(count). An Array of fewer than two elements is sorted.

**Returns**
- true when the Array is sorted

#### sort_unstable

```pepper
sort_unstable()
```

Sorts the elements in place into their own order, `compare`, without
keeping equal elements in their original order; otherwise behaves
like `sort_unstable(compare)`.

**Panics**
- if comparing modifies the Array ("Array modified during sort")

**Example**
```pepper
var a = [3, 1, 2];
a.sort_unstable();   # [1, 2, 3]
```

#### select_nth

```pepper
select_nth(nth: ulong)
```

Reorders the elements so that the one at `nth` is the one sorting
would put there, with the elements before it sorting before or with
it and those after it after or with it; see
`select_nth(nth, compare)`.

**Parameters**
- `nth` — the position to settle; less than `count`

**Panics**
- if `nth < count` does not hold ("Array select_nth index out of bounds")
- if comparing modifies the Array ("Array modified during sort")

**Example**
```pepper
var a = [9, 1, 8, 2, 7];
a.select_nth(2);   # a[2] == 7, the median
```

#### partial_sort

```pepper
partial_sort(count: ulong)
```

Puts the `count` smallest elements into the first `count` positions,
in order; see `partial_sort(count, compare)`.

**Parameters**
- `count` — the number of leading elements to sort; from 0 through the Array's `count`

**Panics**
- if `count` is more than the Array's `count` ("Array partial_sort count out of bounds")
- if comparing modifies the Array ("Array modified during sort")

**Example**
```pepper
var a = [5, 3, 9, 1, 7];
a.partial_sort(2);   # starts [1, 3]
```

#### compare

```pepper
[__Reads] compare(other: Array<T>): int
```

Returns the lexicographic order of this Array and `other`: the order
of the first pair of elements that differ (by their `compare`), or,
when one Array is the start of the other, the shorter first.

Runs in O(count); stops at the first difference. Two empty Arrays
sort together. It follows `Comparable`'s convention, so an Array of
Arrays sorts with `sort((a, b) => a.compare(b))`.

**Parameters**
- `other` — the Array to compare with

**Returns**
- a negative number, zero or a positive number as this Array sorts before, with or after `other`

**Example**
```pepper
assert([1, 2, 3].compare([1, 3]) < 0, "2 sorts before 3");
assert([1, 2].compare([1, 2, 0]) < 0, "the shorter first");
```

## ArrayIterator

```pepper
[Value] struct ArrayIterator<T>
```

An `Iterator<T>` over the elements of an Array, in index order; returned by
`Array.iterate()` and driven by `for (var x in array)`.

Holds a reference to the Array, so iterating a temporary keeps it alive for
the whole loop. The iterator is fail-fast: if the Array is modified after
the iterator was created (see `Array` for which operations count), its next
`next()` or `current()` panics instead of skipping or repeating elements
(an iterator over an Array that was empty when it was made just ends).

**Type parameters**
- `T` — the element type of the source Array

**See also**
- `Array.iterate`

**Example**
```pepper
var it = a.iterate();
while (it.next()) {
    var x = it.current();
}
```

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element.

The first call moves to index 0. Once it returns false it keeps
returning false.

**Returns**
- true when there is a current element, false once past the end

**Panics**
- if the Array was modified since the iterator was created ("Array modified during iteration")

#### current

```pepper
current(): T
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current element

**Panics**
- if the Array was modified since the iterator was created ("Array modified during iteration")
- if `next()` was never called ("ArrayIterator.current() before next()")
- if `next()` already returned false ("ArrayIterator.current() past the end")

## ArraySlice

```pepper
[Value] struct ArraySlice<T>
```

A read-only view of a run of an Array's elements, made by `Array.slice`,
that lets a function take "some of the elements" without copying them.

A slice holds a reference to its Array, so the Array lives at least as
long as the slice. It is fail-fast like `ArrayIterator`: once the Array
is modified (see `Array` for which operations count), every later use of
the slice panics with "Array modified while a slice of it is in use"
instead of reading elements that moved or were freed. Make a new slice
after changing the Array.

A slice is `Iterable<T>`: `for (var x in slice)` visits its elements in
order.

**Type parameters**
- `T` — the element type of the Array

**See also**
- `Array.slice`

**Example**
```pepper
total(values: ArraySlice<int>): int {
    var sum = 0;
    for (var x in values) {
        sum = sum + x;
    }
    return sum;
}

var a = [1, 2, 3, 4];
var tail_sum = total(a.slice(2, 4));   # 7
```

### Properties

#### count

```pepper
var count: ulong { get; }
```

The number of elements in the slice.

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the slice has no elements.

### Methods

#### operator []

```pepper
[](index: ulong): T
```

Returns the element at `index` in the slice, `index` 0 being the
slice's first element; this is the indexer read `slice[index]`.

**Parameters**
- `index` — the zero-based position in the slice

**Returns**
- the element at `index`

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
- if `index < count` does not hold ("ArraySlice index out of bounds")

#### slice

```pepper
slice(start: ulong, end: ulong): ArraySlice<T>
```

Returns a view of this slice's elements from `start` up to but not
including `end`, positions counted within this slice.

**Parameters**
- `start` — the position of the first element
- `end` — the position one past the last element; from `start` through `count`

**Returns**
- a view of `end - start` elements of the same Array

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
- if `start <= end` and `end <= count` do not both hold ("ArraySlice slice out of bounds")

#### iterate

```pepper
iterate(): ArraySliceIterator<T>
```

Returns an iterator over the slice's elements in order; this is what
`for (var x in slice)` calls.

**Returns**
- a new iterator positioned before the first element

#### to_array

```pepper
to_array(): Array<T>
```

Returns a new Array holding a copy of the slice's elements, in order.

The copy is shallow, as `Array.clone` is: for a struct `T` the new
Array shares the element objects.

**Returns**
- an independent Array with the slice's elements

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")

#### find

```pepper
find(item: T): ulong?
```

Returns the position in the slice of the first element equal (`==`)
to `item`, or none, compared as `Array.find` does.

**Parameters**
- `item` — the value to look for

**Returns**
- the index of the first match, or none when no element matches

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")

#### contains

```pepper
contains(item: T): bool
```

Reports whether any element equals `item`, compared as `find` does.

**Parameters**
- `item` — the value to look for

**Returns**
- true when `find(item)` finds a match

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")

#### binary_search_by

```pepper
binary_search_by(order: (T) => int): ulong?
```

Returns the position of the first element that `order` reports equal
to the target, in a slice sorted in the order `order` follows, or
none; see `Array.binary_search_by`.

**Parameters**
- `order` — returns a negative number when its argument sorts before the target, 0 when it matches, and a positive number when it sorts after

**Returns**
- the index of the first matching element, or none

**Panics**
- if the Array was modified since the slice was made, `order` included ("Array modified while a slice of it is in use")

## extend ArraySlice<T>

```pepper
extend ArraySlice<T: Comparable>
```

The searches of a sorted ArraySlice, for an element type with an order
(see `Comparable`).

**Type parameters**
- `T` — the element type, `Comparable`

### Methods

#### binary_search

```pepper
binary_search(item: T): ulong?
```

Returns the position of the first element equal to `item` in this
slice, which must be sorted in `compare` order, or none; see
`Array.binary_search`.

**Parameters**
- `item` — the value to look for

**Returns**
- the index of the first element equal to `item`, or none

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")

#### lower_bound

```pepper
lower_bound(item: T): ulong
```

Returns the index of the first element of this sorted slice that
does not sort before `item`, or `count`; see `Array.lower_bound`.

**Parameters**
- `item` — the value to place

**Returns**
- the index of the first element at or after `item`

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")

#### upper_bound

```pepper
upper_bound(item: T): ulong
```

Returns the index of the first element of this sorted slice that
sorts after `item`, or `count`; see `Array.upper_bound`.

**Parameters**
- `item` — the value to place

**Returns**
- the index of the first element after `item`

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")

#### is_sorted

```pepper
is_sorted(): bool
```

Reports whether the elements are in `compare` order; see
`Array.is_sorted`.

**Returns**
- true when no element sorts after the one that follows it

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")

## ArraySliceIterator

```pepper
[Value] struct ArraySliceIterator<T>
```

An `Iterator<T>` over the elements of an `ArraySlice`, in order; returned
by `ArraySlice.iterate()` and driven by `for (var x in slice)`.

**Type parameters**
- `T` — the element type of the slice

**See also**
- `ArraySlice.iterate`

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element.

**Returns**
- true when there is a current element, false once past the end

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")

#### current

```pepper
current(): T
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current element

**Panics**
- if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
- if `next()` was never called ("ArraySliceIterator.current() before next()")
- if `next()` already returned false ("ArraySlice index out of bounds")
