## Reading integers from text.

## Deprecated: use `long.parse` instead, which every program has without an
## import (each number type has a static `parse`).
##
## Parses `text` as an integer written in `base`: an optional `+` or `-`,
## then one or more digits, and nothing else.
##
## @param text the text to parse
## @param base the base the digits are written in, from 2 to 36; 10 by
##   default
## @returns the value, or none when `text` is not an integer in `base` or
##   the value does not fit a `long`
## @panics if `base` is less than 2 or greater than 36
[Deprecated("use 'long.parse' instead")]
export parse_int(text: String, base: int = 10): long? {
    return long.parse(text, base);
}
