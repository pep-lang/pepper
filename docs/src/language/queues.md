# Queues: Deque and PriorityQueue

Two collections take elements out in an order other than an `Array`'s:

| Type | Takes out | Push, pop | Elements need |
| --- | --- | --- | --- |
| `Deque<T>` | either end | amortized O(1) at both ends | nothing |
| `PriorityQueue<T>` | the greatest element | O(log n) | `compare<T>`, or a comparer |

An `Array` can stand in for either, but removing its first element takes
O(n), and keeping it sorted takes O(n) per insert.

## Deque

A `Deque` (a double-ended queue) is a ring buffer that grows when full:
`push_back`, `push_front`, `pop_back` and `pop_front` add and remove at the
two ends, `front()` and `back()` read them, and `d[i]` reads or writes the
element `i` places from the front. It is the queue of a breadth-first
search, a sliding window, or an undo history that drops its oldest entry.

```pepper
{{#include ../../examples/queues-deque.pep}}
```

An array converts to a `Deque`, so an array literal can initialize one.
`count`, `is_empty`, `capacity`, `reserve` and `clear` work as they do on an
`Array`. A `for` loop visits the elements from front to back; changing the
deque while a loop iterates it panics ("Deque modified during iteration").
Popping, or reading `front()` or `back()`, of an empty deque panics, as does
an index past the back.

## PriorityQueue

A `PriorityQueue` is a binary heap: `push` adds an element in O(log n), `pop`
removes the greatest in O(log n), and `peek()` reads the greatest without
removing it. It is the frontier of Dijkstra's and A* searches, a scheduler's
run queue, or the k largest values of a stream.

```pepper
{{#include ../../examples/queues-priority.pep}}
```

Elements are ordered by `compare<T>`, so numbers, `String`, and any
[`Comparable`](ordering.md) type need nothing more. To order by something
else, pass a comparer to the constructor: a function that returns a
negative number, zero or a positive number as its first argument sorts
before, with or after its second. For the smallest first, reverse the
comparer, `(a, b) => b.compare(a)`. Elements that sort together come out in
no particular order.

An array converts to a `PriorityQueue`, and `PriorityQueue<T>(items,
compare)` builds one from an array with a comparer; both take O(n), and copy
the array. `into_sorted_array()` empties the queue and returns its elements
from smallest to greatest. `pop` and `peek` of an empty queue panic.

Neither type is `[Shared]`: like an `Array`, each stays on one thread.
