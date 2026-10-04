# The SHA-256 and SHA-1 engines of a build that defines `USE_LIBCRYPTO`:
# OpenSSL's libcrypto (`EVP_Digest*`) on Linux and macOS, and CNG
# (`BCrypt*Hash*`) on Windows. Both use the CPU's SHA instructions where
# there are any. sha256.pep and sha1.pep declare the portable engines with
# the same names and methods for every other build:
#
# - `construct()`: a hasher with no input
# - `reset()`: discards the input
# - `update(data, size)`: hashes `size` bytes at `data`
# - `finish(out)`: appends the digest to `out`, then resets
#
# Every declaration here carries `BuildOption(USE_LIBCRYPTO)`, so a build
# without it links neither library.

import "words";

# ── libcrypto (Linux and macOS) ──────────────────────────────────────────────

[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
[Link("crypto")]
extern void* EVP_MD_CTX_new();
[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
[Link("crypto")]
extern void EVP_MD_CTX_free(void* context);
[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
[Link("crypto")]
extern void* EVP_sha256();
[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
[Link("crypto")]
extern void* EVP_sha1();
[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
[Link("crypto")]
extern int EVP_DigestInit_ex(void* context, void* algorithm, void* engine);
[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
[Link("crypto")]
extern int EVP_DigestUpdate(void* context, void* data, ulong size);
[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
[Link("crypto")]
extern int EVP_DigestFinal_ex(void* context, u8* digest, uint* size);

# A libcrypto digest context for one algorithm, freed with the struct.
[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
struct _DigestNative {
    var _context: Handle<__ptr<void>>;
    # The `EVP_MD` (`EVP_sha256()`, `EVP_sha1()`).
    var _algorithm: __ptr<void>;
    # The digest's size in bytes.
    var _size: ulong;

    construct(algorithm: __ptr<void>, size: ulong) {
        var context = EVP_MD_CTX_new();
        assert(context != __null, "libcrypto could not allocate a digest context");
        _context = Handle<__ptr<void>>(context, (c) => EVP_MD_CTX_free(c));
        _algorithm = algorithm;
        _size = size;
        reset();
    }

    reset() {
        var initialized = EVP_DigestInit_ex(_context.value, _algorithm, __null);
        assert(initialized == 1, "libcrypto could not start a digest");
    }

    update(data: __ptr<u8>, size: ulong) {
        if (size > 0) {
            EVP_DigestUpdate(_context.value, data as __ptr<void>, size);
        }
    }

    finish(out: u8[]) {
        var digest = _digest_bytes(64);
        EVP_DigestFinal_ex(_context.value, digest._data, __null);
        out._append_raw(digest._data, _size);
        reset();
    }
}

[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
_digest_native_sha256(): _DigestNative {
    return _DigestNative(EVP_sha256(), 32);
}

[Target(BuildOption(USE_LIBCRYPTO) && !OS(Windows))]
_digest_native_sha1(): _DigestNative {
    return _DigestNative(EVP_sha1(), 20);
}

# ── CNG (Windows) ────────────────────────────────────────────────────────────

[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
[Link("bcrypt")]
extern int BCryptCreateHash(
    void* algorithm, void** hash, u8* object, uint object_size, u8* secret, uint secret_size, uint flags
);
[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
[Link("bcrypt")]
extern int BCryptHashData(void* hash, u8* input, uint size, uint flags);
[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
[Link("bcrypt")]
extern int BCryptFinishHash(void* hash, u8* output, uint size, uint flags);
[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
[Link("bcrypt")]
extern int BCryptDestroyHash(void* hash);

# The pseudo-handles of the algorithms (Windows 10 and later), which need
# no BCryptOpenAlgorithmProvider: `BCRYPT_SHA1_ALG_HANDLE` and
# `BCRYPT_SHA256_ALG_HANDLE` in bcrypt.h (0x11 is MD4's).
[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
const _DIGEST_CNG_SHA1: long = 0x31;
[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
const _DIGEST_CNG_SHA256: long = 0x41;
# BCRYPT_HASH_REUSABLE_FLAG: BCryptFinishHash leaves the hash ready for new
# input.
[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
const _DIGEST_CNG_REUSABLE: uint = 0x20;

# A CNG hash object for one algorithm, destroyed with the struct.
[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
struct _DigestNative {
    var _hash: Handle<__ptr<void>>;
    # The digest's size in bytes.
    var _size: ulong;

    construct(algorithm: long, size: ulong) {
        var slot = Array<__ptr<void>>(1);
        slot.append(__null);
        var status = BCryptCreateHash(
            unsafe_cast<__ptr<void>>(algorithm), slot._data, __null, 0, __null, 0, _DIGEST_CNG_REUSABLE
        );
        assert(status == 0, "CNG could not create a hash object");
        _hash = Handle<__ptr<void>>(slot[0], (h) => {
            BCryptDestroyHash(h);
        });
        _size = size;
    }

    reset() {
        # A reusable hash starts over once it is finished.
        var discard = _digest_bytes(_size);
        BCryptFinishHash(_hash.value, discard._data, _size as uint, 0);
    }

    update(data: __ptr<u8>, size: ulong) {
        # BCryptHashData takes at most 4 GiB - 1 bytes a call.
        ulong done = 0;
        while (done < size) {
            var count = size - done;
            if (count > 0x40000000) {
                count = 0x40000000;
            }
            BCryptHashData(_hash.value, data + done, count as uint, 0);
            done += count;
        }
    }

    finish(out: u8[]) {
        var digest = _digest_bytes(_size);
        BCryptFinishHash(_hash.value, digest._data, _size as uint, 0);
        out._append_raw(digest._data, _size);
    }
}

[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
_digest_native_sha256(): _DigestNative {
    return _DigestNative(_DIGEST_CNG_SHA256, 32);
}

[Target(BuildOption(USE_LIBCRYPTO) && OS(Windows))]
_digest_native_sha1(): _DigestNative {
    return _DigestNative(_DIGEST_CNG_SHA1, 20);
}

# ── The engines ──────────────────────────────────────────────────────────────

[BuildOption("USE_LIBCRYPTO")]
struct _Sha256Engine {
    var _native: _DigestNative;

    construct() {
        _native = _digest_native_sha256();
    }

    reset() {
        _native.reset();
    }

    update(data: __ptr<u8>, size: ulong) {
        _native.update(data, size);
    }

    finish(out: u8[]) {
        _native.finish(out);
    }
}

[BuildOption("USE_LIBCRYPTO")]
struct _Sha1Engine {
    var _native: _DigestNative;

    construct() {
        _native = _digest_native_sha1();
    }

    reset() {
        _native.reset();
    }

    update(data: __ptr<u8>, size: ulong) {
        _native.update(data, size);
    }

    finish(out: u8[]) {
        _native.finish(out);
    }
}
