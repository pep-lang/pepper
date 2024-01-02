
use internals;

struct array<T> {
    __ptr<T> Data;
    ulong Size;
    ulong Capacity;

    new(this.Data = __null, this.Size = 0) {
        Capacity = Size;
    }

    destruct {
        this.clear();
        _pep_free(Data);
    }

    ulong count() { return Size; }

    void clear() {
        if (!__is_pod<T>()) {
            ulong idx = 0;
            while (idx < Size) {
                release<T>(Data[idx++]);
            }
        }
        Size = 0;
    }

    T [](ulong idx) {
        assert(idx < Size, @"array index read out of bounds");
        # allow negative indices to index from the end
        while (idx < 0 && Size > 0) {
            idx += Size;
        }

        return Data[idx];
    }

    T [](ulong idx, T value) {
        assert(idx < Size, @"array index write out of bounds");
        # allow negative indices to index from the end
        while (idx < 0 && Size > 0) {
            idx += Size;
        }

        Data[idx] = value;
        return Data[idx];
    }

    void append(T item) {
        if (Capacity - Size == 0) {
            Data = _pep_realloc(Data, sizeof<T>() * Capacity, sizeof<T>() * (++Capacity));
        }
        Data[Size++] = item;
    }
}
