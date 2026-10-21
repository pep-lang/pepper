## HMAC (RFC 2104): a message authentication code from a hash and a secret
## key, as webhook signatures, JWTs (HS256) and S3-style request signing
## use, and a constant-time comparison to check one. Also PBKDF2, the
## password-based key derivation built on HMAC-SHA-256.

import "hex";
import "sha1";
import "sha256";
import "words";

# The block size of SHA-256 and SHA-1, which sizes HMAC's padded key.
const _HMAC_BLOCK_SIZE: ulong = 64;

## An incremental HMAC hasher over the hash `T`: feed it the message with
## `update`, any number of times and in pieces of any size, then read the
## MAC with `finish`.
##
## Only someone with the key can compute the MAC of a message, so a
## receiver that shares the key can check that the message is authentic.
## Compare a MAC you receive with `equal_constant_time`, not `==`.
## `finish` resets the hasher to the same key, so it can sign a new
## message.
##
## @typeParam T the hash: `Sha256` or `Sha1`, or another hasher with a
##     64-byte block, a constructor taking no arguments, and `update` and
##     `finish` methods
## @example
##     import digest;
##
##     var mac = digest.Hmac<digest.Sha256>("key");
##     mac.update("The quick brown fox ");
##     mac.update("jumps over the lazy dog");
##     var expected = "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8";
##     assert(mac.finish_hex() == expected, "HMAC-SHA-256");
export struct Hmac<T> {
    # The hash of the key and the message, and the hasher of the outer
    # hash, over the key and the inner hash.
    var _inner: T;
    var _outer: T;
    # The key, padded to a block, XORed with 0x36 (ipad) and 0x5c (opad).
    var _inner_pad: u8[];
    var _outer_pad: u8[];

    ## Creates a hasher for MACs under `key`, with no input.
    ##
    ## A key longer than 64 bytes is hashed with `T` first, as RFC 2104
    ## says; one as long as `T`'s digest is the usual choice.
    ##
    ## @param key the secret key
    construct(key: u8[]) {
        _use_key(key);
    }

    ## Creates a hasher for MACs under the UTF-8 bytes of `key`, with no
    ## input.
    ##
    ## @param key the secret key
    construct(key: String) {
        _use_key(key.bytes());
    }

    # Starts over with the key `key`.
    _use_key(key: u8[]) {
        _inner = T();
        _outer = T();
        var block = key;
        if (key.count > _HMAC_BLOCK_SIZE) {
            var key_hasher = T();
            key_hasher.update(key);
            block = key_hasher.finish();
        }
        _inner_pad = Array<u8>(_HMAC_BLOCK_SIZE);
        _outer_pad = Array<u8>(_HMAC_BLOCK_SIZE);
        ulong index = 0;
        while (index < _HMAC_BLOCK_SIZE) {
            u8 byte = index < block.count ? block[index] : 0;
            _inner_pad.append(byte ^ 0x36);
            _outer_pad.append(byte ^ 0x5c);
            index += 1;
        }
        reset();
    }

    ## Discards the input given so far, returning the hasher to its initial
    ## state under the same key.
    reset() {
        _inner.reset();
        _inner.update(_inner_pad);
    }

    ## Adds `bytes` as the next part of the message.
    ##
    ## @param bytes the bytes to add
    update(bytes: u8[]) {
        _inner.update(bytes);
    }

    ## Adds the UTF-8 bytes of `text` (without a terminating NUL) as the
    ## next part of the message.
    ##
    ## @param text the text to add
    update(text: String) {
        _inner.update(text);
    }

    ## Returns the MAC of the message given since the hasher was created or
    ## last reset, then resets it.
    ##
    ## @returns the MAC, as long as `T`'s digest
    finish(): u8[] {
        var inner_digest = _inner.finish();
        _outer.update(_outer_pad);
        _outer.update(inner_digest);
        var mac = _outer.finish();
        reset();
        return mac;
    }

    # Replaces the contents of `out` with the MAC, then resets: `finish`
    # without allocating, for PBKDF2's rounds. Only `Sha256` has the
    # `_finish_into` this needs.
    _finish_into(out: u8[]) {
        _inner._finish_into(out);
        _outer.update(_outer_pad);
        _outer.update(out);
        _outer._finish_into(out);
        reset();
    }

    ## Returns the MAC as `finish` does, written as lowercase hexadecimal
    ## digits.
    ##
    ## @returns the MAC in hexadecimal
    finish_hex(): String {
        return to_hex(finish());
    }
}

## Returns the HMAC-SHA-256 of `message` under `key`.
##
## @param key the secret key
## @param message the message to sign
## @returns the 32-byte MAC
export hmac_sha256(key: u8[], message: u8[]): u8[] {
    var mac = Hmac<Sha256>(key);
    mac.update(message);
    return mac.finish();
}

## Returns the HMAC-SHA-256 of the UTF-8 bytes of `message` under the UTF-8
## bytes of `key`.
##
## @param key the secret key
## @param message the message to sign
## @returns the 32-byte MAC
## @example
##     import digest;
##
##     var mac = digest.hmac_sha256("key", "The quick brown fox jumps over the lazy dog");
##     var expected = "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8";
##     assert(digest.to_hex(mac) == expected, "HMAC-SHA-256");
export hmac_sha256(key: String, message: String): u8[] {
    return hmac_sha256(key.bytes(), message.bytes());
}

## Returns the HMAC-SHA-1 of `message` under `key`, for formats that
## require it. HMAC-SHA-1 is still secure as a MAC, though SHA-1 alone is
## not.
##
## @param key the secret key
## @param message the message to sign
## @returns the 20-byte MAC
export hmac_sha1(key: u8[], message: u8[]): u8[] {
    var mac = Hmac<Sha1>(key);
    mac.update(message);
    return mac.finish();
}

## Returns the HMAC-SHA-1 of the UTF-8 bytes of `message` under the UTF-8
## bytes of `key`.
##
## @param key the secret key
## @param message the message to sign
## @returns the 20-byte MAC
export hmac_sha1(key: String, message: String): u8[] {
    return hmac_sha1(key.bytes(), message.bytes());
}

# RFC 8018's limit on PBKDF2's output: (2^32 - 1) blocks of HMAC-SHA-256's
# 32 bytes.
const _PBKDF2_SHA256_MAX_LENGTH: ulong = 0xffffffff * 32;

## Derives `length` bytes from `password` and `salt` with PBKDF2-HMAC-SHA256
## (RFC 8018), running `rounds` iterations of HMAC-SHA-256 for each 32-byte
## block of the output.
##
## This is SCRAM's `Hi()` (PostgreSQL, MongoDB and SASL logins), and it
## derives keys from passphrases for formats that specify it. To store new
## passwords, use Argon2id (`crypto.hash_password` in pepper-crypto)
## instead: PBKDF2 needs almost no memory, so GPUs and ASICs test guesses
## against it cheaply.
## Where PBKDF2 is required, give each password its own random salt of 16
## bytes or more, and as many rounds as the login can afford (OWASP suggests
## 600,000).
##
## The time grows with `rounds` times the number of 32-byte blocks, so a
## `length` above 32 costs the caller more but an attacker, who needs only
## the first block, no more.
##
## @param password the password or passphrase
## @param salt the salt
## @param rounds the iteration count, at least 1
## @param length the number of bytes to derive; 0 returns none
## @returns the `length`-byte derived key
## @panics if `rounds` is 0, or `length` is over (2^32 - 1) * 32 bytes,
##     RFC 8018's limit
## @example
##     import digest;
##
##     var key = digest.pbkdf2_sha256("passwd".bytes(), "salt".bytes(), 1, 16);
##     assert(digest.to_hex(key) == "55ac046e56e3089fec1691c22544b605", "RFC 7914 section 11");
export pbkdf2_sha256(password: u8[], salt: u8[], rounds: ulong, length: ulong): u8[] {
    assert(rounds > 0, "pbkdf2_sha256: 'rounds' must be at least 1");
    assert(length <= _PBKDF2_SHA256_MAX_LENGTH, "pbkdf2_sha256: 'length' is over RFC 8018's limit");
    var mac = Hmac<Sha256>(password);
    var key = Array<u8>(length);
    # One round's U_j, the XOR of a block's rounds (T_i), and INT(i). The
    # rounds reuse them, so the portable path allocates nothing per round.
    var round = Array<u8>(32);
    var block = Array<u8>(32);
    var counter = Array<u8>(4);
    uint index = 1;
    while (key.count < length) {
        counter.clear();
        _digest_append_be(counter, index);
        mac.update(salt);
        mac.update(counter);
        mac._finish_into(round);
        block.clear();
        block.append_all(round);
        ulong done = 1;
        while (done < rounds) {
            mac.update(round);
            mac._finish_into(round);
            ulong byte = 0;
            while (byte < 32) {
                block[byte] = block[byte] ^ round[byte];
                byte += 1;
            }
            done += 1;
        }
        var left = length - key.count;
        key.append_from(block._data, left < 32 ? left : 32);
        index += 1;
    }
    return key;
}

## Derives `length` bytes from the UTF-8 bytes of `password` and `salt`
## with PBKDF2-HMAC-SHA256, as the `u8[]` overload does.
##
## @param password the password or passphrase
## @param salt the salt
## @param rounds the iteration count, at least 1
## @param length the number of bytes to derive; 0 returns none
## @returns the `length`-byte derived key
## @panics if `rounds` is 0, or `length` is over (2^32 - 1) * 32 bytes,
##     RFC 8018's limit
## @example
##     import digest;
##
##     var key = digest.pbkdf2_sha256("passwd", "salt".bytes(), 1, 16);
##     assert(digest.to_hex(key) == "55ac046e56e3089fec1691c22544b605", "RFC 7914 section 11");
export pbkdf2_sha256(password: String, salt: u8[], rounds: ulong, length: ulong): u8[] {
    return pbkdf2_sha256(password.bytes(), salt, rounds, length);
}

## Returns whether `a` and `b` hold the same bytes, taking the same time
## wherever they first differ.
##
## Check a MAC with this rather than `==`, which stops at the first
## difference: timing it would let an attacker find a valid MAC a byte at a
## time. The lengths are not secret, so arrays of different lengths return
## `false` at once.
##
## @param a the first bytes, such as the MAC computed
## @param b the second bytes, such as the MAC received
## @returns `true` if `a` and `b` have the same length and bytes
## @example
##     import digest;
##
##     var mac = digest.hmac_sha256("key", "message");
##     assert(digest.equal_constant_time(mac, digest.hmac_sha256("key", "message")), "a valid MAC");
export equal_constant_time(a: u8[], b: u8[]): bool {
    if (a.count != b.count) {
        return false;
    }
    u8 difference = 0;
    ulong index = 0;
    while (index < a.count) {
        difference = difference | (a[index] ^ b[index]);
        index += 1;
    }
    return difference == 0;
}
