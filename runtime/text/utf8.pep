## UTF-8, the encoding a `String` holds.

## Encodes a `String` to UTF-8 bytes and decodes them back. A String already
## holds UTF-8, so encoding copies its bytes; decoding checks them.
##
## @example
##     import text;
##
##     var bytes = text.Utf8.encode("hi");
##     assert(text.Utf8.decode(bytes).value() == "hi", "round trip");
export struct Utf8 {
    ## Returns the UTF-8 bytes of `value`, without a terminating NUL.
    ##
    ## @param value the text to encode
    ## @returns a new array of `value.size` bytes
    static encode(value: String): u8[] {
        return value.bytes();
    }

    ## Returns whether `bytes` is valid UTF-8: no stray continuation bytes,
    ## no truncated, overlong or surrogate sequences, and nothing past
    ## U+10FFFF.
    ##
    ## @param bytes the bytes to check
    ## @returns true when every byte is part of a valid sequence
    static is_valid(bytes: u8[]): bool {
        var size = bytes.count;
        ulong index = 0;
        while (index < size) {
            var run = String._utf8_sequence(bytes._data, index, size);
            if (run == 0) {
                return false;
            }
            index = index + run;
        }
        return true;
    }

    ## Decodes `bytes` as UTF-8, or gives none when they are not valid UTF-8
    ## (see `is_valid`). A byte-order mark is kept as part of the text.
    ##
    ## @param bytes the bytes to decode
    ## @returns the text, or none when `bytes` is not valid UTF-8
    ## @example
    ##     import text;
    ##
    ##     var bad = Array<u8>();
    ##     bad.append(255);
    ##     assert(text.Utf8.decode(bad).is_empty(), "0xFF is never UTF-8");
    static decode(bytes: u8[]): String? {
        if (!Utf8.is_valid(bytes)) {
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(Utf8.decode_lossy(bytes));
    }

    ## Decodes `bytes` as UTF-8, replacing each byte that does not start a
    ## valid sequence with U+FFFD, so it always succeeds. Valid input gives
    ## the same text as `decode`.
    ##
    ## @param bytes the bytes to decode
    ## @returns the text
    ## @example
    ##     import text;
    ##
    ##     var data = Array<u8>();
    ##     data.append(104);
    ##     data.append(255);
    ##     data.append(105);
    ##     assert(text.Utf8.decode_lossy(data) == "h\u{FFFD}i", "255 is replaced");
    static decode_lossy(bytes: u8[]): String {
        return String._from_bytes(bytes);
    }

    ## Returns the byte offset of the first byte of `value` that does not
    ## start a valid UTF-8 sequence (see `is_valid`), or none when all of it
    ## is valid. A `String` made from checked bytes is always valid; one made
    ## from C memory may not be.
    ##
    ## @param value the text to check
    ## @returns the offset of the first invalid byte, or none
    ## @example
    ##     import text;
    ##
    ##     assert(text.Utf8.find_invalid("héllo").is_empty(), "valid");
    static find_invalid(value: String): ulong? {
        __ptr<u8> data = unsafe_cast<__ptr<u8>>(value._data);
        var size = value.size;
        ulong index = 0;
        while (index < size) {
            var run = String._utf8_sequence(data, index, size);
            if (run == 0) {
                return Optional<ulong>.Value(index);
            }
            index = index + run;
        }
        return Optional<ulong>.Empty;
    }

    ## Decodes the code point whose UTF-8 sequence starts at byte `offset`
    ## of `value`.
    ##
    ## @param value the text to read
    ## @param offset the byte offset where the sequence starts
    ## @returns the code point and the number of bytes its sequence takes,
    ##   from 1 to 4, so `offset` plus that is where the next one starts
    ## @panics if `offset` is not less than `value.size`
    ##   ("Utf8.code_point_at offset out of bounds")
    ## @panics if no valid sequence starts at `offset`
    ##   ("Utf8.code_point_at found invalid UTF-8")
    ## @example
    ##     import text;
    ##
    ##     var (point, run) = text.Utf8.code_point_at("é!", 0);
    ##     assert(point == 233 and run == 2, "U+00E9 takes two bytes");
    static code_point_at(value: String, offset: ulong): (uint, ulong) {
        var size = value.size;
        assert(offset < size, "Utf8.code_point_at offset out of bounds");
        __ptr<u8> data = unsafe_cast<__ptr<u8>>(value._data);
        var run = String._utf8_sequence(data, offset, size);
        assert(run != 0, "Utf8.code_point_at found invalid UTF-8");
        return (_text_code_point(data, offset, run), run);
    }

    ## Appends the UTF-8 encoding of `code_point`, from 1 to 4 bytes, to
    ## `out`.
    ##
    ## @param out the bytes to append to
    ## @param code_point the code point to encode
    ## @panics if `code_point` is a surrogate (U+D800 to U+DFFF) or above
    ##   U+10FFFF ("Utf8.append_code_point needs a Unicode scalar value")
    ## @example
    ##     import text;
    ##
    ##     var out = Array<u8>();
    ##     text.Utf8.append_code_point(out, 8364);
    ##     assert(text.Utf8.decode(out).value() == "€", "U+20AC");
    static append_code_point(out: u8[], code_point: uint) {
        assert(
            code_point <= 1114111 and (code_point < 55296 or code_point > 57343),
            "Utf8.append_code_point needs a Unicode scalar value"
        );
        _text_append_utf8(out, code_point);
    }
}

# The code point of the valid UTF-8 sequence of `run` bytes at `index` of
# `data`.
_text_code_point(data: __ptr<u8>, index: ulong, run: ulong): uint {
    var first = data[index] as uint;
    if (run == 1) {
        return first;
    }
    uint value = 0;
    if (run == 2) {
        value = first & 31;
    } else if (run == 3) {
        value = first & 15;
    } else {
        value = first & 7;
    }
    ulong k = 1;
    while (k < run) {
        value = (value << 6) | ((data[index + k] as uint) & 63);
        k = k + 1;
    }
    return value;
}

# Appends the UTF-8 bytes of the code point `value` to `out`.
_text_append_utf8(out: u8[], value: uint) {
    if (value < 128) {
        out.append(value as u8);
    } else if (value < 2048) {
        out.append((192 | (value >> 6)) as u8);
        out.append((128 | (value & 63)) as u8);
    } else if (value < 65536) {
        out.append((224 | (value >> 12)) as u8);
        out.append((128 | ((value >> 6) & 63)) as u8);
        out.append((128 | (value & 63)) as u8);
    } else {
        out.append((240 | (value >> 18)) as u8);
        out.append((128 | ((value >> 12) & 63)) as u8);
        out.append((128 | ((value >> 6) & 63)) as u8);
        out.append((128 | (value & 63)) as u8);
    }
}
