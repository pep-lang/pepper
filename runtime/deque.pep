## `Deque`: a double-ended queue over a growable ring buffer.

import "array";
import "iterator";
import "optional";

# The ring is an `Array<T?>` whose count is the capacity: element `i` lives
# in slot `(_head + i) % capacity`, and every slot outside the live range is
# Empty, so a removed element is released at once and nothing is read
# uninitialized. Growing copies the elements, in order, into a ring twice
# the size starting at slot 0.

## A double-ended queue: a sequence that grows and shrinks at both ends in
## amortized O(1).
##
## Elements live in a ring buffer that doubles when full (starting at 4
## slots), so `push_front`, `push_back`, `pop_front` and `pop_back` are
## amortized O(1), and indexing is O(1) with index 0 at the front. Use it for
## first-in first-out queues, breadth-first search, sliding windows and undo
## history; an `Array` takes O(count) to remove its first element.
##
## For a struct `T` the deque holds a counted reference to each element, as
## an `Array` does: pushing acquires it, and popping hands the deque's
## reference to the caller. `Deque` is itself a struct, so assigning it
## shares the same deque. A `Deque` is not `[Shared]`: keep each one on one
## thread.
##
## A `Deque` is `Iterable<T>`: `for (var x in d)` visits the elements from
## front to back. Every change (a push, a pop, an element store, `clear`)
## invalidates running iterators, and the next step of such a loop panics
## with "Deque modified during iteration". An array converts to a deque, so
## an array literal can initialize one.
##
## @typeParam T the element type
## @example
##     Deque<int> queue = [1, 2];
##     queue.push_back(3);
##     queue.push_front(0);
##     assert(queue.pop_front() == 0, "front first");
##     assert(queue.pop_back() == 3, "then the back");
##     assert(queue[0] == 1 and queue.count == 2, "1 and 2 remain");
export struct Deque<T> {
    ## The ring: `capacity` slots, the elements in `_count` of them from
    ## `_head` on, wrapping around, and every other slot Empty. Internal.
    Array<T?> _slots;
    ## The slot holding the front element. Internal.
    ulong _head;
    ## The number of elements. Read it through `count`.
    ulong _count;
    ## Incremented by every change, so an iterator can detect one. Internal.
    ulong _version;

    ## Creates an empty deque with room for `capacity` elements before it
    ## grows.
    ##
    ## @param capacity the number of slots to allocate up front
    construct(capacity: ulong = 0) {
        _resize(capacity);
    }

    ## Creates a deque holding the elements of `items`, front to back in
    ## index order. The array is copied, not shared.
    ##
    ## The constructor is `[Implicit]`: an array converts to a deque
    ## wherever a deque is expected, so an array literal can initialize one.
    ##
    ## @param items the elements, the first at the front
    ## @example
    ##     Deque<String> names = ["ada", "grace"];
    ##     assert(names.front() == "ada", "the first element is the front");
    [Implicit]
    construct(items: T[]) {
        _resize(items.count);
        for (var item in items) {
            push_back(item);
        }
    }

    # The slot of element `index`, which must be less than `capacity`.
    _slot(index: ulong): ulong {
        return (_head + index) % _slots.count;
    }

    # Moves the elements into a new ring of `capacity` slots, at least
    # `_count`, starting at slot 0.
    _resize(capacity: ulong) {
        var slots = Array<T?>(capacity);
        ulong i = 0;
        while (i < capacity) {
            slots.append(i < _count ? _slots[_slot(i)] : Optional<T>.Empty);
            i = i + 1;
        }
        _slots = slots;
        _head = 0;
    }

    # Makes room for one more element.
    _grow() {
        if (_count < _slots.count) {
            return;
        }
        _resize(_slots.count < 4 ? 4 : _slots.count * 2);
    }

    ## The number of elements.
    var count: ulong {
        get {
            return _count;
        }
    }

    ## Whether the deque has no elements.
    var is_empty: bool {
        get {
            return _count == 0;
        }
    }

    ## The number of elements the deque holds without growing.
    var capacity: ulong {
        get {
            return _slots.count;
        }
    }

    ## Makes room for `capacity` elements in all, so pushing up to that
    ## many does not grow the deque. Never shrinks it.
    ##
    ## @param capacity the number of elements to make room for
    reserve(capacity: ulong) {
        if (capacity <= _slots.count) {
            return;
        }
        _resize(capacity);
    }

    ## Adds `item` at the back. Amortized O(1). Invalidates running
    ## iterators.
    ##
    ## @param item the element to add
    push_back(item: T) {
        _grow();
        _version = _version + 1;
        _slots[_slot(_count)] = Optional<T>.Value(item);
        _count = _count + 1;
    }

    ## Adds `item` at the front, so it becomes element 0. Amortized O(1).
    ## Invalidates running iterators.
    ##
    ## @param item the element to add
    push_front(item: T) {
        _grow();
        _version = _version + 1;
        _head = _slot(_slots.count - 1);
        _slots[_head] = Optional<T>.Value(item);
        _count = _count + 1;
    }

    ## Removes and returns the front element. O(1). Invalidates running
    ## iterators.
    ##
    ## @returns the element that was at the front
    ## @panics if the deque is empty ("Deque pop_front on empty Deque")
    pop_front(location: __ptr<char> = __caller_location()): T {
        assert(_count > 0, "Deque pop_front on empty Deque", location);
        var item = _take(_head);
        _head = _slot(1);
        return item;
    }

    ## Removes and returns the back element. O(1). Invalidates running
    ## iterators.
    ##
    ## @returns the element that was at the back
    ## @panics if the deque is empty ("Deque pop_back on empty Deque")
    pop_back(location: __ptr<char> = __caller_location()): T {
        assert(_count > 0, "Deque pop_back on empty Deque", location);
        return _take(_slot(_count - 1));
    }

    # Empties slot `slot`, an end of the live range, and returns its element.
    _take(slot: ulong): T {
        _version = _version + 1;
        var item = _slots[slot].value();
        _slots[slot] = Optional<T>.Empty;
        _count = _count - 1;
        return item;
    }

    ## Returns the front element without removing it; the same as `d[0]`.
    ##
    ## @returns the element at index 0
    ## @panics if the deque is empty ("Deque front on empty Deque")
    front(location: __ptr<char> = __caller_location()): T {
        assert(_count > 0, "Deque front on empty Deque", location);
        return _slots[_head].value();
    }

    ## Returns the back element without removing it; the same as
    ## `d[d.count - 1]`.
    ##
    ## @returns the element at index `count - 1`
    ## @panics if the deque is empty ("Deque back on empty Deque")
    back(location: __ptr<char> = __caller_location()): T {
        assert(_count > 0, "Deque back on empty Deque", location);
        return _slots[_slot(_count - 1)].value();
    }

    ## Returns the element at `index`, counting from 0 at the front; this is
    ## the indexer read `d[index]`. O(1).
    ##
    ## @param index the position to read
    ## @returns the element at `index`
    ## @panics if `index < count` does not hold ("Deque index read out of
    ##   bounds")
    [](index: ulong, location: __ptr<char> = __caller_location()): T {
        _pep_check_bounds(index < _count, "Deque index read out of bounds", location);
        return _slots[_slot(index)].value();
    }

    ## Replaces the element at `index`; this is the indexer write
    ## `d[index] = value`. Invalidates running iterators.
    ##
    ## @param index the position to overwrite
    ## @param value the new element
    ## @returns the element now stored at `index` (that is, `value`)
    ## @panics if `index < count` does not hold ("Deque index write out of
    ##   bounds")
    [](index: ulong, value: T, location: __ptr<char> = __caller_location()): T {
        _pep_check_bounds(index < _count, "Deque index write out of bounds", location);
        _version = _version + 1;
        _slots[_slot(index)] = Optional<T>.Value(value);
        return value;
    }

    ## Removes every element, releasing each one. The deque keeps its
    ## capacity. Invalidates running iterators.
    clear() {
        _version = _version + 1;
        while (_count > 0) {
            _take(_slot(_count - 1));
        }
        _head = 0;
    }

    ## Returns an iterator over the elements from front to back;
    ## `for (var x in d)` drives it.
    ##
    ## @returns an iterator positioned before the front element
    iterate(): DequeIterator<T> {
        return DequeIterator<T>(this);
    }
}

## An `Iterator<T>` over the elements of a `Deque` from front to back;
## returned by `Deque.iterate()` and driven by `for (var x in d)`.
##
## @typeParam T the element type of the deque
## @see Deque.iterate
[Value]
export struct DequeIterator<T> {
    ## The deque being iterated.
    Deque<T> _source;
    ## The index of the next element `next()` moves to.
    ulong _next;
    ## The deque's `_version` when iteration began.
    ulong _version;

    ## Creates an iterator positioned before the front element of `source`.
    ##
    ## @param source the deque to iterate
    construct(source: Deque<T>) {
        _source = source;
        _version = source._version;
    }

    ## Advances to the next element.
    ##
    ## @returns true when there is a current element, false once past the
    ##   back
    ## @panics if the deque changed since the iterator was created ("Deque
    ##   modified during iteration")
    next(): bool {
        return next(__caller_location());
    }

    ## `next()` for a `for` loop, which passes its own location so that
    ## the panic names the loop.
    ##
    ## @param location the loop's location, which a panic reports
    ## @returns true when there is a current element, false once past the
    ## @panics if the deque changed since the iterator was created ("Deque
    next(location: __ptr<char>): bool {
        assert(_source._version == _version, "Deque modified during iteration", location);
        if (_next > _source._count) {
            return false;
        }
        _next = _next + 1;
        return _next <= _source._count;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    ## @panics if the deque changed since the iterator was created ("Deque
    ##   modified during iteration")
    ## @panics if `next()` was never called or already returned false
    ##   ("DequeIterator.current() without an element")
    current(): T {
        assert(_source._version == _version, "Deque modified during iteration");
        assert(_next > 0 and _next <= _source._count, "DequeIterator.current() without an element");
        return _source[_next - 1];
    }
}

extend DequeIterator<T> with Iterator<T>;
