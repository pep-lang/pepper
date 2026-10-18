# Encodings and UUIDs

Networked programs keep writing bytes as text and back: credentials in an
HTTP header, a token in a URL, a value in a query string, an identifier in a
database. These live in a few places:

| What | Where | Functions |
|---|---|---|
| Base64 | `import base64` | `base64.encode`, `base64.decode` |
| Hexadecimal | `import digest` | `digest.to_hex`, `digest.from_hex` |
| Percent-escapes | `Uri`, in the prelude | `Uri.encode`, `Uri.decode` |
| Form data | `Uri`, in the prelude | `Uri.encode_form`, `Uri.decode_form` |
| UUIDs | `import uuid` | `Uuid.v4`, `Uuid.v7`, `Uuid.parse`, `to_string` |

```pepper
{{#include ../../examples/encodings.pep}}
```

## Base64

`base64.encode(bytes)` writes RFC 4648 base64 with the standard alphabet
(`A-Z a-z 0-9 + /`) and `=` padding. Two optional arguments change that:
`url_safe = true` uses `-` and `_` in place of `+` and `/`, so the text can
go in a URL or a file name, and `padded = false` leaves off the padding, as
JSON Web Tokens do.

`base64.decode(text)` returns a `Result<u8[]>`. It accepts text with or
without padding (pass `url_safe = true` for the other alphabet), and is
strict otherwise: whitespace, a character outside the alphabet, a length no
encoding gives, or unused bits that are not zero is an error. Remove line
breaks from PEM or MIME text before decoding it. The functions work on
whole arrays; there is no streaming encoder yet.

## Hexadecimal

`digest.to_hex(bytes)` writes two lowercase digits per byte, and
`digest.from_hex(text)` reads them back, in either case; an odd length or
a character that is not a digit is an error.

## Percent-escapes and form data

`Uri.encode(text)` escapes every byte outside RFC 3986's unreserved set
(`A-Z a-z 0-9 - . _ ~`), so the result is safe as one path segment or one
query value: `/`, `?`, `&`, `=` and `%` are escaped too. `Uri.decode`
reverses it.

`Uri.encode_form(pairs)` writes names and values as
`application/x-www-form-urlencoded`, the format of HTML forms and most
query strings (`q=pepper+lang&page=2`), and `Uri.decode_form(text)` reads
it back into an `Array<(String, String)>`, in order, keeping repeated
names. In this format a space is `+`.

## UUIDs

`uuid.Uuid` is a 128-bit identifier (RFC 9562), a
[value struct](value-structs.md) of two `ulong` halves, `high` and `low`,
so `==` and `hash` work and it can key a map.

- `Uuid.v4()` makes a random one: 122 bits from the operating system's
  secure source.
- `Uuid.v7()` puts the wall clock's Unix time in milliseconds first, then
  74 random bits, so ids made later sort later, both as values and as
  text. That keeps database indexes compact. Ids made in the same
  millisecond are in no particular order.
- `Uuid.parse(text)` reads the usual form,
  `0190163d-8694-739b-aea5-966c26f8ad91`, in either case, and
  `to_string()` (or interpolation) writes it in lowercase.
- `version()` returns the version digit and `bytes()` the 16 bytes, for a
  database or a binary format.

The full API is in the reference: [base64](../reference/base64-module.md),
[uuid](../reference/uuid-module.md), [hexadecimal](../reference/digest-hex.md)
and [`Uri`](../reference/uri.md).
