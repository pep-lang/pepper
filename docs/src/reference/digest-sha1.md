<!-- Generated from runtime/digest/sha1.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# SHA-1

SHA-1 (FIPS 180-4): 20-byte digests, as git uses for object ids. SHA-1
is broken for collision resistance; use it to read existing formats,
and SHA-256 or BLAKE3 for anything new.

Source: `runtime/digest/sha1.pep`

## Sha1

```pepper
struct Sha1
```

An incremental SHA-1 hasher: feed it bytes with `update`, any number of
times and in pieces of any size, then read the 20-byte digest with
`finish`.

SHA-1 is not collision resistant: someone can make two inputs with the
same digest. Use it only where a format requires it, such as git object
ids. `finish` resets the hasher, so it can hash a new input.

**Example**
```pepper
    import digest;

    # The id git gives an empty file ("blob 0" and a NUL byte).
    u8[] nul = [0];
    var hasher = digest.Sha1();
    hasher.update("blob 0");
    hasher.update(nul);
    assert(hasher.finish_hex() == "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", "git blob id");
```

### Constructor

#### Sha1()

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

Returns the 20-byte digest of the input given since the hasher was
created or last reset, then resets it.

**Returns**
- the digest, most significant byte first

#### finish_hex

```pepper
finish_hex(): String
```

Returns the digest as `finish` does, written as 40 lowercase
hexadecimal digits.

**Returns**
- the digest in hexadecimal

## sha1

```pepper
sha1(bytes: u8[]): u8[]
```

Returns the SHA-1 digest of `bytes`.

**Parameters**
- `bytes` — the input

**Returns**
- the 20-byte digest

## sha1

```pepper
sha1(text: String): u8[]
```

Returns the SHA-1 digest of the UTF-8 bytes of `text`.

**Parameters**
- `text` — the input

**Returns**
- the 20-byte digest

**Example**
```pepper
    import digest;

    assert(digest.to_hex(digest.sha1("abc")) == "a9993e364706816aba3e25717850c26c9cd0d89d", "FIPS 180-4 example");
```
