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

Each integer type also has bit operations that compile to one
instruction on most CPUs (`leading_zeros`, `trailing_zeros`,
`count_ones`, `count_zeros`, `swap_bytes`, `reverse_bits`, `rotate_left`,
`rotate_right`), and `min`, `max` and, when signed, `abs`. `float` and
`double` have `square_root`, `floor`, `ceiling`, `truncate`, `round`,
`abs`, `copy_sign`, `multiply_add`, `min` and `max`.

**Example**
```pepper
    var port = int.parse("8080");
    assert(port.is_value() && port.value() == 8080, "parsed");
    assert(byte.parse("256").is_empty(), "too big for a byte");
    int big = 2147483647;
    assert(big.wrapping_add(1) == -2147483648, "wraps around");
    assert(big.checked_add(1).is_empty(), "does not fit");
    assert((40 as uint).trailing_zeros() == 3, "40 is 0b101000");
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

#### leading_zeros

```pepper
leading_zeros(): int
```

Returns the number of zero bits above the highest set bit: 8 for
zero, 0 when the highest bit is set. One instruction on most CPUs
(`llvm.ctlz`).

**Returns**
- the count of leading zero bits, from 0 to 8

**Example**
```pepper
    assert(((1 as char)).leading_zeros() == 7, "one bit, at the bottom");
```

#### trailing_zeros

```pepper
trailing_zeros(): int
```

Returns the number of zero bits below the lowest set bit: 8 for
zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
first set bit of a mask without a loop.

**Returns**
- the count of trailing zero bits, from 0 to 8

**Example**
```pepper
    assert((8 as char).trailing_zeros() == 3, "8 is 0b1000");
```

#### count_ones

```pepper
count_ones(): int
```

Returns the number of bits that are set (the population count,
`llvm.ctpop`).

**Returns**
- the count of one bits, from 0 to 8

**Example**
```pepper
    assert((11 as char).count_ones() == 3, "three bits set");
```

#### count_zeros

```pepper
count_zeros(): int
```

Returns the number of bits that are clear.

**Returns**
- the count of zero bits, from 0 to 8

**Example**
```pepper
    assert((11 as char).count_zeros() == 5, "three bits set");
```

#### swap_bytes

```pepper
swap_bytes(): char
```

Returns this value with its bytes in reverse order: a one-byte value
is itself. Each integer type has this method; see `int.swap_bytes`.

**Returns**
- this value

#### reverse_bits

```pepper
reverse_bits(): char
```

Returns this value with its bits in reverse order: the lowest bit
becomes the highest (`llvm.bitreverse`).

**Returns**
- the value with its 8 bits reversed

**Example**
```pepper
    assert(((1 as char)).reverse_bits().leading_zeros() == 0, "bottom to top");
```

#### rotate_left

```pepper
rotate_left(count: int): char
```

Returns this value's bits rotated left by `count`: the bits shifted
out at the top come back in at the bottom (`llvm.fshl`). `count` is
taken modulo 8, so a negative count rotates right.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert((9 as char).rotate_left(7) == (9 as char).rotate_right(1), "the same rotation");
```

#### rotate_right

```pepper
rotate_right(count: int): char
```

Returns this value's bits rotated right by `count`: the bits shifted
out at the bottom come back in at the top (`llvm.fshr`). `count` is
taken modulo 8, so a negative count rotates left.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert(((1 as char)).rotate_right(1) == ((1 as char)).rotate_left(7), "the bottom bit to the top");
```

#### min

```pepper
min(other: char): char
```

Returns the smaller of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not greater than `other`, else `other`

**Example**
```pepper
    assert((3 as char).min(5) == 3, "smaller");
```

#### max

```pepper
max(other: char): char
```

Returns the larger of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not less than `other`, else `other`

**Example**
```pepper
    assert((3 as char).max(5) == 5, "larger");
```

#### abs

```pepper
abs(location: __ptr<char> = __caller_location()): char
```

Returns the absolute value: `this` without its sign. The lowest
value, -128, has no positive counterpart in a `char`, so it panics, as
its negation does.

**Parameters**
- `location` — where a failure is reported; left out, this call's location

**Returns**
- `-this` when this value is negative, else `this`

**Panics**
- if this value is -128 ("integer overflow in 'char' absolute value")

**Example**
```pepper
    assert((-5 as char).abs() == 5, "negative");
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

#### leading_zeros

```pepper
leading_zeros(): int
```

Returns the number of zero bits above the highest set bit: 8 for
zero, 0 when the highest bit is set. One instruction on most CPUs
(`llvm.ctlz`).

**Returns**
- the count of leading zero bits, from 0 to 8

**Example**
```pepper
    assert(((1 as byte)).leading_zeros() == 7, "one bit, at the bottom");
```

#### trailing_zeros

```pepper
trailing_zeros(): int
```

Returns the number of zero bits below the lowest set bit: 8 for
zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
first set bit of a mask without a loop.

**Returns**
- the count of trailing zero bits, from 0 to 8

**Example**
```pepper
    assert((8 as byte).trailing_zeros() == 3, "8 is 0b1000");
```

#### count_ones

```pepper
count_ones(): int
```

Returns the number of bits that are set (the population count,
`llvm.ctpop`).

**Returns**
- the count of one bits, from 0 to 8

**Example**
```pepper
    assert((11 as byte).count_ones() == 3, "three bits set");
```

#### count_zeros

```pepper
count_zeros(): int
```

Returns the number of bits that are clear.

**Returns**
- the count of zero bits, from 0 to 8

**Example**
```pepper
    assert((11 as byte).count_zeros() == 5, "three bits set");
```

#### swap_bytes

```pepper
swap_bytes(): byte
```

Returns this value with its bytes in reverse order: a one-byte value
is itself. Each integer type has this method; see `int.swap_bytes`.

**Returns**
- this value

#### reverse_bits

```pepper
reverse_bits(): byte
```

Returns this value with its bits in reverse order: the lowest bit
becomes the highest (`llvm.bitreverse`).

**Returns**
- the value with its 8 bits reversed

**Example**
```pepper
    assert(((1 as byte)).reverse_bits().leading_zeros() == 0, "bottom to top");
```

#### rotate_left

```pepper
rotate_left(count: int): byte
```

Returns this value's bits rotated left by `count`: the bits shifted
out at the top come back in at the bottom (`llvm.fshl`). `count` is
taken modulo 8, so a negative count rotates right.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert((9 as byte).rotate_left(7) == (9 as byte).rotate_right(1), "the same rotation");
```

#### rotate_right

```pepper
rotate_right(count: int): byte
```

Returns this value's bits rotated right by `count`: the bits shifted
out at the bottom come back in at the top (`llvm.fshr`). `count` is
taken modulo 8, so a negative count rotates left.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert(((1 as byte)).rotate_right(1) == ((1 as byte)).rotate_left(7), "the bottom bit to the top");
```

#### min

```pepper
min(other: byte): byte
```

Returns the smaller of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not greater than `other`, else `other`

**Example**
```pepper
    assert((3 as byte).min(5) == 3, "smaller");
```

#### max

```pepper
max(other: byte): byte
```

Returns the larger of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not less than `other`, else `other`

**Example**
```pepper
    assert((3 as byte).max(5) == 5, "larger");
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

#### leading_zeros

```pepper
leading_zeros(): int
```

Returns the number of zero bits above the highest set bit: 16 for
zero, 0 when the highest bit is set. One instruction on most CPUs
(`llvm.ctlz`).

**Returns**
- the count of leading zero bits, from 0 to 16

**Example**
```pepper
    assert(((1 as short)).leading_zeros() == 15, "one bit, at the bottom");
```

#### trailing_zeros

```pepper
trailing_zeros(): int
```

Returns the number of zero bits below the lowest set bit: 16 for
zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
first set bit of a mask without a loop.

**Returns**
- the count of trailing zero bits, from 0 to 16

**Example**
```pepper
    assert((8 as short).trailing_zeros() == 3, "8 is 0b1000");
```

#### count_ones

```pepper
count_ones(): int
```

Returns the number of bits that are set (the population count,
`llvm.ctpop`).

**Returns**
- the count of one bits, from 0 to 16

**Example**
```pepper
    assert((11 as short).count_ones() == 3, "three bits set");
```

#### count_zeros

```pepper
count_zeros(): int
```

Returns the number of bits that are clear.

**Returns**
- the count of zero bits, from 0 to 16

**Example**
```pepper
    assert((11 as short).count_zeros() == 13, "three bits set");
```

#### swap_bytes

```pepper
swap_bytes(): short
```

Returns this value with its bytes in reverse order (`llvm.bswap`), to
convert between little-endian and big-endian byte order.

**Returns**
- the value with its 2 bytes reversed

**Example**
```pepper
    assert((0x1234 as short).swap_bytes() == 0x3412, "bytes reversed");
```

#### reverse_bits

```pepper
reverse_bits(): short
```

Returns this value with its bits in reverse order: the lowest bit
becomes the highest (`llvm.bitreverse`).

**Returns**
- the value with its 16 bits reversed

**Example**
```pepper
    assert(((1 as short)).reverse_bits().leading_zeros() == 0, "bottom to top");
```

#### rotate_left

```pepper
rotate_left(count: int): short
```

Returns this value's bits rotated left by `count`: the bits shifted
out at the top come back in at the bottom (`llvm.fshl`). `count` is
taken modulo 16, so a negative count rotates right.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert((9 as short).rotate_left(15) == (9 as short).rotate_right(1), "the same rotation");
```

#### rotate_right

```pepper
rotate_right(count: int): short
```

Returns this value's bits rotated right by `count`: the bits shifted
out at the bottom come back in at the top (`llvm.fshr`). `count` is
taken modulo 16, so a negative count rotates left.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert(((1 as short)).rotate_right(1) == ((1 as short)).rotate_left(15), "the bottom bit to the top");
```

#### min

```pepper
min(other: short): short
```

Returns the smaller of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not greater than `other`, else `other`

**Example**
```pepper
    assert((3 as short).min(5) == 3, "smaller");
```

#### max

```pepper
max(other: short): short
```

Returns the larger of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not less than `other`, else `other`

**Example**
```pepper
    assert((3 as short).max(5) == 5, "larger");
```

#### abs

```pepper
abs(location: __ptr<char> = __caller_location()): short
```

Returns the absolute value: `this` without its sign. The lowest
value, -32768, has no positive counterpart in a `short`, so it panics, as
its negation does.

**Parameters**
- `location` — where a failure is reported; left out, this call's location

**Returns**
- `-this` when this value is negative, else `this`

**Panics**
- if this value is -32768 ("integer overflow in 'short' absolute value")

**Example**
```pepper
    assert((-5 as short).abs() == 5, "negative");
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

#### leading_zeros

```pepper
leading_zeros(): int
```

Returns the number of zero bits above the highest set bit: 16 for
zero, 0 when the highest bit is set. One instruction on most CPUs
(`llvm.ctlz`).

**Returns**
- the count of leading zero bits, from 0 to 16

**Example**
```pepper
    assert(((1 as ushort)).leading_zeros() == 15, "one bit, at the bottom");
```

#### trailing_zeros

```pepper
trailing_zeros(): int
```

Returns the number of zero bits below the lowest set bit: 16 for
zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
first set bit of a mask without a loop.

**Returns**
- the count of trailing zero bits, from 0 to 16

**Example**
```pepper
    assert((8 as ushort).trailing_zeros() == 3, "8 is 0b1000");
```

#### count_ones

```pepper
count_ones(): int
```

Returns the number of bits that are set (the population count,
`llvm.ctpop`).

**Returns**
- the count of one bits, from 0 to 16

**Example**
```pepper
    assert((11 as ushort).count_ones() == 3, "three bits set");
```

#### count_zeros

```pepper
count_zeros(): int
```

Returns the number of bits that are clear.

**Returns**
- the count of zero bits, from 0 to 16

**Example**
```pepper
    assert((11 as ushort).count_zeros() == 13, "three bits set");
```

#### swap_bytes

```pepper
swap_bytes(): ushort
```

Returns this value with its bytes in reverse order (`llvm.bswap`), to
convert between little-endian and big-endian byte order.

**Returns**
- the value with its 2 bytes reversed

**Example**
```pepper
    assert((0x1234 as ushort).swap_bytes() == 0x3412, "bytes reversed");
```

#### reverse_bits

```pepper
reverse_bits(): ushort
```

Returns this value with its bits in reverse order: the lowest bit
becomes the highest (`llvm.bitreverse`).

**Returns**
- the value with its 16 bits reversed

**Example**
```pepper
    assert(((1 as ushort)).reverse_bits().leading_zeros() == 0, "bottom to top");
```

#### rotate_left

```pepper
rotate_left(count: int): ushort
```

Returns this value's bits rotated left by `count`: the bits shifted
out at the top come back in at the bottom (`llvm.fshl`). `count` is
taken modulo 16, so a negative count rotates right.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert((9 as ushort).rotate_left(15) == (9 as ushort).rotate_right(1), "the same rotation");
```

#### rotate_right

```pepper
rotate_right(count: int): ushort
```

Returns this value's bits rotated right by `count`: the bits shifted
out at the bottom come back in at the top (`llvm.fshr`). `count` is
taken modulo 16, so a negative count rotates left.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert(((1 as ushort)).rotate_right(1) == ((1 as ushort)).rotate_left(15), "the bottom bit to the top");
```

#### min

```pepper
min(other: ushort): ushort
```

Returns the smaller of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not greater than `other`, else `other`

**Example**
```pepper
    assert((3 as ushort).min(5) == 3, "smaller");
```

#### max

```pepper
max(other: ushort): ushort
```

Returns the larger of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not less than `other`, else `other`

**Example**
```pepper
    assert((3 as ushort).max(5) == 5, "larger");
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
    assert(int.parse("12x").is_empty(), "not a number");
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

#### leading_zeros

```pepper
leading_zeros(): int
```

Returns the number of zero bits above the highest set bit: 32 for
zero, 0 when the highest bit is set. One instruction on most CPUs
(`llvm.ctlz`).

**Returns**
- the count of leading zero bits, from 0 to 32

**Example**
```pepper
    assert(((1 as int)).leading_zeros() == 31, "one bit, at the bottom");
```

#### trailing_zeros

```pepper
trailing_zeros(): int
```

Returns the number of zero bits below the lowest set bit: 32 for
zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
first set bit of a mask without a loop.

**Returns**
- the count of trailing zero bits, from 0 to 32

**Example**
```pepper
    assert((8 as int).trailing_zeros() == 3, "8 is 0b1000");
```

#### count_ones

```pepper
count_ones(): int
```

Returns the number of bits that are set (the population count,
`llvm.ctpop`).

**Returns**
- the count of one bits, from 0 to 32

**Example**
```pepper
    assert((11 as int).count_ones() == 3, "three bits set");
```

#### count_zeros

```pepper
count_zeros(): int
```

Returns the number of bits that are clear.

**Returns**
- the count of zero bits, from 0 to 32

**Example**
```pepper
    assert((11 as int).count_zeros() == 29, "three bits set");
```

#### swap_bytes

```pepper
swap_bytes(): int
```

Returns this value with its bytes in reverse order (`llvm.bswap`), to
convert between little-endian and big-endian byte order.

**Returns**
- the value with its 4 bytes reversed

**Example**
```pepper
    assert((0x12345678 as int).swap_bytes() == 0x78563412, "bytes reversed");
```

#### reverse_bits

```pepper
reverse_bits(): int
```

Returns this value with its bits in reverse order: the lowest bit
becomes the highest (`llvm.bitreverse`).

**Returns**
- the value with its 32 bits reversed

**Example**
```pepper
    assert(((1 as int)).reverse_bits().leading_zeros() == 0, "bottom to top");
```

#### rotate_left

```pepper
rotate_left(count: int): int
```

Returns this value's bits rotated left by `count`: the bits shifted
out at the top come back in at the bottom (`llvm.fshl`). `count` is
taken modulo 32, so a negative count rotates right.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert((9 as int).rotate_left(31) == (9 as int).rotate_right(1), "the same rotation");
```

#### rotate_right

```pepper
rotate_right(count: int): int
```

Returns this value's bits rotated right by `count`: the bits shifted
out at the bottom come back in at the top (`llvm.fshr`). `count` is
taken modulo 32, so a negative count rotates left.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert(((1 as int)).rotate_right(1) == ((1 as int)).rotate_left(31), "the bottom bit to the top");
```

#### min

```pepper
min(other: int): int
```

Returns the smaller of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not greater than `other`, else `other`

**Example**
```pepper
    assert((3 as int).min(5) == 3, "smaller");
```

#### max

```pepper
max(other: int): int
```

Returns the larger of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not less than `other`, else `other`

**Example**
```pepper
    assert((3 as int).max(5) == 5, "larger");
```

#### abs

```pepper
abs(location: __ptr<char> = __caller_location()): int
```

Returns the absolute value: `this` without its sign. The lowest
value, -2147483648, has no positive counterpart in a `int`, so it panics, as
its negation does.

**Parameters**
- `location` — where a failure is reported; left out, this call's location

**Returns**
- `-this` when this value is negative, else `this`

**Panics**
- if this value is -2147483648 ("integer overflow in 'int' absolute value")

**Example**
```pepper
    assert((-5 as int).abs() == 5, "negative");
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

#### leading_zeros

```pepper
leading_zeros(): int
```

Returns the number of zero bits above the highest set bit: 32 for
zero, 0 when the highest bit is set. One instruction on most CPUs
(`llvm.ctlz`).

**Returns**
- the count of leading zero bits, from 0 to 32

**Example**
```pepper
    assert(((1 as uint)).leading_zeros() == 31, "one bit, at the bottom");
```

#### trailing_zeros

```pepper
trailing_zeros(): int
```

Returns the number of zero bits below the lowest set bit: 32 for
zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
first set bit of a mask without a loop.

**Returns**
- the count of trailing zero bits, from 0 to 32

**Example**
```pepper
    assert((8 as uint).trailing_zeros() == 3, "8 is 0b1000");
```

#### count_ones

```pepper
count_ones(): int
```

Returns the number of bits that are set (the population count,
`llvm.ctpop`).

**Returns**
- the count of one bits, from 0 to 32

**Example**
```pepper
    assert((11 as uint).count_ones() == 3, "three bits set");
```

#### count_zeros

```pepper
count_zeros(): int
```

Returns the number of bits that are clear.

**Returns**
- the count of zero bits, from 0 to 32

**Example**
```pepper
    assert((11 as uint).count_zeros() == 29, "three bits set");
```

#### swap_bytes

```pepper
swap_bytes(): uint
```

Returns this value with its bytes in reverse order (`llvm.bswap`), to
convert between little-endian and big-endian byte order.

**Returns**
- the value with its 4 bytes reversed

**Example**
```pepper
    assert((0x12345678 as uint).swap_bytes() == 0x78563412, "bytes reversed");
```

#### reverse_bits

```pepper
reverse_bits(): uint
```

Returns this value with its bits in reverse order: the lowest bit
becomes the highest (`llvm.bitreverse`).

**Returns**
- the value with its 32 bits reversed

**Example**
```pepper
    assert(((1 as uint)).reverse_bits().leading_zeros() == 0, "bottom to top");
```

#### rotate_left

```pepper
rotate_left(count: int): uint
```

Returns this value's bits rotated left by `count`: the bits shifted
out at the top come back in at the bottom (`llvm.fshl`). `count` is
taken modulo 32, so a negative count rotates right.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert((9 as uint).rotate_left(31) == (9 as uint).rotate_right(1), "the same rotation");
```

#### rotate_right

```pepper
rotate_right(count: int): uint
```

Returns this value's bits rotated right by `count`: the bits shifted
out at the bottom come back in at the top (`llvm.fshr`). `count` is
taken modulo 32, so a negative count rotates left.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert(((1 as uint)).rotate_right(1) == ((1 as uint)).rotate_left(31), "the bottom bit to the top");
```

#### min

```pepper
min(other: uint): uint
```

Returns the smaller of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not greater than `other`, else `other`

**Example**
```pepper
    assert((3 as uint).min(5) == 3, "smaller");
```

#### max

```pepper
max(other: uint): uint
```

Returns the larger of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not less than `other`, else `other`

**Example**
```pepper
    assert((3 as uint).max(5) == 5, "larger");
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
    assert(long.parse("9223372036854775808").is_empty(), "too big");
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

#### leading_zeros

```pepper
leading_zeros(): int
```

Returns the number of zero bits above the highest set bit: 64 for
zero, 0 when the highest bit is set. One instruction on most CPUs
(`llvm.ctlz`).

**Returns**
- the count of leading zero bits, from 0 to 64

**Example**
```pepper
    assert(((1 as long)).leading_zeros() == 63, "one bit, at the bottom");
```

#### trailing_zeros

```pepper
trailing_zeros(): int
```

Returns the number of zero bits below the lowest set bit: 64 for
zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
first set bit of a mask without a loop.

**Returns**
- the count of trailing zero bits, from 0 to 64

**Example**
```pepper
    assert((8 as long).trailing_zeros() == 3, "8 is 0b1000");
```

#### count_ones

```pepper
count_ones(): int
```

Returns the number of bits that are set (the population count,
`llvm.ctpop`).

**Returns**
- the count of one bits, from 0 to 64

**Example**
```pepper
    assert((11 as long).count_ones() == 3, "three bits set");
```

#### count_zeros

```pepper
count_zeros(): int
```

Returns the number of bits that are clear.

**Returns**
- the count of zero bits, from 0 to 64

**Example**
```pepper
    assert((11 as long).count_zeros() == 61, "three bits set");
```

#### swap_bytes

```pepper
swap_bytes(): long
```

Returns this value with its bytes in reverse order (`llvm.bswap`), to
convert between little-endian and big-endian byte order.

**Returns**
- the value with its 8 bytes reversed

**Example**
```pepper
    assert((0x0102030405060708 as long).swap_bytes() == 0x0807060504030201, "bytes reversed");
```

#### reverse_bits

```pepper
reverse_bits(): long
```

Returns this value with its bits in reverse order: the lowest bit
becomes the highest (`llvm.bitreverse`).

**Returns**
- the value with its 64 bits reversed

**Example**
```pepper
    assert(((1 as long)).reverse_bits().leading_zeros() == 0, "bottom to top");
```

#### rotate_left

```pepper
rotate_left(count: int): long
```

Returns this value's bits rotated left by `count`: the bits shifted
out at the top come back in at the bottom (`llvm.fshl`). `count` is
taken modulo 64, so a negative count rotates right.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert((9 as long).rotate_left(63) == (9 as long).rotate_right(1), "the same rotation");
```

#### rotate_right

```pepper
rotate_right(count: int): long
```

Returns this value's bits rotated right by `count`: the bits shifted
out at the bottom come back in at the top (`llvm.fshr`). `count` is
taken modulo 64, so a negative count rotates left.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert(((1 as long)).rotate_right(1) == ((1 as long)).rotate_left(63), "the bottom bit to the top");
```

#### min

```pepper
min(other: long): long
```

Returns the smaller of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not greater than `other`, else `other`

**Example**
```pepper
    assert((3 as long).min(5) == 3, "smaller");
```

#### max

```pepper
max(other: long): long
```

Returns the larger of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not less than `other`, else `other`

**Example**
```pepper
    assert((3 as long).max(5) == 5, "larger");
```

#### abs

```pepper
abs(location: __ptr<char> = __caller_location()): long
```

Returns the absolute value: `this` without its sign. The lowest
value, -9223372036854775808, has no positive counterpart in a `long`, so it panics, as
its negation does.

**Parameters**
- `location` — where a failure is reported; left out, this call's location

**Returns**
- `-this` when this value is negative, else `this`

**Panics**
- if this value is -9223372036854775808 ("integer overflow in 'long' absolute value")

**Example**
```pepper
    assert((-5 as long).abs() == 5, "negative");
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
    assert(ulong.parse("ffffffffffffffff", 16).is_value(), "the highest");
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

#### leading_zeros

```pepper
leading_zeros(): int
```

Returns the number of zero bits above the highest set bit: 64 for
zero, 0 when the highest bit is set. One instruction on most CPUs
(`llvm.ctlz`).

**Returns**
- the count of leading zero bits, from 0 to 64

**Example**
```pepper
    assert(((1 as ulong)).leading_zeros() == 63, "one bit, at the bottom");
```

#### trailing_zeros

```pepper
trailing_zeros(): int
```

Returns the number of zero bits below the lowest set bit: 64 for
zero. One instruction on most CPUs (`llvm.cttz`), so it finds the
first set bit of a mask without a loop.

**Returns**
- the count of trailing zero bits, from 0 to 64

**Example**
```pepper
    assert((8 as ulong).trailing_zeros() == 3, "8 is 0b1000");
```

#### count_ones

```pepper
count_ones(): int
```

Returns the number of bits that are set (the population count,
`llvm.ctpop`).

**Returns**
- the count of one bits, from 0 to 64

**Example**
```pepper
    assert((11 as ulong).count_ones() == 3, "three bits set");
```

#### count_zeros

```pepper
count_zeros(): int
```

Returns the number of bits that are clear.

**Returns**
- the count of zero bits, from 0 to 64

**Example**
```pepper
    assert((11 as ulong).count_zeros() == 61, "three bits set");
```

#### swap_bytes

```pepper
swap_bytes(): ulong
```

Returns this value with its bytes in reverse order (`llvm.bswap`), to
convert between little-endian and big-endian byte order.

**Returns**
- the value with its 8 bytes reversed

**Example**
```pepper
    assert((0x0102030405060708 as ulong).swap_bytes() == 0x0807060504030201, "bytes reversed");
```

#### reverse_bits

```pepper
reverse_bits(): ulong
```

Returns this value with its bits in reverse order: the lowest bit
becomes the highest (`llvm.bitreverse`).

**Returns**
- the value with its 64 bits reversed

**Example**
```pepper
    assert(((1 as ulong)).reverse_bits().leading_zeros() == 0, "bottom to top");
```

#### rotate_left

```pepper
rotate_left(count: int): ulong
```

Returns this value's bits rotated left by `count`: the bits shifted
out at the top come back in at the bottom (`llvm.fshl`). `count` is
taken modulo 64, so a negative count rotates right.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert((9 as ulong).rotate_left(63) == (9 as ulong).rotate_right(1), "the same rotation");
```

#### rotate_right

```pepper
rotate_right(count: int): ulong
```

Returns this value's bits rotated right by `count`: the bits shifted
out at the bottom come back in at the top (`llvm.fshr`). `count` is
taken modulo 64, so a negative count rotates left.

**Parameters**
- `count` — how many places to rotate

**Returns**
- the rotated value

**Example**
```pepper
    assert(((1 as ulong)).rotate_right(1) == ((1 as ulong)).rotate_left(63), "the bottom bit to the top");
```

#### min

```pepper
min(other: ulong): ulong
```

Returns the smaller of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not greater than `other`, else `other`

**Example**
```pepper
    assert((3 as ulong).min(5) == 3, "smaller");
```

#### max

```pepper
max(other: ulong): ulong
```

Returns the larger of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- `this` when it is not less than `other`, else `other`

**Example**
```pepper
    assert((3 as ulong).max(5) == 5, "larger");
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
    assert(float.parse("1e39").is_empty(), "too big");
```

### Methods

#### square_root

```pepper
square_root(): float
```

Returns the square root (`llvm.sqrt`, one instruction on most CPUs):
NaN for a negative value, and `-0.0` for `-0.0`.

**Returns**
- the non-negative square root

**Example**
```pepper
    assert((2.25 as float).square_root() == 1.5, "exact");
```

#### floor

```pepper
floor(): float
```

Returns the largest whole number not greater than this value
(`llvm.floor`).

**Returns**
- the value rounded toward negative infinity

**Example**
```pepper
    assert((-1.5 as float).floor() == -2.0, "down");
```

#### ceiling

```pepper
ceiling(): float
```

Returns the smallest whole number not less than this value
(`llvm.ceil`).

**Returns**
- the value rounded toward positive infinity

**Example**
```pepper
    assert((-1.5 as float).ceiling() == -1.0, "up");
```

#### truncate

```pepper
truncate(): float
```

Returns this value without its fractional part (`llvm.trunc`).

**Returns**
- the value rounded toward zero

**Example**
```pepper
    assert((-1.5 as float).truncate() == -1.0, "toward zero");
```

#### round

```pepper
round(): float
```

Returns the nearest whole number, halfway cases away from zero
(`llvm.round`).

**Returns**
- the rounded value

**Example**
```pepper
    assert((2.5 as float).round() == 3.0, "half away from zero");
```

#### abs

```pepper
abs(): float
```

Returns the absolute value: this value with its sign bit cleared
(`llvm.fabs`).

**Returns**
- the value without its sign

**Example**
```pepper
    assert((-2.0 as float).abs() == 2.0, "negative");
```

#### copy_sign

```pepper
copy_sign(sign: float): float
```

Returns this value's magnitude with the sign of `sign`
(`llvm.copysign`).

**Parameters**
- `sign` — the value whose sign the result takes

**Returns**
- `abs()` of this value, negated when `sign` is negative

**Example**
```pepper
    assert((3.0 as float).copy_sign(-0.0) == -3.0, "negative zero is negative");
```

#### multiply_add

```pepper
multiply_add(factor: float, addend: float): float
```

Returns `this * factor + addend` with a single rounding, as one fused
multiply-add (`llvm.fma`): more precise than the two operations, and
one instruction where the CPU has it.

**Parameters**
- `factor` — the value to multiply by
- `addend` — the value to add to the product

**Returns**
- the fused product and sum

**Example**
```pepper
    assert((2.0 as float).multiply_add(3.0, 1.0) == 7.0, "2 * 3 + 1");
```

#### min

```pepper
min(other: float): float
```

Returns the smaller of this value and `other`; when one of them is
NaN, the other (`llvm.minnum`).

**Parameters**
- `other` — the value to compare with

**Returns**
- the smaller value

**Example**
```pepper
    assert((1.5 as float).min(-2.0) == -2.0, "smaller");
```

#### max

```pepper
max(other: float): float
```

Returns the larger of this value and `other`; when one of them is
NaN, the other (`llvm.maxnum`).

**Parameters**
- `other` — the value to compare with

**Returns**
- the larger value

**Example**
```pepper
    assert((1.5 as float).max(-2.0) == 1.5, "larger");
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
    assert(double.parse("1.5.2").is_empty(), "not a number");
```

### Methods

#### square_root

```pepper
square_root(): double
```

Returns the square root (`llvm.sqrt`, one instruction on most CPUs):
NaN for a negative value, and `-0.0` for `-0.0`.

**Returns**
- the non-negative square root

**Example**
```pepper
    assert((2.25 as double).square_root() == 1.5, "exact");
```

#### floor

```pepper
floor(): double
```

Returns the largest whole number not greater than this value
(`llvm.floor`).

**Returns**
- the value rounded toward negative infinity

**Example**
```pepper
    assert((-1.5 as double).floor() == -2.0, "down");
```

#### ceiling

```pepper
ceiling(): double
```

Returns the smallest whole number not less than this value
(`llvm.ceil`).

**Returns**
- the value rounded toward positive infinity

**Example**
```pepper
    assert((-1.5 as double).ceiling() == -1.0, "up");
```

#### truncate

```pepper
truncate(): double
```

Returns this value without its fractional part (`llvm.trunc`).

**Returns**
- the value rounded toward zero

**Example**
```pepper
    assert((-1.5 as double).truncate() == -1.0, "toward zero");
```

#### round

```pepper
round(): double
```

Returns the nearest whole number, halfway cases away from zero
(`llvm.round`).

**Returns**
- the rounded value

**Example**
```pepper
    assert((2.5 as double).round() == 3.0, "half away from zero");
```

#### abs

```pepper
abs(): double
```

Returns the absolute value: this value with its sign bit cleared
(`llvm.fabs`).

**Returns**
- the value without its sign

**Example**
```pepper
    assert((-2.0 as double).abs() == 2.0, "negative");
```

#### copy_sign

```pepper
copy_sign(sign: double): double
```

Returns this value's magnitude with the sign of `sign`
(`llvm.copysign`).

**Parameters**
- `sign` — the value whose sign the result takes

**Returns**
- `abs()` of this value, negated when `sign` is negative

**Example**
```pepper
    assert((3.0 as double).copy_sign(-0.0) == -3.0, "negative zero is negative");
```

#### multiply_add

```pepper
multiply_add(factor: double, addend: double): double
```

Returns `this * factor + addend` with a single rounding, as one fused
multiply-add (`llvm.fma`): more precise than the two operations, and
one instruction where the CPU has it.

**Parameters**
- `factor` — the value to multiply by
- `addend` — the value to add to the product

**Returns**
- the fused product and sum

**Example**
```pepper
    assert((2.0 as double).multiply_add(3.0, 1.0) == 7.0, "2 * 3 + 1");
```

#### min

```pepper
min(other: double): double
```

Returns the smaller of this value and `other`; when one of them is
NaN, the other (`llvm.minnum`).

**Parameters**
- `other` — the value to compare with

**Returns**
- the smaller value

**Example**
```pepper
    assert((1.5 as double).min(-2.0) == -2.0, "smaller");
```

#### max

```pepper
max(other: double): double
```

Returns the larger of this value and `other`; when one of them is
NaN, the other (`llvm.maxnum`).

**Parameters**
- `other` — the value to compare with

**Returns**
- the larger value

**Example**
```pepper
    assert((1.5 as double).max(-2.0) == 1.5, "larger");
```
