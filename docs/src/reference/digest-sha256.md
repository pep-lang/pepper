<!-- Generated from runtime/digest/sha256.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# SHA-256

SHA-256 (FIPS 180-4): 32-byte digests, as used to check downloads and
sign data.

Source: `runtime/digest/sha256.pep`

## Sha256

```pepper
struct Sha256
```

An incremental SHA-256 hasher: feed it bytes with `update`, any number of
times and in pieces of any size, then read the 32-byte digest with
`finish`.

The digest of the input is the same however it was split between
`update` calls. `finish` resets the hasher, so it can hash a new input.

**Example**
```pepper
import digest;

var hasher = digest.Sha256();
hasher.update("hello ");
hasher.update("world");
assert(hasher.finish_hex() == digest.to_hex(digest.sha256("hello world")), "same digest");
```

### Constructor

#### Sha256()

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
- the digest, most significant byte first

#### finish_hex

```pepper
finish_hex(): String
```

Returns the digest as `finish` does, written as 64 lowercase
hexadecimal digits.

**Returns**
- the digest in hexadecimal

## sha256

```pepper
sha256(bytes: u8[]): u8[]
```

Returns the SHA-256 digest of `bytes`.

**Parameters**
- `bytes` — the input

**Returns**
- the 32-byte digest

**Example**
```pepper
import digest;

var empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
assert(digest.to_hex(digest.sha256(Array<u8>())) == empty, "SHA-256 of nothing");
```

## sha256

```pepper
sha256(text: String): u8[]
```

Returns the SHA-256 digest of the UTF-8 bytes of `text`.

**Parameters**
- `text` — the input

**Returns**
- the 32-byte digest

**Example**
```pepper
import digest;

var abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
assert(digest.to_hex(digest.sha256("abc")) == abc, "FIPS 180-4 example");
```
