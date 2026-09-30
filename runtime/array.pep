import "internals";

# Elements of a struct-typed Array are references: the constructor initializes
# each to null (zero-init), every store into a slot releases the old occupant
# and acquires the new value (codegen, at the store site), and every place an
# element leaves the live range nulls its slot so the reference is released.
# Shifts (insert backward, remove_at forward) move each reference to its new
# slot with _pep_move_ref, and swap exchanges two slots with _pep_swap_refs:
# a move does not change a reference's count, exactly as moving shared_ptrs
# between slots would not.
#
# Every mutating method (element store, append, insert, remove_at, pop, clear,
# truncate, swap) bumps _version; an ArrayIterator panics when it sees a
# _version other than the one it started with, so modifying an Array while a
# `for` loop iterates it is a panic rather than skipped or repeated elements.

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
export struct Array<T> {
    ## The element buffer: `_capacity` slots, of which the first `_size` hold
    ## live elements and the rest are zeroed (null for struct `T`). Null while
    ## `_capacity` is 0. Internal storage; use the methods instead of touching
    ## it directly.
    __ptr<T> _data;
    ## The number of live elements; always at most `_capacity`. Read it through `count()`.
    ulong _size;
    ## The number of element slots allocated in `_data`; never shrinks. Read it through `capacity()`.
    ulong _capacity;
    ## The modification counter: incremented by every mutating operation so
    ## that an `ArrayIterator` can detect changes made while it runs. Its
    ## value carries no other meaning.
    ulong _version;

    ## Creates an empty Array, optionally preallocating room for `capacity`
    ## elements.
    ##
    ## With the default `capacity` of 0, nothing is allocated until the first
    ## element is added. Preallocating avoids the reallocations `append`
    ## would otherwise perform while the Array grows to a known size.
    ##
    ## @param capacity the number of element slots to allocate up front; `count()` is still 0
    ## @example
    ##     var a = Array<int>(16);   # a.count() == 0, a.capacity() == 16
    construct(ulong capacity = 0) {
        if (capacity > 0) {
            _data = _pep_malloc(sizeof<T>() * capacity);
            _capacity = capacity;
        }
    }

    destruct {
        ulong __i = 0;
        while (__i < _size) {
            _data[__i] = __default<T>();
            __i = __i + 1;
        }
        _pep_free(_data);
    }

    ## Returns an iterator over the elements in index order; this is what
    ## `for (var x in array)` calls (the `Iterable<T>` protocol).
    ##
    ## The iterator holds a reference to the Array, so iterating a temporary
    ## keeps it alive for the whole loop. Modifying the Array while the
    ## iterator is in use makes the iterator's next `next()` or `current()`
    ## panic.
    ##
    ## @returns a new iterator positioned before the first element
    ## @example
    ##     for (var x in a) {
    ##         total = total + x;
    ##     }
    ArrayIterator<T> iterate() {
        var it = ArrayIterator<T>();
        it._source = this;
        it._version = _version;
        return it;
    }

    ## Returns the number of elements in the Array.
    ##
    ## @returns the element count; 0 for an empty Array
    ulong count() {
        return _size;
    }

    ## Returns the number of elements the Array can hold before its buffer
    ## must be reallocated.
    ##
    ## @returns the allocated slot count, which is at least `count()`
    ulong capacity() {
        return _capacity;
    }

    ## Reports whether the Array has no elements.
    ##
    ## @returns true when `count()` is 0
    bool empty() {
        return _size == 0;
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
    ## @example
    ##     var a = Array<int>();
    ##     a.reserve(8);   # a.capacity() >= 8
    ##     a.reserve(2);   # no effect: capacity never shrinks
    void reserve(ulong capacity) {
        if (capacity > _capacity) {
            _data = _pep_realloc(_data, sizeof<T>() * _capacity, sizeof<T>() * capacity);
            _capacity = capacity;
        }
    }

    ## Makes room for one more element: when the buffer is full, doubles its
    ## capacity (to at least 4); otherwise does nothing.
    ##
    ## `append` and `insert` call this themselves; callers rarely need it.
    ## Does not change the elements or invalidate iterators.
    void grow() {
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
    ## @panics if `idx < count()` does not hold ("Array index read out of bounds")
    ## @example
    ##     var first = a[0];
    T [](ulong idx) {
        assert(idx < _size, "Array index read out of bounds");
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
    ## @panics if `idx < count()` does not hold ("Array index write out of bounds")
    ## @example
    ##     a[0] = 42;
    T [](ulong idx, T value) {
        assert(idx < _size, "Array index write out of bounds");
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
    ## @example
    ##     var a = Array<int>();
    ##     a.append(1);
    ##     a.append(2);   # a holds [1, 2]
    void append(T item) {
        _version = _version + 1;
        grow();
        _data[_size] = item;
        _size = _size + 1;
    }

    ## Inserts `item` at position `idx`, shifting the element there and every
    ## later element up by one.
    ##
    ## Runs in O(count - idx), plus a reallocation when the buffer is full.
    ## `idx == count()` appends. For a struct `T` the Array acquires a
    ## reference to `item`; shifted elements keep their reference counts.
    ## Invalidates running iterators.
    ##
    ## @param idx the position `item` will occupy; from 0 through `count()`
    ## @param item the element to insert
    ## @panics if `idx <= count()` does not hold ("Array insert index out of bounds")
    ## @example
    ##     var a = Array<int>();
    ##     a.append(1);
    ##     a.append(3);
    ##     a.insert(1, 2);   # a holds [1, 2, 3]
    void insert(ulong idx, T item) {
        assert(idx <= _size, "Array insert index out of bounds");
        _version = _version + 1;
        grow();
        # Backward shift as a raw pointer move: each slot's reference is
        # transferred to its new position without changing its count, exactly
        # as moving `shared_ptr`s between slots would. A per-slot release/
        # acquire store would destroy elements the Array solely owns (their
        # only reference) and churn counts of externally shared ones.
        ulong cursor = _size;
        while (cursor > idx) {
            _pep_move_ref(_data, sizeof<T>(), cursor - 1, cursor);
            cursor = cursor - 1;
        }
        _data[idx] = item;
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
    ## @panics if `idx < count()` does not hold ("Array remove index out of bounds")
    ## @example
    ##     var a = Array<int>();
    ##     a.append(1);
    ##     a.append(2);
    ##     var x = a.remove_at(0);   # x == 1; a holds [2]
    T remove_at(ulong idx) {
        assert(idx < _size, "Array remove index out of bounds");
        _version = _version + 1;
        T removed = _data[idx];
        # The copy above acquired a reference for `removed`; release the
        # slot's own reference now — the forward shift below overwrites this
        # slot, and a shared_ptr move-assign would release its old occupant.
        _data[idx] = __default<T>();
        # Forward shift as a raw pointer move: each slot's reference is
        # transferred to its new position without changing its count; the
        # vacated tail is nulled so its reference is released. A per-slot
        # release/acquire store would destroy elements the Array solely owns.
        ulong cursor = idx;
        while (cursor + 1 < _size) {
            _pep_move_ref(_data, sizeof<T>(), cursor + 1, cursor);
            cursor = cursor + 1;
        }
        _data[_size - 1] = __default<T>();
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
    T pop() {
        assert(_size > 0, "Array pop on empty Array");
        _version = _version + 1;
        T r = _data[_size - 1];
        _data[_size - 1] = __default<T>();
        _size = _size - 1;
        return r;
    }

    ## Returns the first element without removing it; the same as `a[0]`.
    ##
    ## @returns the element at index 0
    ## @panics if the Array is empty ("Array first on empty Array")
    T first() {
        assert(_size > 0, "Array first on empty Array");
        return _data[0];
    }

    ## Returns the last element without removing it; the same as
    ## `a[a.count() - 1]`.
    ##
    ## @returns the element at index `count() - 1`
    ## @panics if the Array is empty ("Array last on empty Array")
    T last() {
        assert(_size > 0, "Array last on empty Array");
        return _data[_size - 1];
    }

    ## Removes every element, leaving the Array empty.
    ##
    ## Runs in O(count). For a struct `T` each element's reference is
    ## released. The capacity is kept, so refilling the Array does not
    ## reallocate. Always invalidates running iterators, even on an empty
    ## Array.
    void clear() {
        _version = _version + 1;
        ulong __i = 0;
        while (__i < _size) {
            _data[__i] = __default<T>();
            __i = __i + 1;
        }
        _size = 0;
    }

    ## Shortens the Array to its first `count` elements, removing the rest.
    ##
    ## Runs in O(removed elements). For a struct `T` each removed element's
    ## reference is released. A `count` at or above the current `count()`
    ## does nothing (the Array never grows) and leaves iterators valid; an
    ## actual shrink invalidates them. The capacity is kept.
    ##
    ## @param count the number of leading elements to keep
    ## @example
    ##     a.truncate(1);   # keeps only a[0]
    ##     a.truncate(5);   # no effect when a has fewer than 5 elements
    void truncate(ulong count) {
        if (count < _size) {
            _version = _version + 1;
            ulong __i = count;
            while (__i < _size) {
                _data[__i] = __default<T>();
                __i = __i + 1;
            }
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
    ## @panics if `a < count()` does not hold ("Array swap index out of bounds")
    ## @panics if `b < count()` does not hold ("Array swap index out of bounds")
    void swap(ulong a, ulong b) {
        assert(a < _size, "Array swap index out of bounds");
        assert(b < _size, "Array swap index out of bounds");
        _version = _version + 1;
        _pep_swap_refs(_data, sizeof<T>(), a, b);
    }

    ## Reverses the order of the elements in place.
    ##
    ## Runs in O(count) using `swap`, so reference counts are unchanged. An
    ## Array of fewer than two elements is left untouched and its iterators
    ## stay valid; otherwise running iterators are invalidated.
    ##
    ## @example
    ##     a.reverse();   # [1, 2, 3] becomes [3, 2, 1]
    void reverse() {
        if (_size >= 2) {
            ulong lo = 0;
            ulong hi = _size - 1;
            while (lo < hi) {
                swap(lo, hi);
                lo = lo + 1;
                hi = hi - 1;
            }
        }
    }

    ## Returns the position of the first element equal to `item`.
    ##
    ## Runs in O(count), scanning from the front. Elements are compared with
    ## `==`: when `T` declares an `==` operator (as `String` does) that
    ## operator decides; for any other struct `T` it compares references, so
    ## only the very same object matches.
    ##
    ## @param item the value to look for
    ## @returns the index of the first match, or -1 when no element matches
    ## @example
    ##     var i = a.find(9);   # -1 if a holds no 9
    long find(T item) {
        ulong idx = 0;
        while (idx < _size) {
            if (_data[idx] == item) {
                return idx;
            }
            idx = idx + 1;
        }
        return -1;
    }

    ## Reports whether any element equals `item`, compared as `find` does.
    ##
    ## Runs in O(count).
    ##
    ## @param item the value to look for
    ## @returns true when `find(item)` finds a match
    bool contains(T item) {
        return find(item) >= 0;
    }

    ## Appends every element of `rhs`, in order, to the end of this Array.
    ##
    ## Runs in O(count of `rhs`), reserving the needed capacity once up
    ## front. `rhs` is unchanged, and it may be this same Array
    ## (`a.append_all(a)` doubles `a`). For a struct `T` each appended element
    ## is acquired once more, since both Arrays now hold it. Invalidates this
    ## Array's running iterators when `rhs` is not empty.
    ##
    ## @param rhs the Array whose elements are copied
    ## @see +=
    void append_all(Array<T> rhs) {
        # Snapshot the bound: with `a += a` (rhs aliases this), appending
        # grows _size and an unbounded loop would never terminate.
        ulong n = rhs._size;
        reserve(_size + n);
        ulong idx = 0;
        while (idx < n) {
            append(rhs._data[idx]);
            idx = idx + 1;
        }
    }

    ## Returns a new Array holding the same elements in the same order.
    ##
    ## Runs in O(count). The copy is shallow: for a struct `T` both Arrays
    ## refer to the same element objects (each acquired once more), but adding
    ## or removing elements in one does not affect the other. The new Array's
    ## capacity equals this Array's `count()`.
    ##
    ## @returns an independent Array with the same elements
    ## @example
    ##     var b = a.clone();
    ##     b.append(7);   # a is unchanged
    Array<T> clone() {
        Array<T> result = Array<T>(_size);
        result.append_all(this);
        return result;
    }

    ## Returns a deep copy: a new Array holding a copy of each element, made
    ## with `copies.copy`. This is how `copy(value)` copies an Array (the
    ## `Copyable<Array<T>>` implementation); call `copy(array)` rather than
    ## this method.
    ##
    ## Unlike `clone()`, which shares struct elements, the result shares no
    ## element that is not thread-safe with this Array. An element that
    ## appears twice is copied once. Runs in O(count) plus the cost of
    ## copying the elements.
    ##
    ## @param copies the objects copied so far
    ## @returns the copy
    ## @example
    ##     var names = Array<String>();
    ##     names.append("ada");
    ##     var copied = copy(names);   # calls this method
    Array<T> copy(Copies copies) {
        Array<T> made = Array<T>(_size);
        copies.register<Array<T>>(this, made);
        ulong i = 0;
        while (i < _size) {
            made.append(copies.copy<T>(_data[i]));
            i = i + 1;
        }
        return made;
    }

    ## Reports whether both Arrays have the same count and pairwise equal
    ## elements, compared with `==` as `find` does.
    ##
    ## Runs in O(count); stops at the first difference. Two empty Arrays are
    ## equal. `capacity()` is not compared.
    ##
    ## @param rhs the Array to compare with
    ## @returns true when the Arrays are element-wise equal
    bool ==(Array<T> rhs) {
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
    bool !=(Array<T> rhs) {
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
    Array<T> +=(Array<T> rhs) {
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
    Array<T> +(Array<T> rhs) {
        Array<T> result = clone();
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
## `next()` or `current()` panics instead of skipping or repeating elements.
##
## @typeParam T the element type of the source Array
## @example
##     var it = a.iterate();
##     while (it.next()) {
##         var x = it.current();
##     }
## @see Array.iterate
export struct ArrayIterator<T> {
    ## The Array being iterated; the iterator holds a reference to it for its whole lifetime.
    Array<T> _source;
    ## The position of the current element in `_source`. Meaningful only after
    ## `_started` is set; equals `_source.count()` once iteration has finished.
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
    bool next() {
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
    T current() {
        assert(_source._version == _version, "Array modified during iteration");
        assert(_started, "ArrayIterator.current() before next()");
        assert(_index < _source._size, "ArrayIterator.current() past the end");
        return _source[_index];
    }
}

extend ArrayIterator<T> with Iterator<T> {}

extend Array<T> with Copyable<Array<T>> {}
