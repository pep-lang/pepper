<!-- Generated from runtime/deque.pep by `pep-doc reference`. Do not edit. -->

# Deque

`Deque`: a double-ended queue over a growable ring buffer.

Source: `runtime/deque.pep`

## Deque

```pepper
struct Deque<T>
```

A double-ended queue: a sequence that grows and shrinks at both ends in
amortized O(1).

Elements live in a ring buffer that doubles when full (starting at 4
slots), so `push_front`, `push_back`, `pop_front` and `pop_back` are
amortized O(1), and indexing is O(1) with index 0 at the front. Use it for
first-in first-out queues, breadth-first search, sliding windows and undo
history; an `Array` takes O(count) to remove its first element.

For a struct `T` the deque holds a counted reference to each element, as
an `Array` does: pushing acquires it, and popping hands the deque's
reference to the caller. `Deque` is itself a struct, so assigning it
shares the same deque. A `Deque` is not `[Shared]`: keep each one on one
thread.

A `Deque` is `Iterable<T>`: `for (var x in d)` visits the elements from
front to back. Every change (a push, a pop, an element store, `clear`)
invalidates running iterators, and the next step of such a loop panics
with "Deque modified during iteration". An array converts to a deque, so
an array literal can initialize one.

**Type parameters**
- `T` — the element type

**Example**
```pepper
Deque<int> queue = [1, 2];
queue.push_back(3);
queue.push_front(0);
assert(queue.pop_front() == 0, "front first");
assert(queue.pop_back() == 3, "then the back");
assert(queue[0] == 1 and queue.count == 2, "1 and 2 remain");
```

### Properties

#### count

```pepper
var count: ulong { get; }
```

The number of elements.

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the deque has no elements.

#### capacity

```pepper
var capacity: ulong { get; }
```

The number of elements the deque holds without growing.

### Constructors

#### Deque()

```pepper
construct(capacity: ulong = 0)
```

Creates an empty deque with room for `capacity` elements before it
grows.

**Parameters**
- `capacity` — the number of slots to allocate up front

#### Deque()

```pepper
[Implicit] construct(items: T[])
```

Creates a deque holding the elements of `items`, front to back in
index order. The array is copied, not shared.

The constructor is `[Implicit]`: an array converts to a deque
wherever a deque is expected, so an array literal can initialize one.

**Parameters**
- `items` — the elements, the first at the front

**Example**
```pepper
Deque<String> names = ["ada", "grace"];
assert(names.front() == "ada", "the first element is the front");
```

### Methods

#### reserve

```pepper
reserve(capacity: ulong)
```

Makes room for `capacity` elements in all, so pushing up to that
many does not grow the deque. Never shrinks it.

**Parameters**
- `capacity` — the number of elements to make room for

#### push_back

```pepper
push_back(item: T)
```

Adds `item` at the back. Amortized O(1). Invalidates running
iterators.

**Parameters**
- `item` — the element to add

#### push_front

```pepper
push_front(item: T)
```

Adds `item` at the front, so it becomes element 0. Amortized O(1).
Invalidates running iterators.

**Parameters**
- `item` — the element to add

#### pop_front

```pepper
pop_front(): T
```

Removes and returns the front element. O(1). Invalidates running
iterators.

**Returns**
- the element that was at the front

**Panics**
- if the deque is empty ("Deque pop_front on empty Deque")

#### pop_back

```pepper
pop_back(): T
```

Removes and returns the back element. O(1). Invalidates running
iterators.

**Returns**
- the element that was at the back

**Panics**
- if the deque is empty ("Deque pop_back on empty Deque")

#### front

```pepper
front(): T
```

Returns the front element without removing it; the same as `d[0]`.

**Returns**
- the element at index 0

**Panics**
- if the deque is empty ("Deque front on empty Deque")

#### back

```pepper
back(): T
```

Returns the back element without removing it; the same as
`d[d.count - 1]`.

**Returns**
- the element at index `count - 1`

**Panics**
- if the deque is empty ("Deque back on empty Deque")

#### operator []

```pepper
[](index: ulong): T
```

Returns the element at `index`, counting from 0 at the front; this is
the indexer read `d[index]`. O(1).

**Parameters**
- `index` — the position to read

**Returns**
- the element at `index`

**Panics**
- if `index < count` does not hold ("Deque index read out of bounds")

#### operator []

```pepper
[](index: ulong, value: T): T
```

Replaces the element at `index`; this is the indexer write
`d[index] = value`. Invalidates running iterators.

**Parameters**
- `index` — the position to overwrite
- `value` — the new element

**Returns**
- the element now stored at `index` (that is, `value`)

**Panics**
- if `index < count` does not hold ("Deque index write out of bounds")

#### clear

```pepper
clear()
```

Removes every element, releasing each one. The deque keeps its
capacity. Invalidates running iterators.

#### iterate

```pepper
iterate(): DequeIterator<T>
```

Returns an iterator over the elements from front to back;
`for (var x in d)` drives it.

**Returns**
- an iterator positioned before the front element

## DequeIterator

```pepper
[Value] struct DequeIterator<T>
```

An `Iterator<T>` over the elements of a `Deque` from front to back;
returned by `Deque.iterate()` and driven by `for (var x in d)`.

**Type parameters**
- `T` — the element type of the deque

**See also**
- `Deque.iterate`

### Constructor

#### DequeIterator()

```pepper
construct(source: Deque<T>)
```

Creates an iterator positioned before the front element of `source`.

**Parameters**
- `source` — the deque to iterate

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element.

**Returns**
- true when there is a current element, false once past the back

**Panics**
- if the deque changed since the iterator was created ("Deque modified during iteration")

#### current

```pepper
current(): T
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current element

**Panics**
- if the deque changed since the iterator was created ("Deque modified during iteration")
- if `next()` was never called or already returned false ("DequeIterator.current() without an element")
