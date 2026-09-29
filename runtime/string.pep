import "internals";

extern void memcpy(void* dest, void* src, ulong n);

## A mutable, reference-counted string of UTF-8 text. String literals
## (`"text"`) are `String` values.
##
## Two measures describe a String, and each API says which one it uses:
##
## - **Code points** (Unicode characters): `Length`, `length()`, `empty()`,
##   the indexer `s[i]`, `substr`, and iteration.
## - **Bytes** of UTF-8: `Size`, `size()`, `find`, `starts_with`, and
##   `ends_with`. `Size` is the authoritative length, so the data may
##   contain NUL bytes. It is never derived from a terminator.
##
## A String is a reference type: `var b = a;` shares one object, so
## `append`, `+=`, and `grow` are visible through every reference. Use
## `clone()` or `+` for an independent copy. Equality (`==`) compares
## content.
##
## `append`, `+=`, and `grow` increment `Version`. A `StringIterator`
## panics when it sees a `Version` other than the one it started with, so
## modifying a String while a `for` loop iterates it panics.
##
## @example
##     var s = "héllo";
##     assert(s.length() == 5, "5 code points");
##     assert(s.size() == 6, "6 bytes: 'é' is 2");
##     s.append(" world");
##     assert(s.find("world") == 7, "find returns a byte offset");
##     assert(s[1] == "é", "the indexer counts code points");
##     for (var c in s) {
##         print(c);   # one code point per line
##     }
export struct String {
    ## The heap buffer: `Size` bytes of UTF-8 followed by a NUL terminator,
    ## or `__null` for a String built with no data (`String()`). The String
    ## owns it and frees it on destruction. `append` and `grow` may move it.
    __ptr<char> Data;
    ## The number of Unicode code points. The constructor and `append` keep
    ## it current; `grow` does not update it.
    ulong Length;
    ## The number of bytes of UTF-8 in `Data`, not counting the NUL terminator.
    ulong Size;
    ## A modification counter, incremented by `append` and `grow`. A
    ## `StringIterator` compares it to detect modification during iteration.
    ## `clone()` starts the copy at 0.
    ulong Version;

    ## Creates a String by copying `Size` bytes of `data` into a new
    ## NUL-terminated buffer. With no arguments, it creates an empty String
    ## whose `Data` is `__null`.
    ##
    ## When `data` is not `__null` and `Size` is 0, `data` is treated as a
    ## NUL-terminated C string:
    ##
    ## - with `Length` nonzero, `Size` becomes the byte length of its first
    ##   `Length` code points (0 if the C string is not valid UTF-8);
    ## - with `Length` 0, `Size` becomes the C string's whole byte length.
    ##
    ## When `Length` is 0, it is counted from the bytes. A nonzero `Length` is
    ## trusted, not checked against the data. Runs in O(Size).
    ##
    ## @param data the bytes to copy; `__null` for an empty String (then pass
    ##   no sizes, because they are stored as given)
    ## @param this.Size the number of bytes to copy from `data`; 0 treats `data` as
    ##   a NUL-terminated C string
    ## @param this.Length the number of code points in those bytes
    ## @example
    ##     var empty = String();
    ##     var s = "abc";
    ##     var copy = String(s.c_str(), s.size(), s.length());
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
            # Callers that know only the bytes (`String(ptr)`,
            # `String(ptr, size)`) leave the character count to be derived.
            if (Length == 0) {
                Length = _pep_utf8_length(data, Size);
            }
            Data = _pep_malloc(Size + 1);
            memcpy(Data, data, Size);
            Data[Size] = 0;
        }
    }

    destruct {
        _pep_free(Data);
    }

    ## Returns the number of Unicode code points in the first `size` bytes at
    ## `data`. Runs in O(size).
    ##
    ## Returns 0 when `data` is `__null`, when `size` is 0, or when the bytes
    ## are not valid UTF-8: any malformed or truncated sequence makes the
    ## whole count 0.
    ##
    ## @param data the UTF-8 bytes to measure
    ## @param size the number of bytes to measure
    ## @returns the number of code points, or 0 for invalid UTF-8
    static ulong length_of(__ptr<char> data, ulong size) {
        return _pep_utf8_length(data, size);
    }

    ## Returns the number of Unicode code points (`Length`). O(1).
    ##
    ## @returns the length in code points, not bytes
    ## @see size
    ulong length() {
        return Length;
    }

    ## Extends the byte buffer to `newSize` bytes and fills the new bytes
    ## with zeros. Does nothing when `newSize` is not greater than `Size`.
    ##
    ## A low-level primitive for `append`. It sets `Size` but not `Length`,
    ## so the zero bytes it adds are not counted as code points until the
    ## caller overwrites them and fixes `Length`. When it grows the buffer,
    ## it increments `Version` and may reallocate `Data`, which invalidates
    ## pointers from `c_str()`. Runs in O(newSize).
    ##
    ## @param newSize the new byte length
    void grow(ulong newSize) {
        if (newSize > Size) {
            Version = Version + 1;
            Data = _pep_realloc(Data, Size + 1, newSize + 1);
            Size = newSize;
            Data[Size] = 0;
        }
    }

    ## Appends the content of `rhs` to this String in place, updating `Size`
    ## and `Length`.
    ##
    ## Always increments `Version`, even when `rhs` is empty, so appending
    ## during iteration panics. It may reallocate `Data`. Every reference to
    ## this String sees the change. Runs in O(Size + rhs.Size).
    ##
    ## @param rhs the String to append; it is not modified
    ## @example
    ##     var s = "TEST";
    ##     s.append("ING");   # s == "TESTING"
    void append(String rhs) {
        Version = Version + 1;
        # Read rhs before growing: `s.append(s)` makes rhs this String, whose
        # Size grow() changes and whose Data it may move.
        ulong oldSize = Size;
        ulong addSize = rhs.Size;
        ulong addLength = rhs.Length;
        grow(Size + addSize);
        memcpy(Data + oldSize, rhs.Data, addSize);
        Length += addLength;
        Data[Size] = 0;
    }

    ## Returns the code point at code-point index `idx` as a new
    ## one-code-point String.
    ##
    ## A negative `idx` counts from the end (`s[-1]` is the last code point).
    ## `Length` is added until the index is non-negative, so any negative
    ## index wraps, and `s[-7]` of a 3-code-point String is `s[2]`. Runs in
    ## O(idx) because it walks the UTF-8 bytes. Use `for (var c in s)` to
    ## visit every code point in O(size).
    ##
    ## @param idx the code-point index; negative counts from the end
    ## @returns a new String that holds the one code point
    ## @panics if `idx` is not less than `length()` after the negative index is
    ##   normalized, which includes any index into an empty String
    ## @example
    ##     var s = "TEST";
    ##     assert(s[0] == "T", "first");
    ##     assert(s[-1] == "T", "last");
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

    ## Returns whether this String and `rhs` have the same content, compared
    ## byte by byte. Strings with different `Length` are unequal without
    ## comparing bytes. Runs in O(Size).
    ##
    ## @param rhs the String to compare with
    ## @returns true when both hold the same bytes
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

    ## Appends `rhs` in place, like `append`, and returns this same String,
    ## not a copy. `s += t` modifies the object that every reference to `s`
    ## shares, and increments `Version`.
    ##
    ## @param rhs the String to append
    ## @returns this String, after appending
    ## @example
    ##     var s = "a";
    ##     s += "b";   # s == "ab"
    String +=(String rhs) {
        append(rhs);
        return this;
    }

    ## Returns the number of bytes of UTF-8 (`Size`), not counting the NUL
    ## terminator. O(1).
    ##
    ## @returns the length in bytes, not code points
    ## @see length
    ulong size() {
        return Size;
    }

    ## Returns an iterator over the String's code points, which makes String
    ## `Iterable<String>`: `for (var c in s)` visits each code point as a
    ## one-code-point String, the same value `s[i]` gives.
    ##
    ## The iterator holds a reference to this String. The whole loop runs in
    ## O(size). Modifying the String during iteration makes the iterator
    ## panic.
    ##
    ## @returns a new iterator, positioned before the first code point
    ## @example
    ##     var n = 0;
    ##     for (var c in "héllo") {
    ##         n = n + 1;   # 5 iterations
    ##     }
    StringIterator iterate() {
        var it = StringIterator();
        it.Source = this;
        it.Version = Version;
        return it;
    }

    ## Returns whether the String has no code points (`Length` is 0). O(1).
    ##
    ## @returns true when `length()` is 0
    bool empty() {
        return Length == 0;
    }

    ## Returns the String's buffer as a NUL-terminated C string (`Data`).
    ##
    ## The pointer is owned by the String. It is valid until the String is
    ## destroyed or `append`, `+=`, or `grow` reallocates it. It is `__null`
    ## for a String built with no data (`String()`), so check it before you
    ## pass it to C. C functions stop at the first NUL byte in the content.
    ##
    ## @returns the String's NUL-terminated byte buffer, or `__null`
    __ptr<char> c_str() {
        return Data;
    }

    ## Returns a new String with the same content and its own buffer, so
    ## later changes to either String do not affect the other. The copy's
    ## `Version` starts at 0. Runs in O(Size).
    ##
    ## @returns an independent copy of this String
    String clone() {
        return String(Data, Size, Length);
    }

    ## Returns the **byte offset** of the first occurrence of `needle`, or -1
    ## when it does not occur.
    ##
    ## The offset counts bytes, not code points. To use it with `s[i]` or
    ## `substr`, convert it with `String.length_of(s.c_str(), offset)`.
    ## An empty `needle` is found at 0 unless this String is empty, in which
    ## case the result is -1. The result is also -1 when either String is not
    ## valid UTF-8. Runs in O(Size * needle.Size).
    ##
    ## @param needle the text to search for
    ## @returns the byte offset of the first match, or -1 when there is none
    ## @example
    ##     var s = "TESTING";
    ##     assert(s.find("STI") == 2, "byte offset");
    ##     assert(s.find("xyz") == -1, "absent");
    long find(String needle) {
        return _pep_utf8_find(Data, Size, needle.Data, needle.Size);
    }

    ## Returns whether `needle` occurs in this String (`find(needle) >= 0`).
    ## Because of that, an empty String contains nothing, not even `""`.
    ## Runs in O(Size * needle.Size).
    ##
    ## @param needle the text to search for
    ## @returns true when `needle` occurs
    bool contains(String needle) {
        return find(needle) >= 0;
    }

    ## Returns whether this String begins with the bytes of `prefix`. An
    ## empty `prefix` always matches. Runs in O(prefix.Size).
    ##
    ## @param prefix the text to test for
    ## @returns true when the first `prefix.size()` bytes equal `prefix`
    bool starts_with(String prefix) {
        if (prefix.Size > Size) {
            return false;
        }
        if (prefix.Size == 0) {
            return true;
        }
        return _pep_utf8_compare(Data, Size, prefix.Data, prefix.Size, prefix.Size);
    }

    ## Returns whether this String ends with the bytes of `suffix`. An empty
    ## `suffix` always matches. Runs in O(suffix.Size).
    ##
    ## @param suffix the text to test for
    ## @returns true when the last `suffix.size()` bytes equal `suffix`
    bool ends_with(String suffix) {
        if (suffix.Size > Size) {
            return false;
        }
        if (suffix.Size == 0) {
            return true;
        }
        return _pep_utf8_compare(Data + (Size - suffix.Size), Size, suffix.Data, suffix.Size, suffix.Size);
    }

    ## Returns a new String of up to `count` code points starting at
    ## code-point index `start`. Both arguments count code points, not bytes.
    ##
    ## `count` is clamped to the code points that remain. When `start` is at
    ## or past `length()`, the result is an empty String. Runs in O(Size).
    ##
    ## @param start the code-point index of the first code point to copy
    ## @param count the maximum number of code points to copy
    ## @returns a new String that holds the selected code points
    ## @example
    ##     var s = "TEST";
    ##     assert(s.substr(1, 2) == "ES", "middle");
    ##     assert(s.substr(0, 99) == "TEST", "count is clamped");
    ##     assert(s.substr(4, 5) == "", "start past the end");
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
        # A zero size would tell the constructor to measure the C string.
        if (count == 0) {
            return String();
        }
        ulong len = _pep_utf8_char_offset(Data + begin, Size - begin, count);
        return String(Data + begin, len, count);
    }

    ## Returns whether this String and `rhs` differ in content, the negation
    ## of `==`. Runs in O(Size).
    ##
    ## @param rhs the String to compare with
    ## @returns true when the contents differ
    bool !=(String rhs) {
        return !(this == rhs);
    }

    ## Returns a new String that holds this String followed by `rhs`. Neither
    ## operand is modified. Runs in O(Size + rhs.Size).
    ##
    ## @param rhs the String to append to the copy
    ## @returns a new concatenated String
    ## @example
    ##     var greeting = "Hello, " + "world";
    String +(String rhs) {
        String result = clone();
        result.append(rhs);
        return result;
    }
}

# Walks the UTF-8 bytes forward, so a whole loop is O(size) rather than an
# O(size) `s[i]` lookup per index.

## An `Iterator<String>` over a String's code points, returned by
## `String.iterate()` and used by `for (var c in s)`.
##
## Call `next()` to advance, then `current()` for the code point it moved
## to. The iterator records the String's `Version` when it is created, and
## both methods panic if the String has been modified since. Create it with
## `String.iterate()`: a default-constructed `StringIterator()` has a null
## `Source`.
##
## @example
##     var it = "ab".iterate();
##     while (it.next()) {
##         print(it.current());   # "a", then "b"
##     }
export struct StringIterator {
    ## The String being iterated. The iterator holds a reference to it.
    String Source;
    ## The byte offset in `Source` of the current code point.
    ulong Offset;
    ## The byte offset in `Source` of the code point after the current one,
    ## or `Source.Size` at the end.
    ulong NextOffset;
    ## `Source.Version` when iteration began; a mismatch means modification.
    ulong Version;
    ## Whether `next()` has been called at least once.
    bool Started;

    ## Advances to the next code point. Runs in O(1) per code point.
    ##
    ## Returns false once it passes the end, and on every call after that.
    ## A malformed UTF-8 sequence is yielded, together with the rest of the
    ## bytes, as one final "code point".
    ##
    ## @returns true when positioned on a code point, false at the end
    ## @panics if `Source` was modified (its `Version` changed) since the
    ##   iterator was created
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

    ## Returns the code point that the last successful `next()` moved to, as
    ## a new one-code-point String.
    ##
    ## @returns a new String that holds the current code point
    ## @panics if `Source` was modified since the iterator was created
    ## @panics if `next()` has not been called yet
    ## @panics if `next()` has returned false (the iterator is past the end)
    String current() {
        assert(Source.Version == Version, "String modified during iteration");
        assert(Started, "StringIterator.current() before next()");
        assert(Offset < Source.Size, "StringIterator.current() past the end");
        return String(Source.Data + Offset, NextOffset - Offset, 1);
    }
}
