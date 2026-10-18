## Hexadecimal text for digests, and back.

import "words";

## Returns `bytes` as lowercase hexadecimal text, two digits per byte, the
## way checksums and git object ids are usually written.
##
## @param bytes the bytes to write, such as a digest from `finish`
## @returns a String of `2 * bytes.count` characters from `0-9a-f`
## @example
##     import digest;
##
##     assert(digest.to_hex([0, 15, 255]) == "000fff", "two digits per byte");
export to_hex(bytes: u8[]): String {
    var out = Array<u8>(bytes.count * 2);
    ulong index = 0;
    while (index < bytes.count) {
        var value = bytes[index] as uint;
        out.append(_digest_hex_digit(value >> 4));
        out.append(_digest_hex_digit(value & 15));
        index += 1;
    }
    return String._from_bytes(out);
}

## Returns the bytes that hexadecimal `text` stands for, two digits per
## byte, the reverse of `to_hex`. Upper- and lowercase digits are both
## accepted.
##
## @param text hexadecimal text, such as a checksum
## @returns the bytes, or an error when `text` has an odd length or a
##   character that is not a hexadecimal digit
## @example
##     import digest;
##
##     var bytes = digest.from_hex("000fFF").value();
##     assert(bytes.count == 3 && bytes[2] == 255, "two digits per byte");
##     assert(digest.from_hex("abc").is_err(), "an odd length");
export from_hex(text: String): Result<u8[]> {
    var data = text.bytes();
    if (data.count % 2 != 0) {
        return Result<u8[]>.err(Error($"odd length of hexadecimal text '{text}'"));
    }
    var out = Array<u8>(data.count / 2);
    ulong index = 0;
    while (index < data.count) {
        var high = _pep_hex_digit(data[index] as int);
        var low = _pep_hex_digit(data[index + 1] as int);
        if (high < 0 || low < 0) {
            return Result<u8[]>.err(Error($"invalid hexadecimal digit in '{text}'"));
        }
        out.append((high * 16 + low) as u8);
        index += 2;
    }
    return Result<u8[]>.ok(out);
}

# The lowercase hexadecimal digit for `value` (0-15).
_digest_hex_digit(value: uint): u8 {
    if (value < 10) {
        return ('0' + value) as u8;
    }
    return ('a' + value - 10) as u8;
}
