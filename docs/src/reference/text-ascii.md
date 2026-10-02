<!-- Generated from runtime/text/ascii.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# text/ascii.pep

ASCII, the first 128 code points, one byte each.

Source: `runtime/text/ascii.pep`

## Ascii

```pepper
struct Ascii
```

Encodes a `String` to ASCII bytes and decodes them back. Only code
points below 128 have an ASCII byte.

**Example**
```pepper
    import text;

    assert(text.Ascii.encode("ok").value().count == 2, "one byte each");
    assert(text.Ascii.encode("é").is_empty(), "not ASCII");
```

### Static methods

#### encode

```pepper
static encode(value: String): u8[]?
```

Returns the ASCII bytes of `value`, or none when it holds a code
point past 127.

**Parameters**
- `value` — the text to encode

**Returns**
- a new array of one byte per code point, or none

#### encode_lossy

```pepper
static encode_lossy(value: String): u8[]
```

Returns the ASCII bytes of `value`, with `?` for each code point past
127.

**Parameters**
- `value` — the text to encode

**Returns**
- a new array of one byte per code point

#### is_ascii

```pepper
static is_ascii(value: String): bool
```

Returns whether every code point of `value` is ASCII (below 128).

**Parameters**
- `value` — the text to check

**Returns**
- true when `value` is all ASCII

#### decode

```pepper
static decode(bytes: u8[]): String?
```

Decodes ASCII `bytes`, or gives none when one is 128 or more.

**Parameters**
- `bytes` — the bytes to decode

**Returns**
- the text, or none when `bytes` is not all ASCII

#### decode_lossy

```pepper
static decode_lossy(bytes: u8[]): String
```

Decodes ASCII `bytes`, replacing each byte of 128 or more with
U+FFFD, so it always succeeds.

**Parameters**
- `bytes` — the bytes to decode

**Returns**
- the text
