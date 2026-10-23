<!-- Generated from runtime/digest/hmac.pep by `pep-doc reference`. Do not edit. -->

# HMAC

HMAC (RFC 2104): a message authentication code from a hash and a secret
key, as webhook signatures, JWTs (HS256) and S3-style request signing
use, and a constant-time comparison to check one. Also PBKDF2, the
password-based key derivation built on HMAC-SHA-256.

Source: `runtime/digest/hmac.pep`

## Hmac

```pepper
struct Hmac<T>
```

An incremental HMAC hasher over the hash `T`: feed it the message with
`update`, any number of times and in pieces of any size, then read the
MAC with `finish`.

Only someone with the key can compute the MAC of a message, so a
receiver that shares the key can check that the message is authentic.
Compare a MAC you receive with `equal_constant_time`, not `==`.
`finish` resets the hasher to the same key, so it can sign a new
message.

**Type parameters**
- `T` — the hash: `Sha256` or `Sha1`, or another hasher with a 64-byte block, a constructor taking no arguments, and `update` and `finish` methods

**Example**
```pepper
import digest;

var mac = digest.Hmac<digest.Sha256>("key");
mac.update("The quick brown fox ");
mac.update("jumps over the lazy dog");
var expected = "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8";
assert(mac.finish_hex() == expected, "HMAC-SHA-256");
```

### Constructors

#### Hmac()

```pepper
construct(key: u8[])
```

Creates a hasher for MACs under `key`, with no input.

A key longer than 64 bytes is hashed with `T` first, as RFC 2104
says; one as long as `T`'s digest is the usual choice.

**Parameters**
- `key` — the secret key

#### Hmac()

```pepper
construct(key: String)
```

Creates a hasher for MACs under the UTF-8 bytes of `key`, with no
input.

**Parameters**
- `key` — the secret key

### Methods

#### reset

```pepper
reset()
```

Discards the input given so far, returning the hasher to its initial
state under the same key.

#### update

```pepper
update(bytes: u8[])
```

Adds `bytes` as the next part of the message.

**Parameters**
- `bytes` — the bytes to add

#### update

```pepper
update(text: String)
```

Adds the UTF-8 bytes of `text` (without a terminating NUL) as the
next part of the message.

**Parameters**
- `text` — the text to add

#### finish

```pepper
finish(): u8[]
```

Returns the MAC of the message given since the hasher was created or
last reset, then resets it.

**Returns**
- the MAC, as long as `T`'s digest

#### finish_hex

```pepper
finish_hex(): String
```

Returns the MAC as `finish` does, written as lowercase hexadecimal
digits.

**Returns**
- the MAC in hexadecimal

## hmac_sha256

```pepper
hmac_sha256(key: u8[], message: u8[]): u8[]
```

Returns the HMAC-SHA-256 of `message` under `key`.

**Parameters**
- `key` — the secret key
- `message` — the message to sign

**Returns**
- the 32-byte MAC

## hmac_sha256

```pepper
hmac_sha256(key: String, message: String): u8[]
```

Returns the HMAC-SHA-256 of the UTF-8 bytes of `message` under the UTF-8
bytes of `key`.

**Parameters**
- `key` — the secret key
- `message` — the message to sign

**Returns**
- the 32-byte MAC

**Example**
```pepper
import digest;

var mac = digest.hmac_sha256("key", "The quick brown fox jumps over the lazy dog");
var expected = "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8";
assert(digest.to_hex(mac) == expected, "HMAC-SHA-256");
```

## hmac_sha1

```pepper
hmac_sha1(key: u8[], message: u8[]): u8[]
```

Returns the HMAC-SHA-1 of `message` under `key`, for formats that
require it. HMAC-SHA-1 is still secure as a MAC, though SHA-1 alone is
not.

**Parameters**
- `key` — the secret key
- `message` — the message to sign

**Returns**
- the 20-byte MAC

## hmac_sha1

```pepper
hmac_sha1(key: String, message: String): u8[]
```

Returns the HMAC-SHA-1 of the UTF-8 bytes of `message` under the UTF-8
bytes of `key`.

**Parameters**
- `key` — the secret key
- `message` — the message to sign

**Returns**
- the 20-byte MAC

## pbkdf2_sha256

```pepper
pbkdf2_sha256(password: u8[], salt: u8[], rounds: ulong, length: ulong): u8[]
```

Derives `length` bytes from `password` and `salt` with PBKDF2-HMAC-SHA256
(RFC 8018), running `rounds` iterations of HMAC-SHA-256 for each 32-byte
block of the output.

This is SCRAM's `Hi()` (PostgreSQL, MongoDB and SASL logins), and it
derives keys from passphrases for formats that specify it. To store new
passwords, use Argon2id (`crypto.hash_password` in pepper-crypto)
instead: PBKDF2 needs almost no memory, so GPUs and ASICs test guesses
against it cheaply.
Where PBKDF2 is required, give each password its own random salt of 16
bytes or more, and as many rounds as the login can afford (OWASP suggests
600,000).

The time grows with `rounds` times the number of 32-byte blocks, so a
`length` above 32 costs the caller more but an attacker, who needs only
the first block, no more.

**Parameters**
- `password` — the password or passphrase
- `salt` — the salt
- `rounds` — the iteration count, at least 1
- `length` — the number of bytes to derive; 0 returns none

**Returns**
- the `length`-byte derived key

**Panics**
- if `rounds` is 0, or `length` is over (2^32 - 1) * 32 bytes, RFC 8018's limit; under `-D USE_LIBCRYPTO`, also if a size or `rounds` is over what the platform takes (2^31 - 1 for libcrypto, 2^32 - 1 bytes for CNG), or the platform's PBKDF2 fails

**Example**
```pepper
import digest;

var key = digest.pbkdf2_sha256("passwd".bytes(), "salt".bytes(), 1, 16);
assert(digest.to_hex(key) == "55ac046e56e3089fec1691c22544b605", "RFC 7914 section 11");
```

## pbkdf2_sha256

```pepper
pbkdf2_sha256(password: String, salt: u8[], rounds: ulong, length: ulong): u8[]
```

Derives `length` bytes from the UTF-8 bytes of `password` and `salt`
with PBKDF2-HMAC-SHA256, as the `u8[]` overload does.

**Parameters**
- `password` — the password or passphrase
- `salt` — the salt
- `rounds` — the iteration count, at least 1
- `length` — the number of bytes to derive; 0 returns none

**Returns**
- the `length`-byte derived key

**Panics**
- if `rounds` is 0, or `length` is over (2^32 - 1) * 32 bytes, RFC 8018's limit; under `-D USE_LIBCRYPTO`, also if a size or `rounds` is over what the platform takes (2^31 - 1 for libcrypto, 2^32 - 1 bytes for CNG), or the platform's PBKDF2 fails

**Example**
```pepper
import digest;

var key = digest.pbkdf2_sha256("passwd", "salt".bytes(), 1, 16);
assert(digest.to_hex(key) == "55ac046e56e3089fec1691c22544b605", "RFC 7914 section 11");
```

## equal_constant_time

```pepper
equal_constant_time(a: u8[], b: u8[]): bool
```

Returns whether `a` and `b` hold the same bytes, taking the same time
wherever they first differ.

Check a MAC with this rather than `==`, which stops at the first
difference: timing it would let an attacker find a valid MAC a byte at a
time. The lengths are not secret, so arrays of different lengths return
`false` at once.

**Parameters**
- `a` — the first bytes, such as the MAC computed
- `b` — the second bytes, such as the MAC received

**Returns**
- `true` if `a` and `b` have the same length and bytes

**Example**
```pepper
import digest;

var mac = digest.hmac_sha256("key", "message");
assert(digest.equal_constant_time(mac, digest.hmac_sha256("key", "message")), "a valid MAC");
```
