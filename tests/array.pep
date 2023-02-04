
use internals;
use support;

struct array<T> {
    __ptr<T> Data;
    ulong Size;
    ulong Capacity;

    new(this.Data = __null, this.Size = 0) {
        Capacity = Size;
    }

    del() {
        clear();
        _pep_free(Data);
    }
}

extend array<T> {
    ulong count() { return Size; }

    void clear() {
        if (!__is_pod<T>()) {
            ulong idx = 0;
            while (idx < Size) {
                trace_region(Data, Capacity* sizeof<T>(), "array.clear");
                release<T>(Data[idx++]);
            }
            trace_region(Data, Capacity * sizeof<T>(), "array.dtor");
        }
        Size = 0;
    }

    T [](ulong idx) {
        assert(idx < Size, "array index read out of bounds");
        return Data[idx];
    }

    T [](ulong idx, T value) {
        assert(idx < Size, "array index write out of bounds");
        Data[idx] = value;
        return Data[idx];
    }

    void append(T item) {
        if (Capacity - Size == 0) {
            Data = _pep_realloc(Data, sizeof<T>() * Capacity, sizeof<T>() * (++Capacity));
        }
        Data[Size++] = item;
        trace_region(Data, Capacity * sizeof<T>(), "array data");
    }
}
