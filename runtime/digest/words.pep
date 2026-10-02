# Helpers shared by the hash implementations: word loads and stores in
# either byte order, rotations, and zero-filled scratch arrays.

extern void memcpy(void* dest, void* src, ulong n);
extern void memset(void* p, int c, ulong n);

# The big-endian 32-bit word at `data[index]`.
export _digest_load_be(data: __ptr<u8>, index: ulong): uint {
    return ((data[index] as uint) << 24)
        | ((data[index + 1] as uint) << 16)
        | ((data[index + 2] as uint) << 8)
        | (data[index + 3] as uint);
}

# The little-endian 32-bit word at `data[index]`.
export _digest_load_le(data: __ptr<u8>, index: ulong): uint {
    return (data[index] as uint)
        | ((data[index + 1] as uint) << 8)
        | ((data[index + 2] as uint) << 16)
        | ((data[index + 3] as uint) << 24);
}

# Appends `value` to `out` as 4 big-endian bytes.
export _digest_append_be(out: u8[], value: uint) {
    out.append((value >> 24) as u8);
    out.append((value >> 16) as u8);
    out.append((value >> 8) as u8);
    out.append(value as u8);
}

# Appends `value` to `out` as 4 little-endian bytes.
export _digest_append_le(out: u8[], value: uint) {
    out.append(value as u8);
    out.append((value >> 8) as u8);
    out.append((value >> 16) as u8);
    out.append((value >> 24) as u8);
}

# `value` rotated right by `count` bits (1-31).
export _digest_rotate_right(value: uint, count: uint): uint {
    return (value >> count) | (value << (32 - count));
}

# `value` rotated left by `count` bits (1-31).
export _digest_rotate_left(value: uint, count: uint): uint {
    return (value << count) | (value >> (32 - count));
}

# A new array of `count` zero words.
export _digest_words(count: ulong): uint[] {
    var words = Array<uint>(count);
    ulong index = 0;
    while (index < count) {
        words.append(0);
        index += 1;
    }
    return words;
}

# A new array of `count` zero bytes.
export _digest_bytes(count: ulong): u8[] {
    var bytes = Array<u8>(count);
    ulong index = 0;
    while (index < count) {
        bytes.append(0);
        index += 1;
    }
    return bytes;
}

# Copies `size` bytes from `source` to `target`; the two must not overlap.
export _digest_copy(target: __ptr<u8>, source: __ptr<u8>, size: ulong) {
    memcpy(target as __ptr<void>, source as __ptr<void>, size);
}

# Sets `size` bytes at `target` to zero.
export _digest_zero(target: __ptr<u8>, size: ulong) {
    memset(target as __ptr<void>, 0, size);
}

# A hash built on a 64-byte block compression function (SHA-1, SHA-256).
export trait _DigestCompressor {
    _compress(block: __ptr<u8>);
}

# The input of a Merkle-Damgård hash (SHA-1, SHA-256) not yet compressed,
# and its total length. Splits the input into 64-byte blocks for a
# `_DigestCompressor` and pads the last one.
export struct _DigestBuffer {
    # The pending input: `size` of its 64 bytes.
    var block: u8[];
    var size: ulong;
    # The number of input bytes given since the last reset.
    var length: ulong;

    construct() {
        block = _digest_bytes(64);
    }

    reset() {
        size = 0;
        length = 0;
    }

    # Adds `count` bytes at `data`, compressing each block it completes.
    feed<T: _DigestCompressor>(hasher: T, data: __ptr<u8>, count: ulong) {
        length += count;
        ulong offset = 0;
        if (size > 0) {
            var take = 64 - size;
            if (take > count) {
                take = count;
            }
            _digest_copy(block._data + size, data, take);
            size += take;
            offset = take;
            if (size < 64) {
                return;
            }
            hasher._compress(block._data);
            size = 0;
        }
        while (count - offset >= 64) {
            hasher._compress(data + offset);
            offset += 64;
        }
        if (offset < count) {
            _digest_copy(block._data, data + offset, count - offset);
            size = count - offset;
        }
    }

    # Pads the input (0x80, zeros, then the bit length big-endian) and
    # compresses the last block or two.
    pad<T: _DigestCompressor>(hasher: T) {
        var data = block._data;
        data[size] = 0x80;
        _digest_zero(data + size + 1, 63 - size);
        if (size >= 56) {
            hasher._compress(data);
            _digest_zero(data, 56);
        }
        var bits = length * 8;
        ulong index = 0;
        while (index < 8) {
            data[56 + index] = (bits >> (56 - index * 8)) as u8;
            index += 1;
        }
        hasher._compress(data);
    }
}
