<!-- Generated from runtime/digest/blake3.pep by `pep-doc reference`. Do not edit. -->

# BLAKE3

BLAKE3: 32-byte digests, faster than SHA-256 in hardware without SHA
instructions, and the hash the compiler's build cache keys objects with.
Also a keyed hash (a MAC), key derivation, and output of any length.

Source: `runtime/digest/blake3.pep`

## Blake3

```pepper
struct Blake3
```

An incremental BLAKE3 hasher: feed it bytes with `update`, any number of
times and in pieces of any size, then read the 32-byte digest with
`finish`.

`Blake3()` is the default hash mode; `Blake3.keyed` and
`Blake3.derive_key` make hashers for the other two modes, and
`finish(length)` reads output of any length in each.

This is a portable implementation, one block at a time; it does not use
SIMD or threads, so it runs well below the speed of the official C and
Rust implementations. The digests are the same. `finish` resets the
hasher, so it can hash a new input.

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

### Static methods

#### keyed

```pepper
static keyed(key: u8[]): Blake3
```

Returns a hasher for BLAKE3's keyed mode, a MAC: only someone with
`key` can compute or check the digest of an input.

**Parameters**
- `key` — the 32-byte secret key

**Returns**
- a hasher with no input, keyed with `key`

**Panics**
- if `key` is not 32 bytes

**Example**
```pepper
import digest;

var key = digest.blake3("a key made some other way");
var mac = digest.Blake3.keyed(key);
mac.update("message");
assert(mac.finish().count == 32, "a 32-byte MAC");
```

#### derive_key

```pepper
static derive_key(context: String): Blake3
```

Returns a hasher for BLAKE3's key derivation mode: the digest of its
input (the key material, such as a shared secret or a password hash)
is a key for the purpose that `context` names.

`context` should be a hard-coded string, unique to the application
and the purpose, such as
`"example.com 2026-10-16 session tokens v1"`; different contexts give
unrelated keys from the same material. Read the key with `finish`,
or `finish(length)` for one of another length.

**Parameters**
- `context` — the application and purpose the key is for

**Returns**
- a hasher with no input, for keys in `context`

**Example**
```pepper
import digest;

var hasher = digest.Blake3.derive_key("example.com 2026-10-16 session tokens v1");
hasher.update("the shared secret");
var key = hasher.finish();
```

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

#### update_range

```pepper
update_range(bytes: u8[], start: ulong, count: ulong)
```

Hashes `count` bytes of `bytes`, from index `start`, as the next part
of the input; those past the end of `bytes` are left out.

**Parameters**
- `bytes` — the bytes
- `start` — the index of the first byte to add
- `count` — how many bytes to add

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

#### finish

```pepper
finish(length: ulong): u8[]
```

Returns `length` bytes of output for the input given since the
hasher was created or last reset, then resets it: BLAKE3's extended
output. The first 32 bytes are the digest `finish()` returns, and a
shorter output is a prefix of a longer one.

**Parameters**
- `length` — how many bytes to return

**Returns**
- the output

**Example**
```pepper
import digest;

var long_output = digest.Blake3();
long_output.update("abc");
var bytes = long_output.finish(100);
assert(digest.to_hex(bytes).starts_with(digest.to_hex(digest.blake3("abc"))), "a prefix");
```

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
