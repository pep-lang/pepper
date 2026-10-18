<!-- Generated from runtime/digest/hex.pep by `pep-doc reference`. Do not edit. -->

# Hexadecimal

Hexadecimal text for digests, and back.

Source: `runtime/digest/hex.pep`

## to_hex

```pepper
to_hex(bytes: u8[]): String
```

Returns `bytes` as lowercase hexadecimal text, two digits per byte, the
way checksums and git object ids are usually written.

**Parameters**
- `bytes` — the bytes to write, such as a digest from `finish`

**Returns**
- a String of `2 * bytes.count` characters from `0-9a-f`

**Example**
```pepper
import digest;

assert(digest.to_hex([0, 15, 255]) == "000fff", "two digits per byte");
```

## from_hex

```pepper
from_hex(text: String): Result<u8[]>
```

Returns the bytes that hexadecimal `text` stands for, two digits per
byte, the reverse of `to_hex`. Upper- and lowercase digits are both
accepted.

**Parameters**
- `text` — hexadecimal text, such as a checksum

**Returns**
- the bytes, or an error when `text` has an odd length or a character that is not a hexadecimal digit

**Example**
```pepper
import digest;

var bytes = digest.from_hex("000fFF").value();
assert(bytes.count == 3 && bytes[2] == 255, "two digits per byte");
assert(digest.from_hex("abc").is_err(), "an odd length");
```
