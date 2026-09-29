import "internals";

# Elements of a struct-typed Array are references: the constructor initializes
# each to null (zero-init), every store into a slot releases the old occupant
# and acquires the new value (codegen, at the store site), and every place an
# element leaves the live range nulls its slot so the reference is released.
# Shifts therefore use store semantics (insert backward, remove_at forward) so
# each moved reference is re-counted in its new slot; swap exchanges raw
# pointer slots via _pep_swap_refs because it moves two references without
# changing their count.
#
# Every mutating method (element store, append, insert, remove_at, pop, clear,
# truncate, swap) bumps Version; an ArrayIterator panics when it sees a
# Version other than the one it started with, so modifying an Array while a
# `for` loop iterates it is a panic rather than skipped or repeated elements.

export struct Array<T> {
    __ptr<T> Data;
    ulong Size;
    ulong Capacity;
    ulong Version;

    new(ulong capacity = 0) {
        if (capacity > 0) {
            Data = _pep_malloc(sizeof<T>() * capacity);
            Capacity = capacity;
        }
    }

    destruct {
        ulong __i = 0;
        while (__i < Size) {
            Data[__i] = __default<T>();
            __i = __i + 1;
        }
        _pep_free(Data);
    }

    # Iterable<T>: `for (var x in array)` visits each element in order.
    ArrayIterator<T> iterate() {
        var it = ArrayIterator<T>();
        it.Source = this;
        it.Version = Version;
        return it;
    }

    ulong count() {
        return Size;
    }

    ulong capacity() {
        return Capacity;
    }

    bool empty() {
        return Size == 0;
    }

    void reserve(ulong capacity) {
        if (capacity > Capacity) {
            Data = _pep_realloc(Data, sizeof<T>() * Capacity, sizeof<T>() * capacity);
            Capacity = capacity;
        }
    }

    void grow() {
        if (Size >= Capacity) {
            ulong next = Capacity * 2;
            if (next < 4) {
                next = 4;
            }
            reserve(next);
        }
    }

    T [](ulong idx) {
        assert(idx < Size, "Array index read out of bounds");
        return Data[idx];
    }

    T [](ulong idx, T value) {
        assert(idx < Size, "Array index write out of bounds");
        Version = Version + 1;
        Data[idx] = value;
        return Data[idx];
    }

    void append(T item) {
        Version = Version + 1;
        grow();
        Data[Size] = item;
        Size = Size + 1;
    }

    void insert(ulong idx, T item) {
        assert(idx <= Size, "Array insert index out of bounds");
        Version = Version + 1;
        grow();
        # Backward shift as a raw pointer move: each slot's reference is
        # transferred to its new position without changing its count, exactly
        # as moving `shared_ptr`s between slots would. A per-slot release/
        # acquire store would destroy elements the Array solely owns (their
        # only reference) and churn counts of externally shared ones.
        ulong cursor = Size;
        while (cursor > idx) {
            _pep_move_ref(Data, sizeof<T>(), cursor - 1, cursor);
            cursor = cursor - 1;
        }
        Data[idx] = item;
        Size = Size + 1;
    }
    T remove_at(ulong idx) {
        assert(idx < Size, "Array remove index out of bounds");
        Version = Version + 1;
        T removed = Data[idx];
        # The copy above acquired a reference for `removed`; release the
        # slot's own reference now — the forward shift below overwrites this
        # slot, and a shared_ptr move-assign would release its old occupant.
        Data[idx] = __default<T>();
        # Forward shift as a raw pointer move: each slot's reference is
        # transferred to its new position without changing its count; the
        # vacated tail is nulled so its reference is released. A per-slot
        # release/acquire store would destroy elements the Array solely owns.
        ulong cursor = idx;
        while (cursor + 1 < Size) {
            _pep_move_ref(Data, sizeof<T>(), cursor + 1, cursor);
            cursor = cursor + 1;
        }
        Data[Size - 1] = __default<T>();
        Size = Size - 1;
        return removed;
    }

    T pop() {
        assert(Size > 0, "Array pop on empty Array");
        Version = Version + 1;
        T r = Data[Size - 1];
        Data[Size - 1] = __default<T>();
        Size = Size - 1;
        return r;
    }

    T first() {
        assert(Size > 0, "Array first on empty Array");
        return Data[0];
    }

    T last() {
        assert(Size > 0, "Array last on empty Array");
        return Data[Size - 1];
    }

    void clear() {
        Version = Version + 1;
        ulong __i = 0;
        while (__i < Size) {
            Data[__i] = __default<T>();
            __i = __i + 1;
        }
        Size = 0;
    }

    void truncate(ulong count) {
        if (count < Size) {
            Version = Version + 1;
            ulong __i = count;
            while (__i < Size) {
                Data[__i] = __default<T>();
                __i = __i + 1;
            }
            Size = count;
        }
    }

    void swap(ulong a, ulong b) {
        assert(a < Size, "Array swap index out of bounds");
        assert(b < Size, "Array swap index out of bounds");
        Version = Version + 1;
        _pep_swap_refs(Data, sizeof<T>(), a, b);
    }

    void reverse() {
        if (Size >= 2) {
            ulong lo = 0;
            ulong hi = Size - 1;
            while (lo < hi) {
                swap(lo, hi);
                lo = lo + 1;
                hi = hi - 1;
            }
        }
    }

    long find(T item) {
        ulong idx = 0;
        while (idx < Size) {
            if (Data[idx] == item) {
                return idx;
            }
            idx = idx + 1;
        }
        return -1;
    }

    bool contains(T item) {
        return find(item) >= 0;
    }

    void append_all(Array<T> rhs) {
        # Snapshot the bound: with `a += a` (rhs aliases this), appending
        # grows Size and an unbounded loop would never terminate.
        ulong n = rhs.Size;
        reserve(Size + n);
        ulong idx = 0;
        while (idx < n) {
            append(rhs.Data[idx]);
            idx = idx + 1;
        }
    }

    Array<T> clone() {
        Array<T> result = Array<T>(Size);
        result.append_all(this);
        return result;
    }

    bool ==(Array<T> rhs) {
        if (Size != rhs.Size) {
            return false;
        }
        ulong idx = 0;
        while (idx < Size) {
            if (!(Data[idx] == rhs.Data[idx])) {
                return false;
            }
            idx = idx + 1;
        }
        return true;
    }

    bool !=(Array<T> rhs) {
        return !(this == rhs);
    }

    Array<T> +=(Array<T> rhs) {
        append_all(rhs);
        return this;
    }

    Array<T> +(Array<T> rhs) {
        Array<T> result = clone();
        result.append_all(rhs);
        return result;
    }
}


# Iterator<T> over an Array (Array.iterate()). Holds a reference to the
# Array, so iterating a temporary keeps it alive for the whole loop.
export struct ArrayIterator<T> {
    Array<T> Source;
    ulong Index;
    ulong Version;
    bool Started;

    # Advance to the next element; false once past the end (and after).
    bool next() {
        assert(Source.Version == Version, "Array modified during iteration");
        if (Started) {
            if (Index < Source.Size) {
                Index = Index + 1;
            }
        } else {
            Started = true;
        }
        return Index < Source.Size;
    }

    # The element the last successful next() moved to.
    T current() {
        assert(Source.Version == Version, "Array modified during iteration");
        assert(Started, "ArrayIterator.current() before next()");
        assert(Index < Source.Size, "ArrayIterator.current() past the end");
        return Source[Index];
    }
}
