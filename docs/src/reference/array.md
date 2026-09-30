<!-- Generated from runtime/array.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Array

Source: `runtime/array.pep`

## Array

```pepper
struct Array<T>
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

An Array is `Iterable<T>`: `for (var x in a)` visits each element in index
order. Every mutating operation (an element store through `[]`, `append`,
`insert`, `remove_at`, `pop`, `clear`, a shrinking `truncate`, `swap`, and
`reverse` of two or more elements) invalidates running iterators, and the
next step of such a loop panics with "Array modified during iteration".

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

### Constructor

#### Array()

```pepper
construct(ulong capacity = 0)
```

Creates an empty Array, optionally preallocating room for `capacity`
elements.

With the default `capacity` of 0, nothing is allocated until the first
element is added. Preallocating avoids the reallocations `append`
would otherwise perform while the Array grows to a known size.

**Parameters**
- `capacity` — the number of element slots to allocate up front; `count()` is still 0

**Example**
```pepper
    var a = Array<int>(16);   # a.count() == 0, a.capacity() == 16
```

### Methods

#### iterate

```pepper
ArrayIterator<T> iterate()
```

Returns an iterator over the elements in index order; this is what
`for (var x in array)` calls (the `Iterable<T>` protocol).

The iterator holds a reference to the Array, so iterating a temporary
keeps it alive for the whole loop. Modifying the Array while the
iterator is in use makes the iterator's next `next()` or `current()`
panic.

**Returns**
- a new iterator positioned before the first element

**Example**
```pepper
    for (var x in a) {
        total = total + x;
    }
```

#### count

```pepper
ulong count()
```

Returns the number of elements in the Array.

**Returns**
- the element count; 0 for an empty Array

#### capacity

```pepper
ulong capacity()
```

Returns the number of elements the Array can hold before its buffer
must be reallocated.

**Returns**
- the allocated slot count, which is at least `count()`

#### empty

```pepper
bool empty()
```

Reports whether the Array has no elements.

**Returns**
- true when `count()` is 0

#### reserve

```pepper
void reserve(ulong capacity)
```

Ensures the buffer has room for at least `capacity` elements,
reallocating it when it is smaller.

Never shrinks the buffer: a `capacity` at or below the current one does
nothing. Elements, their order, and their reference counts are
unchanged, and running iterators stay valid. Growing copies the
existing elements, which costs O(count).

**Parameters**
- `capacity` — the minimum number of element slots required

**Example**
```pepper
    var a = Array<int>();
    a.reserve(8);   # a.capacity() >= 8
    a.reserve(2);   # no effect: capacity never shrinks
```

#### grow

```pepper
void grow()
```

Makes room for one more element: when the buffer is full, doubles its
capacity (to at least 4); otherwise does nothing.

`append` and `insert` call this themselves; callers rarely need it.
Does not change the elements or invalidate iterators.

#### operator []

```pepper
T [](ulong idx)
```

Returns the element at `idx`; this is the indexer read `a[idx]`.

Runs in O(1). For a struct `T` the result is the stored reference
itself; binding it to a variable acquires it like any shared copy.

**Parameters**
- `idx` — the zero-based position to read

**Returns**
- the element at `idx`

**Panics**
- if `idx < count()` does not hold ("Array index read out of bounds")

**Example**
```pepper
    var first = a[0];
```

#### operator []

```pepper
T [](ulong idx, T value)
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
- if `idx < count()` does not hold ("Array index write out of bounds")

**Example**
```pepper
    a[0] = 42;
```

#### append

```pepper
void append(T item)
```

Adds `item` to the end of the Array.

Amortized O(1): when the buffer is full it doubles (O(count) for that
call). For a struct `T` the Array acquires a reference to `item`.
Invalidates running iterators.

**Parameters**
- `item` — the element to add

**Example**
```pepper
    var a = Array<int>();
    a.append(1);
    a.append(2);   # a holds [1, 2]
```

#### insert

```pepper
void insert(ulong idx, T item)
```

Inserts `item` at position `idx`, shifting the element there and every
later element up by one.

Runs in O(count - idx), plus a reallocation when the buffer is full.
`idx == count()` appends. For a struct `T` the Array acquires a
reference to `item`; shifted elements keep their reference counts.
Invalidates running iterators.

**Parameters**
- `idx` — the position `item` will occupy; from 0 through `count()`
- `item` — the element to insert

**Panics**
- if `idx <= count()` does not hold ("Array insert index out of bounds")

**Example**
```pepper
    var a = Array<int>();
    a.append(1);
    a.append(3);
    a.insert(1, 2);   # a holds [1, 2, 3]
```

#### remove_at

```pepper
T remove_at(ulong idx)
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
- if `idx < count()` does not hold ("Array remove index out of bounds")

**Example**
```pepper
    var a = Array<int>();
    a.append(1);
    a.append(2);
    var x = a.remove_at(0);   # x == 1; a holds [2]
```

#### pop

```pepper
T pop()
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
T first()
```

Returns the first element without removing it; the same as `a[0]`.

**Returns**
- the element at index 0

**Panics**
- if the Array is empty ("Array first on empty Array")

#### last

```pepper
T last()
```

Returns the last element without removing it; the same as
`a[a.count() - 1]`.

**Returns**
- the element at index `count() - 1`

**Panics**
- if the Array is empty ("Array last on empty Array")

#### clear

```pepper
void clear()
```

Removes every element, leaving the Array empty.

Runs in O(count). For a struct `T` each element's reference is
released. The capacity is kept, so refilling the Array does not
reallocate. Always invalidates running iterators, even on an empty
Array.

#### truncate

```pepper
void truncate(ulong count)
```

Shortens the Array to its first `count` elements, removing the rest.

Runs in O(removed elements). For a struct `T` each removed element's
reference is released. A `count` at or above the current `count()`
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
void swap(ulong a, ulong b)
```

Exchanges the elements at positions `a` and `b`.

Runs in O(1). Reference counts are unchanged: the two references just
trade slots. Swapping a position with itself is allowed and changes no
element, but still invalidates running iterators like every swap.

**Parameters**
- `a` — the position of the first element
- `b` — the position of the second element

**Panics**
- if `a < count()` does not hold ("Array swap index out of bounds")
- if `b < count()` does not hold ("Array swap index out of bounds")

#### reverse

```pepper
void reverse()
```

Reverses the order of the elements in place.

Runs in O(count) using `swap`, so reference counts are unchanged. An
Array of fewer than two elements is left untouched and its iterators
stay valid; otherwise running iterators are invalidated.

**Example**
```pepper
    a.reverse();   # [1, 2, 3] becomes [3, 2, 1]
```

#### find

```pepper
long find(T item)
```

Returns the position of the first element equal to `item`.

Runs in O(count), scanning from the front. Elements are compared with
`==`: when `T` declares an `==` operator (as `String` does) that
operator decides; for any other struct `T` it compares references, so
only the very same object matches.

**Parameters**
- `item` — the value to look for

**Returns**
- the index of the first match, or -1 when no element matches

**Example**
```pepper
    var i = a.find(9);   # -1 if a holds no 9
```

#### contains

```pepper
bool contains(T item)
```

Reports whether any element equals `item`, compared as `find` does.

Runs in O(count).

**Parameters**
- `item` — the value to look for

**Returns**
- true when `find(item)` finds a match

#### append_all

```pepper
void append_all(Array<T> rhs)
```

Appends every element of `rhs`, in order, to the end of this Array.

Runs in O(count of `rhs`), reserving the needed capacity once up
front. `rhs` is unchanged, and it may be this same Array
(`a.append_all(a)` doubles `a`). For a struct `T` each appended element
is acquired once more, since both Arrays now hold it. Invalidates this
Array's running iterators when `rhs` is not empty.

**Parameters**
- `rhs` — the Array whose elements are copied

**See also**
- `+=`

#### clone

```pepper
Array<T> clone()
```

Returns a new Array holding the same elements in the same order.

Runs in O(count). The copy is shallow: for a struct `T` both Arrays
refer to the same element objects (each acquired once more), but adding
or removing elements in one does not affect the other. The new Array's
capacity equals this Array's `count()`.

**Returns**
- an independent Array with the same elements

**Example**
```pepper
    var b = a.clone();
    b.append(7);   # a is unchanged
```

#### copy

```pepper
Array<T> copy(Copies copies)
```

Returns a deep copy: a new Array holding a copy of each element, made
with `copies.copy`. This is how `copy(value)` copies an Array (the
`Copyable<Array<T>>` implementation); call `copy(array)` rather than
this method.

Unlike `clone()`, which shares struct elements, the result shares no
element that is not thread-safe with this Array. An element that
appears twice is copied once. Runs in O(count) plus the cost of
copying the elements.

**Parameters**
- `copies` — the objects copied so far

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
bool ==(Array<T> rhs)
```

Reports whether both Arrays have the same count and pairwise equal
elements, compared with `==` as `find` does.

Runs in O(count); stops at the first difference. Two empty Arrays are
equal. `capacity()` is not compared.

**Parameters**
- `rhs` — the Array to compare with

**Returns**
- true when the Arrays are element-wise equal

#### operator !=

```pepper
bool !=(Array<T> rhs)
```

Reports whether the Arrays differ in count or in any element; the
negation of `==`.

**Parameters**
- `rhs` — the Array to compare with

**Returns**
- true when the Arrays are not element-wise equal

#### operator +=

```pepper
Array<T> +=(Array<T> rhs)
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
Array<T> +(Array<T> rhs)
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

## ArrayIterator

```pepper
struct ArrayIterator<T>
```

An `Iterator<T>` over the elements of an Array, in index order; returned by
`Array.iterate()` and driven by `for (var x in array)`.

Holds a reference to the Array, so iterating a temporary keeps it alive for
the whole loop. The iterator is fail-fast: if the Array is modified after
the iterator was created (see `Array` for which operations count), its next
`next()` or `current()` panics instead of skipping or repeating elements.

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
bool next()
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
T current()
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current element

**Panics**
- if the Array was modified since the iterator was created ("Array modified during iteration")
- if `next()` was never called ("ArrayIterator.current() before next()")
- if `next()` already returned false ("ArrayIterator.current() past the end")
