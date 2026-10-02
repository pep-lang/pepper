# Cryptographic hashes

The `digest` module computes SHA-256, SHA-1 and BLAKE3 digests: fixed-size
fingerprints of data, used to check that a download arrived intact, to name
content by its hash, or to key a cache. Bring it in with `import digest`;
the full API is in the [reference](../reference/digest-module.md).

```pepper
{{#include ../../examples/digest-basics.pep}}
```

## One-shot and incremental

Each hash has a one-shot function and a hasher type:

| Hash | Function | Hasher | Digest size |
|---|---|---|---|
| SHA-256 | `digest.sha256(input)` | `digest.Sha256` | 32 bytes |
| SHA-1 | `digest.sha1(input)` | `digest.Sha1` | 20 bytes |
| BLAKE3 | `digest.blake3(input)` | `digest.Blake3` | 32 bytes |

- The input is a `u8[]`, or a `String`, which hashes its UTF-8 bytes
  (without a terminating NUL).
- A hasher takes the input in pieces: call `update` any number of times,
  then `finish` for the digest. Splitting the input differently gives the
  same digest. `finish` also resets the hasher, so it can hash another
  input; `reset` discards the input so far.
- A digest is a `u8[]`. `digest.to_hex(bytes)` writes it as lowercase
  hexadecimal, the way checksums are usually shown, and each hasher's
  `finish_hex()` does both steps.
- An array literal passed straight to `update` is ambiguous between its
  `u8[]` and `String` overloads; give it a type first
  (`u8[] nul = [0]; hasher.update(nul);`).

## Which hash

- **SHA-256** is the common choice for published checksums and anything
  that must interoperate.
- **BLAKE3** is faster and as strong; the compiler's build cache keys its
  objects with it.
- **SHA-1** is broken for collision resistance: someone can make two inputs
  with the same digest. Use it only where a format requires it, such as git
  object ids.

None of these is the hash for a hash table: `HashMap` and `HashSet` use
[`hash<T>`](hashing.md), which is much faster but neither cryptographic nor
stable between versions.

## Limitations

- The hashes are written in Pepper, with no link dependency. They run at a
  few hundred megabytes per second, below OpenSSL's SHA-256 with CPU SHA
  instructions and the official BLAKE3, which uses SIMD and threads.
- BLAKE3's keyed hashing, key derivation and extended output are not
  supported yet; `Blake3` computes the default 32-byte hash.
- The code is not hardened against timing side channels, which matters only
  when hashing secrets. There is no HMAC yet.
