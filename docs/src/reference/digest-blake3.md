<!-- Generated from runtime/digest/blake3.pep by `pep-doc reference`. Do not edit. -->

# BLAKE3

BLAKE3: 32-byte digests, faster than SHA-256 in hardware without SHA
instructions, and the hash the compiler's build cache keys objects with.

Source: `runtime/digest/blake3.pep`

## Blake3

```pepper
struct Blake3
```

An incremental BLAKE3 hasher: feed it bytes with `update`, any number of
times and in pieces of any size, then read the 32-byte digest with
`finish`.

This is a portable implementation of the default hash mode, one block
at a time; it does not use SIMD or threads, so it runs well below the
speed of the official C and Rust implementations. The digests are the
same. `finish` resets the hasher, so it can hash a new input.

**Example**
```pepper
import digest;

var hasher = digest.Blake3();
hasher.update("hello ");
hasher.update("world");
assert(hasher.finish_hex() == digest.to_hex(digest.blake3("hello world")), "same digest");
```

### Constructor

#### Blake3()

```pepper
construct()
```

Creates a hasher in the initial state, with no input.

### Methods

#### reset

```pepper
reset()
```

Discards the input given so far, returning the hasher to its initial
state.

#### update

```pepper
update(bytes: u8[])
```

Hashes `bytes` as the next part of the input.

**Parameters**
- `bytes` — the bytes to add

#### update

```pepper
update(text: String)
```

Hashes the UTF-8 bytes of `text` (without a terminating NUL) as the
next part of the input.

**Parameters**
- `text` — the text to add

#### finish

```pepper
finish(): u8[]
```

Returns the 32-byte digest of the input given since the hasher was
created or last reset, then resets it.

**Returns**
- the digest

#### finish_hex

```pepper
finish_hex(): String
```

Returns the digest as `finish` does, written as 64 lowercase
hexadecimal digits.

**Returns**
- the digest in hexadecimal

## blake3

```pepper
blake3(bytes: u8[]): u8[]
```

Returns the BLAKE3 digest of `bytes`.

**Parameters**
- `bytes` — the input

**Returns**
- the 32-byte digest

**Example**
```pepper
import digest;

var empty = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";
assert(digest.to_hex(digest.blake3(Array<u8>())) == empty, "BLAKE3 of nothing");
```

## blake3

```pepper
blake3(text: String): u8[]
```

Returns the BLAKE3 digest of the UTF-8 bytes of `text`.

**Parameters**
- `text` — the input

**Returns**
- the 32-byte digest
