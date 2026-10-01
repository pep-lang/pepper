<!-- Generated from runtime/math/parse.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# math/parse.pep

Reading integers from text.

Source: `runtime/math/parse.pep`

## parse_int

```pepper
parse_int(text: String, base: int = 10): long?
```

Parses `text` as an integer written in `base`: an optional `+` or `-`,
then one or more digits, and nothing else. Digits past 9 are the
letters, either case (`"ff"` in base 16 is 255). No spaces, prefixes
(`0x`) or separators are accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value does not fit a `long`

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    import math;

    assert(math.parse_int("-42").value() == -42, "decimal");
    assert(math.parse_int("ff", 16).value() == 255, "hexadecimal");
    assert(!math.parse_int("12x").is_some(), "not a number");
    assert(!math.parse_int("9223372036854775808").is_some(), "too big");
```
