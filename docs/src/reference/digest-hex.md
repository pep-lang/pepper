<!-- Generated from runtime/digest/hex.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Hexadecimal

Hexadecimal text for digests.

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
