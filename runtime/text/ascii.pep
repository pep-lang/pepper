## ASCII, the first 128 code points, one byte each.

import "utf8";

## Encodes a `String` to ASCII bytes and decodes them back. Only code
## points below 128 have an ASCII byte.
##
## @example
##     import text;
##
##     assert(text.Ascii.encode("ok").value().count == 2, "one byte each");
##     assert(text.Ascii.encode("é").is_none(), "not ASCII");
export struct Ascii {
    ## Returns the ASCII bytes of `value`, or none when it holds a code
    ## point past 127.
    ##
    ## @param value the text to encode
    ## @returns a new array of one byte per code point, or none
    static encode(value: String): u8[]? {
        if (!Ascii.is_ascii(value)) {
            return Optional<u8[]>.none();
        }
        return Optional<u8[]>.some(value.bytes());
    }

    ## Returns the ASCII bytes of `value`, with `?` for each code point past
    ## 127.
    ##
    ## @param value the text to encode
    ## @returns a new array of one byte per code point
    static encode_lossy(value: String): u8[] {
        var out = Array<u8>(value.size);
        __ptr<u8> data = value._data as __ptr<u8>;
        var size = value.size;
        ulong index = 0;
        while (index < size) {
            var run = String._utf8_sequence(data, index, size);
            if (run == 1) {
                out.append(data[index]);
            } else {
                out.append(63);  # '?'
            }
            index = index + run;
        }
        return out;
    }

    ## Returns whether every code point of `value` is ASCII (below 128).
    ##
    ## @param value the text to check
    ## @returns true when `value` is all ASCII
    static is_ascii(value: String): bool {
        __ptr<u8> data = value._data as __ptr<u8>;
        ulong index = 0;
        while (index < value.size) {
            if (data[index] >= 128) {
                return false;
            }
            index = index + 1;
        }
        return true;
    }

    ## Decodes ASCII `bytes`, or gives none when one is 128 or more.
    ##
    ## @param bytes the bytes to decode
    ## @returns the text, or none when `bytes` is not all ASCII
    static decode(bytes: u8[]): String? {
        ulong index = 0;
        while (index < bytes.count) {
            if (bytes[index] >= 128) {
                return Optional<String>.none();
            }
            index = index + 1;
        }
        return Optional<String>.some(Utf8.decode_lossy(bytes));
    }

    ## Decodes ASCII `bytes`, replacing each byte of 128 or more with
    ## U+FFFD, so it always succeeds.
    ##
    ## @param bytes the bytes to decode
    ## @returns the text
    static decode_lossy(bytes: u8[]): String {
        var out = Array<u8>(bytes.count);
        ulong index = 0;
        while (index < bytes.count) {
            var value = bytes[index];
            if (value >= 128) {
                _text_append_utf8(out, 65533);
            } else {
                out.append(value);
            }
            index = index + 1;
        }
        return Utf8.decode_lossy(out);
    }
}
