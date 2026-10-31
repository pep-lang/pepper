<!-- Generated from runtime/random/entropy.pep by `pep-doc reference`. Do not edit. -->

# Entropy

Secure random bytes from the operating system: `getentropy` on Linux,
Android, macOS, iOS and WASI, and `BCryptGenRandom` on Windows. They are
unpredictable, so they suit keys, tokens and identifiers, but each call
asks the kernel; a `Generator` is much faster for everything else.

Source: `runtime/random/entropy.pep`

## fill

```pepper
fill(bytes: u8[])
```

Overwrites every element of `bytes` with secure random bytes from the
operating system.

**Parameters**
- `bytes` — the array to overwrite; its `count` does not change

**Panics**
- if the operating system cannot give random bytes, which only a broken system does

**Example**
```pepper
var nonce = random.bytes(12);
random.fill(nonce);   # a fresh 12 bytes in the same array
```

## bytes

```pepper
bytes(count: ulong): u8[]
```

Returns `count` secure random bytes from the operating system.

**Parameters**
- `count` — the number of bytes

**Returns**
- a new array of `count` random bytes

**Panics**
- if the operating system cannot give random bytes, which only a broken system does

**Example**
```pepper
var key = random.bytes(32);   # a 256-bit key
```

## secure_ulong

```pepper
secure_ulong(): ulong
```

Returns a secure random `ulong` from the operating system.

**Returns**
- a number from 0 to 2^64 - 1, every value equally likely

**Panics**
- if the operating system cannot give random bytes, which only a broken system does

**Example**
```pepper
var token = random.secure_ulong();
```
