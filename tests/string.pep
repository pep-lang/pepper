
use internals;

extern ulong _pep_utf8_length(char* str);
extern ulong _pep_utf8_size(char* str, uint chars);
extern  bool _pep_utf8_compare(char* a, char* b, uint size);

extern int strncmp(char* a, char* b, uint size);

struct string {
    __ptr<char> Data;
    ulong Length;
    ulong Size;

    new(__ptr<char> data = __null, this.Size = 0, this.Length = 0) {
        if (data) {
            if (Size == 0) {
                # This will either compute the size using the supplied length or it will find the 0 terminator
                Size = _pep_utf8_size(data, Length);
            }
            if (Length == 0) {
                Length = length_of(data);
            }
            Data = _pep_malloc(Size + 1);
            memcpy(Data, data, Size);
            Data[Size] = 0;
        }
    }

    destruct {
        trace_ptr(Data, @"string.Data");
        trace_ptr(this, Data);
        _pep_free(Data);
    }

    static ulong length_of(__ptr<char> c_str) {
        return _pep_utf8_length(c_str);
    }

    ulong length() {
        return Length;
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
        memcpy(Data + oldSize, rhs.Data, Size);
        Length += rhs.length();
    }

    string [](int idx) {
        assert(idx < Length, @"string[] idx must be < length");
        # allow negative indices to index from the end
        if (Length > 0) {
            while (idx < 0) {
                idx += Length;
            }
        }
        return string(Data + idx, 0, 1);
    }

    bool ==(string rhs) {
        trace_ptr(this, @"this");
        trace_ptr(rhs, @"rhs");
        if (Length != rhs.Length) {
            return false;
        }
        var eq = _pep_utf8_compare(Data, rhs.Data, Length);
        return eq;
    }

    string +=(string rhs) {
        append(rhs);
        return this;
    }
}
