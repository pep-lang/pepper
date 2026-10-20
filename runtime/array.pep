import "internals";

# Elements of a struct-typed Array are references: the constructor initializes
# each to null (zero-init), every store into a slot releases the old occupant
# and acquires the new value (codegen, at the store site), and every place an
# element leaves the live range nulls its slot so the reference is released
# (or moves out with `move`). The destructor detaches the buffer and releases
# each element (`data[i].__release()`) without writing the slot, since the
# buffer is freed next. A plain-value `T` (`int`,
# a tuple of numbers) owns nothing, so none of this applies to it: its slots
# are left as they are.
#
# Shifts (insert, remove_at) move a whole run of slots with one memmove, swap
# exchanges two slots' bytes, and sort permutes raw slots through a scratch
# buffer: a move does not change a reference's count, exactly as moving
# shared_ptrs between slots would not.
#
# Every mutating method (element store, append, insert, remove_at, pop, clear,
# truncate, swap) bumps _version; an ArrayIterator panics when it sees a
# _version other than the one it started with, so modifying an Array while a
# `for` loop iterates it is a panic rather than skipped or repeated elements.
#
# `[__Lazy]`: an empty Array is a null reference until it is written
# or shared. `Array<T>()` is null; codegen allocates the object (this
# constructor with capacity 0) when a place holding null is read for anything
# but a `[__Reads]` method's receiver or a field read, and a field read
# through null reads a zeroed constant. So the `[__Reads]` methods below run
# with a null `this`, and `check_lazy` keeps them from writing to it. An
# iterator made from an empty Array holds null, so appending to the Array
# while it runs is not detected; it simply ends.

## A growable, contiguous, zero-indexed sequence of `T` values.
##
## Elements live in one heap buffer that doubles when full (starting at 4
## slots), so `append` is amortized O(1) and indexing is O(1). When `T` is a
## struct type, each slot holds a counted reference, exactly like a
## `std::vector<std::shared_ptr<T>>`: storing an element acquires it,
## overwriting or removing one releases the old occupant, and destroying the
## Array releases every element it still holds. Moving elements within the
## Array (`insert`, `remove_at`, `swap`, `reverse`) does not change their
## reference counts.
##
## `Array` is itself a struct, so assigning it or passing it to a function
## shares the same Array rather than copying its elements; use `clone()` for
## an independent copy.
##
## An empty Array allocates nothing: `Array<T>()` makes no object until the
## Array is first written (`append`, `insert`, `reserve`, ...) or shared
## (assigned, stored, passed or returned), and reading it (`count`,
## `is_empty`, `capacity`, `find`, `contains`, iterating) allocates nothing.
## Sharing allocates first, so every name for an Array sees the same
## elements.
##
## An Array is `Iterable<T>`: `for (var x in a)` visits each element in index
## order. Every mutating operation (an element store through `[]`, `append`,
## `insert`, `remove_at`, `pop`, `clear`, a shrinking `truncate`, `swap`,
## `fill`, `retain`, `remove_if`, `resize`, `split_off`, `drain`,
## `extend_from`, `rotate`, `select_nth`, `partial_sort`, and `reverse`,
## `sort`, `sort_unstable` or `dedup` of two or more elements) invalidates
## running iterators and slices
## (`slice`), and the next step of such a loop panics with "Array modified
## during iteration".
##
## @typeParam T the element type
## @example
##     main(): int {
##         var a = Array<int>();
##         a.append(1);
##         a.append(2);
##         a[0] = 5;
##         var total = 0;
##         for (var x in a) {
##             total = total + x;
##         }
##         return total;   # 7
##     }
## @see ArrayIterator
[__Lazy]
export struct Array<T> {
    ## The element buffer: `_capacity` slots, of which the first `_size` hold
    ## live elements. When `T` holds references the rest are zeroed (null for
    ## struct `T`); for a plain-value `T` they may hold stale values. Null while
    ## `_capacity` is 0. Internal storage; use the methods instead of touching
    ## it directly.
    __ptr<T> _data;
    ## The number of live elements; always at most `_capacity`. Read it through `count`.
    ulong _size;
    ## The number of element slots allocated in `_data`; never shrinks. Read it through `capacity`.
    ulong _capacity;
    ## The modification counter: incremented by every mutating operation so
    ## that an `ArrayIterator` can detect changes made while it runs. Its
    ## value carries no other meaning.
    ulong _version;
    ## The number of I/O operations using the buffer right now (a file read
    ## or write in a task, which another thread or the kernel carries out
    ## while other tasks run). While it is not 0 the buffer must not move,
    ## so growing it panics.
    ulong _pins;

    ## Creates an empty Array, optionally preallocating room for `capacity`
    ## elements.
    ##
    ## With the default `capacity` of 0, nothing is allocated, not even the
    ## Array itself, until the Array is first written or shared (see `Array`).
    ## Preallocating avoids the reallocations `append`
    ## would otherwise perform while the Array grows to a known size.
    ##
    ## @param capacity the number of element slots to allocate up front; `count` is still 0
    ## @example
    ##     var a = Array<int>(16);   # a.count == 0, a.capacity == 16
    construct(capacity: ulong = 0) {
        if (capacity > 0) {
            _data = _pep_malloc(sizeof<T>() * capacity);
            _capacity = capacity;
        }
    }

    destruct {
        # Detach the buffer before releasing anything: an element's
        # destructor that reaches this Array through a cycle then finds it
        # empty, never an element being destroyed. The slots are not
        # written, since the buffer is freed next. Anything such a
        # destructor appends lands in a new buffer, released the same way.
        # The pointer compares as bytes: `__ptr<T>` would pick `T`'s own `!=`.
        while (unsafe_cast<__ptr<u8>>(_data) != __null) {
            __ptr<T> data = _data;
            ulong count = _size;
            _data = __null;
            _size = 0;
            _capacity = 0;
            # A plain value owns nothing, so it is skipped.
            if (!__is_pod<T>()) {
                ulong index = 0;
                while (index < count) {
                    data[index].__release();
                    index = index + 1;
                }
            }
            _pep_free(data);
        }
    }

    # The address of slot `index`, in bytes: `_data + index` would pick `T`'s
    # own `+` when `T` has one.
    _slot(index: ulong): __ptr<u8> {
        __ptr<u8> bytes = unsafe_cast<__ptr<u8>>(_data);
        return bytes + index * sizeof<T>();
    }

    # Releases the elements in slots `start` up to `end`, nulling each slot
    # before its element is released (`operator=`), so a destructor that
    # reads the Array finds null there, never the element being destroyed.
    # Leaves `_size` alone.
    _release_range(start: ulong, end: ulong) {
        if (!__is_pod<T>()) {
            ulong index = start;
            while (index < end) {
                _data[index] = __default<T>();
                index = index + 1;
            }
        }
    }

    # Makes room for `extra` more elements, at least doubling the capacity
    # when it must grow so that repeated bulk appends stay amortized O(1).
    _reserve_extra(extra: ulong) {
        if (_size + extra > _capacity) {
            var capacity = _capacity * 2;
            if (capacity < _size + extra) {
                capacity = _size + extra;
            }
            reserve(capacity);
        }
    }

    ## Returns an iterator over the elements in index order; this is what
    ## `for (var x in array)` calls (the `Iterable<T>` protocol).
    ##
    ## The iterator holds a reference to the Array, so iterating a temporary
    ## keeps it alive for the whole loop. Modifying the Array while the
    ## iterator is in use makes the iterator's next `next()` or `current()`
    ## panic, except when the Array was empty when the iterator was made:
    ## the iterator then sees no elements and ends.
    ##
    ## @returns a new iterator positioned before the first element
    ## @example
    ##     for (var x in a) {
    ##         total = total + x;
    ##     }
    [__Reads]
    iterate(): ArrayIterator<T> {
        var it = ArrayIterator<T>();
        it._source = this;
        it._version = _version;
        return it;
    }

    ## The number of elements in the Array.
    [__Reads]
    var count: ulong {
        get {
            return _size;
        }
    }

    ## The number of elements the Array can hold before its buffer
    ## must be reallocated.
    [__Reads]
    var capacity: ulong {
        get {
            return _capacity;
        }
    }

    ## Returns a pointer to the first element, for passing the elements to C,
    ## as `String.c_str()` does for text.
    ##
    ## The pointer is owned by the Array. It is valid until the Array is
    ## destroyed or its buffer reallocates (`append`, `insert`, `reserve`, or
    ## anything else that grows it); writes through it change the elements.
    ## For an empty Array it is `__null`, even when capacity is reserved.
    ##
    ## @returns the address of element 0, or `__null` when the Array is empty
    ## @see append_from
    ## @example
    ##     var a = Array<int>();
    ##     a.append(7);
    ##     var p = a.data();   # p[0] == 7
    data(): __ptr<T> {
        if (_size == 0) {
            return __null;
        }
        return _data;
    }

    ## Whether the Array has no elements.
    [__Reads]
    var is_empty: bool {
        get {
            return _size == 0;
        }
    }

    ## Ensures the buffer has room for at least `capacity` elements,
    ## reallocating it when it is smaller.
    ##
    ## Never shrinks the buffer: a `capacity` at or below the current one does
    ## nothing. Elements, their order, and their reference counts are
    ## unchanged, and running iterators stay valid. Growing copies the
    ## existing elements, which costs O(count).
    ##
    ## @param capacity the minimum number of element slots required
    ## @panics if the buffer must grow while an I/O operation in a task is using it
    ## @example
    ##     var a = Array<int>();
    ##     a.reserve(8);   # a.capacity >= 8
    ##     a.reserve(2);   # no effect: capacity never shrinks
    reserve(capacity: ulong) {
        if (capacity > _capacity) {
            assert(_pins == 0, "Array: the buffer is in use by an I/O operation");
            ulong prev_size = sizeof<T>() * _capacity;
            ulong new_size = sizeof<T>() * capacity;
            # Slots past `count` are read only when they hold references, which must start null.
            _data = __is_pod<T>() ?
                _pep_realloc_uninit(_data, prev_size, new_size) :
                _pep_realloc(_data, prev_size, new_size);
            _capacity = capacity;
        }
    }

    ## Makes room for one more element: when the buffer is full, doubles its
    ## capacity (to at least 4); otherwise does nothing.
    ##
    ## `append` and `insert` call this themselves; callers rarely need it.
    ## Does not change the elements or invalidate iterators.
    ##
    ## @panics if the buffer must grow while an I/O operation in a task is using it
    grow() {
        if (_size >= _capacity) {
            ulong next = _capacity * 2;
            if (next < 4) {
                next = 4;
            }
            reserve(next);
        }
    }

    ## Returns the element at `idx`; this is the indexer read `a[idx]`.
    ##
    ## Runs in O(1). For a struct `T` the result is the stored reference
    ## itself; binding it to a variable acquires it like any shared copy.
    ##
    ## @param idx the zero-based position to read
    ## @returns the element at `idx`
    ## @panics if `idx < count` does not hold ("Array index read out of bounds")
    ## @example
    ##     var first = a[0];
    [__Reads]
    [](idx: ulong, location: __ptr<char> = __caller_location()): T {
        _pep_check_bounds(idx < _size, "Array index read out of bounds", location);
        return _data[idx];
    }

    ## Replaces the element at `idx` with `value`; this is the indexer write
    ## `a[idx] = value`.
    ##
    ## For a struct `T` the slot acquires `value` and releases its previous
    ## occupant; assigning an element to its own slot (`a[i] = a[i]`) leaves
    ## counts unchanged. Only replaces an existing element: use `append` to
    ## add one. Invalidates running iterators, even when the value is
    ## unchanged.
    ##
    ## @param idx the zero-based position to overwrite
    ## @param value the new element
    ## @returns the element now stored at `idx` (that is, `value`)
    ## @panics if `idx < count` does not hold ("Array index write out of bounds")
    ## @example
    ##     a[0] = 42;
    [](idx: ulong, value: T, location: __ptr<char> = __caller_location()): T {
        _pep_check_bounds(idx < _size, "Array index write out of bounds", location);
        _version = _version + 1;
        _data[idx] = value;
        return _data[idx];
    }

    ## Adds `item` to the end of the Array.
    ##
    ## Amortized O(1): when the buffer is full it doubles (O(count) for that
    ## call). For a struct `T` the Array acquires a reference to `item`.
    ## Invalidates running iterators.
    ##
    ## @param item the element to add
    ## @panics if the buffer must grow while an I/O operation in a task is using it
    ## @example
    ##     var a = Array<int>();
    ##     a.append(1);
    ##     a.append(2);   # a holds [1, 2]
    append(item: T) {
        _version = _version + 1;
        grow();
        # Slots past `count` are kept empty, so the store only acquires.
        __construct_at(_data[_size], item);
        _size = _size + 1;
    }

    ## Appends the `count` elements at `source`, in order: the way to fill an
    ## Array from a C buffer, as `String(data, size)` does for text.
    ##
    ## Runs in O(count), with one copy of the whole range for a POD `T`. For
    ## a struct `T` the Array acquires a reference to each element. `source`
    ## must point at `count` valid elements, and not into this Array, which
    ## may reallocate. Invalidates running iterators.
    ##
    ## @param source the first element to copy; may be `__null` when `count` is 0
    ## @param count the number of elements to copy
    ## @panics if the buffer must grow while an I/O operation in a task is using it
    ## @see data
    ## @example
    ##     var a = Array<u8>();
    ##     a.append(1);
    ##     a.append(2);
    ##     var b = Array<u8>();
    ##     b.append_from(a.data(), a.count);   # b holds [1, 2]
    append_from(source: __ptr<T>, count: ulong) {
        if (__is_pod<T>()) {
            _append_raw(source, count);
            return;
        }
        _version = _version + 1;
        _reserve_extra(count);
        ulong index = 0;
        while (index < count) {
            # Slots past `count` are kept empty, so the store only acquires.
            __construct_at(_data[_size], source[index]);
            _size = _size + 1;
            index = index + 1;
        }
    }

    # Appends the `count` elements at `source` with one copy, for a POD `T`
    # only (no reference counting is done): a byte buffer filling from
    # another. Internal.
    _append_raw(source: __ptr<T>, count: ulong) {
        if (count == 0) {
            return;
        }
        _version = _version + 1;
        _reserve_extra(count);
        _array_copy(_slot(_size), source, count * sizeof<T>());
        _size = _size + count;
    }

    ## Inserts `item` at position `idx`, shifting the element there and every
    ## later element up by one.
    ##
    ## Runs in O(count - idx), plus a reallocation when the buffer is full.
    ## `idx == count` appends. For a struct `T` the Array acquires a
    ## reference to `item`; shifted elements keep their reference counts.
    ## Invalidates running iterators.
    ##
    ## @param idx the position `item` will occupy; from 0 through `count`
    ## @param item the element to insert
    ## @panics if `idx <= count` does not hold ("Array insert index out of bounds")
    ## @panics if the buffer must grow while an I/O operation in a task is using it
    ## @example
    ##     var a = Array<int>();
    ##     a.append(1);
    ##     a.append(3);
    ##     a.insert(1, 2);   # a holds [1, 2, 3]
    insert(idx: ulong, item: T, location: __ptr<char> = __caller_location()) {
        assert(idx <= _size, "Array insert index out of bounds", location);
        _version = _version + 1;
        grow();
        # Shift the tail up one slot as raw bytes: each reference moves to
        # its new slot without changing its count, exactly as moving
        # `shared_ptr`s between slots would. The vacated slot still holds a
        # copy of the bits it moved, so it is zeroed, leaving an empty slot
        # for the store to construct into.
        if (idx < _size) {
            _array_move(_slot(idx + 1), _slot(idx), (_size - idx) * sizeof<T>());
            _array_zero(_slot(idx), sizeof<T>());
        }
        __construct_at(_data[idx], item);
        _size = _size + 1;
    }
    ## Removes and returns the element at `idx`, shifting every later element
    ## down by one.
    ##
    ## Runs in O(count - idx). For a struct `T` the Array's reference is
    ## transferred to the caller, so the element stays alive as long as the
    ## result is held; shifted elements keep their reference counts. The
    ## capacity is unchanged. Invalidates running iterators.
    ##
    ## @param idx the position of the element to remove
    ## @returns the removed element
    ## @panics if `idx < count` does not hold ("Array remove index out of bounds")
    ## @example
    ##     var a = Array<int>();
    ##     a.append(1);
    ##     a.append(2);
    ##     var x = a.remove_at(0);   # x == 1; a holds [2]
    remove_at(idx: ulong, location: __ptr<char> = __caller_location()): T {
        assert(idx < _size, "Array remove index out of bounds", location);
        _version = _version + 1;
        # The slot's reference moves to the caller, with no count step.
        var removed = move(_data[idx]);
        # Shift the tail down one slot as raw bytes (references keep their
        # counts), then zero the last slot, whose reference moved down.
        _array_move(_slot(idx), _slot(idx + 1), (_size - idx - 1) * sizeof<T>());
        if (!__is_pod<T>()) {
            _array_zero(_slot(_size - 1), sizeof<T>());
        }
        _size = _size - 1;
        return removed;
    }

    ## Removes and returns the last element.
    ##
    ## Runs in O(1). For a struct `T` the Array's reference is transferred to
    ## the caller. The capacity is unchanged. Invalidates running iterators.
    ##
    ## @returns the element that was last
    ## @panics if the Array is empty ("Array pop on empty Array")
    ## @example
    ##     var top = a.pop();
    pop(location: __ptr<char> = __caller_location()): T {
        assert(_size > 0, "Array pop on empty Array", location);
        _version = _version + 1;
        _size = _size - 1;
        # The slot's reference moves to the caller, with no count step.
        return move(_data[_size]);
    }

    ## Returns the first element without removing it; the same as `a[0]`.
    ##
    ## @returns the element at index 0
    ## @panics if the Array is empty ("Array first on empty Array")
    [__Reads]
    first(location: __ptr<char> = __caller_location()): T {
        assert(_size > 0, "Array first on empty Array", location);
        return _data[0];
    }

    ## Returns the last element without removing it; the same as
    ## `a[a.count - 1]`.
    ##
    ## @returns the element at index `count - 1`
    ## @panics if the Array is empty ("Array last on empty Array")
    [__Reads]
    last(location: __ptr<char> = __caller_location()): T {
        assert(_size > 0, "Array last on empty Array", location);
        return _data[_size - 1];
    }

    ## Removes every element, leaving the Array empty.
    ##
    ## Runs in O(count) for a `T` holding references, each of which is
    ## released, and in O(1) for a plain value `T` (`int`, `u8`, a tuple of
    ## numbers). The capacity is kept, so refilling the Array does not
    ## reallocate. Always invalidates running iterators, even on an empty
    ## Array.
    clear() {
        _version = _version + 1;
        _release_range(0, _size);
        _size = 0;
    }

    ## Shortens the Array to its first `count` elements, removing the rest.
    ##
    ## Runs in O(removed elements). For a struct `T` each removed element's
    ## reference is released. A `count` at or above the current `count`
    ## does nothing (the Array never grows) and leaves iterators valid; an
    ## actual shrink invalidates them. The capacity is kept.
    ##
    ## @param count the number of leading elements to keep
    ## @example
    ##     a.truncate(1);   # keeps only a[0]
    ##     a.truncate(5);   # no effect when a has fewer than 5 elements
    truncate(count: ulong) {
        if (count < _size) {
            _version = _version + 1;
            _release_range(count, _size);
            _size = count;
        }
    }

    ## Exchanges the elements at positions `a` and `b`.
    ##
    ## Runs in O(1). Reference counts are unchanged: the two references just
    ## trade slots. Swapping a position with itself is allowed and changes no
    ## element, but still invalidates running iterators like every swap.
    ##
    ## @param a the position of the first element
    ## @param b the position of the second element
    ## @panics if `a < count` does not hold ("Array swap index out of bounds")
    ## @panics if `b < count` does not hold ("Array swap index out of bounds")
    swap(a: ulong, b: ulong, location: __ptr<char> = __caller_location()) {
        assert(a < _size, "Array swap index out of bounds", location);
        assert(b < _size, "Array swap index out of bounds", location);
        _version = _version + 1;
        if (a != b) {
            _array_swap(_slot(a), _slot(b), sizeof<T>());
        }
    }

    ## Reverses the order of the elements in place.
    ##
    ## Runs in O(count), exchanging elements pairwise, so reference counts
    ## are unchanged. An Array of fewer than two elements is left untouched
    ## and its iterators stay valid; otherwise running iterators are
    ## invalidated.
    ##
    ## @example
    ##     a.reverse();   # [1, 2, 3] becomes [3, 2, 1]
    reverse() {
        if (_size >= 2) {
            _version = _version + 1;
            _reverse_range(0, _size);
        }
    }

    # Reverses slots `start` up to `end` by exchanging raw slots, so no
    # count changes. Leaves `_version` alone.
    _reverse_range(start: ulong, end: ulong) {
        if (end - start < 2) {
            return;
        }
        ulong low = start;
        ulong high = end - 1;
        while (low < high) {
            _array_swap(_slot(low), _slot(high), sizeof<T>());
            low = low + 1;
            high = high - 1;
        }
    }

    ## Moves the first `count` elements to the end, keeping the order within
    ## each part: the element at `count` becomes the first.
    ##
    ## Runs in O(count of the Array), exchanging elements, so reference
    ## counts are unchanged. Rotating by 0 or by the Array's `count` changes
    ## nothing and leaves iterators valid; any other rotation invalidates
    ## them.
    ##
    ## @param count the number of leading elements to move; from 0 through the Array's `count`
    ## @panics if `count` is more than the Array's `count` ("Array rotate count out of bounds")
    ## @example
    ##     var a = [1, 2, 3, 4, 5];
    ##     a.rotate(2);   # [3, 4, 5, 1, 2]
    rotate(count: ulong, location: __ptr<char> = __caller_location()) {
        assert(count <= _size, "Array rotate count out of bounds", location);
        if (count == 0 || count == _size) {
            return;
        }
        _version = _version + 1;
        _reverse_range(0, count);
        _reverse_range(count, _size);
        _reverse_range(0, _size);
    }

    ## Sorts the elements in place into the order `compare` defines. The
    ## sort is stable: elements that compare equal keep their relative
    ## order.
    ##
    ## `compare(a, b)` returns a negative number when `a` belongs before
    ## `b`, 0 when their order does not matter, and a positive number when
    ## `a` belongs after `b`, the convention `String.compare` follows. It is
    ## a merge sort: O(count log count) calls to `compare`, plus a scratch
    ## buffer of `count` slots. Elements move between the two buffers
    ## without changing any reference count. Invalidates running iterators
    ## when there are two or more elements.
    ##
    ## `compare` must not modify the Array: its elements are spread over
    ## the two buffers while the sort runs.
    ##
    ## @param compare returns the order of its two arguments, as above
    ## @panics if `compare` modifies the Array ("Array modified during sort")
    ## @example
    ##     var names = Array<String>();
    ##     names.append("pear");
    ##     names.append("apple");
    ##     names.sort((a, b) => a.compare(b));   # ["apple", "pear"]
    ##     var numbers = Array<int>();
    ##     numbers.append(3);
    ##     numbers.append(1);
    ##     numbers.sort((a, b) => b - a);        # descending: [3, 1]
    sort(compare: (T, T) => int) {
        _merge_sort(compare);
    }

    ## Sorts the elements in place into the order `compare` defines, without
    ## keeping equal elements in their original order.
    ##
    ## `compare` follows the convention of `sort(compare)`. It is
    ## pattern-defeating quicksort (pdqsort): O(count log count) calls to
    ## `compare` in the worst case, O(count) on an Array that is already
    ## sorted or all equal, and no scratch buffer, so it is the faster sort
    ## when stability does not matter. Elements only trade slots, so no
    ## reference count changes. Invalidates running iterators when there
    ## are two or more elements.
    ##
    ## @param compare returns the order of its two arguments, as for `sort`
    ## @panics if `compare` modifies the Array ("Array modified during sort")
    ## @example
    ##     var a = [5, 1, 4, 2, 3];
    ##     a.sort_unstable((x, y) => x - y);   # [1, 2, 3, 4, 5]
    sort_unstable(compare: (T, T) => int) {
        _pdq_sort(compare);
    }

    # The body of `sort_unstable(compare)`, which `sort_unstable()` calls
    # too (see `_merge_sort`).
    _pdq_sort(compare: (T, T) => int) {
        if (_size < 2) {
            return;
        }
        var sorter = _ArraySorter<T>(this, compare);
        sorter.sort(0, _size);
    }

    ## Reorders the elements so that the one at `nth` is the element a full
    ## sort would put there, every element before it sorts before or with
    ## it, and every element after it sorts after or with it (C++'s
    ## `nth_element`). Each side is otherwise in no particular order.
    ##
    ## `compare` follows the convention of `sort(compare)`. Runs in O(count)
    ## calls to `compare` on average and O(count log count) in the worst
    ## case, with no scratch buffer. Elements only trade slots, so no
    ## reference count changes. Invalidates running iterators.
    ##
    ## @param nth the position to settle; less than `count`
    ## @param compare returns the order of its two arguments, as for `sort`
    ## @panics if `nth < count` does not hold ("Array select_nth index out of bounds")
    ## @panics if `compare` modifies the Array ("Array modified during sort")
    ## @example
    ##     var a = [9, 1, 8, 2, 7, 3];
    ##     a.select_nth(2, (x, y) => x - y);   # a[2] == 3, the third smallest
    select_nth(nth: ulong, compare: (T, T) => int, location: __ptr<char> = __caller_location()) {
        _select_nth(nth, compare, location);
    }

    # The body of `select_nth(nth, compare)`, shared with `select_nth(nth)`.
    _select_nth(nth: ulong, compare: (T, T) => int, location: __ptr<char>) {
        assert(nth < _size, "Array select_nth index out of bounds", location);
        var sorter = _ArraySorter<T>(this, compare);
        sorter.select(nth);
    }

    ## Puts the `count` elements that sort first into the first `count`
    ## positions, in order, and leaves the rest after them in no particular
    ## order: the start of a full sort, found faster.
    ##
    ## `compare` follows the convention of `sort(compare)`. Runs in
    ## O(count of the Array + `count` log `count`) calls to `compare` on
    ## average, with no scratch buffer; it is not stable. Elements only
    ## trade slots, so no reference count changes. Invalidates running
    ## iterators.
    ##
    ## @param count the number of leading elements to sort; from 0 through the Array's `count`
    ## @param compare returns the order of its two arguments, as for `sort`
    ## @panics if `count` is more than the Array's `count` ("Array partial_sort count out of bounds")
    ## @panics if `compare` modifies the Array ("Array modified during sort")
    ## @example
    ##     var scores = [40, 95, 12, 77, 63];
    ##     scores.partial_sort(3, (x, y) => y - x);   # starts [95, 77, 63]
    partial_sort(count: ulong, compare: (T, T) => int, location: __ptr<char> = __caller_location()) {
        _partial_sort(count, compare, location);
    }

    # The body of `partial_sort(count, compare)`, shared with
    # `partial_sort(count)`.
    _partial_sort(count: ulong, compare: (T, T) => int, location: __ptr<char>) {
        assert(count <= _size, "Array partial_sort count out of bounds", location);
        var sorter = _ArraySorter<T>(this, compare);
        if (count > 0 && count < _size) {
            sorter.select(count - 1);
        }
        sorter.sort(0, count);
    }

    # The body of `sort(compare)`, which `sort()` on `Comparable` elements
    # (runtime/compare.pep) calls too: a call to `sort` from there is
    # ambiguous, as the extension's lookup finds this overload twice.
    _merge_sort(compare: (T, T) => int) {
        if (_size < 2) {
            return;
        }
        _version = _version + 1;
        var version = _version;
        # Bottom-up merge sort: runs of `width` merge from `source` into
        # `target`, and the two swap each pass. Each element moves (`move`
        # nulls the slot it leaves and the store takes its reference without
        # a count step), so the sort changes no count, and every pass starts
        # with an all-null `target` (`_pep_malloc` zeroes `scratch`).
        __ptr<T> scratch = _pep_malloc(sizeof<T>() * _size);
        __ptr<T> source = _data;
        __ptr<T> target = scratch;
        ulong width = 1;
        while (width < _size) {
            ulong low = 0;
            while (low < _size) {
                ulong middle = _min(low + width, _size);
                ulong high = _min(low + 2 * width, _size);
                ulong left = low;
                ulong right = middle;
                ulong out = low;
                while (out < high) {
                    # Take from the right run only when it is strictly
                    # smaller, which keeps equal elements in order.
                    var take_left = left < middle;
                    if (take_left && right < high) {
                        take_left = compare(source[right], source[left]) >= 0;
                        # `compare` must not change the Array: its elements
                        # are spread over two buffers.
                        assert(_version == version, "Array modified during sort");
                    }
                    if (take_left) {
                        target[out] = move(source[left]);
                        left = left + 1;
                    } else {
                        target[out] = move(source[right]);
                        right = right + 1;
                    }
                    out = out + 1;
                }
                low = high;
            }
            var swapped = source;
            source = target;
            target = swapped;
            width = width * 2;
        }
        # The sorted elements ended in `scratch`: copy them back as bytes,
        # leaving `scratch` with copies it does not own, and free it as is.
        if (unsafe_cast<__ptr<u8>>(source) == unsafe_cast<__ptr<u8>>(scratch)) {
            _array_copy(_data, scratch, sizeof<T>() * _size);
        }
        _pep_free(scratch);
    }

    # An array literal `[a, b, c]` is built as
    # `_array_literal(a)._literal_append(b)._literal_append(c)`: each step
    # appends and returns the same Array.
    _literal_append(item: T): Array<T> {
        append(item);
        return this;
    }

    # A literal too long for one chain is built as a balanced tree of short
    # chains, all appending to the same Array, joined left to right by this
    # (see `_build_literal` in tools/compiler/sema/builder.pep): `this` is built first, then
    # `next`, and both are that Array.
    _literal_then(next: Array<T>): Array<T> {
        return next;
    }

    static _min(a: ulong, b: ulong): ulong {
        if (a < b) {
            return a;
        }
        return b;
    }

    ## Returns the position of the first element equal to `item`, or none
    ## when no element matches.
    ##
    ## Runs in O(count), scanning from the front. Elements are compared with
    ## `==`: when `T` declares an `==` operator (as `String` does) that
    ## operator decides; for any other struct `T` it compares references, so
    ## only the very same object matches.
    ##
    ## Breaking change: `find` used to return a `long` that was `-1` when
    ## nothing matched. It now returns `ulong?`: test it with `is_some()` (or
    ## as a condition) and read the index with `value()`.
    ##
    ## @param item the value to look for
    ## @returns the index of the first match, or none when no element matches
    ## (always none for an empty Array)
    ## @example
    ##     var a = [3, 9, 4];
    ##     var i = a.find(9);         # i.value() == 1
    ##     var missing = a.find(7);   # missing.is_empty() == true
    [__Reads]
    find(item: T): ulong? {
        ulong index = 0;
        while (index < _size) {
            if (_data[index] == item) {
                return Optional<ulong>.Value(index);
            }
            index = index + 1;
        }
        return Optional<ulong>.Empty;
    }

    ## Reports whether any element equals `item`, compared as `find` does.
    ##
    ## Runs in O(count).
    ##
    ## @param item the value to look for
    ## @returns true when `find(item)` finds a match
    [__Reads]
    contains(item: T): bool {
        return find(item).is_value();
    }

    ## Returns a read-only view of the elements from `start` up to but not
    ## including `end`, without copying them.
    ##
    ## The slice holds a reference to this Array, so it cannot outlive it,
    ## and it is fail-fast like an iterator: once the Array is modified (see
    ## `Array` for which operations count), every later use of the slice
    ## panics, so it never reads elements that moved or were freed.
    ##
    ## @param start the position of the first element in the slice
    ## @param end the position one past the last element; from `start` through `count`
    ## @returns a view of `end - start` elements
    ## @panics if `start <= end` and `end <= count` do not both hold ("Array slice out of bounds")
    ## @example
    ##     var a = [1, 2, 3, 4, 5];
    ##     var middle = a.slice(1, 4);   # views [2, 3, 4]
    ##     var second = middle[1];       # 3
    [__Reads]
    slice(start: ulong, end: ulong, location: __ptr<char> = __caller_location()): ArraySlice<T> {
        _pep_check_bounds(start <= end && end <= _size, "Array slice out of bounds", location);
        var view = ArraySlice<T>();
        view._source = this;
        view._start = start;
        view._end = end;
        view._version = _version;
        return view;
    }

    ## Returns the position of the element that `order` reports equal to the
    ## target, searching an Array sorted in the order `order` follows, or
    ## none when there is none.
    ##
    ## Runs in O(log count) calls to `order`, which must not modify the
    ## Array. When several elements match, the first of them is found.
    ##
    ## @param order returns a negative number when its argument sorts before
    ##   the target, 0 when it matches, and a positive number when it sorts after
    ## @returns the index of the first matching element, or none
    ## @panics if `order` modifies the Array ("Array modified while a slice of it is in use")
    ## @example
    ##     var a = [10, 20, 30];
    ##     var i = a.binary_search_by((x) => x.compare(20));   # i.value() == 1
    [__Reads]
    binary_search_by(order: (T) => int): ulong? {
        return slice(0, _size).binary_search_by(order);
    }

    ## Replaces every element with `value`.
    ##
    ## Runs in O(count). For a struct `T` every slot acquires `value` and
    ## releases its previous occupant. Invalidates running iterators.
    ##
    ## @param value the value each element becomes
    ## @example
    ##     var a = [1, 2, 3];
    ##     a.fill(0);   # [0, 0, 0]
    fill(value: T) {
        _version = _version + 1;
        ulong index = 0;
        while (index < _size) {
            _data[index] = value;
            index = index + 1;
        }
    }

    ## Removes every element for which `keep` returns false, keeping the
    ## order of the rest.
    ##
    ## Runs in O(count) calls to `keep`, which sees each element once, in
    ## index order, and must not modify the Array. For a struct `T` each
    ## removed element is released and kept elements keep their counts. The
    ## capacity is unchanged. Invalidates running iterators.
    ##
    ## @param keep returns true for an element to keep
    ## @panics if `keep` modifies the Array ("Array modified during retain")
    ## @example
    ##     var a = [1, 2, 3, 4];
    ##     a.retain((x) => x % 2 == 0);   # [2, 4]
    retain(keep: (T) => bool) {
        _version = _version + 1;
        var version = _version;
        ulong kept = 0;
        ulong index = 0;
        while (index < _size) {
            var keeping = keep(_data[index]);
            assert(_version == version, "Array modified during retain");
            if (keeping) {
                _keep_at(kept, index);
                kept = kept + 1;
            }
            index = index + 1;
        }
        _release_range(kept, _size);
        _size = kept;
    }

    ## Removes every element for which `remove` returns true, keeping the
    ## order of the rest; the opposite of `retain`.
    ##
    ## Runs in O(count) calls to `remove`, which sees each element once, in
    ## index order, and must not modify the Array. For a struct `T` each
    ## removed element is released. Invalidates running iterators.
    ##
    ## @param remove returns true for an element to remove
    ## @panics if `remove` modifies the Array ("Array modified during retain")
    ## @example
    ##     var a = [1, 2, 3, 4];
    ##     a.remove_if((x) => x > 2);   # [1, 2]
    remove_if(remove: (T) => bool) {
        retain((x) => !remove(x));
    }

    ## Removes each element equal (`==`) to the one before it, so a run of
    ## equal elements keeps only its first. On a sorted Array this removes
    ## every duplicate.
    ##
    ## Runs in O(count). Elements are compared as `find` does. For a struct
    ## `T` each removed element is released. Invalidates running iterators
    ## when there are two or more elements.
    ##
    ## @example
    ##     var a = [1, 1, 2, 3, 3, 3, 1];
    ##     a.dedup();   # [1, 2, 3, 1]
    dedup() {
        if (_size < 2) {
            return;
        }
        _version = _version + 1;
        ulong kept = 1;
        ulong index = 1;
        while (index < _size) {
            if (!(_data[index] == _data[kept - 1])) {
                _keep_at(kept, index);
                kept = kept + 1;
            }
            index = index + 1;
        }
        _release_range(kept, _size);
        _size = kept;
    }

    # Moves the element at `index` down to slot `kept` (at or before it) for
    # `retain` and `dedup`: the store releases the dropped element there, and
    # `move` nulls `index`'s slot, so the reference keeps its count.
    _keep_at(kept: ulong, index: ulong) {
        if (kept != index) {
            _data[kept] = move(_data[index]);
        }
    }

    ## Changes the count to `count`: removes elements past it, as
    ## `truncate` does, or appends copies of `value` until there are
    ## `count` elements.
    ##
    ## Runs in O(difference in count), plus at most one reallocation.
    ## Invalidates running iterators when the count changes.
    ##
    ## @param count the number of elements the Array will hold
    ## @param value the element to append when the Array grows
    ## @panics if the buffer must grow while an I/O operation in a task is using it
    ## @example
    ##     var a = [1, 2];
    ##     a.resize(4, 0);   # [1, 2, 0, 0]
    ##     a.resize(1, 0);   # [1]
    resize(count: ulong, value: T) {
        if (count <= _size) {
            truncate(count);
            return;
        }
        reserve(count);
        while (_size < count) {
            append(value);
        }
    }

    ## Removes the elements from `index` on and returns them as a new Array,
    ## leaving this Array with its first `index` elements.
    ##
    ## Runs in O(count - index). The elements move without changing their
    ## reference counts. This Array's capacity is unchanged. Invalidates
    ## running iterators when any element moves.
    ##
    ## @param index the position of the first element to move; from 0 through `count`
    ## @returns a new Array holding the elements that were at `index` and after
    ## @panics if `index <= count` does not hold ("Array split_off index out of bounds")
    ## @example
    ##     var a = [1, 2, 3, 4];
    ##     var tail = a.split_off(1);   # a holds [1]; tail holds [2, 3, 4]
    split_off(index: ulong, location: __ptr<char> = __caller_location()): Array<T> {
        assert(index <= _size, "Array split_off index out of bounds", location);
        return drain(index, _size);
    }

    ## Removes the elements from `start` up to but not including `end` and
    ## returns them as a new Array, shifting the later elements down.
    ##
    ## Runs in O(count - start). The elements move without changing their
    ## reference counts. This Array's capacity is unchanged. Invalidates
    ## running iterators when any element is removed.
    ##
    ## @param start the position of the first element to remove
    ## @param end the position one past the last element to remove; from `start` through `count`
    ## @returns a new Array holding the removed elements, in order
    ## @panics if `start <= end` and `end <= count` do not both hold ("Array drain range out of bounds")
    ## @example
    ##     var a = [1, 2, 3, 4, 5];
    ##     var middle = a.drain(1, 3);   # a holds [1, 4, 5]; middle holds [2, 3]
    drain(start: ulong, end: ulong, location: __ptr<char> = __caller_location()): Array<T> {
        assert(start <= end && end <= _size, "Array drain range out of bounds", location);
        ulong moved = end - start;
        if (moved == 0) {
            return Array<T>();
        }
        _version = _version + 1;
        Array<T> drained = Array<T>(moved);
        # The references move to `drained` and the tail moves down as raw
        # bytes, so no count changes; the slots vacated at the end are
        # zeroed to stay empty.
        _array_copy(drained._data, _slot(start), moved * sizeof<T>());
        _array_move(_slot(start), _slot(end), (_size - end) * sizeof<T>());
        if (!__is_pod<T>()) {
            _array_zero(_slot(_size - moved), moved * sizeof<T>());
        }
        drained._size = moved;
        _size = _size - moved;
        return drained;
    }

    ## Appends every element of `rhs`, in order, to the end of this Array.
    ##
    ## Runs in O(count of `rhs`), growing the buffer at most once and copying
    ## the elements in one block. `rhs` is unchanged, and it may be this same Array
    ## (`a.append_all(a)` doubles `a`). For a struct `T` each appended element
    ## is acquired once more, since both Arrays now hold it. Invalidates this
    ## Array's running iterators when `rhs` is not empty.
    ##
    ## @param rhs the Array whose elements are copied
    ## @panics if the buffer must grow while an I/O operation in a task is using it
    ## @see +=
    append_all(rhs: Array<T>) {
        _append_from(rhs, 0, rhs._size);
    }

    ## Appends every element of `items`, in order, to the end of this Array.
    ##
    ## Runs in O(count of `items`), growing the buffer at most once. `items`
    ## may view this same Array. For a struct `T` each appended element is
    ## acquired once more. Invalidates this Array's running iterators and
    ## slices (`items` among them, when it views this Array) when `items`
    ## is not empty.
    ##
    ## @param items the elements to copy
    ## @panics if the Array `items` views was modified since `items` was made ("Array modified while a slice of it is in use")
    ## @panics if the buffer must grow while an I/O operation in a task is using it
    ## @example
    ##     var a = [1, 2];
    ##     var b = [7, 8, 9];
    ##     a.extend_from(b.slice(1, 3));   # [1, 2, 8, 9]
    extend_from(items: ArraySlice<T>, location: __ptr<char> = __caller_location()) {
        items._check(location);
        _append_from(items._source, items._start, items.count);
    }

    # Appends `count` elements of `source` from `start` on with one block
    # copy. `count` is read by the caller first and `source`'s buffer only
    # after growing, since `source` may be this Array (`a += a`).
    _append_from(source: Array<T>, start: ulong, count: ulong) {
        if (count == 0) {
            return;
        }
        _version = _version + 1;
        _reserve_extra(count);
        _array_copy(_slot(_size), source._slot(start), count * sizeof<T>());
        # The copied slots are new references to the same elements.
        if (!__is_pod<T>()) {
            ulong index = _size;
            while (index < _size + count) {
                _data[index].__acquire();
                index = index + 1;
            }
        }
        _size = _size + count;
    }

    ## Returns a new Array holding the same elements in the same order.
    ##
    ## Runs in O(count). The copy is shallow: for a struct `T` both Arrays
    ## refer to the same element objects (each acquired once more), but adding
    ## or removing elements in one does not affect the other. The new Array's
    ## capacity equals this Array's `count`.
    ##
    ## @returns an independent Array with the same elements
    ## @example
    ##     var b = a.clone();
    ##     b.append(7);   # a is unchanged
    [__Reads]
    clone(): Array<T> {
        Array<T> result = Array<T>(_size);
        result.append_all(this);
        return result;
    }

    ## Returns a deep copy: a new Array holding a copy of each element, made
    ## with `copy`. This is how `copy(value)` copies an Array (the
    ## `Copyable<Array<T>>` implementation); call `copy(array)` rather than
    ## this method.
    ##
    ## Unlike `clone()`, which shares struct elements, the result shares no
    ## element that is not thread-safe with this Array. An element that
    ## appears twice is copied once. Runs in O(count) plus the cost of
    ## copying the elements.
    ##
    ## @returns the copy
    ## @example
    ##     var names = Array<String>();
    ##     names.append("ada");
    ##     var copied = copy(names);   # calls this method
    copy(): Array<T> {
        Array<T> made = Array<T>(_size);
        register_copy<Array<T>>(this, made);
        # Numbers are their own copies: one block copy, and no element
        # visits the running copy.
        if (__is_pod<T>()) {
            made.append_all(this);
            return made;
        }
        ulong i = 0;
        while (i < _size) {
            made.append(copy<T>(_data[i]));
            i = i + 1;
        }
        return made;
    }

    ## Reports whether both Arrays have the same count and pairwise equal
    ## elements, compared with `==` as `find` does.
    ##
    ## Runs in O(count); stops at the first difference. Two empty Arrays are
    ## equal. `capacity` is not compared.
    ##
    ## @param rhs the Array to compare with
    ## @returns true when the Arrays are element-wise equal
    [__Reads]
    ==(rhs: Array<T>): bool {
        if (_size != rhs._size) {
            return false;
        }
        ulong idx = 0;
        while (idx < _size) {
            if (!(_data[idx] == rhs._data[idx])) {
                return false;
            }
            idx = idx + 1;
        }
        return true;
    }

    ## Reports whether the Arrays differ in count or in any element; the
    ## negation of `==`.
    ##
    ## @param rhs the Array to compare with
    ## @returns true when the Arrays are not element-wise equal
    [__Reads]
    !=(rhs: Array<T>): bool {
        return !(this == rhs);
    }

    ## Appends every element of `rhs` to this Array in place (`a += b`); the
    ## same as `append_all`.
    ##
    ## `a += a` is allowed and doubles `a`.
    ##
    ## @param rhs the Array whose elements are appended
    ## @returns this Array, after the append
    ## @example
    ##     a += b;   # a now ends with b's elements
    ## @see append_all
    +=(rhs: Array<T>): Array<T> {
        append_all(rhs);
        return this;
    }

    ## Returns a new Array holding this Array's elements followed by those of
    ## `rhs` (`a + b`).
    ##
    ## Runs in O(count + count of `rhs`). Neither operand is modified; like
    ## `clone`, the result shares struct elements with its operands.
    ##
    ## @param rhs the Array whose elements come second
    ## @returns the concatenation of this Array and `rhs`
    ## @example
    ##     var c = a + b;
    [__Reads]
    +(rhs: Array<T>): Array<T> {
        Array<T> result = Array<T>(_size + rhs._size);
        result.append_all(this);
        result.append_all(rhs);
        return result;
    }
}

## The searches of a sorted Array, for an element type with an order
## (see `Comparable`).
##
## @typeParam T the element type, `Comparable`
export extend Array<T: Comparable> {
    ## Returns the position of an element equal to `item` in this Array,
    ## which must be sorted in `compare` order, or none when there is
    ## none.
    ##
    ## Runs in O(log count). When several elements equal `item`, the first
    ## of them is found. On an Array that is not sorted the result is
    ## unspecified (but never out of bounds).
    ##
    ## @param item the value to look for
    ## @returns the index of the first element equal to `item`, or none
    ## @example
    ##     var a = [1, 3, 5, 7];
    ##     var i = a.binary_search(5);   # i.value() == 2
    [__Reads]
    binary_search(item: T): ulong? {
        return slice(0, _size).binary_search(item);
    }

    ## Returns the first position at which `item` could be inserted while
    ## keeping this sorted Array sorted: the index of the first element that
    ## does not sort before `item` (in `compare` order), or `count` when
    ## every element does.
    ##
    ## Runs in O(log count).
    ##
    ## @param item the value to place
    ## @returns the index of the first element at or after `item`
    ## @example
    ##     var a = [1, 3, 3, 5];
    ##     var i = a.lower_bound(3);   # 1
    [__Reads]
    lower_bound(item: T): ulong {
        return slice(0, _size).lower_bound(item);
    }

    ## Returns the last position at which `item` could be inserted while
    ## keeping this sorted Array sorted: the index of the first element that
    ## sorts after `item` (in `compare` order), or `count` when none does.
    ##
    ## Runs in O(log count). `upper_bound(x) - lower_bound(x)` is the number
    ## of elements equal to `x`.
    ##
    ## @param item the value to place
    ## @returns the index of the first element after `item`
    ## @example
    ##     var a = [1, 3, 3, 5];
    ##     var i = a.upper_bound(3);   # 3
    [__Reads]
    upper_bound(item: T): ulong {
        return slice(0, _size).upper_bound(item);
    }

    ## Reports whether the elements are in `compare` order: no element
    ## sorts after the one that follows it.
    ##
    ## Runs in O(count). An Array of fewer than two elements is sorted.
    ##
    ## @returns true when the Array is sorted
    [__Reads]
    is_sorted(): bool {
        return slice(0, _size).is_sorted();
    }

    ## Sorts the elements in place into their own order, `compare`, without
    ## keeping equal elements in their original order; otherwise behaves
    ## like `sort_unstable(compare)`.
    ##
    ## @panics if comparing modifies the Array ("Array modified during sort")
    ## @example
    ##     var a = [3, 1, 2];
    ##     a.sort_unstable();   # [1, 2, 3]
    sort_unstable() {
        _pdq_sort((a, b) => a.compare(b));
    }

    ## Reorders the elements so that the one at `nth` is the one sorting
    ## would put there, with the elements before it sorting before or with
    ## it and those after it after or with it; see
    ## `select_nth(nth, compare)`.
    ##
    ## @param nth the position to settle; less than `count`
    ## @panics if `nth < count` does not hold ("Array select_nth index out of bounds")
    ## @panics if comparing modifies the Array ("Array modified during sort")
    ## @example
    ##     var a = [9, 1, 8, 2, 7];
    ##     a.select_nth(2);   # a[2] == 7, the median
    select_nth(nth: ulong, location: __ptr<char> = __caller_location()) {
        _select_nth(nth, (a, b) => a.compare(b), location);
    }

    ## Puts the `count` smallest elements into the first `count` positions,
    ## in order; see `partial_sort(count, compare)`.
    ##
    ## @param count the number of leading elements to sort; from 0 through the Array's `count`
    ## @panics if `count` is more than the Array's `count` ("Array partial_sort count out of bounds")
    ## @panics if comparing modifies the Array ("Array modified during sort")
    ## @example
    ##     var a = [5, 3, 9, 1, 7];
    ##     a.partial_sort(2);   # starts [1, 3]
    partial_sort(count: ulong, location: __ptr<char> = __caller_location()) {
        _partial_sort(count, (a, b) => a.compare(b), location);
    }

    ## Returns the lexicographic order of this Array and `other`: the order
    ## of the first pair of elements that differ (by their `compare`), or,
    ## when one Array is the start of the other, the shorter first.
    ##
    ## Runs in O(count); stops at the first difference. Two empty Arrays
    ## sort together. It follows `Comparable`'s convention, so an Array of
    ## Arrays sorts with `sort((a, b) => a.compare(b))`.
    ##
    ## @param other the Array to compare with
    ## @returns a negative number, zero or a positive number as this Array
    ##   sorts before, with or after `other`
    ## @example
    ##     assert([1, 2, 3].compare([1, 3]) < 0, "2 sorts before 3");
    ##     assert([1, 2].compare([1, 2, 0]) < 0, "the shorter first");
    [__Reads]
    compare(other: Array<T>): int {
        ulong index = 0;
        while (index < _size && index < other._size) {
            var order = _data[index].compare(other._data[index]);
            if (order != 0) {
                return order;
            }
            index = index + 1;
        }
        return _size.compare(other._size);
    }
}

## An `Iterator<T>` over the elements of an Array, in index order; returned by
## `Array.iterate()` and driven by `for (var x in array)`.
##
## Holds a reference to the Array, so iterating a temporary keeps it alive for
## the whole loop. The iterator is fail-fast: if the Array is modified after
## the iterator was created (see `Array` for which operations count), its next
## `next()` or `current()` panics instead of skipping or repeating elements
## (an iterator over an Array that was empty when it was made just ends).
##
## @typeParam T the element type of the source Array
## @example
##     var it = a.iterate();
##     while (it.next()) {
##         var x = it.current();
##     }
## @see Array.iterate
[Value]
export struct ArrayIterator<T> {
    ## The Array being iterated; the iterator holds a reference to it for its whole lifetime.
    Array<T> _source;
    ## The position of the current element in `_source`. Meaningful only after
    ## `_started` is set; equals `_source.count` once iteration has finished.
    ulong _index;
    ## The `_source._version` recorded when iteration began; a mismatch means the Array was modified.
    ulong _version;
    ## Whether `next()` has been called at least once; the first call stays at index 0 instead of advancing.
    bool _started;

    ## Advances to the next element.
    ##
    ## The first call moves to index 0. Once it returns false it keeps
    ## returning false.
    ##
    ## @returns true when there is a current element, false once past the end
    ## @panics if the Array was modified since the iterator was created ("Array modified during iteration")
    next(): bool {
        assert(_source._version == _version, "Array modified during iteration");
        if (_started) {
            if (_index < _source._size) {
                _index = _index + 1;
            }
        } else {
            _started = true;
        }
        return _index < _source._size;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    ## @panics if the Array was modified since the iterator was created ("Array modified during iteration")
    ## @panics if `next()` was never called ("ArrayIterator.current() before next()")
    ## @panics if `next()` already returned false ("ArrayIterator.current() past the end")
    current(): T {
        assert(_source._version == _version, "Array modified during iteration");
        assert(_started, "ArrayIterator.current() before next()");
        assert(_index < _source._size, "ArrayIterator.current() past the end");
        return _source._data[_index];
    }
}

## A read-only view of a run of an Array's elements, made by `Array.slice`,
## that lets a function take "some of the elements" without copying them.
##
## A slice holds a reference to its Array, so the Array lives at least as
## long as the slice. It is fail-fast like `ArrayIterator`: once the Array
## is modified (see `Array` for which operations count), every later use of
## the slice panics with "Array modified while a slice of it is in use"
## instead of reading elements that moved or were freed. Make a new slice
## after changing the Array.
##
## A slice is `Iterable<T>`: `for (var x in slice)` visits its elements in
## order.
##
## @typeParam T the element type of the Array
## @example
##     total(values: ArraySlice<int>): int {
##         var sum = 0;
##         for (var x in values) {
##             sum = sum + x;
##         }
##         return sum;
##     }
##
##     var a = [1, 2, 3, 4];
##     var tail_sum = total(a.slice(2, 4));   # 7
## @see Array.slice
[Value]
export struct ArraySlice<T> {
    ## The Array viewed; the slice holds a reference to it.
    Array<T> _source;
    ## The position in `_source` of the slice's first element.
    ulong _start;
    ## The position in `_source` one past the slice's last element.
    ulong _end;
    ## The `_source._version` when the slice was made; a mismatch means the Array was modified.
    ulong _version;

    # Panics when the Array changed since the slice was made.
    _check(location: __ptr<char>) {
        assert(_source._version == _version, "Array modified while a slice of it is in use", location);
    }

    # The element at `index` in the slice, already bounds-checked.
    _at(index: ulong): T {
        _check(__caller_location());
        return _source._data[_start + index];
    }

    ## The number of elements in the slice.
    var count: ulong {
        get {
            return _end - _start;
        }
    }

    ## Whether the slice has no elements.
    var is_empty: bool {
        get {
            return _end == _start;
        }
    }

    ## Returns the element at `index` in the slice, `index` 0 being the
    ## slice's first element; this is the indexer read `slice[index]`.
    ##
    ## @param index the zero-based position in the slice
    ## @returns the element at `index`
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    ## @panics if `index < count` does not hold ("ArraySlice index out of bounds")
    [](index: ulong, location: __ptr<char> = __caller_location()): T {
        _check(location);
        _pep_check_bounds(index < _end - _start, "ArraySlice index out of bounds", location);
        return _source._data[_start + index];
    }

    ## Returns a view of this slice's elements from `start` up to but not
    ## including `end`, positions counted within this slice.
    ##
    ## @param start the position of the first element
    ## @param end the position one past the last element; from `start` through `count`
    ## @returns a view of `end - start` elements of the same Array
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    ## @panics if `start <= end` and `end <= count` do not both hold ("ArraySlice slice out of bounds")
    slice(start: ulong, end: ulong, location: __ptr<char> = __caller_location()): ArraySlice<T> {
        _check(location);
        _pep_check_bounds(start <= end && end <= _end - _start, "ArraySlice slice out of bounds", location);
        var view = this;
        view._start = _start + start;
        view._end = _start + end;
        return view;
    }

    ## Returns an iterator over the slice's elements in order; this is what
    ## `for (var x in slice)` calls.
    ##
    ## @returns a new iterator positioned before the first element
    iterate(): ArraySliceIterator<T> {
        var it = ArraySliceIterator<T>();
        it._slice = this;
        return it;
    }

    ## Returns a new Array holding a copy of the slice's elements, in order.
    ##
    ## The copy is shallow, as `Array.clone` is: for a struct `T` the new
    ## Array shares the element objects.
    ##
    ## @returns an independent Array with the slice's elements
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    to_array(): Array<T> {
        _check(__caller_location());
        Array<T> result = Array<T>(count);
        ulong index = 0;
        while (index < count) {
            result.append(_at(index));
            index = index + 1;
        }
        return result;
    }

    ## Returns the position in the slice of the first element equal (`==`)
    ## to `item`, or none, compared as `Array.find` does.
    ##
    ## @param item the value to look for
    ## @returns the index of the first match, or none when no element matches
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    find(item: T): ulong? {
        ulong index = 0;
        while (index < count) {
            if (_at(index) == item) {
                return Optional<ulong>.Value(index);
            }
            index = index + 1;
        }
        return Optional<ulong>.Empty;
    }

    ## Reports whether any element equals `item`, compared as `find` does.
    ##
    ## @param item the value to look for
    ## @returns true when `find(item)` finds a match
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    contains(item: T): bool {
        return find(item).is_value();
    }

    ## Returns the position of the first element that `order` reports equal
    ## to the target, in a slice sorted in the order `order` follows, or
    ## none; see `Array.binary_search_by`.
    ##
    ## @param order returns a negative number when its argument sorts before
    ##   the target, 0 when it matches, and a positive number when it sorts after
    ## @returns the index of the first matching element, or none
    ## @panics if the Array was modified since the slice was made, `order` included ("Array modified while a slice of it is in use")
    binary_search_by(order: (T) => int): ulong? {
        var index = _partition(order, true);
        if (index == count || order(_at(index)) != 0) {
            return Optional<ulong>.Empty;
        }
        return Optional<ulong>.Value(index);
    }

    # The first index whose element `order` places at or after the target
    # (`at_equal`), or strictly after it, by binary search. `_at` checks the
    # version before each read, so an `order` that changes the Array panics.
    _partition(order: (T) => int, at_equal: bool): ulong {
        ulong low = 0;
        ulong high = count;
        while (low < high) {
            ulong middle = low + (high - low) / 2;
            var side = order(_at(middle));
            if (side < 0 || (side == 0 && !at_equal)) {
                low = middle + 1;
                continue;
            }
            high = middle;
        }
        _check(__caller_location());
        return low;
    }
}

## The searches of a sorted ArraySlice, for an element type with an order
## (see `Comparable`).
##
## @typeParam T the element type, `Comparable`
export extend ArraySlice<T: Comparable> {
    ## Returns the position of the first element equal to `item` in this
    ## slice, which must be sorted in `compare` order, or none; see
    ## `Array.binary_search`.
    ##
    ## @param item the value to look for
    ## @returns the index of the first element equal to `item`, or none
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    binary_search(item: T): ulong? {
        return binary_search_by((x) => x.compare(item));
    }

    ## Returns the index of the first element of this sorted slice that
    ## does not sort before `item`, or `count`; see `Array.lower_bound`.
    ##
    ## @param item the value to place
    ## @returns the index of the first element at or after `item`
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    lower_bound(item: T): ulong {
        return _partition((x) => x.compare(item), true);
    }

    ## Returns the index of the first element of this sorted slice that
    ## sorts after `item`, or `count`; see `Array.upper_bound`.
    ##
    ## @param item the value to place
    ## @returns the index of the first element after `item`
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    upper_bound(item: T): ulong {
        return _partition((x) => x.compare(item), false);
    }

    ## Reports whether the elements are in `compare` order; see
    ## `Array.is_sorted`.
    ##
    ## @returns true when no element sorts after the one that follows it
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    is_sorted(): bool {
        ulong index = 1;
        while (index < count) {
            if (_at(index - 1).compare(_at(index)) > 0) {
                return false;
            }
            index = index + 1;
        }
        return true;
    }
}

## An `Iterator<T>` over the elements of an `ArraySlice`, in order; returned
## by `ArraySlice.iterate()` and driven by `for (var x in slice)`.
##
## @typeParam T the element type of the slice
## @see ArraySlice.iterate
[Value]
export struct ArraySliceIterator<T> {
    ## The slice being iterated.
    ArraySlice<T> _slice;
    ## The position of the current element in `_slice`; meaningful once `_started` is set.
    ulong _index;
    ## Whether `next()` has been called at least once.
    bool _started;

    ## Advances to the next element.
    ##
    ## @returns true when there is a current element, false once past the end
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    next(): bool {
        _slice._check(__caller_location());
        if (!_started) {
            _started = true;
            return _index < _slice.count;
        }
        if (_index < _slice.count) {
            _index = _index + 1;
        }
        return _index < _slice.count;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    ## @panics if the Array was modified since the slice was made ("Array modified while a slice of it is in use")
    ## @panics if `next()` was never called ("ArraySliceIterator.current() before next()")
    ## @panics if `next()` already returned false ("ArraySlice index out of bounds")
    current(): T {
        assert(_started, "ArraySliceIterator.current() before next()");
        return _slice[_index];
    }
}

extend ArraySliceIterator<T> with Iterator<T>;

# `_ArraySorter` insertion sorts a range this small, or smaller.
const _SORT_INSERTION_SIZE: ulong = 24;
# `_ArraySorter` takes the pivot of a larger range as a median of three medians.
const _SORT_NINTHER_SIZE: ulong = 128;

# One `sort_unstable`, `select_nth` or `partial_sort` of `_array`:
# pattern-defeating quicksort (Orson Peters' pdqsort), which falls back to
# heapsort when partitions keep coming out unbalanced, so it is
# O(count log count) in the worst case with no scratch buffer. Elements only
# trade slots (`_swap`), so no count changes. Every comparison is followed
# by a version check, so a `compare` that changes the Array panics before
# the next slot is read; and every scan is bounded by its range, so even an
# inconsistent `compare` stays in bounds (its result is then just unsorted).
[Value]
struct _ArraySorter<T> {
    Array<T> _array;
    (T, T) => int _compare;
    ulong _version;
    # Whether the last `_partition_right` found the range already partitioned.
    bool _partitioned;

    construct(array: Array<T>, compare: (T, T) => int) {
        array._version = array._version + 1;
        _array = array;
        _compare = compare;
        _version = array._version;
    }

    # Sorts slots `begin` up to `end`.
    sort(begin: ulong, end: ulong) {
        _sort(begin, end, _bad_allowed(end - begin), true);
    }

    # Moves the element a full sort puts at `nth` there, with every element
    # before it sorting before or with it and every element after it after
    # or with it: quickselect on the same partitions as `_sort`.
    select(nth: ulong) {
        ulong begin = 0;
        ulong end = _array._size;
        var bad_allowed = _bad_allowed(end);
        var leftmost = true;
        while (end - begin > _SORT_INSERTION_SIZE) {
            _choose_pivot(begin, end);
            # See `_sort`: every element of the range sorts with or after
            # the pivot, so the equal ones go left and are in place.
            if (!leftmost && !_less(begin - 1, begin)) {
                ulong equal_end = _partition_left(begin, end);
                if (nth <= equal_end) {
                    return;
                }
                begin = equal_end + 1;
                continue;
            }
            ulong size = end - begin;
            ulong pivot = _partition_right(begin, end);
            if (pivot == nth) {
                return;
            }
            if (pivot - begin < size / 8 || end - pivot - 1 < size / 8) {
                bad_allowed = bad_allowed - 1;
                if (bad_allowed == 0) {
                    _heap_sort(begin, end);
                    return;
                }
                _break_patterns(begin, pivot, end);
            }
            if (nth < pivot) {
                end = pivot;
            } else {
                begin = pivot + 1;
                leftmost = false;
            }
        }
        _insertion_sort(begin, end);
    }

    # The number of unbalanced partitions a range of `count` may take
    # before it falls back to heapsort: log2(count), at least 1.
    static _bad_allowed(count: ulong): ulong {
        ulong log = 1;
        while (count > 2) {
            count = count / 2;
            log = log + 1;
        }
        return log;
    }

    # Whether the element at `a` sorts before the one at `b`.
    _less(a: ulong, b: ulong): bool {
        var order = _compare(_array._data[a], _array._data[b]);
        assert(_array._version == _version, "Array modified during sort");
        return order < 0;
    }

    _swap(a: ulong, b: ulong) {
        if (a != b) {
            _array_swap(_array._slot(a), _array._slot(b), sizeof<T>());
        }
    }

    # Orders the elements at `a` and `b`.
    _sort2(a: ulong, b: ulong) {
        if (_less(b, a)) {
            _swap(a, b);
        }
    }

    # Orders the elements at `a`, `b` and `c`.
    _sort3(a: ulong, b: ulong, c: ulong) {
        _sort2(a, b);
        _sort2(b, c);
        _sort2(a, b);
    }

    _sort(begin: ulong, end: ulong, bad_allowed: ulong, leftmost: bool) {
        while (true) {
            ulong size = end - begin;
            if (size <= _SORT_INSERTION_SIZE) {
                _insertion_sort(begin, end);
                return;
            }
            _choose_pivot(begin, end);
            # Outside the leftmost range the element before `begin` is a
            # pivot that sorts before or with every element here. A pivot
            # that sorts with it is the smallest, so the elements equal to it
            # go left and need no more sorting: runs of equal elements cost
            # O(count).
            if (!leftmost && !_less(begin - 1, begin)) {
                begin = _partition_left(begin, end) + 1;
                continue;
            }
            ulong pivot = _partition_right(begin, end);
            bool partitioned = _partitioned;
            if (pivot - begin < size / 8 || end - pivot - 1 < size / 8) {
                bad_allowed = bad_allowed - 1;
                if (bad_allowed == 0) {
                    _heap_sort(begin, end);
                    return;
                }
                _break_patterns(begin, pivot, end);
            } else if (partitioned
                && _partial_insertion_sort(begin, pivot)
                && _partial_insertion_sort(pivot + 1, end)) {
                # Already sorted input stops here, in O(count).
                return;
            }
            _sort(begin, pivot, bad_allowed, leftmost);
            begin = pivot + 1;
            leftmost = false;
        }
    }

    # Moves the median of a sample of the range to `begin`, as the pivot.
    _choose_pivot(begin: ulong, end: ulong) {
        ulong half = (end - begin) / 2;
        if (end - begin > _SORT_NINTHER_SIZE) {
            _sort3(begin, begin + half, end - 1);
            _sort3(begin + 1, begin + half - 1, end - 2);
            _sort3(begin + 2, begin + half + 1, end - 3);
            _sort3(begin + half - 1, begin + half, begin + half + 1);
            _swap(begin, begin + half);
        } else {
            _sort3(begin + half, begin, end - 1);
        }
    }

    # Partitions the range around the pivot at `begin`: elements that sort
    # before it go left, the rest right. Returns the pivot's new position,
    # and sets `_partitioned` when no element had to move.
    _partition_right(begin: ulong, end: ulong): ulong {
        ulong first = begin + 1;
        while (first < end && _less(first, begin)) {
            first = first + 1;
        }
        ulong last = end;
        while (last > first) {
            last = last - 1;
            if (_less(last, begin)) {
                break;
            }
        }
        _partitioned = first >= last;
        while (first < last) {
            _swap(first, last);
            first = first + 1;
            while (first < end && _less(first, begin)) {
                first = first + 1;
            }
            last = last - 1;
            while (last > first && !_less(last, begin)) {
                last = last - 1;
            }
        }
        ulong pivot = first - 1;
        _swap(begin, pivot);
        return pivot;
    }

    # Partitions the range around the pivot at `begin`, elements that sort
    # with it going left; for a pivot no element sorts before. Returns the
    # pivot's new position, the last of the elements equal to it.
    _partition_left(begin: ulong, end: ulong): ulong {
        ulong last = end - 1;
        while (last > begin && _less(begin, last)) {
            last = last - 1;
        }
        ulong first = begin;
        while (first < last) {
            first = first + 1;
            if (_less(begin, first)) {
                break;
            }
        }
        while (first < last) {
            _swap(first, last);
            last = last - 1;
            while (last > first && _less(begin, last)) {
                last = last - 1;
            }
            first = first + 1;
            while (first < last && !_less(begin, first)) {
                first = first + 1;
            }
        }
        _swap(begin, last);
        return last;
    }

    # Swaps a few elements on each side of an unbalanced partition into new
    # places, breaking up the pattern that made it unbalanced.
    _break_patterns(begin: ulong, pivot: ulong, end: ulong) {
        ulong left = pivot - begin;
        ulong right = end - pivot - 1;
        if (left >= _SORT_INSERTION_SIZE) {
            _swap(begin, begin + left / 4);
            _swap(pivot - 1, pivot - left / 4);
            if (left > _SORT_NINTHER_SIZE) {
                _swap(begin + 1, begin + left / 4 + 1);
                _swap(begin + 2, begin + left / 4 + 2);
                _swap(pivot - 2, pivot - left / 4 - 1);
                _swap(pivot - 3, pivot - left / 4 - 2);
            }
        }
        if (right >= _SORT_INSERTION_SIZE) {
            _swap(pivot + 1, pivot + 1 + right / 4);
            _swap(end - 1, end - right / 4);
            if (right > _SORT_NINTHER_SIZE) {
                _swap(pivot + 2, pivot + 2 + right / 4);
                _swap(pivot + 3, pivot + 3 + right / 4);
                _swap(end - 2, end - right / 4 - 1);
                _swap(end - 3, end - right / 4 - 2);
            }
        }
    }

    _insertion_sort(begin: ulong, end: ulong) {
        ulong index = begin + 1;
        while (index < end) {
            ulong at = index;
            while (at > begin && _less(at, at - 1)) {
                _swap(at, at - 1);
                at = at - 1;
            }
            index = index + 1;
        }
    }

    # Insertion sorts the range unless that would move elements more than
    # 8 places in all; returns whether it finished.
    _partial_insertion_sort(begin: ulong, end: ulong): bool {
        ulong moves = 0;
        ulong index = begin + 1;
        while (index < end) {
            ulong at = index;
            while (at > begin && _less(at, at - 1)) {
                _swap(at, at - 1);
                at = at - 1;
            }
            moves = moves + (index - at);
            if (moves > 8) {
                return false;
            }
            index = index + 1;
        }
        return true;
    }

    _heap_sort(begin: ulong, end: ulong) {
        ulong count = end - begin;
        ulong index = count / 2;
        while (index > 0) {
            index = index - 1;
            _sift_down(begin, index, count);
        }
        while (count > 1) {
            count = count - 1;
            _swap(begin, begin + count);
            _sift_down(begin, 0, count);
        }
    }

    # Moves the element at heap position `root` down the max-heap of
    # `count` elements starting at slot `begin`.
    _sift_down(begin: ulong, root: ulong, count: ulong) {
        while (true) {
            ulong child = 2 * root + 1;
            if (child >= count) {
                return;
            }
            if (child + 1 < count && _less(begin + child, begin + child + 1)) {
                child = child + 1;
            }
            if (!_less(begin + root, begin + child)) {
                return;
            }
            _swap(begin + root, begin + child);
            root = child;
        }
    }
}

# The start of an array literal: a new Array holding `first`, whose type
# gives the literal's element type (see `_literal_append`).
export _array_literal<T>(first: T): Array<T> {
    var result = Array<T>();
    result.append(first);
    return result;
}

extend ArrayIterator<T> with Iterator<T>;

extend Array<T> with Copyable<Array<T>>;

extern void memcpy(void* dest, void* src, ulong n);
extern void memmove(void* dest, void* src, ulong n);
extern void memset(void* p, int c, ulong n);

# Copies `size` bytes from `source` to `target`; the two must not overlap.
_array_copy(target: __ptr<void>, source: __ptr<void>, size: ulong) {
    memcpy(target, source, size);
}

# Copies `size` bytes from `source` to `target`, which may overlap.
_array_move(target: __ptr<void>, source: __ptr<void>, size: ulong) {
    memmove(target, source, size);
}

# Sets `size` bytes at `target` to 0.
_array_zero(target: __ptr<void>, size: ulong) {
    memset(target, 0, size);
}

# Exchanges the `size` bytes at `a` with those at `b` (distinct slots of one
# buffer), eight at a time while `size` allows and then byte by byte, with
# no allocation.
_array_swap(a: __ptr<u8>, b: __ptr<u8>, size: ulong) {
    ulong offset = 0;
    if (size % 8 == 0) {
        while (offset < size) {
            __ptr<ulong> x = unsafe_cast<__ptr<ulong>>(a + offset);
            __ptr<ulong> y = unsafe_cast<__ptr<ulong>>(b + offset);
            ulong held = x[0];
            x[0] = y[0];
            y[0] = held;
            offset = offset + 8;
        }
        return;
    }
    while (offset < size) {
        u8 held = a[offset];
        a[offset] = b[offset];
        b[offset] = held;
        offset = offset + 1;
    }
}
