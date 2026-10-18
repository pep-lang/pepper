## Base64 (RFC 4648): bytes written as text, for HTTP basic authentication,
## data URIs, JSON Web Tokens, PEM files and WebSocket handshakes.
##
## Bring it in with `import base64`. `encode` writes the standard alphabet
## (`A-Z a-z 0-9 + /`) with `=` padding; pass `url_safe` for the URL and
## file name alphabet (`-` and `_` in place of `+` and `/`), and
## `padded = false` to leave the padding off, as JSON Web Tokens do.
## `decode` takes text with or without padding, and rejects anything else
## that is not base64, including whitespace.
##
## @example
##     import base64;
##
##     main(): int {
##         var text = base64.encode("user:secret".bytes());
##         assert(text == "dXNlcjpzZWNyZXQ=", "standard, padded");
##         var bytes = base64.decode(text).value();
##         assert(bytes.count == 11 && bytes[0] == 'u', "round trip");
##         assert(base64.encode([251, 255], true, false) == "-_8", "URL-safe, unpadded");
##         return 0;
##     }

## Returns `bytes` as base64 text: four characters for each three bytes.
##
## @param bytes the bytes to write
## @param url_safe true for the URL and file name alphabet, with `-` and `_`
##   in place of `+` and `/`
## @param padded false to leave off the `=` that pads the text to a
##   multiple of four characters
## @returns the base64 text, empty when `bytes` is
## @example
##     assert(base64.encode("hi".bytes()) == "aGk=", "padded");
##     assert(base64.encode("hi".bytes(), false, false) == "aGk", "unpadded");
export encode(bytes: u8[], url_safe: bool = false, padded: bool = true): String {
    var standard = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var alphabet = (url_safe ? standard.replace("+/", "-_") : standard).bytes();
    var out = Array<u8>((bytes.count + 2) / 3 * 4);
    ulong index = 0;
    while (index < bytes.count) {
        var left = bytes.count - index;
        var group = (bytes[index] as uint) << 16;
        if (left > 1) {
            group |= (bytes[index + 1] as uint) << 8;
        }
        if (left > 2) {
            group |= bytes[index + 2] as uint;
        }
        out.append(alphabet[((group >> 18) & 63) as ulong]);
        out.append(alphabet[((group >> 12) & 63) as ulong]);
        if (left > 1) {
            out.append(alphabet[((group >> 6) & 63) as ulong]);
        } else if (padded) {
            out.append('=' as u8);
        }
        if (left > 2) {
            out.append(alphabet[(group & 63) as ulong]);
        } else if (padded) {
            out.append('=' as u8);
        }
        index += 3;
    }
    return String._from_bytes(out);
}

## Returns the bytes that base64 `text` stands for.
##
## The padding is optional, but when present it must complete the last
## group of four. The decoding is strict, so each text has one meaning: a
## character outside the alphabet (whitespace included), a length no
## encoding gives, or unused bits that are not zero is an error.
##
## @param text base64 text, such as `aGk=` or `aGk`
## @param url_safe true for the URL and file name alphabet, with `-` and `_`
##   in place of `+` and `/`
## @returns the decoded bytes, or an error naming what is not base64
## @example
##     var bytes = base64.decode("aGk").value();
##     assert(bytes.count == 2 && bytes[1] == 'i', "unpadded");
##     assert(base64.decode("a b=").is_err(), "a space");
export decode(text: String, url_safe: bool = false): Result<u8[]> {
    var data = text.bytes();
    var size = data.count;
    if (size % 4 == 0 && size > 0 && data[size - 1] == '=') {
        size -= data[size - 2] == '=' ? 2 : 1;
    }
    if (size % 4 == 1) {
        return Result<u8[]>.err(Error($"invalid base64 length in '{text}'"));
    }
    var out = Array<u8>(size * 3 / 4);
    uint accumulator = 0;
    uint bits = 0;
    ulong index = 0;
    while (index < size) {
        var value = _base64_value(data[index] as int, url_safe);
        if (value < 0) {
            return Result<u8[]>.err(Error($"invalid base64 character at offset {index} in '{text}'"));
        }
        accumulator = (accumulator << 6) | value as uint;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.append((accumulator >> bits) as u8);
            accumulator &= ((1 as uint) << bits) - 1;
        }
        index += 1;
    }
    if (accumulator != 0) {
        return Result<u8[]>.err(Error($"invalid base64 ending in '{text}'"));
    }
    return Result<u8[]>.ok(out);
}

# The value (0-63) of the base64 character `c`, or -1 when it is not one.
_base64_value(c: int, url_safe: bool): int {
    if (c >= 'A' && c <= 'Z') {
        return c - 'A';
    }
    if (c >= 'a' && c <= 'z') {
        return c - 'a' + 26;
    }
    if (c >= '0' && c <= '9') {
        return c - '0' + 52;
    }
    if (c == (url_safe ? '-' : '+')) {
        return 62;
    }
    if (c == (url_safe ? '_' : '/')) {
        return 63;
    }
    return -1;
}
