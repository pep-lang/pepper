<!-- Generated from runtime/number.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# number.pep

Reading numbers from text: every number type has a static `parse`.

`int.parse("42")` gives an `int?`, empty when the text is not a number
of that type. The integer types take a base from 2 to 36; `float` and
`double` read decimal notation. Each spelling of a type is the same
type, so `i32.parse` is `int.parse`.

**Example**
```pepper
    var port = int.parse("8080");
    assert(port.is_some() && port.value() == 8080, "parsed");
    assert(byte.parse("256").is_none(), "too big for a byte");
```

Source: `runtime/number.pep`

## extend char

```pepper
extend char
```

### Static methods

#### parse

```pepper
static parse(text: String, base: int = 10): char?
```

Parses `text` as a `char` (`i8`) written in `base`: an optional `+`
or `-`, then one or more digits, and nothing else. Digits past 9 are
the letters, either case. No spaces, prefixes (`0x`) or separators
are accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value is outside -128 to 127

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    assert(i8.parse("-128").value() == -128, "the lowest");
```

## extend byte

```pepper
extend byte
```

### Static methods

#### parse

```pepper
static parse(text: String, base: int = 10): byte?
```

Parses `text` as a `byte` (`u8`) written in `base`: an optional `+`,
then one or more digits, and nothing else. Digits past 9 are the
letters, either case. No spaces, prefixes (`0x`) or separators are
accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value is above 255 (a `-` sign is never accepted)

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    assert(byte.parse("ff", 16).value() == 255, "hexadecimal");
```

## extend short

```pepper
extend short
```

### Static methods

#### parse

```pepper
static parse(text: String, base: int = 10): short?
```

Parses `text` as a `short` (`i16`) written in `base`: an optional
`+` or `-`, then one or more digits, and nothing else. Digits past 9
are the letters, either case. No spaces, prefixes (`0x`) or
separators are accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value is outside -32768 to 32767

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    assert(short.parse("-300").value() == -300, "decimal");
```

## extend ushort

```pepper
extend ushort
```

### Static methods

#### parse

```pepper
static parse(text: String, base: int = 10): ushort?
```

Parses `text` as a `ushort` (`u16`) written in `base`: an optional
`+`, then one or more digits, and nothing else. Digits past 9 are the
letters, either case. No spaces, prefixes (`0x`) or separators are
accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value is above 65535 (a `-` sign is never accepted)

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    assert(ushort.parse("8080").value() == 8080, "a port");
```

## extend int

```pepper
extend int
```

### Static methods

#### parse

```pepper
static parse(text: String, base: int = 10): int?
```

Parses `text` as an `int` (`i32`) written in `base`: an optional `+`
or `-`, then one or more digits, and nothing else. Digits past 9 are
the letters, either case (`"ff"` in base 16 is 255). No spaces,
prefixes (`0x`) or separators are accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value does not fit an `int`

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    assert(int.parse("-42").value() == -42, "decimal");
    assert(int.parse("ff", 16).value() == 255, "hexadecimal");
    assert(int.parse("12x").is_none(), "not a number");
```

## extend uint

```pepper
extend uint
```

### Static methods

#### parse

```pepper
static parse(text: String, base: int = 10): uint?
```

Parses `text` as a `uint` (`u32`) written in `base`: an optional `+`,
then one or more digits, and nothing else. Digits past 9 are the
letters, either case. No spaces, prefixes (`0x`) or separators are
accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value does not fit a `uint` (a `-` sign is never accepted)

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    assert(uint.parse("4294967295").value() == 4294967295, "the highest");
```

## extend long

```pepper
extend long
```

### Static methods

#### parse

```pepper
static parse(text: String, base: int = 10): long?
```

Parses `text` as a `long` (`i64`) written in `base`: an optional `+`
or `-`, then one or more digits, and nothing else. Digits past 9 are
the letters, either case. No spaces, prefixes (`0x`) or separators
are accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value does not fit a `long`

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    assert(long.parse("-9000000000").value() == -9000000000, "decimal");
    assert(long.parse("9223372036854775808").is_none(), "too big");
```

## extend ulong

```pepper
extend ulong
```

### Static methods

#### parse

```pepper
static parse(text: String, base: int = 10): ulong?
```

Parses `text` as a `ulong` (`u64`) written in `base`: an optional
`+`, then one or more digits, and nothing else. Digits past 9 are the
letters, either case. No spaces, prefixes (`0x`) or separators are
accepted.

**Parameters**
- `text` — the text to parse
- `base` — the base the digits are written in, from 2 to 36; 10 by default

**Returns**
- the value, or none when `text` is not an integer in `base` or the value does not fit a `ulong` (a `-` sign is never accepted)

**Panics**
- if `base` is less than 2 or greater than 36

**Example**
```pepper
    assert(ulong.parse("ffffffffffffffff", 16).is_some(), "the highest");
```

## extend float

```pepper
extend float
```

### Static methods

#### parse

```pepper
static parse(text: String): float?
```

Parses `text` as a `float` written in decimal notation: an optional
`+` or `-`, digits with an optional `.` among them (`"1.5"`, `".5"`,
`"2."`), then an optional exponent (`"1e-3"`, `"2.5E8"`), and nothing
else. The value is the nearest `float`. No spaces, `inf`, `nan` or
hexadecimal are accepted.

**Parameters**
- `text` — the text to parse

**Returns**
- the value, or none when `text` is not decimal notation or its value is too large for a `float` (one too small rounds to zero)

**Example**
```pepper
    assert(float.parse("0.25").value() == 0.25, "decimal");
    assert(float.parse("1e39").is_none(), "too big");
```

## extend double

```pepper
extend double
```

### Static methods

#### parse

```pepper
static parse(text: String): double?
```

Parses `text` as a `double` written in decimal notation: an optional
`+` or `-`, digits with an optional `.` among them (`"1.5"`, `".5"`,
`"2."`), then an optional exponent (`"1e-3"`, `"2.5E8"`), and nothing
else. The value is the nearest `double`. No spaces, `inf`, `nan` or
hexadecimal are accepted.

**Parameters**
- `text` — the text to parse

**Returns**
- the value, or none when `text` is not decimal notation or its value is too large for a `double` (one too small rounds to zero)

**Example**
```pepper
    assert(double.parse("-2.5e3").value() == -2500.0, "an exponent");
    assert(double.parse("1.5.2").is_none(), "not a number");
```
