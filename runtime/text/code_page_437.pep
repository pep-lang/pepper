## Code page 437, the character set of the original IBM PC, which old zip
## archives use for entry names.

import "utf8";

## Encodes a `String` to code page 437 bytes and decodes them back. Bytes
## below 128 are ASCII; each of the 128 above stands for one character
## (accented letters, Greek letters, box-drawing and math symbols), so
## every byte decodes and `decode` always succeeds. Bytes below 32 decode
## as the ASCII control characters, not the PC's graphical glyphs, as zip
## readers do.
##
## @example
##     import text;
##
##     var bytes = text.CodePage437.encode("café").value();
##     assert(bytes.count == 4 && bytes[3] == 0x82, "é is 0x82");
##     assert(text.CodePage437.decode(bytes) == "café", "round trip");
export struct CodePage437 {
    ## Returns the code page 437 bytes of `value`, or none when it holds a
    ## character the code page lacks.
    ##
    ## @param value the text to encode
    ## @returns a new array of one byte per code point, or none
    static encode(value: String): u8[]? {
        var out = Array<u8>(value.size);
        if (!_text_encode_437(value, out, false)) {
            return Optional<u8[]>.Empty;
        }
        return Optional<u8[]>.Value(out);
    }

    ## Returns the code page 437 bytes of `value`, with `?` for each
    ## character the code page lacks.
    ##
    ## @param value the text to encode
    ## @returns a new array of one byte per code point
    static encode_lossy(value: String): u8[] {
        var out = Array<u8>(value.size);
        _text_encode_437(value, out, true);
        return out;
    }

    ## Decodes code page 437 `bytes`. Every byte is a character, so it
    ## always succeeds.
    ##
    ## @param bytes the bytes to decode
    ## @returns the text
    static decode(bytes: u8[]): String {
        var table = _text_437_high();
        var out = Array<u8>(bytes.count);
        for (var value in bytes) {
            if (value < 128) {
                out.append(value);
            } else {
                _text_append_utf8(out, table[(value - 128) as ulong]);
            }
        }
        return Utf8.decode_lossy(out);
    }
}

# Appends the code page 437 bytes of `value` to `out`; a character the code
# page lacks becomes `?` when `lossy` is set, and otherwise stops the
# encoding with false.
_text_encode_437(value: String, out: u8[], lossy: bool): bool {
    var table = _text_437_high();
    ulong offset = 0;
    while (offset < value.size) {
        var (code_point, length) = Utf8.code_point_at(value, offset);
        offset += length;
        if (code_point < 128) {
            out.append(code_point as u8);
            continue;
        }
        var found = false;
        ulong index = 0;
        while (index < 128) {
            if (table[index] == code_point) {
                out.append((index + 128) as u8);
                found = true;
                break;
            }
            index += 1;
        }
        if (!found) {
            if (!lossy) {
                return false;
            }
            out.append(63);  # '?'
        }
    }
    return true;
}

# The code points of bytes 128 through 255.
_text_437_high(): uint[] {
    # format: off
    return [
        0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7,
        0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
        0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9,
        0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
        0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA,
        0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
        0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
        0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
        0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,
        0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
        0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,
        0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
        0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4,
        0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
        0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248,
        0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0,
    ];
    # format: on
}
