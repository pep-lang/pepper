<!-- Generated from runtime/digest/module.pep by `pep-doc reference`. Do not edit. -->

# The digest module

Cryptographic hashes: SHA-256, SHA-1 and BLAKE3, and HMAC.

Bring it in with `import digest`. Each hash has an incremental hasher
(`update` any number of times, then `finish`) and a one-shot function,
and both take bytes (`u8[]`) or a `String` (its UTF-8 bytes). A digest
is a `u8[]`; `to_hex` writes it as text.

- [SHA-256](digest-sha256.md): `Sha256`, `sha256`
- [SHA-1](digest-sha1.md): `Sha1`, `sha1`, for formats that need it,
  such as git object ids
- [BLAKE3](digest-blake3.md): `Blake3`, `blake3`, with keyed hashing,
  key derivation and output of any length
- [HMAC](digest-hmac.md): `Hmac`, `hmac_sha256`, `hmac_sha1`, and
  `equal_constant_time` to check a MAC
- [Hexadecimal](digest-hex.md): `to_hex` and `from_hex`

The implementations are portable Pepper with no link dependency, unless
the program is built with `-D USE_LIBCRYPTO`: then SHA-256 and SHA-1 call
OpenSSL's libcrypto (CNG on Windows), which uses the CPU's SHA
instructions. They are not hardened against timing side channels, which
matters only when hashing secrets.

For the hash tables of `HashMap` and `HashSet`, use `hash<T>` instead:
it is much faster, but neither cryptographic nor stable between
versions.

**Example**
```pepper
import digest;

main(): int {
    var id = digest.to_hex(digest.sha256("hello"));
    assert(id == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "SHA-256");
    return 0;
}
```

Source: `runtime/digest/module.pep`
