## `PriorityQueue`: a binary heap that hands out its greatest element first.

import "array";
import "map";

# A binary max-heap in `_heap`: the parent of element `i` is `(i - 1) / 2`,
# and no element sorts after its parent under `_compare`, so element 0 is
# the greatest.

## A priority queue: `push` adds elements in any order and `pop` removes
## the greatest one.
##
## A binary heap over an `Array`: `push` and `pop` take O(log count),
## `peek` takes O(1), and building a queue from an array takes O(count).
## Use it for Dijkstra's and A* searches, schedulers, timers and top-k
## selection.
##
## Elements are ordered by `compare<T>` (numbers by value, `String` by
## content, a `Comparable` struct by its `compare`), or by a comparer given
## to the constructor, which returns a negative number, zero or a positive
## number as its first argument sorts before, with or after its second. The
## greatest element comes out first; reverse the comparer for the smallest
## first. Elements that sort together come out in no particular order.
##
## For a struct `T` the queue holds a counted reference to each element:
## pushing acquires it, and popping hands the queue's reference to the
## caller. A `PriorityQueue` is not `[Shared]`: keep each one on one
## thread.
##
## @typeParam T the element type
## @example
##     PriorityQueue<int> queue = [3, 1, 4];
##     queue.push(5);
##     assert(queue.pop() == 5, "the greatest first");
##     assert(queue.peek() == 4, "then 4");
##
##     # The smallest first, through a reversed comparer.
##     var earliest = PriorityQueue<int>((a, b) => b.compare(a));
##     earliest.push(30);
##     earliest.push(10);
##     assert(earliest.pop() == 10, "the smallest first");
export struct PriorityQueue<T> {
    ## The heap: each element sorts with or before its parent. Internal.
    T[] _heap;
    ## The order: negative, zero or positive as the first argument sorts
    ## before, with or after the second. Internal.
    (T, T) => int _compare;

    ## Creates an empty queue ordered by `compare<T>`.
    construct() {
        _compare = compare<T>;
    }

    ## Creates an empty queue ordered by `compare`.
    ##
    ## @param compare returns a negative number, zero or a positive number
    ##   as its first argument sorts before, with or after its second
    ## @example
    ##     var by_length = PriorityQueue<String>((a, b) => a.length.compare(b.length));
    construct(compare: (T, T) => int) {
        _compare = compare;
    }

    ## Creates a queue holding the elements of `items`, ordered by
    ## `compare<T>`. O(count). The array is copied, not shared.
    ##
    ## The constructor is `[Implicit]`: an array converts to a queue
    ## wherever a queue is expected, so an array literal can initialize one.
    ##
    ## @param items the elements, in any order
    [Implicit]
    construct(items: T[]) {
        _compare = compare<T>;
        _heapify(items);
    }

    ## Creates a queue holding the elements of `items`, ordered by
    ## `compare`. O(count). The array is copied, not shared.
    ##
    ## @param items the elements, in any order
    ## @param compare returns a negative number, zero or a positive number
    ##   as its first argument sorts before, with or after its second
    construct(items: T[], compare: (T, T) => int) {
        _compare = compare;
        _heapify(items);
    }

    # Takes a copy of `items` as the heap and sifts each parent down, from
    # the last up: O(count).
    _heapify(items: T[]) {
        _heap = items.clone();
        ulong parent = _heap.count / 2;
        while (parent > 0) {
            parent = parent - 1;
            _sift_down(parent, _heap.count);
        }
    }

    # Whether element `a` sorts after element `b`.
    _after(a: ulong, b: ulong): bool {
        return _compare(_heap[a], _heap[b]) > 0;
    }

    # Moves element `index` up until it sorts with or before its parent.
    _sift_up(index: ulong) {
        while (index > 0) {
            ulong parent = (index - 1) / 2;
            if (!_after(index, parent)) {
                return;
            }
            _heap.swap(index, parent);
            index = parent;
        }
    }

    # Moves element `index` down, within the first `end` elements, until
    # neither child sorts after it.
    _sift_down(index: ulong, end: ulong) {
        while (true) {
            ulong largest = index;
            ulong left = index * 2 + 1;
            ulong right = left + 1;
            if (left < end and _after(left, largest)) {
                largest = left;
            }
            if (right < end and _after(right, largest)) {
                largest = right;
            }
            if (largest == index) {
                return;
            }
            _heap.swap(index, largest);
            index = largest;
        }
    }

    ## The number of elements.
    var count: ulong {
        get {
            return _heap.count;
        }
    }

    ## Whether the queue has no elements.
    var is_empty: bool {
        get {
            return _heap.is_empty;
        }
    }

    ## Adds `item`. O(log count), amortized.
    ##
    ## @param item the element to add
    push(item: T) {
        _heap.append(item);
        _sift_up(_heap.count - 1);
    }

    ## Removes and returns the greatest element. O(log count).
    ##
    ## @returns the greatest element
    ## @panics if the queue is empty ("PriorityQueue pop on empty
    ##   PriorityQueue")
    pop(location: __ptr<char> = __caller_location()): T {
        assert(!_heap.is_empty, "PriorityQueue pop on empty PriorityQueue", location);
        _heap.swap(0, _heap.count - 1);
        var top = _heap.pop();
        _sift_down(0, _heap.count);
        return top;
    }

    ## Returns the greatest element without removing it. O(1).
    ##
    ## @returns the greatest element
    ## @panics if the queue is empty ("PriorityQueue peek on empty
    ##   PriorityQueue")
    peek(location: __ptr<char> = __caller_location()): T {
        assert(!_heap.is_empty, "PriorityQueue peek on empty PriorityQueue", location);
        return _heap[0];
    }

    ## Removes every element, releasing each one.
    clear() {
        _heap.clear();
    }

    ## Removes every element and returns them sorted from smallest to
    ## greatest. O(count log count). The queue is left empty, keeping its
    ## comparer.
    ##
    ## @returns the elements in ascending order
    ## @example
    ##     PriorityQueue<int> queue = [2, 3, 1];
    ##     var sorted = queue.into_sorted_array();   # [1, 2, 3]
    into_sorted_array(): T[] {
        # Heap sort: the greatest of the first `end` elements moves to the
        # end of them, one at a time.
        ulong end = _heap.count;
        while (end > 1) {
            end = end - 1;
            _heap.swap(0, end);
            _sift_down(0, end);
        }
        var sorted = _heap;
        _heap = Array<T>();
        return sorted;
    }
}
