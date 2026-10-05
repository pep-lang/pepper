<!-- Generated from runtime/math/parse.pep by `pep-doc reference`. Do not edit. -->

# Parsing integers

Reading integers from text.

Source: `runtime/math/parse.pep`

## parse_int

```pepper
[Deprecated("use 'long.parse' instead")] parse_int(text: String, base: int = 10): long?
```

Deprecated: use `long.parse` instead, which every program has without an
import (each number type has a static `parse`).

Parses `text` as an integer written in `base`: an optional `+` or `-`,
then one or more digits, and nothing else.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value does not fit a `long`

**Panics**
- if `base` is less than 2 or greater than 36
