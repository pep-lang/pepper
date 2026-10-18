<!-- Generated from runtime/base64/module.pep by `pep-doc reference`. Do not edit. -->

# The base64 module

Base64 (RFC 4648): bytes written as text, for HTTP basic authentication,
data URIs, JSON Web Tokens, PEM files and WebSocket handshakes.

Bring it in with `import base64`. `encode` writes the standard alphabet
(`A-Z a-z 0-9 + /`) with `=` padding; pass `url_safe` for the URL and
file name alphabet (`-` and `_` in place of `+` and `/`), and
`padded = false` to leave the padding off, as JSON Web Tokens do.
`decode` takes text with or without padding, and rejects anything else
that is not base64, including whitespace.

**Example**
```pepper
import base64;

main(): int {
    var text = base64.encode("user:secret".bytes());
    assert(text == "dXNlcjpzZWNyZXQ=", "standard, padded");
    var bytes = base64.decode(text).value();
    assert(bytes.count == 11 && bytes[0] == 'u', "round trip");
    assert(base64.encode([251, 255], true, false) == "-_8", "URL-safe, unpadded");
    return 0;
}
```

Source: `runtime/base64/module.pep`

## encode

```pepper
encode(bytes: u8[], url_safe: bool = false, padded: bool = true): String
```

Returns `bytes` as base64 text: four characters for each three bytes.

**Parameters**
- `bytes` — the bytes to write
- `url_safe` — true for the URL and file name alphabet, with `-` and `_` in place of `+` and `/`
- `padded` — false to leave off the `=` that pads the text to a multiple of four characters

**Returns**
- the base64 text, empty when `bytes` is

**Example**
```pepper
assert(base64.encode("hi".bytes()) == "aGk=", "padded");
assert(base64.encode("hi".bytes(), false, false) == "aGk", "unpadded");
```

## decode

```pepper
decode(text: String, url_safe: bool = false): Result<u8[]>
```

Returns the bytes that base64 `text` stands for.

The padding is optional, but when present it must complete the last
group of four. The decoding is strict, so each text has one meaning: a
character outside the alphabet (whitespace included), a length no
encoding gives, or unused bits that are not zero is an error.

**Parameters**
- `text` — base64 text, such as `aGk=` or `aGk`
- `url_safe` — true for the URL and file name alphabet, with `-` and `_` in place of `+` and `/`

**Returns**
- the decoded bytes, or an error naming what is not base64

**Example**
```pepper
var bytes = base64.decode("aGk").value();
assert(bytes.count == 2 && bytes[1] == 'i', "unpadded");
assert(base64.decode("a b=").is_err(), "a space");
```
