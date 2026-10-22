## SHA-256 (FIPS 180-4): 32-byte digests, as used to check downloads and
## sign data.

import "hex";
import "libcrypto";
import "words";

## An incremental SHA-256 hasher: feed it bytes with `update`, any number of
## times and in pieces of any size, then read the 32-byte digest with
## `finish`.
##
## The digest of the input is the same however it was split between
## `update` calls. `finish` resets the hasher, so it can hash a new input.
##
## @example
##     import digest;
##
##     var hasher = digest.Sha256();
##     hasher.update("hello ");
##     hasher.update("world");
##     assert(hasher.finish_hex() == digest.to_hex(digest.sha256("hello world")), "same digest");
export struct Sha256 {
    # The portable Pepper code, or libcrypto or CNG under `USE_LIBCRYPTO`.
    var _engine: _Sha256Engine;

    ## Creates a hasher in the initial state, with no input.
    construct() {
        _engine = _Sha256Engine();
    }

    ## Discards the input given so far, returning the hasher to its initial
    ## state.
    reset() {
        _engine.reset();
    }

    ## Hashes `bytes` as the next part of the input.
    ##
    ## @param bytes the bytes to add
    update(bytes: u8[]) {
        _engine.update(bytes._data, bytes.count);
    }

    ## Hashes the UTF-8 bytes of `text` (without a terminating NUL) as the
    ## next part of the input.
    ##
    ## @param text the text to add
    update(text: String) {
        _engine.update(unsafe_cast<__ptr<u8>>(text.c_str()), text.size);
    }

    ## Returns the 32-byte digest of the input given since the hasher was
    ## created or last reset, then resets it.
    ##
    ## @returns the digest, most significant byte first
    finish(): u8[] {
        var out = Array<u8>(32);
        _engine.finish(out);
        return out;
    }

    # Replaces the contents of `out` with the digest, then resets: `finish`
    # without allocating, for PBKDF2's rounds.
    _finish_into(out: u8[]) {
        out.clear();
        _engine.finish(out);
    }

    ## Returns the digest as `finish` does, written as 64 lowercase
    ## hexadecimal digits.
    ##
    ## @returns the digest in hexadecimal
    finish_hex(): String {
        return to_hex(finish());
    }
}

# The portable SHA-256, used unless the build defines `USE_LIBCRYPTO`
# (see libcrypto.pep).
[Target(!BuildOption(USE_LIBCRYPTO))]
struct _Sha256Engine {
    # The eight state words (H0-H7).
    var _state: uint[];
    # The 64-word message schedule, scratch space for `_compress`.
    var _schedule: uint[];
    # The 64 round constants (K).
    var _constants: uint[];
    # The input not yet compressed.
    var _buffer: _DigestBuffer;

    construct() {
        _state = _digest_words(8);
        _schedule = _digest_words(64);
        _constants = _digest_sha256_constants();
        _buffer = _DigestBuffer();
        reset();
    }

    reset() {
        uint[] initial = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ];
        ulong index = 0;
        while (index < 8) {
            _state[index] = initial[index];
            index += 1;
        }
        _buffer.reset();
    }

    update(data: __ptr<u8>, size: ulong) {
        _buffer.feed<_Sha256Engine>(this, data, size);
    }

    # Appends the digest to `out`, then resets.
    finish(out: u8[]) {
        _buffer.pad<_Sha256Engine>(this);
        ulong index = 0;
        while (index < 8) {
            _digest_append_be(out, _state[index]);
            index += 1;
        }
        reset();
    }

    # Runs the compression function over the 64 bytes at `block`.
    _compress(block: __ptr<u8>) {
        var w = _schedule._data;
        var k = _constants._data;
        ulong t = 0;
        while (t < 16) {
            w[t] = _digest_load_be(block, t * 4);
            t += 1;
        }
        while (t < 64) {
            uint w15 = w[t - 15];
            uint w2 = w[t - 2];
            uint s0 = _digest_rotate_right(w15, 7) ^ _digest_rotate_right(w15, 18) ^ (w15 >> 3);
            uint s1 = _digest_rotate_right(w2, 17) ^ _digest_rotate_right(w2, 19) ^ (w2 >> 10);
            w[t] = w[t - 16].wrapping_add(s0).wrapping_add(w[t - 7]).wrapping_add(s1);
            t += 1;
        }
        var h = _state._data;
        uint a = h[0];
        uint b = h[1];
        uint c = h[2];
        uint d = h[3];
        uint e = h[4];
        uint f = h[5];
        uint g = h[6];
        uint hh = h[7];
        t = 0;
        while (t < 64) {
            uint sum1 = _digest_rotate_right(e, 6) ^ _digest_rotate_right(e, 11) ^ _digest_rotate_right(e, 25);
            uint choose = (e & f) ^ (~e & g);
            uint temp1 = hh.wrapping_add(sum1).wrapping_add(choose).wrapping_add(k[t]).wrapping_add(w[t]);
            uint sum0 = _digest_rotate_right(a, 2) ^ _digest_rotate_right(a, 13) ^ _digest_rotate_right(a, 22);
            uint majority = (a & b) ^ (a & c) ^ (b & c);
            uint temp2 = sum0.wrapping_add(majority);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
            t += 1;
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }
}

[Target(!BuildOption(USE_LIBCRYPTO))]
extend _Sha256Engine with _DigestCompressor;

## Returns the SHA-256 digest of `bytes`.
##
## @param bytes the input
## @returns the 32-byte digest
## @example
##     import digest;
##
##     var empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
##     assert(digest.to_hex(digest.sha256(Array<u8>())) == empty, "SHA-256 of nothing");
export sha256(bytes: u8[]): u8[] {
    var hasher = Sha256();
    hasher.update(bytes);
    return hasher.finish();
}

## Returns the SHA-256 digest of the UTF-8 bytes of `text`.
##
## @param text the input
## @returns the 32-byte digest
## @example
##     import digest;
##
##     var abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
##     assert(digest.to_hex(digest.sha256("abc")) == abc, "FIPS 180-4 example");
export sha256(text: String): u8[] {
    var hasher = Sha256();
    hasher.update(text);
    return hasher.finish();
}

# SHA-256's round constants: the first 32 bits of the fractional parts of
# the cube roots of the first 64 primes.
[Target(!BuildOption(USE_LIBCRYPTO))]
_digest_sha256_constants(): uint[] {
    # format: off
    uint[] constants = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    # format: on
    return constants;
}
