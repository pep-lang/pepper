## Hexadecimal text for digests.

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

# The lowercase hexadecimal digit for `value` (0-15).
_digest_hex_digit(value: uint): u8 {
    if (value < 10) {
        return ('0' + value) as u8;
    }
    return ('a' + value - 10) as u8;
}
