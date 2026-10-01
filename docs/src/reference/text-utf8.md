<!-- Generated from runtime/text/utf8.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# text/utf8.pep

UTF-8, the encoding a `String` holds.

Source: `runtime/text/utf8.pep`

## Utf8

```pepper
struct Utf8
```

Encodes a `String` to UTF-8 bytes and decodes them back. A String already
holds UTF-8, so encoding copies its bytes; decoding checks them.

**Example**
```pepper
    import text;

    var bytes = text.Utf8.encode("hi");
    assert(text.Utf8.decode(bytes).value() == "hi", "round trip");
```

### Static methods

#### encode

```pepper
static encode(value: String): u8[]
```

Returns the UTF-8 bytes of `value`, without a terminating NUL.

**Parameters**
- `value` — the text to encode

**Returns**
- a new array of `value.size()` bytes

#### is_valid

```pepper
static is_valid(bytes: u8[]): bool
```

Returns whether `bytes` is valid UTF-8: no stray continuation bytes,
no truncated, overlong or surrogate sequences, and nothing past
U+10FFFF.

**Parameters**
- `bytes` — the bytes to check

**Returns**
- true when every byte is part of a valid sequence

#### decode

```pepper
static decode(bytes: u8[]): String?
```

Decodes `bytes` as UTF-8, or gives none when they are not valid UTF-8
(see `is_valid`). A byte-order mark is kept as part of the text.

**Parameters**
- `bytes` — the bytes to decode

**Returns**
- the text, or none when `bytes` is not valid UTF-8

**Example**
```pepper
    import text;

    var bad = Array<u8>();
    bad.append(255);
    assert(text.Utf8.decode(bad).is_none(), "0xFF is never UTF-8");
```

#### decode_lossy

```pepper
static decode_lossy(bytes: u8[]): String
```

Decodes `bytes` as UTF-8, replacing each byte that does not start a
valid sequence with U+FFFD, so it always succeeds. Valid input gives
the same text as `decode`.

**Parameters**
- `bytes` — the bytes to decode

**Returns**
- the text

**Example**
```pepper
    import text;

    var data = Array<u8>();
    data.append(104);
    data.append(255);
    data.append(105);
    assert(text.Utf8.decode_lossy(data) == "h\u{FFFD}i", "255 is replaced");
```
