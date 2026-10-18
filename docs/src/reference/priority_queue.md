<!-- Generated from runtime/priority_queue.pep by `pep-doc reference`. Do not edit. -->

# PriorityQueue

`PriorityQueue`: a binary heap that hands out its greatest element first.

Source: `runtime/priority_queue.pep`

## PriorityQueue

```pepper
struct PriorityQueue<T>
```

A priority queue: `push` adds elements in any order and `pop` removes
the greatest one.

A binary heap over an `Array`: `push` and `pop` take O(log count),
`peek` takes O(1), and building a queue from an array takes O(count).
Use it for Dijkstra's and A* searches, schedulers, timers and top-k
selection.

Elements are ordered by `compare<T>` (numbers by value, `String` by
content, a `Comparable` struct by its `compare`), or by a comparer given
to the constructor, which returns a negative number, zero or a positive
number as its first argument sorts before, with or after its second. The
greatest element comes out first; reverse the comparer for the smallest
first. Elements that sort together come out in no particular order.

For a struct `T` the queue holds a counted reference to each element:
pushing acquires it, and popping hands the queue's reference to the
caller. A `PriorityQueue` is not `[Shared]`: keep each one on one
thread.

**Type parameters**
- `T` — the element type

**Example**
```pepper
PriorityQueue<int> queue = [3, 1, 4];
queue.push(5);
assert(queue.pop() == 5, "the greatest first");
assert(queue.peek() == 4, "then 4");

# The smallest first, through a reversed comparer.
var earliest = PriorityQueue<int>((a, b) => b.compare(a));
earliest.push(30);
earliest.push(10);
assert(earliest.pop() == 10, "the smallest first");
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

Whether the queue has no elements.

### Constructors

#### PriorityQueue()

```pepper
construct()
```

Creates an empty queue ordered by `compare<T>`.

#### PriorityQueue()

```pepper
construct(compare: (T, T) => int)
```

Creates an empty queue ordered by `compare`.

**Parameters**
- `compare` — returns a negative number, zero or a positive number as its first argument sorts before, with or after its second

**Example**
```pepper
var by_length = PriorityQueue<String>((a, b) => a.length.compare(b.length));
```

#### PriorityQueue()

```pepper
[Implicit] construct(items: T[])
```

Creates a queue holding the elements of `items`, ordered by
`compare<T>`. O(count). The array is copied, not shared.

The constructor is `[Implicit]`: an array converts to a queue
wherever a queue is expected, so an array literal can initialize one.

**Parameters**
- `items` — the elements, in any order

#### PriorityQueue()

```pepper
construct(items: T[], compare: (T, T) => int)
```

Creates a queue holding the elements of `items`, ordered by
`compare`. O(count). The array is copied, not shared.

**Parameters**
- `items` — the elements, in any order
- `compare` — returns a negative number, zero or a positive number as its first argument sorts before, with or after its second

### Methods

#### push

```pepper
push(item: T)
```

Adds `item`. O(log count), amortized.

**Parameters**
- `item` — the element to add

#### pop

```pepper
pop(): T
```

Removes and returns the greatest element. O(log count).

**Returns**
- the greatest element

**Panics**
- if the queue is empty ("PriorityQueue pop on empty PriorityQueue")

#### peek

```pepper
peek(): T
```

Returns the greatest element without removing it. O(1).

**Returns**
- the greatest element

**Panics**
- if the queue is empty ("PriorityQueue peek on empty PriorityQueue")

#### clear

```pepper
clear()
```

Removes every element, releasing each one.

#### into_sorted_array

```pepper
into_sorted_array(): T[]
```

Removes every element and returns them sorted from smallest to
greatest. O(count log count). The queue is left empty, keeping its
comparer.

**Returns**
- the elements in ascending order

**Example**
```pepper
PriorityQueue<int> queue = [2, 3, 1];
var sorted = queue.into_sorted_array();   # [1, 2, 3]
```
