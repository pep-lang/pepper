import "internals";

# `append` and `grow` bump Version; a StringIterator panics when it sees a
# Version other than the one it started with (modified during iteration).
export struct String {
    __ptr<char> Data;
    ulong Length;
    ulong Size;
    ulong Version;

    construct(__ptr<char> data = __null, this.Size = 0, this.Length = 0) {
        if (data) {
            # Size is the authoritative byte length; inline NULs are legal in
            # UTF-8 data, so it is never derived from a terminator. A raw
            # `char*` with no size is a C String by contract: measure it once
            # to bound the char-count derivation below.
            if (Size == 0) {
                var src = _pep_c_strlen(data);
                Size = _pep_utf8_size(data, src, Length);
            }
            Data = _pep_malloc(Size + 1);
            memcpy(Data, data, Size);
            Data[Size] = 0;
        }
    }

    destruct {
        _pep_free(Data);
    }

    static ulong length_of(__ptr<char> data, ulong size) {
        return _pep_utf8_length(data, size);
    }

    ulong length() {
        return Length;
    }

    void grow(ulong newSize) {
        if (newSize > Size) {
            Version = Version + 1;
            Data = _pep_realloc(Data, Size + 1, newSize + 1);
            Size = newSize;
            Data[Size] = 0;
        }
    }

    void append(String rhs) {
        Version = Version + 1;
        ulong oldSize = Size;
        grow(Size + rhs.Size);
        memcpy(Data + oldSize, rhs.Data, rhs.Size);
        Length += rhs.Length;
        Data[Size] = 0;
    }

    String [](int idx) {
        # Normalize a negative index to the end-relative offset *before* the
        # bounds check: `idx < Length` compares int against ulong, which
        # promotes to unsigned (a negative idx would wrap to ~2^64).
        if (Length > 0) {
            while (idx < 0) {
                idx += Length;
            }
        }
        assert(idx < Length, "String[] idx must be < length");
        ulong begin = _pep_utf8_char_offset(Data, Size, idx);
        return String(Data + begin, 0, 1);
    }

    bool ==(String rhs) {
        if (Length != rhs.Length) {
            return false;
        }
        if (Size == 0) {
            return true;
        }
        bool eq = _pep_utf8_compare(Data, Size, rhs.Data, rhs.Size, Size);
        return eq;
    }

    String +=(String rhs) {
        append(rhs);
        return this;
    }

    ulong size() {
        return Size;
    }

    # Iterable<String>: `for (var c in s)` visits each code point as a
    # one-code-point String, the same value `s[i]` gives.
    StringIterator iterate() {
        var it = StringIterator();
        it.Source = this;
        it.Version = Version;
        return it;
    }

    bool empty() {
        return Length == 0;
    }

    __ptr<char> c_str() {
        return Data;
    }

    String clone() {
        return String(Data, Size, Length);
    }

    long find(String needle) {
        return _pep_utf8_find(Data, Size, needle.Data, needle.Size);
    }

    bool contains(String needle) {
        return find(needle) >= 0;
    }

    bool starts_with(String prefix) {
        if (prefix.Size > Size) {
            return false;
        }
        if (prefix.Size == 0) {
            return true;
        }
        return _pep_utf8_compare(Data, Size, prefix.Data, prefix.Size, prefix.Size);
    }

    bool ends_with(String suffix) {
        if (suffix.Size > Size) {
            return false;
        }
        if (suffix.Size == 0) {
            return true;
        }
        return _pep_utf8_compare(Data + (Size - suffix.Size), Size, suffix.Data, suffix.Size, suffix.Size);
    }

    String substr(ulong start, ulong count) {
        if (start >= Length) {
            return String();
        }
        ulong begin = _pep_utf8_char_offset(Data, Size, start);
        # Clamp the requested character count to what remains in the String.
        ulong avail = length_of(Data + begin, Size - begin);
        if (count > avail) {
            count = avail;
        }
        ulong len = _pep_utf8_char_offset(Data + begin, Size - begin, count);
        return String(Data + begin, len, count);
    }

    bool !=(String rhs) {
        return !(this == rhs);
    }

    String +(String rhs) {
        String result = clone();
        result.append(rhs);
        return result;
    }
}

# Iterator<String> over a String's code points (String.iterate()). Walks the
# UTF-8 bytes forward, so a whole loop is O(size) rather than an O(size)
# `s[i]` lookup per index.
export struct StringIterator {
    String Source;
    # Byte offsets of the current code point and of the one after it.
    ulong Offset;
    ulong NextOffset;
    ulong Version;
    bool Started;

    # Advance to the next code point; false once past the end (and after).
    bool next() {
        assert(Source.Version == Version, "String modified during iteration");
        if (Started) {
            Offset = NextOffset;
        } else {
            Started = true;
        }
        if (Offset >= Source.Size) {
            NextOffset = Offset;
            return false;
        }
        NextOffset = Offset + _pep_utf8_char_offset(Source.Data + Offset, Source.Size - Offset, 1);
        return true;
    }

    # The code point the last successful next() moved to.
    String current() {
        assert(Source.Version == Version, "String modified during iteration");
        assert(Started, "StringIterator.current() before next()");
        assert(Offset < Source.Size, "StringIterator.current() past the end");
        return String(Source.Data + Offset, NextOffset - Offset, 1);
    }
}
