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
- a new array of `value.size` bytes

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

#### find_invalid

```pepper
static find_invalid(value: String): ulong?
```

Returns the byte offset of the first byte of `value` that does not
start a valid UTF-8 sequence (see `is_valid`), or none when all of it
is valid. A `String` made from checked bytes is always valid; one made
from C memory may not be.

**Parameters**
- `value` — the text to check

**Returns**
- the offset of the first invalid byte, or none

**Example**
```pepper
    import text;

    assert(text.Utf8.find_invalid("héllo").is_none(), "valid");
```

#### code_point_at

```pepper
static code_point_at(value: String, offset: ulong): (uint, ulong)
```

Decodes the code point whose UTF-8 sequence starts at byte `offset`
of `value`.

**Parameters**
- `value` — the text to read
- `offset` — the byte offset where the sequence starts

**Returns**
- the code point and the number of bytes its sequence takes, from 1 to 4, so `offset` plus that is where the next one starts

**Panics**
- if `offset` is not less than `value.size` ("Utf8.code_point_at offset out of bounds")
- if no valid sequence starts at `offset` ("Utf8.code_point_at found invalid UTF-8")

**Example**
```pepper
    import text;

    var (point, run) = text.Utf8.code_point_at("é!", 0);
    assert(point == 233 and run == 2, "U+00E9 takes two bytes");
```

#### append_code_point

```pepper
static append_code_point(out: u8[], code_point: uint)
```

Appends the UTF-8 encoding of `code_point`, from 1 to 4 bytes, to
`out`.

**Parameters**
- `out` — the bytes to append to
- `code_point` — the code point to encode

**Panics**
- if `code_point` is a surrogate (U+D800 to U+DFFF) or above U+10FFFF ("Utf8.append_code_point needs a Unicode scalar value")

**Example**
```pepper
    import text;

    var out = Array<u8>();
    text.Utf8.append_code_point(out, 8364);
    assert(text.Utf8.decode(out).value() == "€", "U+20AC");
```
