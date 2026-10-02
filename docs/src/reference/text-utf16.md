<!-- Generated from runtime/text/utf16.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# text/utf16.pep

UTF-16, as Windows and Java hold text.

Source: `runtime/text/utf16.pep`

## Utf16

```pepper
struct Utf16
```

Encodes a `String` to UTF-16 bytes and decodes them back. Each code
unit takes two bytes, little-endian unless `big_endian` is set; a code
point past U+FFFF takes two units (a surrogate pair). No byte-order mark
is written, and one read is kept as part of the text.

**Example**
```pepper
    import text;

    var bytes = text.Utf16.encode("hi");
    assert(bytes.count == 4 && bytes[0] == 104 && bytes[1] == 0, "little-endian");
    assert(text.Utf16.decode(bytes).value() == "hi", "round trip");
```

### Static methods

#### encode

```pepper
static encode(value: String, big_endian: bool = false): u8[]
```

Returns the UTF-16 bytes of `value`.

**Parameters**
- `value` — the text to encode
- `big_endian` — whether each code unit's high byte comes first; false (little-endian) by default

**Returns**
- a new array of two bytes per code unit

#### decode

```pepper
static decode(bytes: u8[], big_endian: bool = false): String?
```

Decodes UTF-16 `bytes`, or gives none when they are not valid UTF-16:
an odd number of bytes, or a surrogate without its partner.

**Parameters**
- `bytes` — the bytes to decode
- `big_endian` — whether each code unit's high byte comes first; false (little-endian) by default

**Returns**
- the text, or none when `bytes` is not valid UTF-16

#### decode_lossy

```pepper
static decode_lossy(bytes: u8[], big_endian: bool = false): String
```

Decodes UTF-16 `bytes`, replacing each unpaired surrogate, and a
final odd byte, with U+FFFD, so it always succeeds.

**Parameters**
- `bytes` — the bytes to decode
- `big_endian` — whether each code unit's high byte comes first; false (little-endian) by default

**Returns**
- the text
