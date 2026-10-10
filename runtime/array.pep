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
# `[__Lazy]` (#652): an empty Array is a null reference until it is written
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
## `insert`, `remove_at`, `pop`, `clear`, a shrinking `truncate`, `swap`, and
## `reverse` of two or more elements) invalidates running iterators, and the
## next step of such a loop panics with "Array modified during iteration".
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
            _data = _pep_realloc(_data, sizeof<T>() * _capacity, sizeof<T>() * capacity);
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
            ulong low = 0;
            ulong high = _size - 1;
            while (low < high) {
                _array_swap(_slot(low), _slot(high), sizeof<T>());
                low = low + 1;
                high = high - 1;
            }
        }
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
        # Snapshot the count, and read `rhs._data` only after growing: with
        # `a += a` (rhs aliases this) both change.
        ulong count = rhs._size;
        if (count == 0) {
            return;
        }
        _version = _version + 1;
        _reserve_extra(count);
        _array_copy(_slot(_size), rhs._data, count * sizeof<T>());
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
