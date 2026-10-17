## HMAC (RFC 2104): a message authentication code from a hash and a secret
## key, as webhook signatures, JWTs (HS256) and S3-style request signing
## use, and a constant-time comparison to check one.

import "hex";
import "sha1";
import "sha256";

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
