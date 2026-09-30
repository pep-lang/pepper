import "internals";

extern void memcpy(void* dest, void* src, ulong n);
extern int memcmp(void* a, void* b, ulong n);

## A mutable, reference-counted string of UTF-8 text. String literals
## (`"text"`) are `String` values.
##
## Two measures describe a String, and each API says which one it uses:
##
## - **Code points** (Unicode characters): `length()`, `empty()`,
##   the indexer `s[i]`, `substr`, and iteration.
## - **Bytes** of UTF-8: `size()`, `find`, `starts_with`, and
##   `ends_with`. The byte size is the authoritative length, so the data may
##   contain NUL bytes. It is never derived from a terminator.
##
## A String is a reference type: `var b = a;` shares one object, so
## `append`, `+=`, and `grow` are visible through every reference. Use
## `copy()` or `+` for an independent copy. Equality (`==`) compares
## content.
##
## A `StringIterator` panics when the String has been changed by `append`,
## `+=`, or `grow` since the iterator was created, so modifying a String
## while a `for` loop iterates it panics.
##
## To build text from values, use an interpolated string
## (`$"{name}: {count:>4}"`) or `String.format("{0}: {1:>4}", name, count)`,
## a compiler intrinsic whose braces name its arguments by position (see
## the String interpolation chapter).
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
    ## The heap buffer: `_size` bytes of UTF-8 followed by a NUL terminator,
    ## or `__null` for a String built with no data (`String()`). The String
    ## owns it and frees it on destruction. `append` and `grow` may move it.
    __ptr<char> _data;
    ## The number of Unicode code points. The constructor and `append` keep
    ## it current; `grow` does not update it.
    ulong _length;
    ## The number of bytes of UTF-8 in `_data`, not counting the NUL terminator.
    ulong _size;
    ## A modification counter, incremented by `append` and `grow`. A
    ## `StringIterator` compares it to detect modification during iteration.
    ## `copy()` starts the copy at 0.
    ulong _version;

    ## Creates a String by copying `size` bytes of `data` into a new
    ## NUL-terminated buffer. With no arguments, it creates an empty String
    ## whose `c_str()` is `__null`.
    ##
    ## When `data` is not `__null` and `size` is 0, `data` is treated as a
    ## NUL-terminated C string:
    ##
    ## - with `length` nonzero, `size` becomes the byte length of its first
    ##   `length` code points (0 if the C string is not valid UTF-8);
    ## - with `length` 0, `size` becomes the C string's whole byte length.
    ##
    ## When `length` is 0, it is counted from the bytes. A nonzero `length` is
    ## trusted, not checked against the data. Runs in O(size).
    ##
    ## @param data the bytes to copy; `__null` for an empty String (then pass
    ##   no sizes, because they are stored as given)
    ## @param size the number of bytes to copy from `data`; 0 treats `data` as
    ##   a NUL-terminated C string
    ## @param length the number of code points in those bytes
    ## @example
    ##     var empty = String();
    ##     var s = "abc";
    ##     var copy = String(s.c_str(), s.size(), s.length());
    construct(data: __ptr<char> = __null, size: ulong = 0, length: ulong = 0) {
        _size = size;
        _length = length;
        if (data) {
            # _size is the authoritative byte length; inline NULs are legal in
            # UTF-8 data, so it is never derived from a terminator. A raw
            # `char*` with no size is a C String by contract: measure it once
            # to bound the char-count derivation below.
            if (_size == 0) {
                var src = _pep_c_strlen(data);
                _size = _pep_utf8_size(data, src, _length);
            }
            # Callers that know only the bytes (`String(ptr)`,
            # `String(ptr, size)`) leave the character count to be derived.
            if (_length == 0) {
                _length = _pep_utf8_length(data, _size);
            }
            _data = _pep_malloc(_size + 1);
            memcpy(_data, data, _size);
            _data[_size] = 0;
        }
    }

    destruct {
        _pep_free(_data);
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
    static length_of(data: __ptr<char>, size: ulong): ulong {
        return _pep_utf8_length(data, size);
    }

    # A new String decoded from the UTF-8 bytes in `data`, each byte that
    # does not start a valid sequence becoming U+FFFD. For the http module
    # until text.Utf8.decode_lossy replaces it.
    static _from_bytes(data: u8[]): String {
        var size = data.count();
        if (size == 0) {
            return "";
        }
        __ptr<u8> source = data._data;
        # Each byte becomes at most 3 (a replacement character).
        __ptr<u8> decoded = _pep_malloc(size * 3 + 1);
        ulong length = 0;
        ulong written = 0;
        ulong index = 0;
        while (index < size) {
            var run = String._utf8_sequence(source, index, size);
            if (run == 0) {
                decoded[written] = 239;
                decoded[written + 1] = 191;
                decoded[written + 2] = 189;
                written = written + 3;
                index = index + 1;
            } else {
                ulong k = 0;
                while (k < run) {
                    decoded[written + k] = source[index + k];
                    k = k + 1;
                }
                written = written + run;
                index = index + run;
            }
            length = length + 1;
        }
        var result = String(decoded as __ptr<char>, written, length);
        _pep_free(decoded);
        return result;
    }

    # The size of the valid UTF-8 sequence starting at byte `index` of the
    # `size` bytes at `data`, or 0 when none starts there. (`&&` does not
    # short-circuit, so each read is guarded by its own `if`.)
    static _utf8_sequence(data: __ptr<u8>, index: ulong, size: ulong): ulong {
        var first = data[index];
        if (first < 128) {
            return 1;
        }
        ulong run = 0;
        u8 low = 128;
        u8 high = 191;
        if (first >= 194 && first <= 223) {
            run = 2;
        } else if (first >= 224 && first <= 239) {
            run = 3;
            if (first == 224) {
                low = 160;
            } else if (first == 237) {
                high = 159;
            }
        } else if (first >= 240 && first <= 244) {
            run = 4;
            if (first == 240) {
                low = 144;
            } else if (first == 244) {
                high = 143;
            }
        }
        if (run == 0 || index + run > size) {
            return 0;
        }
        var second = data[index + 1];
        if (second < low || second > high) {
            return 0;
        }
        ulong k = 2;
        while (k < run) {
            var next = data[index + k];
            if (next < 128 || next > 191) {
                return 0;
            }
            k = k + 1;
        }
        return run;
    }

    ## Returns a new array holding the String's UTF-8 bytes, without a
    ## terminating NUL. Runs in O(size()).
    ##
    ## @returns a new array of `size()` bytes
    ## @example
    ##     var data = "hi".bytes();
    ##     assert(data.count() == 2 && data[0] == 104, "the bytes of 'h' and 'i'");
    bytes(): u8[] {
        var result = Array<u8>(_size);
        ulong index = 0;
        while (index < _size) {
            result.append(_data[index] as u8);
            index = index + 1;
        }
        return result;
    }

    ## Returns the number of Unicode code points. O(1).
    ##
    ## @returns the length in code points, not bytes
    ## @see size
    length(): ulong {
        return _length;
    }

    ## Extends the byte buffer to `new_size` bytes and fills the new bytes
    ## with zeros. Does nothing when `new_size` is not greater than `size()`.
    ##
    ## A low-level primitive for `append`. It updates `size()` but not `length()`,
    ## so the zero bytes it adds are not counted as code points until the
    ## caller overwrites them and fixes the length. When it grows the buffer,
    ## it invalidates running iterators and may reallocate the buffer, which invalidates
    ## pointers from `c_str()`. Runs in O(new_size).
    ##
    ## @param new_size the new byte length
    grow(new_size: ulong) {
        if (new_size > _size) {
            _version = _version + 1;
            _data = _pep_realloc(_data, _size + 1, new_size + 1);
            _size = new_size;
            _data[_size] = 0;
        }
    }

    ## Appends the content of `rhs` to this String in place, updating `size()`
    ## and `length()`.
    ##
    ## Always invalidates running iterators, even when `rhs` is empty, so
    ## appending during iteration panics. It may reallocate the buffer. Every reference to
    ## this String sees the change. Runs in O(size() + rhs.size()).
    ##
    ## @param rhs the String to append; it is not modified
    ## @example
    ##     var s = "TEST";
    ##     s.append("ING");   # s == "TESTING"
    append(rhs: String) {
        _version = _version + 1;
        # Read rhs before growing: `s.append(s)` makes rhs this String, whose
        # _size grow() changes and whose _data it may move.
        ulong old_size = _size;
        ulong add_size = rhs._size;
        ulong add_length = rhs._length;
        grow(_size + add_size);
        memcpy(_data + old_size, rhs._data, add_size);
        _length += add_length;
        _data[_size] = 0;
    }

    ## Returns the code point at code-point index `idx` as a new
    ## one-code-point String.
    ##
    ## A negative `idx` counts from the end (`s[-1]` is the last code point).
    ## `length()` is added until the index is non-negative, so any negative
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
    [](idx: int): String {
        # Normalize a negative index to the end-relative offset *before* the
        # bounds check: `idx < _length` compares int against ulong, which
        # promotes to unsigned (a negative idx would wrap to ~2^64).
        if (_length > 0) {
            while (idx < 0) {
                idx += _length;
            }
        }
        assert(idx < _length, "String[] idx must be < length");
        ulong begin = _pep_utf8_char_offset(_data, _size, idx);
        return String(_data + begin, 0, 1);
    }

    ## Returns whether this String and `rhs` have the same content, compared
    ## byte by byte. Strings with different `length()` are unequal without
    ## comparing bytes. Runs in O(size()).
    ##
    ## @param rhs the String to compare with
    ## @returns true when both hold the same bytes
    ==(rhs: String): bool {
        if (_length != rhs._length) {
            return false;
        }
        if (_size == 0) {
            return true;
        }
        bool eq = _pep_utf8_compare(_data, _size, rhs._data, rhs._size, _size);
        return eq;
    }

    ## Appends `rhs` in place, like `append`, and returns this same String,
    ## not a copy. `s += t` modifies the object that every reference to `s`
    ## shares, and invalidates running iterators.
    ##
    ## @param rhs the String to append
    ## @returns this String, after appending
    ## @example
    ##     var s = "a";
    ##     s += "b";   # s == "ab"
    +=(rhs: String): String {
        append(rhs);
        return this;
    }

    ## Returns the number of bytes of UTF-8, not counting the NUL
    ## terminator. O(1).
    ##
    ## @returns the length in bytes, not code points
    ## @see length
    size(): ulong {
        return _size;
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
    iterate(): StringIterator {
        var it = StringIterator();
        it._source = this;
        it._version = _version;
        return it;
    }

    ## Returns whether the String has no code points. O(1).
    ##
    ## @returns true when `length()` is 0
    empty(): bool {
        return _length == 0;
    }

    ## Returns the String's buffer as a NUL-terminated C string.
    ##
    ## The pointer is owned by the String. It is valid until the String is
    ## destroyed or `append`, `+=`, or `grow` reallocates it. It is `__null`
    ## for a String built with no data (`String()`), so check it before you
    ## pass it to C. C functions stop at the first NUL byte in the content.
    ##
    ## @returns the String's NUL-terminated byte buffer, or `__null`
    c_str(): __ptr<char> {
        return _data;
    }

    ## Returns a new String with the same content and its own buffer, so
    ## later changes to either String do not affect the other. Runs in O(size()).
    ##
    ## This is also how `copy(value)` copies a String (the `Copyable<String>`
    ## implementation), which passes `copies`.
    ##
    ## @param copies the objects copied so far, when `copy(value)` calls it; a String holds no other objects, so it is not used
    ## @returns an independent copy of this String
    ## @example
    ##     var a = "abc";
    ##     var b = a.copy();
    ##     b.append("d");   # a is still "abc"
    copy(copies: Copies = __null): String {
        return String(_data, _size, _length);
    }

    ## Deprecated: use `copy` instead. Returns a new String with the same
    ## content and its own buffer.
    ##
    ## @returns an independent copy of this String
    [Deprecated("use 'copy' instead", "copy")]
    clone(): String {
        return this.copy();
    }

    ## Returns the **byte offset** of the first occurrence of `needle`, or -1
    ## when it does not occur.
    ##
    ## The offset counts bytes, not code points. To use it with `s[i]` or
    ## `substr`, convert it with `String.length_of(s.c_str(), offset)`.
    ## An empty `needle` is found at 0 unless this String is empty, in which
    ## case the result is -1. The result is also -1 when either String is not
    ## valid UTF-8. Runs in O(size() * needle.size()).
    ##
    ## @param needle the text to search for
    ## @returns the byte offset of the first match, or -1 when there is none
    ## @example
    ##     var s = "TESTING";
    ##     assert(s.find("STI") == 2, "byte offset");
    ##     assert(s.find("xyz") == -1, "absent");
    find(needle: String): long {
        return _pep_utf8_find(_data, _size, needle._data, needle._size);
    }

    ## Returns whether `needle` occurs in this String (`find(needle) >= 0`).
    ## Because of that, an empty String contains nothing, not even `""`.
    ## Runs in O(size() * needle.size()).
    ##
    ## @param needle the text to search for
    ## @returns true when `needle` occurs
    contains(needle: String): bool {
        return find(needle) >= 0;
    }

    ## Returns whether this String begins with the bytes of `prefix`. An
    ## empty `prefix` always matches. Runs in O(prefix.size()).
    ##
    ## @param prefix the text to test for
    ## @returns true when the first `prefix.size()` bytes equal `prefix`
    starts_with(prefix: String): bool {
        if (prefix._size > _size) {
            return false;
        }
        if (prefix._size == 0) {
            return true;
        }
        return _pep_utf8_compare(_data, _size, prefix._data, prefix._size, prefix._size);
    }

    ## Returns whether this String ends with the bytes of `suffix`. An empty
    ## `suffix` always matches. Runs in O(suffix.size()).
    ##
    ## @param suffix the text to test for
    ## @returns true when the last `suffix.size()` bytes equal `suffix`
    ends_with(suffix: String): bool {
        if (suffix._size > _size) {
            return false;
        }
        if (suffix._size == 0) {
            return true;
        }
        return _pep_utf8_compare(_data + (_size - suffix._size), _size, suffix._data, suffix._size, suffix._size);
    }

    ## Returns a new String of up to `count` code points starting at
    ## code-point index `start`. Both arguments count code points, not bytes.
    ##
    ## `count` is clamped to the code points that remain. When `start` is at
    ## or past `length()`, the result is an empty String. Runs in O(size()).
    ##
    ## @param start the code-point index of the first code point to copy
    ## @param count the maximum number of code points to copy
    ## @returns a new String that holds the selected code points
    ## @example
    ##     var s = "TEST";
    ##     assert(s.substr(1, 2) == "ES", "middle");
    ##     assert(s.substr(0, 99) == "TEST", "count is clamped");
    ##     assert(s.substr(4, 5) == "", "start past the end");
    substr(start: ulong, count: ulong): String {
        if (start >= _length) {
            return String();
        }
        ulong begin = _pep_utf8_char_offset(_data, _size, start);
        # Clamp the requested character count to what remains in the String.
        ulong avail = length_of(_data + begin, _size - begin);
        if (count > avail) {
            count = avail;
        }
        # A zero size would tell the constructor to measure the C string.
        if (count == 0) {
            return String();
        }
        ulong len = _pep_utf8_char_offset(_data + begin, _size - begin, count);
        return String(_data + begin, len, count);
    }

    ## Returns whether this String and `rhs` differ in content, the negation
    ## of `==`. Runs in O(size()).
    ##
    ## @param rhs the String to compare with
    ## @returns true when the contents differ
    !=(rhs: String): bool {
        return !(this == rhs);
    }

    ## Returns a new String that holds this String followed by `rhs`. Neither
    ## operand is modified. Runs in O(size() + rhs.size()).
    ##
    ## @param rhs the String to append to the copy
    ## @returns a new concatenated String
    ## @example
    ##     var greeting = "Hello, " + "world";
    +(rhs: String): String {
        String result = this.copy();
        result.append(rhs);
        return result;
    }

    ## Returns this String, so a String is `ToString` and can be
    ## interpolated (`$"name: {name}"`). The result is the same object, not
    ## a copy. O(1).
    ##
    ## @returns this String
    to_string(): String {
        return this;
    }

    ## Returns the byte at byte offset `index` of the UTF-8 data. O(1).
    ##
    ## The offset counts bytes, not code points, so a byte inside a
    ## multi-byte code point is returned as it is. Compare the result with a
    ## character literal (`s.byte_at(0) == '#'`).
    ##
    ## @param index the byte offset, less than `size()`
    ## @returns the byte at `index`
    ## @panics if `index` is not less than `size()` ("String byte_at index out of bounds")
    ## @example
    ##     var s = "a=b";
    ##     assert(s.byte_at(1) == '=', "second byte");
    byte_at(index: ulong): byte {
        assert(index < _size, "String byte_at index out of bounds");
        return _data[index] as byte;
    }

    ## Returns a new String of the `size` bytes starting at byte offset
    ## `start`. Both arguments count bytes, not code points, so offsets from
    ## `find` can be used directly. Runs in O(size).
    ##
    ## @param start the byte offset of the first byte to copy
    ## @param size the number of bytes to copy
    ## @returns a new String that holds those bytes
    ## @panics if `start + size` is greater than `size()` ("String substr_bytes range out of bounds")
    ## @panics if `start` or `start + size` falls inside a multi-byte code point
    ##   ("String substr_bytes splits a code point")
    ## @example
    ##     var s = "key=value";
    ##     var eq = s.find("=") as ulong;
    ##     assert(s.substr_bytes(0, eq) == "key", "before '='");
    ##     assert(s.substr_bytes(eq + 1, s.size() - eq - 1) == "value", "after '='");
    substr_bytes(start: ulong, size: ulong): String {
        assert(start <= _size && size <= _size - start, "String substr_bytes range out of bounds");
        assert(_is_boundary(start) && _is_boundary(start + size), "String substr_bytes splits a code point");
        # A zero size would tell the constructor to measure the C string.
        if (size == 0) {
            return String();
        }
        return String(_data + start, size);
    }

    # Whether byte offset `offset` starts a code point or is the end: the
    # byte there is not a UTF-8 continuation byte (10xxxxxx).
    _is_boundary(offset: ulong): bool {
        if (offset >= _size) {
            return true;
        }
        return ((_data[offset] as byte) & 0xC0) != 0x80;
    }

    ## Compares this String with `other` byte by byte, for sorting. For
    ## valid UTF-8 this is code-point order; a String that is a prefix of the
    ## other orders first. Runs in O(min(size(), other.size())).
    ##
    ## @param other the String to compare with
    ## @returns a negative number when this String orders before `other`, 0
    ##   when both hold the same bytes, and a positive number when it orders
    ##   after
    ## @example
    ##     assert("apple".compare("banana") < 0, "a before b");
    ##     assert("ab".compare("abc") < 0, "a prefix orders first");
    ##     assert("x".compare("x") == 0, "equal");
    compare(other: String): int {
        ulong common = _size;
        if (other._size < common) {
            common = other._size;
        }
        if (common > 0) {
            int result = memcmp(_data, other._data, common);
            if (result != 0) {
                return result;
            }
        }
        if (_size < other._size) {
            return -1;
        }
        if (_size > other._size) {
            return 1;
        }
        return 0;
    }

    ## Returns whether this String orders before `other`, as `compare` does.
    ##
    ## @param other the String to compare with
    ## @returns true when `compare(other) < 0`
    <(other: String): bool {
        return compare(other) < 0;
    }

    ## Returns whether this String orders before `other` or equals it, as
    ## `compare` does.
    ##
    ## @param other the String to compare with
    ## @returns true when `compare(other) <= 0`
    <=(other: String): bool {
        return compare(other) <= 0;
    }

    ## Returns whether this String orders after `other`, as `compare` does.
    ##
    ## @param other the String to compare with
    ## @returns true when `compare(other) > 0`
    >(other: String): bool {
        return compare(other) > 0;
    }

    ## Returns whether this String orders after `other` or equals it, as
    ## `compare` does.
    ##
    ## @param other the String to compare with
    ## @returns true when `compare(other) >= 0`
    >=(other: String): bool {
        return compare(other) >= 0;
    }

    ## Returns a new String without the whitespace at the end: spaces, tabs,
    ## carriage returns, line feeds, vertical tabs and form feeds (ASCII
    ## only). Runs in O(size()).
    ##
    ## @returns a new String with the trailing whitespace removed
    ## @example
    ##     assert("code;  \r\n".trim_end() == "code;", "trailing whitespace");
    ##     assert("  indented".trim_end() == "  indented", "leading kept");
    trim_end(): String {
        ulong end = _size;
        while (end > 0 && _is_space(_data[end - 1] as byte)) {
            end = end - 1;
        }
        return substr_bytes(0, end);
    }

    ## Returns a new String without the whitespace at the start: spaces,
    ## tabs, carriage returns, line feeds, vertical tabs and form feeds
    ## (ASCII only). Runs in O(size()).
    ##
    ## @returns a new String with the leading whitespace removed
    ## @example
    ##     assert("  \tcode".trim_start() == "code", "leading whitespace");
    trim_start(): String {
        ulong start = 0;
        while (start < _size && _is_space(_data[start] as byte)) {
            start = start + 1;
        }
        return substr_bytes(start, _size - start);
    }

    ## Returns a new String without the whitespace at either end, as
    ## `trim_start` and `trim_end` do. Runs in O(size()).
    ##
    ## @returns a new String with the leading and trailing whitespace removed
    ## @example
    ##     assert(" \t value \r\n".trim() == "value", "both ends");
    trim(): String {
        return trim_start().trim_end();
    }

    ## Returns a new String with the ASCII letters `A` to `Z` changed to `a`
    ## to `z`. Every other character, including non-ASCII letters, is kept
    ## as it is, so the result is valid UTF-8 of the same size. Runs in
    ## O(size()).
    ##
    ## @returns a new String in lowercase
    ## @example
    ##     assert("Content-Type".lower() == "content-type", "ASCII lowered");
    ##     assert("Ärger".lower() == "Ärger", "non-ASCII kept");
    lower(): String {
        return _map_case(65, 32);
    }

    ## Returns a new String with the ASCII letters `a` to `z` changed to `A`
    ## to `Z`. Every other character, including non-ASCII letters, is kept
    ## as it is, so the result is valid UTF-8 of the same size. Runs in
    ## O(size()).
    ##
    ## @returns a new String in uppercase
    ## @example
    ##     assert("get".upper() == "GET", "ASCII raised");
    upper(): String {
        return _map_case(97, 0 - 32);
    }

    # A copy with the 26 letters from `first` shifted by `shift`.
    _map_case(first: int, shift: int): String {
        __ptr<char> copy = _pep_malloc(_size + 1);
        ulong index = 0;
        while (index < _size) {
            int value = (_data[index] as byte) as int;
            if (value >= first && value < first + 26) {
                value = value + shift;
            }
            copy[index] = value as char;
            index = index + 1;
        }
        var result = String(copy, _size, _length);
        _pep_free(copy);
        return result;
    }

    # Whether `value` is ASCII whitespace: space, \t, \n, \v, \f or \r.
    static _is_space(value: byte): bool {
        return value == ' ' || (value >= 9 && value <= 13);
    }

    ## Splits the String into lines and returns them without their line
    ## endings. A line ends at `"\n"` or `"\r\n"`. A final line with no
    ## ending is included, but the end of the String after a final line
    ## ending does not start another line, so `"a\nb\n"` and `"a\nb"` both
    ## give `["a", "b"]`, and `""` gives no lines. Runs in O(size()).
    ##
    ## @returns a new Array with one new String per line
    ## @example
    ##     var lines = "first\r\nsecond\n\nfourth".lines();
    ##     assert(lines.count() == 4, "four lines");
    ##     assert(lines[1] == "second", "\\r\\n removed");
    ##     assert(lines[2] == "", "an empty line");
    lines(): String[] {
        var result = Array<String>();
        ulong start = 0;
        ulong index = 0;
        while (index < _size) {
            if ((_data[index] as byte) == '\n') {
                ulong end = index;
                if (end > start && (_data[end - 1] as byte) == '\r') {
                    end = end - 1;
                }
                result.append(substr_bytes(start, end - start));
                start = index + 1;
            }
            index = index + 1;
        }
        if (start < _size) {
            result.append(substr_bytes(start, _size - start));
        }
        return result;
    }

    ## Returns a new String that holds this String `count` times in a row.
    ## `count` 0, or an empty String, gives an empty String. Runs in
    ## O(size() * count).
    ##
    ## @param count how many copies to join
    ## @returns a new String of `size() * count` bytes
    ## @example
    ##     assert("ab".repeat(3) == "ababab", "three copies");
    ##     var indent = " ".repeat(8);   # eight spaces
    repeat(count: ulong): String {
        if (count == 0 || _size == 0) {
            return String();
        }
        var result = String();
        result.grow(_size * count);
        ulong index = 0;
        while (index < count) {
            memcpy(result._data + index * _size, _data, _size);
            index = index + 1;
        }
        result._length = _length * count;
        return result;
    }
}

## Returns the decimal text of `value`, with a leading `-` when it is
## negative.
##
## `to_string` is overloaded for every integer type, so a call with any
## integer picks its own overload.
##
## @param value the number to convert
## @returns a new String such as `"-42"`
## @example
##     assert(to_string(-42) == "-42", "negative");
##     var where = to_string(line) + ":" + to_string(column);
export to_string(value: long): String {
    if (value < 0) {
        # Negate as unsigned: -value overflows for the most negative long.
        return _decimal(0 - (value as ulong), true);
    }
    return _decimal(value as ulong, false);
}

## Returns the decimal text of `value`.
##
## @param value the number to convert
## @returns a new String such as `"18446744073709551615"`
export to_string(value: ulong): String {
    return _decimal(value, false);
}

## Returns the decimal text of `value`, with a leading `-` when it is
## negative.
##
## @param value the number to convert
## @returns a new String such as `"7"`
export to_string(value: int): String {
    return to_string(value as long);
}

## Returns the decimal text of `value`.
##
## @param value the number to convert
## @returns a new String such as `"7"`
export to_string(value: uint): String {
    return _decimal(value as ulong, false);
}

## Returns the decimal text of `value`, with a leading `-` when it is
## negative.
##
## @param value the number to convert
## @returns a new String such as `"-7"`
export to_string(value: short): String {
    return to_string(value as long);
}

## Returns the decimal text of `value`.
##
## @param value the number to convert
## @returns a new String such as `"7"`
export to_string(value: ushort): String {
    return _decimal(value as ulong, false);
}

## Returns the decimal text of `value`, with a leading `-` when it is
## negative.
##
## @param value the number to convert
## @returns a new String such as `"-7"`
export to_string(value: char): String {
    return to_string(value as long);
}

## Returns the decimal text of `value`.
##
## @param value the number to convert
## @returns a new String such as `"7"`
export to_string(value: byte): String {
    return _decimal(value as ulong, false);
}

## Returns `"true"` or `"false"`.
##
## @param value the value to convert
## @returns a new String, `"true"` or `"false"`
export to_string(value: bool): String {
    if (value) {
        return "true";
    }
    return "false";
}

## Returns the text of `value` by calling its `to_string()` method: the
## overload for any type that is `ToString`.
##
## Declare a concrete override for a type that has no `to_string()` method
## of its own, or whose interpolated text should differ from it; like
## `hash<Point>`, an override is used by the whole program, including
## interpolated strings.
##
## @typeParam T the type of `value`; it must have a `to_string()` method
## unless an override `to_string<T>` exists
## @param value the value to convert
## @returns the String that `value.to_string()` returns
## @example
##     struct Point {
##         var x: int = 0;
##         var y: int = 0;
##         construct(this.x = 0, this.y = 0) {}
##     }
##
##     to_string<Point>(value: Point): String {
##         var x = value.x;
##         var y = value.y;
##         return $"({x}, {y})";
##     }
export to_string<T>(value: T): String {
    return value.to_string();
}

## Something with a text form: a `to_string()` method returning a String.
##
## An interpolated string (`$"total: {a + b}"`) converts each value it holds
## with `to_string(value)`, so a struct that implements `ToString` can be
## interpolated, as can the integers, `bool`, and `String`, which have
## `to_string` overloads. `String`, `StringBuilder` and `io.Path` implement
## it.
##
## @example
##     struct Point {
##         var x: int = 0;
##         var y: int = 0;
##         construct(this.x = 0, this.y = 0) {}
##     }
##
##     extend Point with ToString {
##         to_string(): String {
##             return $"({x}, {y})";
##         }
##     }
##
##     var p = Point(1, 2);
##     assert($"p = {p}" == "p = (1, 2)", "interpolated");
export trait ToString {
    ## Returns the text of this value.
    ##
    ## @returns a String
    to_string(): String;
}

# The call an interpolated string makes for each `{expression}` it holds
# (the parser lowers `$"a{x + 1}"` to `"a" + _pep_interpolate(x + 1)`). A separate name
# keeps a struct's own `to_string()` method from capturing the call inside
# its methods, and resolves `to_string` here, in the runtime, for every file.
export _pep_interpolate<T>(value: T): String {
    return to_string(value);
}

# The decimal digits of `magnitude`, after a `-` when `negative`.
_decimal(magnitude: ulong, negative: bool): String {
    return _digits(magnitude, negative, false, 10, false);
}

# The digits of `magnitude` in `base` (2 to 16), after a `-` when `negative`
# or a `+` when `plus` and not negative; `upper` spells the digits above 9
# `A` to `F`.
_digits(magnitude: ulong, negative: bool, plus: bool, base: ulong, upper: bool): String {
    # 64 binary digits hold the largest ulong; one more for the sign.
    var digits = _pep_malloc(65) as __ptr<char>;
    ulong start = 65;
    while (true) {
        start = start - 1;
        var digit = magnitude % base;
        if (digit < 10) {
            digits[start] = ('0' + digit) as char;
        } else if (upper) {
            digits[start] = ('A' + digit - 10) as char;
        } else {
            digits[start] = ('a' + digit - 10) as char;
        }
        magnitude = magnitude / base;
        if (magnitude == 0) {
            break;
        }
    }
    if (negative) {
        start = start - 1;
        digits[start] = '-' as char;
    } else if (plus) {
        start = start - 1;
        digits[start] = '+' as char;
    }
    var result = String(digits + start, 65 - start, 65 - start);
    _pep_free(digits);
    return result;
}

# The alignments a format specification names; `_ALIGN_DEFAULT` is none.
const _ALIGN_DEFAULT = 0;
const _ALIGN_LEFT = 1;
const _ALIGN_CENTER = 2;
const _ALIGN_RIGHT = 3;

# Pads `text` with `fill` to `width` characters, placing it by `align`
# (`_ALIGN_LEFT`, `_ALIGN_CENTER` or `_ALIGN_RIGHT`); centered text leans
# left. With `zero`, pads with `0` after any leading sign instead.
_pep_pad(text: String, fill: String, align: int, width: ulong, zero: bool): String {
    var length = text.length();
    if (length >= width) {
        return text;
    }
    var missing = width - length;
    if (zero) {
        var sign = text.starts_with("-") || text.starts_with("+");
        if (sign) {
            return text.substr_bytes(0, 1) + "0".repeat(missing) + text.substr_bytes(1, text.size() - 1);
        }
        return "0".repeat(missing) + text;
    }
    if (align == _ALIGN_LEFT) {
        return text + fill.repeat(missing);
    }
    if (align == _ALIGN_CENTER) {
        return fill.repeat(missing / 2) + text + fill.repeat(missing - missing / 2);
    }
    return fill.repeat(missing) + text;
}

# Where a value is placed in a width when its format names no alignment:
# numbers to the right, everything else to the left.
_pep_default_align(value: long): int {
    return _ALIGN_RIGHT;
}

_pep_default_align(value: ulong): int {
    return _ALIGN_RIGHT;
}

_pep_default_align(value: int): int {
    return _ALIGN_RIGHT;
}

_pep_default_align(value: uint): int {
    return _ALIGN_RIGHT;
}

_pep_default_align(value: short): int {
    return _ALIGN_RIGHT;
}

_pep_default_align(value: ushort): int {
    return _ALIGN_RIGHT;
}

_pep_default_align(value: char): int {
    return _ALIGN_RIGHT;
}

_pep_default_align(value: byte): int {
    return _ALIGN_RIGHT;
}

_pep_default_align<T>(value: T): int {
    return _ALIGN_LEFT;
}

# The call an interpolated string makes for `{value:spec}` when the spec
# names only a fill, an alignment and a width (the parser lowers
# `$"{x:>5}"` to `_pep_format(x, " ", 3, 5)`): the value's text, padded.
export _pep_format<T>(value: T, fill: String, align: int, width: ulong): String {
    var placed = align;
    if (placed == _ALIGN_DEFAULT) {
        placed = _pep_default_align(value);
    }
    return _pep_pad(to_string(value), fill, placed, width, false);
}

# The digits of an integer in `base`, for `_pep_format_integer`: one
# overload per integer type, as for `to_string`.
_pep_radix(value: long, base: ulong, upper: bool, plus: bool): String {
    if (value < 0) {
        return _digits(0 - (value as ulong), true, plus, base, upper);
    }
    return _digits(value as ulong, false, plus, base, upper);
}

_pep_radix(value: ulong, base: ulong, upper: bool, plus: bool): String {
    return _digits(value, false, plus, base, upper);
}

_pep_radix(value: int, base: ulong, upper: bool, plus: bool): String {
    return _pep_radix(value as long, base, upper, plus);
}

_pep_radix(value: uint, base: ulong, upper: bool, plus: bool): String {
    return _digits(value as ulong, false, plus, base, upper);
}

_pep_radix(value: short, base: ulong, upper: bool, plus: bool): String {
    return _pep_radix(value as long, base, upper, plus);
}

_pep_radix(value: ushort, base: ulong, upper: bool, plus: bool): String {
    return _digits(value as ulong, false, plus, base, upper);
}

_pep_radix(value: char, base: ulong, upper: bool, plus: bool): String {
    return _pep_radix(value as long, base, upper, plus);
}

_pep_radix(value: byte, base: ulong, upper: bool, plus: bool): String {
    return _digits(value as ulong, false, plus, base, upper);
}

# The call an interpolated string makes for `{value:spec}` when the spec
# needs an integer: a sign, `0` padding, or a type (`d`, `x`, `X`, `b`,
# `o`). Sema reports any other value at the spec, so only integer types
# reach `_pep_radix`. A negative number keeps its `-` in every base.
export _pep_format_integer<T>(
    value: T, base: ulong, upper: bool, plus: bool, fill: String, align: int, width: ulong, zero: bool
): String {
    var placed = align;
    if (placed == _ALIGN_DEFAULT) {
        placed = _ALIGN_RIGHT;
    }
    return _pep_pad(_pep_radix(value, base, upper, plus), fill, placed, width, zero);
}

## Builds a String from many pieces without copying the text built so far
## on every append.
##
## `String.append` grows its buffer to the exact new size, so a long run of
## appends can copy the text repeatedly. A StringBuilder doubles its buffer
## when it is full, so appending is amortized O(piece size). Call
## `to_string()` for the result; the builder can keep appending afterward.
##
## @example
##     var out = StringBuilder();
##     out.append("line ").append(to_string(3)).append("\n");
##     var text = out.to_string();   # "line 3\n"
export struct StringBuilder {
    ## The buffer: `_capacity` bytes, of which the first `_size` hold the
    ## text built so far. `__null` until the first append.
    __ptr<char> _data;
    ## The number of bytes of text in `_data`.
    ulong _size;
    ## The number of bytes allocated in `_data`.
    ulong _capacity;
    ## The number of code points in the text.
    ulong _length;

    ## Creates an empty StringBuilder, optionally with room for `capacity`
    ## bytes before it has to grow.
    ##
    ## @param capacity the number of bytes to allocate up front
    construct(capacity: ulong = 0) {
        if (capacity > 0) {
            _data = _pep_malloc(capacity) as __ptr<char>;
            _capacity = capacity;
        }
    }

    destruct {
        _pep_free(_data);
    }

    ## Appends the text of `text` and returns this builder, so calls can be
    ## chained. Runs in amortized O(text.size()).
    ##
    ## @param text the String to append; it is not modified
    ## @returns this StringBuilder
    ## @example
    ##     var b = StringBuilder();
    ##     b.append("a").append("b");   # b.to_string() == "ab"
    append(text: String): StringBuilder {
        ulong needed = _size + text._size;
        if (needed > _capacity) {
            ulong capacity = _capacity * 2;
            if (capacity < 16) {
                capacity = 16;
            }
            if (capacity < needed) {
                capacity = needed;
            }
            _data = _pep_realloc(_data, _capacity, capacity) as __ptr<char>;
            _capacity = capacity;
        }
        if (text._size > 0) {
            memcpy(_data + _size, text._data, text._size);
        }
        _size = needed;
        _length = _length + text._length;
        return this;
    }

    ## Returns the number of bytes of UTF-8 appended so far. O(1).
    ##
    ## @returns the size in bytes
    size(): ulong {
        return _size;
    }

    ## Returns the number of code points appended so far. O(1).
    ##
    ## @returns the length in code points
    length(): ulong {
        return _length;
    }

    ## Returns whether nothing has been appended since the builder was
    ## created or last cleared. O(1).
    ##
    ## @returns true when `size()` is 0
    empty(): bool {
        return _size == 0;
    }

    ## Removes all the text and keeps the buffer for reuse. O(1).
    clear() {
        _size = 0;
        _length = 0;
    }

    ## Returns a new String holding the text appended so far. The builder
    ## is unchanged. Runs in O(size()).
    ##
    ## @returns a new String
    to_string(): String {
        # A zero size would tell the constructor to measure the C string.
        if (_size == 0) {
            return String();
        }
        return String(_data, _size, _length);
    }
}

# Walks the UTF-8 bytes forward, so a whole loop is O(size) rather than an
# O(size) `s[i]` lookup per index.

## An `Iterator<String>` over a String's code points, returned by
## `String.iterate()` and used by `for (var c in s)`.
##
## Call `next()` to advance, then `current()` for the code point it moved
## to. Both methods panic if the String has been modified since the
## iterator was created. Create it with `String.iterate()`: a
## default-constructed `StringIterator()` has no String to walk.
##
## @example
##     var it = "ab".iterate();
##     while (it.next()) {
##         print(it.current());   # "a", then "b"
##     }
export struct StringIterator {
    ## The String being iterated. The iterator holds a reference to it.
    String _source;
    ## The byte offset in `_source` of the current code point.
    ulong _offset;
    ## The byte offset in `_source` of the code point after the current one,
    ## or `_source._size` at the end.
    ulong _next_offset;
    ## `_source._version` when iteration began; a mismatch means modification.
    ulong _version;
    ## Whether `next()` has been called at least once.
    bool _started;

    ## Advances to the next code point. Runs in O(1) per code point.
    ##
    ## Returns false once it passes the end, and on every call after that.
    ## A malformed UTF-8 sequence is yielded, together with the rest of the
    ## bytes, as one final "code point".
    ##
    ## @returns true when positioned on a code point, false at the end
    ## @panics if the String was modified since the
    ##   iterator was created
    next(): bool {
        assert(_source._version == _version, "String modified during iteration");
        if (_started) {
            _offset = _next_offset;
        } else {
            _started = true;
        }
        if (_offset >= _source._size) {
            _next_offset = _offset;
            return false;
        }
        _next_offset = _offset + _pep_utf8_char_offset(_source._data + _offset, _source._size - _offset, 1);
        return true;
    }

    ## Returns the code point that the last successful `next()` moved to, as
    ## a new one-code-point String.
    ##
    ## @returns a new String that holds the current code point
    ## @panics if the String was modified since the iterator was created
    ## @panics if `next()` has not been called yet
    ## @panics if `next()` has returned false (the iterator is past the end)
    current(): String {
        assert(_source._version == _version, "String modified during iteration");
        assert(_started, "StringIterator.current() before next()");
        assert(_offset < _source._size, "StringIterator.current() past the end");
        return String(_source._data + _offset, _next_offset - _offset, 1);
    }
}

extend StringIterator with Iterator<String> {}

extend String with Copyable<String> {}

extend String with ToString {}

extend StringBuilder with ToString {}
