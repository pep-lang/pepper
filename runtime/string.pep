import "internals";

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
            Data = _pep_realloc(Data, Size + 1, newSize + 1);
            Size = newSize;
            Data[Size] = 0;
        }
    }

    void append(string rhs) {
        ulong oldSize = Size;
        grow(Size + rhs.Size);
        memcpy(Data + oldSize, rhs.Data, rhs.Size);
        Length += rhs.Length;
        Data[Size] = 0;
    }

    string [](int idx) {
        # Normalize a negative index to the end-relative offset *before* the
        # bounds check: `idx < Length` compares int against ulong, which
        # promotes to unsigned (a negative idx would wrap to ~2^64).
        if (Length > 0) {
            while (idx < 0) {
                idx += Length;
            }
        }
        assert(idx < Length, "string[] idx must be < length");
        ulong begin = _pep_utf8_char_offset(Data, Size, idx);
        return string(Data + begin, 0, 1);
    }

    bool ==(string rhs) {
        if (Length != rhs.Length) {
            return false;
        }
        if (Size == 0) {
            return true;
        }
        bool eq = _pep_utf8_compare(Data, rhs.Data, Size);
        return eq;
    }

    string +=(string rhs) {
        append(rhs);
        return this;
    }

    ulong size() {
        return Size;
    }

    bool empty() {
        return Length == 0;
    }

    __ptr<char> c_str() {
        return Data;
    }

    string clone() {
        return string(Data, Size, Length);
    }

    long find(string needle) {
        return _pep_utf8_find(Data, Size, needle.Data, needle.Size);
    }

    bool contains(string needle) {
        return find(needle) >= 0;
    }

    bool starts_with(string prefix) {
        if (prefix.Size > Size) {
            return false;
        }
        if (prefix.Size == 0) {
            return true;
        }
        return _pep_utf8_compare(Data, prefix.Data, prefix.Size);
    }

    bool ends_with(string suffix) {
        if (suffix.Size > Size) {
            return false;
        }
        if (suffix.Size == 0) {
            return true;
        }
        return _pep_utf8_compare(Data + (Size - suffix.Size), suffix.Data, suffix.Size);
    }

    string substr(ulong start, ulong count) {
        if (start >= Length) {
            return string();
        }
        ulong begin = _pep_utf8_char_offset(Data, Size, start);
        # Clamp the requested character count to what remains in the string.
        ulong avail = length_of(Data + begin);
        if (count > avail) {
            count = avail;
        }
        ulong len = _pep_utf8_char_offset(Data + begin, Size - begin, count);
        return string(Data + begin, len, count);
    }

    bool !=(string rhs) {
        return !(this == rhs);
    }

    string +(string rhs) {
        string result = clone();
        result.append(rhs);
        return result;
    }
}
