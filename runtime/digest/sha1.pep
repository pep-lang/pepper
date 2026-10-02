## SHA-1 (FIPS 180-4): 20-byte digests, as git uses for object ids. SHA-1
## is broken for collision resistance; use it to read existing formats,
## and SHA-256 or BLAKE3 for anything new.

import "hex";
import "words";

## An incremental SHA-1 hasher: feed it bytes with `update`, any number of
## times and in pieces of any size, then read the 20-byte digest with
## `finish`.
##
## SHA-1 is not collision resistant: someone can make two inputs with the
## same digest. Use it only where a format requires it, such as git object
## ids. `finish` resets the hasher, so it can hash a new input.
##
## @example
##     import digest;
##
##     # The id git gives an empty file ("blob 0" and a NUL byte).
##     u8[] nul = [0];
##     var hasher = digest.Sha1();
##     hasher.update("blob 0");
##     hasher.update(nul);
##     assert(hasher.finish_hex() == "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", "git blob id");
export struct Sha1 {
    # The five state words (H0-H4).
    var _state: uint[];
    # The 80-word message schedule, scratch space for `_compress`.
    var _schedule: uint[];
    # The input not yet compressed.
    var _buffer: _DigestBuffer;

    ## Creates a hasher in the initial state, with no input.
    construct() {
        _state = _digest_words(5);
        _schedule = _digest_words(80);
        _buffer = _DigestBuffer();
        reset();
    }

    ## Discards the input given so far, returning the hasher to its initial
    ## state.
    reset() {
        _state[0] = 0x67452301;
        _state[1] = 0xefcdab89;
        _state[2] = 0x98badcfe;
        _state[3] = 0x10325476;
        _state[4] = 0xc3d2e1f0;
        _buffer.reset();
    }

    ## Hashes `bytes` as the next part of the input.
    ##
    ## @param bytes the bytes to add
    update(bytes: u8[]) {
        _buffer.feed<Sha1>(this, bytes._data, bytes.count);
    }

    ## Hashes the UTF-8 bytes of `text` (without a terminating NUL) as the
    ## next part of the input.
    ##
    ## @param text the text to add
    update(text: String) {
        _buffer.feed<Sha1>(this, text.c_str() as __ptr<u8>, text.size);
    }

    ## Returns the 20-byte digest of the input given since the hasher was
    ## created or last reset, then resets it.
    ##
    ## @returns the digest, most significant byte first
    finish(): u8[] {
        _buffer.pad<Sha1>(this);
        var out = Array<u8>(20);
        ulong index = 0;
        while (index < 5) {
            _digest_append_be(out, _state[index]);
            index += 1;
        }
        reset();
        return out;
    }

    ## Returns the digest as `finish` does, written as 40 lowercase
    ## hexadecimal digits.
    ##
    ## @returns the digest in hexadecimal
    finish_hex(): String {
        return to_hex(finish());
    }

    # Runs the compression function over the 64 bytes at `block`.
    _compress(block: __ptr<u8>) {
        var w = _schedule._data;
        ulong t = 0;
        while (t < 16) {
            w[t] = _digest_load_be(block, t * 4);
            t += 1;
        }
        while (t < 80) {
            w[t] = _digest_rotate_left(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1);
            t += 1;
        }
        var h = _state._data;
        uint a = h[0];
        uint b = h[1];
        uint c = h[2];
        uint d = h[3];
        uint e = h[4];
        t = 0;
        while (t < 80) {
            uint f = 0;
            uint k = 0;
            if (t < 20) {
                f = (b & c) | (~b & d);
                k = 0x5a827999;
            } else if (t < 40) {
                f = b ^ c ^ d;
                k = 0x6ed9eba1;
            } else if (t < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8f1bbcdc;
            } else {
                f = b ^ c ^ d;
                k = 0xca62c1d6;
            }
            uint temp = _digest_rotate_left(a, 5) + f + e + k + w[t];
            e = d;
            d = c;
            c = _digest_rotate_left(b, 30);
            b = a;
            a = temp;
            t += 1;
        }
        h[0] = h[0] + a;
        h[1] = h[1] + b;
        h[2] = h[2] + c;
        h[3] = h[3] + d;
        h[4] = h[4] + e;
    }
}

extend Sha1 with _DigestCompressor;

## Returns the SHA-1 digest of `bytes`.
##
## @param bytes the input
## @returns the 20-byte digest
export sha1(bytes: u8[]): u8[] {
    var hasher = Sha1();
    hasher.update(bytes);
    return hasher.finish();
}

## Returns the SHA-1 digest of the UTF-8 bytes of `text`.
##
## @param text the input
## @returns the 20-byte digest
## @example
##     import digest;
##
##     assert(digest.to_hex(digest.sha1("abc")) == "a9993e364706816aba3e25717850c26c9cd0d89d", "FIPS 180-4 example");
export sha1(text: String): u8[] {
    var hasher = Sha1();
    hasher.update(text);
    return hasher.finish();
}
