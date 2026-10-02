<!-- Generated from runtime/compress/checksum.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Checksums

`Crc32` and `Adler32`: the checksums gzip and zlib streams carry, for
checking data as it is read or written.

Source: `runtime/compress/checksum.pep`

## Crc32

```pepper
struct Crc32
```

The CRC-32 checksum (IEEE 802.3, the polynomial gzip, zip and PNG use),
computed over data given in one or more pieces.

**Example**
```pepper
    import compress;

    var crc = compress.Crc32();
    crc.update("hello ".bytes());
    crc.update("world".bytes());
    assert(crc.value == compress.Crc32.of("hello world".bytes()), "same in pieces");
    assert(compress.Crc32.of("123456789".bytes()) == 0xCBF43926, "the check value");
```

### Properties

#### value

```pepper
var value: uint { get; }
```

The checksum of everything given to `update` so far.

### Constructor

#### Crc32()

```pepper
construct()
```

Makes a checksum of no data yet (`value` is 0).

### Static methods

#### of

```pepper
static of(data: u8[]): uint
```

Returns the CRC-32 of `data`.

**Parameters**
- `data` — the bytes to check

**Returns**
- the checksum

### Methods

#### update

```pepper
update(data: u8[])
```

Adds `data` to the checksum.

**Parameters**
- `data` — the next bytes of the data

#### reset

```pepper
reset()
```

Starts over, as if no data had been given.

## Adler32

```pepper
struct Adler32
```

The Adler-32 checksum (RFC 1950, the one zlib streams carry), computed
over data given in one or more pieces.

**Example**
```pepper
    import compress;

    assert(compress.Adler32.of("Wikipedia".bytes()) == 0x11E60398, "the example");
```

### Properties

#### value

```pepper
var value: uint { get; }
```

The checksum of everything given to `update` so far.

### Constructor

#### Adler32()

```pepper
construct()
```

Makes a checksum of no data yet (`value` is 1).

### Static methods

#### of

```pepper
static of(data: u8[]): uint
```

Returns the Adler-32 of `data`.

**Parameters**
- `data` — the bytes to check

**Returns**
- the checksum

### Methods

#### update

```pepper
update(data: u8[])
```

Adds `data` to the checksum.

**Parameters**
- `data` — the next bytes of the data

#### reset

```pepper
reset()
```

Starts over, as if no data had been given.
