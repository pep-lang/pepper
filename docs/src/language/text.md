# Text encodings

A `String` always holds UTF-8. The `text` module converts text to and from
the bytes of an encoding (`u8[]`), for files, network protocols and C
libraries that use another one:

```pepper
{{#include ../../examples/text-encodings.pep}}
```

| Type | Encoding |
|------|----------|
| `text.Utf8` | UTF-8. `encode` copies the String's bytes; `decode` checks them. `is_valid` checks bytes without decoding, and `find_invalid` gives the offset of a String's first invalid byte. `code_point_at` reads one code point and `append_code_point` writes one. |
| `text.Utf16` | UTF-16, two bytes per code unit, little-endian by default (`encode(s, true)` and `decode(bytes, true)` for big-endian). A code point past U+FFFF takes a surrogate pair. |
| `text.Ascii` | ASCII: code points below 128, one byte each. `is_ascii` checks a String. |

- **`decode`** is strict: it gives Empty when the bytes are not valid in the
  encoding (a stray UTF-8 continuation byte, an unpaired UTF-16 surrogate,
  an odd UTF-16 byte count, an ASCII byte of 128 or more).
- **`decode_lossy`** always succeeds: whatever is invalid becomes U+FFFD,
  the replacement character.
- **`Ascii.encode`** gives Empty for text with a code point past 127;
  **`encode_lossy`** writes `?` for each instead.
- No byte-order mark is written, and one that is read stays in the text.
- `io.File.read_string` decodes with `text.Utf8.decode`, and an HTTP body's
  `text()` with `decode_lossy`.

The [reference](../reference/text-module.md) lists every function.
