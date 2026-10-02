## UTF-16, as Windows and Java hold text.

import "utf8";

## Encodes a `String` to UTF-16 bytes and decodes them back. Each code
## unit takes two bytes, little-endian unless `big_endian` is set; a code
## point past U+FFFF takes two units (a surrogate pair). No byte-order mark
## is written, and one read is kept as part of the text.
##
## @example
##     import text;
##
##     var bytes = text.Utf16.encode("hi");
##     assert(bytes.count == 4 && bytes[0] == 104 && bytes[1] == 0, "little-endian");
##     assert(text.Utf16.decode(bytes).value() == "hi", "round trip");
export struct Utf16 {
    ## Returns the UTF-16 bytes of `value`.
    ##
    ## @param value the text to encode
    ## @param big_endian whether each code unit's high byte comes first;
    ##   false (little-endian) by default
    ## @returns a new array of two bytes per code unit
    static encode(value: String, big_endian: bool = false): u8[] {
        var out = Array<u8>(value.size * 2);
        __ptr<u8> data = unsafe_cast<__ptr<u8>>(value._data);
        var size = value.size;
        ulong index = 0;
        while (index < size) {
            # A String holds valid UTF-8, so every sequence has a length.
            var run = String._utf8_sequence(data, index, size);
            var point = _text_code_point(data, index, run);
            if (point >= 65536) {
                var rest = point - 65536;
                _text_append_unit(out, 55296 + (rest >> 10), big_endian);
                _text_append_unit(out, 56320 + (rest & 1023), big_endian);
            } else {
                _text_append_unit(out, point, big_endian);
            }
            index = index + run;
        }
        return out;
    }

    ## Decodes UTF-16 `bytes`, or gives none when they are not valid UTF-16:
    ## an odd number of bytes, or a surrogate without its partner.
    ##
    ## @param bytes the bytes to decode
    ## @param big_endian whether each code unit's high byte comes first;
    ##   false (little-endian) by default
    ## @returns the text, or none when `bytes` is not valid UTF-16
    static decode(bytes: u8[], big_endian: bool = false): String? {
        var out = Array<u8>();
        if (!_text_utf16_decode(bytes, big_endian, false, out)) {
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(Utf8.decode_lossy(out));
    }

    ## Decodes UTF-16 `bytes`, replacing each unpaired surrogate, and a
    ## final odd byte, with U+FFFD, so it always succeeds.
    ##
    ## @param bytes the bytes to decode
    ## @param big_endian whether each code unit's high byte comes first;
    ##   false (little-endian) by default
    ## @returns the text
    static decode_lossy(bytes: u8[], big_endian: bool = false): String {
        var out = Array<u8>();
        _text_utf16_decode(bytes, big_endian, true, out);
        return Utf8.decode_lossy(out);
    }
}

# Appends the code unit `unit` to `out` as two bytes.
_text_append_unit(out: u8[], unit: uint, big_endian: bool) {
    if (big_endian) {
        out.append((unit >> 8) as u8);
        out.append((unit & 255) as u8);
    } else {
        out.append((unit & 255) as u8);
        out.append((unit >> 8) as u8);
    }
}

# The code unit at byte `index` of `data`.
_text_unit(data: __ptr<u8>, index: ulong, big_endian: bool): uint {
    var first = data[index] as uint;
    var second = data[index + 1] as uint;
    if (big_endian) {
        return (first << 8) | second;
    }
    return (second << 8) | first;
}

# Decodes the UTF-16 in `bytes` into UTF-8 in `out`. Something invalid
# becomes U+FFFD when `lossy`, or stops the decoding with false otherwise.
_text_utf16_decode(bytes: u8[], big_endian: bool, lossy: bool, out: u8[]): bool {
    var size = bytes.count;
    __ptr<u8> data = bytes._data;
    ulong index = 0;
    while (index + 1 < size) {
        var unit = _text_unit(data, index, big_endian);
        index = index + 2;
        if (unit >= 55296 && unit < 56320) {
            # A high surrogate needs a low one next.
            if (index + 1 < size) {
                var low = _text_unit(data, index, big_endian);
                if (low >= 56320 && low < 57344) {
                    index = index + 2;
                    _text_append_utf8(out, 65536 + ((unit - 55296) << 10) + (low - 56320));
                    continue;
                }
            }
            if (!lossy) {
                return false;
            }
            _text_append_utf8(out, 65533);
        } else if (unit >= 56320 && unit < 57344) {
            if (!lossy) {
                return false;
            }
            _text_append_utf8(out, 65533);
        } else {
            _text_append_utf8(out, unit);
        }
    }
    if (index < size) {
        if (!lossy) {
            return false;
        }
        _text_append_utf8(out, 65533);
    }
    return true;
}
