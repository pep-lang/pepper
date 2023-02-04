
use internals;

struct string {
    __ptr<char> Data;
    ulong Size;

    new(__ptr<char> data = __null, this.Size = 0) {
        if (data) {
            Data = _pep_malloc(Size);
            memcpy(Data, data, Size);
        }
    }

    destruct {
        _pep_free(Data);
    }

    ulong length() {
        return Size;
    }

    void grow(ulong newSize) {
        if (newSize > Size) {
            Data = _pep_realloc(Data, Size, newSize);
            Size = newSize;
        }
    }

    void append(string rhs) {
        const oldSize = Size;
        grow(Size + rhs.Size);
        memcpy(Data, rhs.Data, Size);
    }
}
