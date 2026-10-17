# Cryptographic hashes

The `digest` module computes SHA-256, SHA-1 and BLAKE3 digests: fixed-size
fingerprints of data, used to check that a download arrived intact, to name
content by its hash, or to key a cache. It also computes
[message authentication codes](#message-authentication) with HMAC or
BLAKE3's keyed mode, and derives keys. Bring it in with `import digest`;
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

## Message authentication

A message authentication code (MAC) is a digest that only someone with a
secret key can compute, so a receiver that shares the key can check that a
message is authentic and unchanged. Webhook signatures, JWTs (HS256) and
S3-style request signing all use HMAC.

```pepper
{{#include ../../examples/digest-mac.pep}}
```

- **HMAC** (RFC 2104) works over SHA-256 or SHA-1:
  `digest.hmac_sha256(key, message)` and `digest.hmac_sha1(key, message)`
  are one-shot, both arguments `u8[]` or both `String`, and
  `digest.Hmac<digest.Sha256>(key)` is the incremental hasher, with the
  same `update`, `finish`, `finish_hex` and `reset` as the hashes. `finish`
  and `reset` keep the key. A key longer than 64 bytes is hashed first.
- **Check a MAC** with `digest.equal_constant_time(a, b)`, not `==`: `==`
  stops at the first byte that differs, and timing it lets an attacker
  find a valid MAC a byte at a time.
- **BLAKE3's keyed mode**, `digest.Blake3.keyed(key)`, is a MAC with a
  32-byte key; it panics on a key of any other length.
- **Key derivation**: `digest.Blake3.derive_key(context)` returns a hasher
  whose digest is a key, derived from the input (a shared secret, say) for
  the purpose `context` names. Make `context` a hard-coded string unique to
  the application and purpose; different contexts give unrelated keys.
- **Extended output**: every `Blake3` hasher's `finish(length)` returns
  `length` bytes, in any of the three modes. The first 32 are the digest
  `finish()` returns.

## Using the system's crypto library

By default the hashes are written in Pepper, so a program that uses them
links no extra library. Building with `-D USE_LIBCRYPTO` (see
[Build options](build-options.md)) makes SHA-256 and SHA-1 call the
platform's crypto library instead, which uses the CPU's SHA instructions
where it has them: several times faster (about 1.7 GB/s instead of
250 MB/s for SHA-256 on an x86-64 with SHA-NI).

```sh
pep-build main.pep -D USE_LIBCRYPTO -o app
```

| Platform | Library | What it needs |
|---|---|---|
| Linux | OpenSSL's libcrypto (`EVP_Digest*`), linked as `-lcrypto` | the development package (`libssl-dev`, `openssl-devel`) |
| macOS | OpenSSL's libcrypto, linked as `-lcrypto` | Homebrew's `openssl@3`, and its `lib` folder named with `-L` or `PEPPER_LIBRARY_PATH` (`-L $(brew --prefix openssl@3)/lib`) |
| Windows | CNG (`BCryptHash*`), linked as `bcrypt.lib` | nothing: CNG is part of Windows 10 and later |

The API and the digests are the same either way. `Blake3` stays portable
Pepper, since libcrypto has no BLAKE3.

## Limitations

- Without `USE_LIBCRYPTO`, SHA-256 and SHA-1 run at a few hundred
  megabytes per second. BLAKE3 is always the portable code, below the
  official BLAKE3, which uses SIMD and threads.
- The hashes have no secret-dependent branches or table lookups, but they
  have not been audited for timing side channels, which matter only when
  hashing secrets. Copies of an HMAC key stay in memory until the hasher
  is freed; nothing wipes them.
- HMAC works over SHA-256 and SHA-1; there is no SHA-512 to put under it.
