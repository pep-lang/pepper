<!-- Generated from runtime/number.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# number.pep

Reading numbers from text, and arithmetic that says what to do on
overflow.

Every number type has a static `parse`: `int.parse("42")` gives an
`int?`, empty when the text is not a number of that type. The integer
types take a base from 2 to 36; `float` and `double` read decimal
notation. Each spelling of a type is the same type, so `i32.parse` is
`int.parse`.

Integer `+`, `-` and `*` panic on overflow. Each integer type also has
`wrapping_add` (the result modulo 2^bits), `checked_add` (none on
overflow), `saturating_add` (clamped to the type's range) and
`overflowing_add` (the wrapped result and whether it overflowed), with
`sub` and `mul` forms of each.

**Example**
```pepper
    var port = int.parse("8080");
    assert(port.is_some() && port.value() == 8080, "parsed");
    assert(byte.parse("256").is_none(), "too big for a byte");
    int big = 2147483647;
    assert(big.wrapping_add(1) == -2147483648, "wraps around");
    assert(big.checked_add(1).is_none(), "does not fit");
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

### Methods

#### wrapping_add

```pepper
wrapping_add(other: char): char
```

Returns `this + other` modulo 2^8: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, wrapped to a `char`

#### checked_add

```pepper
checked_add(other: char): char?
```

Returns `this + other`, or none when the sum does not fit a
`char`.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or none on overflow

#### saturating_add

```pepper
saturating_add(other: char): char
```

Returns `this + other`, clamped to the highest or lowest `char` on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or the nearest `char` to it

#### overflowing_add

```pepper
overflowing_add(other: char): (char, bool)
```

Returns `this + other` modulo 2^8, and whether the operation
overflowed.

**Parameters**
- `other` — the value to add

**Returns**
- the wrapped sum, and true when it overflowed

#### wrapping_sub

```pepper
wrapping_sub(other: char): char
```

Returns `this - other` modulo 2^8: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, wrapped to a `char`

#### checked_sub

```pepper
checked_sub(other: char): char?
```

Returns `this - other`, or none when the difference does not fit a
`char`.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or none on overflow

#### saturating_sub

```pepper
saturating_sub(other: char): char
```

Returns `this - other`, clamped to the highest or lowest `char` on overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or the nearest `char` to it

#### overflowing_sub

```pepper
overflowing_sub(other: char): (char, bool)
```

Returns `this - other` modulo 2^8, and whether the operation
overflowed.

**Parameters**
- `other` — the value to subtract

**Returns**
- the wrapped difference, and true when it overflowed

#### wrapping_mul

```pepper
wrapping_mul(other: char): char
```

Returns `this * other` modulo 2^8: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, wrapped to a `char`

#### checked_mul

```pepper
checked_mul(other: char): char?
```

Returns `this * other`, or none when the product does not fit a
`char`.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or none on overflow

#### saturating_mul

```pepper
saturating_mul(other: char): char
```

Returns `this * other`, clamped to the highest or lowest `char` on overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or the nearest `char` to it

#### overflowing_mul

```pepper
overflowing_mul(other: char): (char, bool)
```

Returns `this * other` modulo 2^8, and whether the operation
overflowed.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the wrapped product, and true when it overflowed

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

### Methods

#### wrapping_add

```pepper
wrapping_add(other: byte): byte
```

Returns `this + other` modulo 2^8: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, wrapped to a `byte`

#### checked_add

```pepper
checked_add(other: byte): byte?
```

Returns `this + other`, or none when the sum does not fit a
`byte`.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or none on overflow

#### saturating_add

```pepper
saturating_add(other: byte): byte
```

Returns `this + other`, clamped to the highest `byte` on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or the nearest `byte` to it

#### overflowing_add

```pepper
overflowing_add(other: byte): (byte, bool)
```

Returns `this + other` modulo 2^8, and whether the operation
overflowed.

**Parameters**
- `other` — the value to add

**Returns**
- the wrapped sum, and true when it overflowed

#### wrapping_sub

```pepper
wrapping_sub(other: byte): byte
```

Returns `this - other` modulo 2^8: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, wrapped to a `byte`

#### checked_sub

```pepper
checked_sub(other: byte): byte?
```

Returns `this - other`, or none when the difference does not fit a
`byte`.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or none on overflow

#### saturating_sub

```pepper
saturating_sub(other: byte): byte
```

Returns `this - other`, clamped to 0 on overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or the nearest `byte` to it

#### overflowing_sub

```pepper
overflowing_sub(other: byte): (byte, bool)
```

Returns `this - other` modulo 2^8, and whether the operation
overflowed.

**Parameters**
- `other` — the value to subtract

**Returns**
- the wrapped difference, and true when it overflowed

#### wrapping_mul

```pepper
wrapping_mul(other: byte): byte
```

Returns `this * other` modulo 2^8: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, wrapped to a `byte`

#### checked_mul

```pepper
checked_mul(other: byte): byte?
```

Returns `this * other`, or none when the product does not fit a
`byte`.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or none on overflow

#### saturating_mul

```pepper
saturating_mul(other: byte): byte
```

Returns `this * other`, clamped to the highest `byte` on overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or the nearest `byte` to it

#### overflowing_mul

```pepper
overflowing_mul(other: byte): (byte, bool)
```

Returns `this * other` modulo 2^8, and whether the operation
overflowed.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the wrapped product, and true when it overflowed

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

### Methods

#### wrapping_add

```pepper
wrapping_add(other: short): short
```

Returns `this + other` modulo 2^16: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, wrapped to a `short`

#### checked_add

```pepper
checked_add(other: short): short?
```

Returns `this + other`, or none when the sum does not fit a
`short`.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or none on overflow

#### saturating_add

```pepper
saturating_add(other: short): short
```

Returns `this + other`, clamped to the highest or lowest `short` on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or the nearest `short` to it

#### overflowing_add

```pepper
overflowing_add(other: short): (short, bool)
```

Returns `this + other` modulo 2^16, and whether the operation
overflowed.

**Parameters**
- `other` — the value to add

**Returns**
- the wrapped sum, and true when it overflowed

#### wrapping_sub

```pepper
wrapping_sub(other: short): short
```

Returns `this - other` modulo 2^16: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, wrapped to a `short`

#### checked_sub

```pepper
checked_sub(other: short): short?
```

Returns `this - other`, or none when the difference does not fit a
`short`.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or none on overflow

#### saturating_sub

```pepper
saturating_sub(other: short): short
```

Returns `this - other`, clamped to the highest or lowest `short` on overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or the nearest `short` to it

#### overflowing_sub

```pepper
overflowing_sub(other: short): (short, bool)
```

Returns `this - other` modulo 2^16, and whether the operation
overflowed.

**Parameters**
- `other` — the value to subtract

**Returns**
- the wrapped difference, and true when it overflowed

#### wrapping_mul

```pepper
wrapping_mul(other: short): short
```

Returns `this * other` modulo 2^16: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, wrapped to a `short`

#### checked_mul

```pepper
checked_mul(other: short): short?
```

Returns `this * other`, or none when the product does not fit a
`short`.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or none on overflow

#### saturating_mul

```pepper
saturating_mul(other: short): short
```

Returns `this * other`, clamped to the highest or lowest `short` on overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or the nearest `short` to it

#### overflowing_mul

```pepper
overflowing_mul(other: short): (short, bool)
```

Returns `this * other` modulo 2^16, and whether the operation
overflowed.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the wrapped product, and true when it overflowed

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

### Methods

#### wrapping_add

```pepper
wrapping_add(other: ushort): ushort
```

Returns `this + other` modulo 2^16: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, wrapped to a `ushort`

#### checked_add

```pepper
checked_add(other: ushort): ushort?
```

Returns `this + other`, or none when the sum does not fit a
`ushort`.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or none on overflow

#### saturating_add

```pepper
saturating_add(other: ushort): ushort
```

Returns `this + other`, clamped to the highest `ushort` on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or the nearest `ushort` to it

#### overflowing_add

```pepper
overflowing_add(other: ushort): (ushort, bool)
```

Returns `this + other` modulo 2^16, and whether the operation
overflowed.

**Parameters**
- `other` — the value to add

**Returns**
- the wrapped sum, and true when it overflowed

#### wrapping_sub

```pepper
wrapping_sub(other: ushort): ushort
```

Returns `this - other` modulo 2^16: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, wrapped to a `ushort`

#### checked_sub

```pepper
checked_sub(other: ushort): ushort?
```

Returns `this - other`, or none when the difference does not fit a
`ushort`.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or none on overflow

#### saturating_sub

```pepper
saturating_sub(other: ushort): ushort
```

Returns `this - other`, clamped to 0 on overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or the nearest `ushort` to it

#### overflowing_sub

```pepper
overflowing_sub(other: ushort): (ushort, bool)
```

Returns `this - other` modulo 2^16, and whether the operation
overflowed.

**Parameters**
- `other` — the value to subtract

**Returns**
- the wrapped difference, and true when it overflowed

#### wrapping_mul

```pepper
wrapping_mul(other: ushort): ushort
```

Returns `this * other` modulo 2^16: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, wrapped to a `ushort`

#### checked_mul

```pepper
checked_mul(other: ushort): ushort?
```

Returns `this * other`, or none when the product does not fit a
`ushort`.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or none on overflow

#### saturating_mul

```pepper
saturating_mul(other: ushort): ushort
```

Returns `this * other`, clamped to the highest `ushort` on overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or the nearest `ushort` to it

#### overflowing_mul

```pepper
overflowing_mul(other: ushort): (ushort, bool)
```

Returns `this * other` modulo 2^16, and whether the operation
overflowed.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the wrapped product, and true when it overflowed

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

### Methods

#### wrapping_add

```pepper
wrapping_add(other: int): int
```

Returns `this + other` modulo 2^32: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, wrapped to a `int`

#### checked_add

```pepper
checked_add(other: int): int?
```

Returns `this + other`, or none when the sum does not fit a
`int`.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or none on overflow

#### saturating_add

```pepper
saturating_add(other: int): int
```

Returns `this + other`, clamped to the highest or lowest `int` on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or the nearest `int` to it

#### overflowing_add

```pepper
overflowing_add(other: int): (int, bool)
```

Returns `this + other` modulo 2^32, and whether the operation
overflowed.

**Parameters**
- `other` — the value to add

**Returns**
- the wrapped sum, and true when it overflowed

#### wrapping_sub

```pepper
wrapping_sub(other: int): int
```

Returns `this - other` modulo 2^32: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, wrapped to a `int`

#### checked_sub

```pepper
checked_sub(other: int): int?
```

Returns `this - other`, or none when the difference does not fit a
`int`.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or none on overflow

#### saturating_sub

```pepper
saturating_sub(other: int): int
```

Returns `this - other`, clamped to the highest or lowest `int` on overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or the nearest `int` to it

#### overflowing_sub

```pepper
overflowing_sub(other: int): (int, bool)
```

Returns `this - other` modulo 2^32, and whether the operation
overflowed.

**Parameters**
- `other` — the value to subtract

**Returns**
- the wrapped difference, and true when it overflowed

#### wrapping_mul

```pepper
wrapping_mul(other: int): int
```

Returns `this * other` modulo 2^32: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, wrapped to a `int`

#### checked_mul

```pepper
checked_mul(other: int): int?
```

Returns `this * other`, or none when the product does not fit a
`int`.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or none on overflow

#### saturating_mul

```pepper
saturating_mul(other: int): int
```

Returns `this * other`, clamped to the highest or lowest `int` on overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or the nearest `int` to it

#### overflowing_mul

```pepper
overflowing_mul(other: int): (int, bool)
```

Returns `this * other` modulo 2^32, and whether the operation
overflowed.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the wrapped product, and true when it overflowed

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

### Methods

#### wrapping_add

```pepper
wrapping_add(other: uint): uint
```

Returns `this + other` modulo 2^32: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, wrapped to a `uint`

#### checked_add

```pepper
checked_add(other: uint): uint?
```

Returns `this + other`, or none when the sum does not fit a
`uint`.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or none on overflow

#### saturating_add

```pepper
saturating_add(other: uint): uint
```

Returns `this + other`, clamped to the highest `uint` on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or the nearest `uint` to it

#### overflowing_add

```pepper
overflowing_add(other: uint): (uint, bool)
```

Returns `this + other` modulo 2^32, and whether the operation
overflowed.

**Parameters**
- `other` — the value to add

**Returns**
- the wrapped sum, and true when it overflowed

#### wrapping_sub

```pepper
wrapping_sub(other: uint): uint
```

Returns `this - other` modulo 2^32: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, wrapped to a `uint`

#### checked_sub

```pepper
checked_sub(other: uint): uint?
```

Returns `this - other`, or none when the difference does not fit a
`uint`.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or none on overflow

#### saturating_sub

```pepper
saturating_sub(other: uint): uint
```

Returns `this - other`, clamped to 0 on overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or the nearest `uint` to it

#### overflowing_sub

```pepper
overflowing_sub(other: uint): (uint, bool)
```

Returns `this - other` modulo 2^32, and whether the operation
overflowed.

**Parameters**
- `other` — the value to subtract

**Returns**
- the wrapped difference, and true when it overflowed

#### wrapping_mul

```pepper
wrapping_mul(other: uint): uint
```

Returns `this * other` modulo 2^32: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, wrapped to a `uint`

#### checked_mul

```pepper
checked_mul(other: uint): uint?
```

Returns `this * other`, or none when the product does not fit a
`uint`.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or none on overflow

#### saturating_mul

```pepper
saturating_mul(other: uint): uint
```

Returns `this * other`, clamped to the highest `uint` on overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or the nearest `uint` to it

#### overflowing_mul

```pepper
overflowing_mul(other: uint): (uint, bool)
```

Returns `this * other` modulo 2^32, and whether the operation
overflowed.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the wrapped product, and true when it overflowed

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

### Methods

#### wrapping_add

```pepper
wrapping_add(other: long): long
```

Returns `this + other` modulo 2^64: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, wrapped to a `long`

#### checked_add

```pepper
checked_add(other: long): long?
```

Returns `this + other`, or none when the sum does not fit a
`long`.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or none on overflow

#### saturating_add

```pepper
saturating_add(other: long): long
```

Returns `this + other`, clamped to the highest or lowest `long` on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or the nearest `long` to it

#### overflowing_add

```pepper
overflowing_add(other: long): (long, bool)
```

Returns `this + other` modulo 2^64, and whether the operation
overflowed.

**Parameters**
- `other` — the value to add

**Returns**
- the wrapped sum, and true when it overflowed

#### wrapping_sub

```pepper
wrapping_sub(other: long): long
```

Returns `this - other` modulo 2^64: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, wrapped to a `long`

#### checked_sub

```pepper
checked_sub(other: long): long?
```

Returns `this - other`, or none when the difference does not fit a
`long`.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or none on overflow

#### saturating_sub

```pepper
saturating_sub(other: long): long
```

Returns `this - other`, clamped to the highest or lowest `long` on overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or the nearest `long` to it

#### overflowing_sub

```pepper
overflowing_sub(other: long): (long, bool)
```

Returns `this - other` modulo 2^64, and whether the operation
overflowed.

**Parameters**
- `other` — the value to subtract

**Returns**
- the wrapped difference, and true when it overflowed

#### wrapping_mul

```pepper
wrapping_mul(other: long): long
```

Returns `this * other` modulo 2^64: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, wrapped to a `long`

#### checked_mul

```pepper
checked_mul(other: long): long?
```

Returns `this * other`, or none when the product does not fit a
`long`.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or none on overflow

#### saturating_mul

```pepper
saturating_mul(other: long): long
```

Returns `this * other`, clamped to the highest or lowest `long` on overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or the nearest `long` to it

#### overflowing_mul

```pepper
overflowing_mul(other: long): (long, bool)
```

Returns `this * other` modulo 2^64, and whether the operation
overflowed.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the wrapped product, and true when it overflowed

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

### Methods

#### wrapping_add

```pepper
wrapping_add(other: ulong): ulong
```

Returns `this + other` modulo 2^64: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, wrapped to a `ulong`

#### checked_add

```pepper
checked_add(other: ulong): ulong?
```

Returns `this + other`, or none when the sum does not fit a
`ulong`.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or none on overflow

#### saturating_add

```pepper
saturating_add(other: ulong): ulong
```

Returns `this + other`, clamped to the highest `ulong` on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the sum, or the nearest `ulong` to it

#### overflowing_add

```pepper
overflowing_add(other: ulong): (ulong, bool)
```

Returns `this + other` modulo 2^64, and whether the operation
overflowed.

**Parameters**
- `other` — the value to add

**Returns**
- the wrapped sum, and true when it overflowed

#### wrapping_sub

```pepper
wrapping_sub(other: ulong): ulong
```

Returns `this - other` modulo 2^64: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, wrapped to a `ulong`

#### checked_sub

```pepper
checked_sub(other: ulong): ulong?
```

Returns `this - other`, or none when the difference does not fit a
`ulong`.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or none on overflow

#### saturating_sub

```pepper
saturating_sub(other: ulong): ulong
```

Returns `this - other`, clamped to 0 on overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the difference, or the nearest `ulong` to it

#### overflowing_sub

```pepper
overflowing_sub(other: ulong): (ulong, bool)
```

Returns `this - other` modulo 2^64, and whether the operation
overflowed.

**Parameters**
- `other` — the value to subtract

**Returns**
- the wrapped difference, and true when it overflowed

#### wrapping_mul

```pepper
wrapping_mul(other: ulong): ulong
```

Returns `this * other` modulo 2^64: on overflow the result wraps
around instead of panicking. For hashes, checksums and random number
generators, which rely on wrapping.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, wrapped to a `ulong`

#### checked_mul

```pepper
checked_mul(other: ulong): ulong?
```

Returns `this * other`, or none when the product does not fit a
`ulong`.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or none on overflow

#### saturating_mul

```pepper
saturating_mul(other: ulong): ulong
```

Returns `this * other`, clamped to the highest `ulong` on overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the product, or the nearest `ulong` to it

#### overflowing_mul

```pepper
overflowing_mul(other: ulong): (ulong, bool)
```

Returns `this * other` modulo 2^64, and whether the operation
overflowed.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the wrapped product, and true when it overflowed

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
