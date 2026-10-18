## Secure random bytes from the operating system: `getentropy` on Linux,
## Android, macOS, iOS and WASI, and `BCryptGenRandom` on Windows. They are
## unpredictable, so they suit keys, tokens and identifiers, but each call
## asks the kernel; a `Generator` is much faster for everything else.

# getentropy is in glibc 2.25 and later, musl, bionic (API level 28; Pepper
# targets 30 and later), macOS 10.12 and later, and wasi-libc, where it
# calls WASI's random_get. It reads at most 256 bytes a call.
[Target(!OS(Windows))]
extern int getentropy(u8* buffer, ulong size);

[Target(OS(Windows))]
[Link("bcrypt")]
extern int BCryptGenRandom(void* algorithm, u8* buffer, uint size, uint flags);

# BCRYPT_USE_SYSTEM_PREFERRED_RNG: no algorithm handle needed.
[Target(OS(Windows))]
const _RANDOM_SYSTEM_PREFERRED_RNG: uint = 2;

# Fills `count` bytes at `at` from the operating system, in chunks each call
# accepts.
[Target(!OS(Windows))]
_random_fill(at: __ptr<u8>, count: ulong) {
    ulong done = 0;
    while (done < count) {
        ulong size = count - done < 256 ? count - done : 256;
        assert(getentropy(at + done, size) == 0, "random: the operating system has no entropy to give");
        done += size;
    }
}

[Target(OS(Windows))]
_random_fill(at: __ptr<u8>, count: ulong) {
    ulong done = 0;
    while (done < count) {
        ulong size = count - done < 1073741824 ? count - done : 1073741824;
        var status = BCryptGenRandom(__null, at + done, size as uint, _RANDOM_SYSTEM_PREFERRED_RNG);
        assert(status == 0, "random: the operating system has no entropy to give");
        done += size;
    }
}

## Overwrites every element of `bytes` with secure random bytes from the
## operating system.
##
## @param bytes the array to overwrite; its `count` does not change
## @panics if the operating system cannot give random bytes, which only a broken system does
## @example
##     var nonce = random.bytes(12);
##     random.fill(nonce);   # a fresh 12 bytes in the same array
fill(bytes: u8[]) {
    if (bytes.count == 0) {
        return;
    }
    _random_fill(bytes._data, bytes.count);
}

## Returns `count` secure random bytes from the operating system.
##
## @param count the number of bytes
## @returns a new array of `count` random bytes
## @panics if the operating system cannot give random bytes, which only a broken system does
## @example
##     var key = random.bytes(32);   # a 256-bit key
bytes(count: ulong): u8[] {
    var result = Array<u8>(count);
    if (count == 0) {
        return result;
    }
    _random_fill(result._data, count);
    result._size = count;
    return result;
}

## Returns a secure random `ulong` from the operating system.
##
## @returns a number from 0 to 2^64 - 1, every value equally likely
## @panics if the operating system cannot give random bytes, which only a broken system does
## @example
##     var token = random.secure_ulong();
secure_ulong(): ulong {
    var raw = bytes(8);
    ulong result = 0;
    for (var b in raw) {
        result = (result << 8) | (b as ulong);
    }
    return result;
}
