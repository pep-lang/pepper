<!-- Generated from runtime/uuid/module.pep by `pep-doc reference`. Do not edit. -->

# The uuid module

UUIDs (RFC 9562): 128-bit identifiers, written as
`0190163d-8694-739b-aea5-966c26f8ad91`.

Bring it in with `import uuid` (or `import [Uuid] from uuid`). `Uuid.v4()`
makes a random one; `Uuid.v7()` puts the time first, so ids made later
sort later, which keeps database indexes compact. Both draw their random
bits from the operating system's secure source (`random.bytes`).

**Example**
```pepper
import uuid;

main(): int {
    var id = uuid.Uuid.v4();
    var text = id.to_string();                       # such as 9b2c3c1e-...
    assert(uuid.Uuid.parse(text).value() == id, "round trip");
    assert(id.version() == 4, "random");
    return 0;
}
```

Source: `runtime/uuid/module.pep`

## Uuid

```pepper
[Value] struct Uuid
```

A UUID, as a [value struct](../language/value-structs.md) of two 64-bit
halves: `==` compares them and `hash` hashes them, so a `Uuid` works as
a map key.

**Example**
```pepper
var id = Uuid.parse("0190163D-8694-739B-AEA5-966C26F8AD91").value();
assert(id.version() == 7, "the version digit");
assert(id.to_string() == "0190163d-8694-739b-aea5-966c26f8ad91", "lowercase");
```

### Fields

#### high

```pepper
var high: ulong
```

The first 8 bytes, the first byte in the top bits.

#### low

```pepper
var low: ulong
```

The last 8 bytes, the first of them in the top bits.

### Constructor

#### Uuid()

```pepper
construct(high: ulong, low: ulong)
```

Makes the UUID with these halves; `Uuid(0, 0)` is the nil UUID.

**Parameters**
- `high` — the first 8 bytes, the first byte in the top bits
- `low` — the last 8 bytes, the first of them in the top bits

### Static methods

#### v4

```pepper
static v4(): Uuid
```

Returns a new random UUID (version 4): 122 random bits.

**Returns**
- the UUID

**Panics**
- if the operating system cannot give random bytes, which only a broken system does

#### v7

```pepper
static v7(): Uuid
```

Returns a new time-ordered UUID (version 7): the wall clock's Unix
time in milliseconds in the first 48 bits, then 74 random bits. Ids
made in different milliseconds sort by time, both as values and as
text; ids made in the same millisecond are in no particular order.

**Returns**
- the UUID

**Panics**
- if the operating system cannot give random bytes, which only a broken system does

#### parse

```pepper
static parse(text: String): Result<Uuid>
```

Returns the UUID that `text` writes: 32 hexadecimal digits, either
case, in groups of 8, 4, 4, 4 and 12 separated by `-`.

**Parameters**
- `text` — the UUID as text, such as `0190163d-8694-739b-aea5-966c26f8ad91`

**Returns**
- the UUID, or an error when `text` is not in that form

### Methods

#### version

```pepper
version(): int
```

Returns the version: 4 for `v4`, 7 for `v7`, 0 for the nil UUID.

**Returns**
- the version digit, from 0 to 15

#### bytes

```pepper
bytes(): u8[]
```

Returns the UUID's 16 bytes, `high` first, as databases and binary
formats store it.

**Returns**
- 16 bytes

#### to_string

```pepper
to_string(): String
```

Returns the UUID as 32 lowercase hexadecimal digits in groups of 8,
4, 4, 4 and 12, such as `0190163d-8694-739b-aea5-966c26f8ad91`.

**Returns**
- the UUID as text, 36 characters
