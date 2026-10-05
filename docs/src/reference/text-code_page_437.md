<!-- Generated from runtime/text/code_page_437.pep by `pep-doc reference`. Do not edit. -->

# Code page 437

Code page 437, the character set of the original IBM PC, which old zip
archives use for entry names.

Source: `runtime/text/code_page_437.pep`

## CodePage437

```pepper
struct CodePage437
```

Encodes a `String` to code page 437 bytes and decodes them back. Bytes
below 128 are ASCII; each of the 128 above stands for one character
(accented letters, Greek letters, box-drawing and math symbols), so
every byte decodes and `decode` always succeeds. Bytes below 32 decode
as the ASCII control characters, not the PC's graphical glyphs, as zip
readers do.

**Example**
```pepper
import text;

var bytes = text.CodePage437.encode("café").value();
assert(bytes.count == 4 && bytes[3] == 0x82, "é is 0x82");
assert(text.CodePage437.decode(bytes) == "café", "round trip");
```

### Static methods

#### encode

```pepper
static encode(value: String): u8[]?
```

Returns the code page 437 bytes of `value`, or none when it holds a
character the code page lacks.

**Parameters**
- `value` — the text to encode

**Returns**
- a new array of one byte per code point, or none

#### encode_lossy

```pepper
static encode_lossy(value: String): u8[]
```

Returns the code page 437 bytes of `value`, with `?` for each
character the code page lacks.

**Parameters**
- `value` — the text to encode

**Returns**
- a new array of one byte per code point

#### decode

```pepper
static decode(bytes: u8[]): String
```

Decodes code page 437 `bytes`. Every byte is a character, so it
always succeeds.

**Parameters**
- `bytes` — the bytes to decode

**Returns**
- the text
