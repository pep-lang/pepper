## `Crc32` and `Adler32`: the checksums gzip and zlib streams carry, for
## checking data as it is read or written.

import "zlib";

## The CRC-32 checksum (IEEE 802.3, the polynomial gzip, zip and PNG use),
## computed over data given in one or more pieces.
##
## @example
##     import compress;
##
##     var crc = compress.Crc32();
##     crc.update("hello ".bytes());
##     crc.update("world".bytes());
##     assert(crc.value == compress.Crc32.of("hello world".bytes()), "same in pieces");
##     assert(compress.Crc32.of("123456789".bytes()) == 0xCBF43926, "the check value");
export struct Crc32 {
    # Eight 256-entry lookup tables, for eight bytes of input at a time
    # ("slicing-by-8"): table `k` holds the remainder of each byte followed
    # by `k` zero bytes.
    var _table: uint[];
    # The running remainder, inverted.
    var _state: uint;

    ## Makes a checksum of no data yet (`value` is 0).
    construct() {
        _table = _compress_crc_table();
        _state = 0xFFFFFFFF;
    }

    ## The checksum of everything given to `update` so far.
    var value: uint {
        get {
            return _state ^ 0xFFFFFFFF;
        }
    }

    ## Adds `data` to the checksum.
    ##
    ## @param data the next bytes of the data
    update(data: u8[]) {
        _update(data._data, data.count);
    }

    # Adds the `count` bytes at `data`.
    [Target(!BuildOption(USE_ZLIB))]
    _update(data: __ptr<u8>, count: ulong) {
        var state = _state;
        __ptr<uint> table = _table._data;
        ulong index = 0;
        while (index + 8 <= count) {
            var word = _compress_load_64(data, index) ^ (state as ulong);
            state = table[1792 + (word & 255)]
                ^ table[1536 + ((word >> 8) & 255)]
                ^ table[1280 + ((word >> 16) & 255)]
                ^ table[1024 + ((word >> 24) & 255)]
                ^ table[768 + ((word >> 32) & 255)]
                ^ table[512 + ((word >> 40) & 255)]
                ^ table[256 + ((word >> 48) & 255)]
                ^ table[word >> 56];
            index += 8;
        }
        while (index < count) {
            state = table[((state ^ (data[index] as uint)) & 255) as ulong] ^ (state >> 8);
            index += 1;
        }
        _state = state;
    }

    # Adds the `count` bytes at `data`, with zlib.
    [BuildOption("USE_ZLIB")]
    _update(data: __ptr<u8>, count: ulong) {
        _state = _compress_zlib_crc32(_state ^ 0xFFFFFFFF, data, count) ^ 0xFFFFFFFF;
    }

    ## Starts over, as if no data had been given.
    reset() {
        _state = 0xFFFFFFFF;
    }

    ## Returns the CRC-32 of `data`.
    ##
    ## @param data the bytes to check
    ## @returns the checksum
    static of(data: u8[]): uint {
        var crc = Crc32();
        crc.update(data);
        return crc.value;
    }
}

# The slicing-by-8 tables of the reflected polynomial 0xEDB88320: table 0
# is the classic byte-at-a-time table, and table `k` entry `n` is
# `table[k - 1][n]` advanced by one more zero byte.
[Target(!BuildOption(USE_ZLIB))]
_compress_crc_table(): uint[] {
    var table = Array<uint>(2048);
    uint n = 0;
    while (n < 256) {
        var c = n;
        var k = 0;
        while (k < 8) {
            if ((c & 1) != 0) {
                c = 0xEDB88320 ^ (c >> 1);
            } else {
                c = c >> 1;
            }
            k += 1;
        }
        table.append(c);
        n += 1;
    }
    ulong index = 256;
    while (index < 2048) {
        var previous = table[index - 256];
        table.append(table[(previous & 255) as ulong] ^ (previous >> 8));
        index += 1;
    }
    return table;
}

# zlib has its own tables.
[BuildOption("USE_ZLIB")]
_compress_crc_table(): uint[] {
    return Array<uint>();
}

# The eight bytes at `data + at` as a little-endian number. LLVM turns the
# byte loads into one unaligned load.
export _compress_load_64(data: __ptr<u8>, at: ulong): ulong {
    __ptr<u8> bytes = data + at;
    var low = (bytes[0] as uint) | ((bytes[1] as uint) << 8) | ((bytes[2] as uint) << 16) | ((bytes[3] as uint) << 24);
    var high = (bytes[4] as uint) | ((bytes[5] as uint) << 8) | ((bytes[6] as uint) << 16) | ((bytes[7] as uint) << 24);
    return (low as ulong) | ((high as ulong) << 32);
}

# Stores `value` as the eight little-endian bytes at `data + at`.
export _compress_store_64(data: __ptr<u8>, at: ulong, value: ulong) {
    __ptr<u8> bytes = data + at;
    bytes[0] = (value & 255) as u8;
    bytes[1] = ((value >> 8) & 255) as u8;
    bytes[2] = ((value >> 16) & 255) as u8;
    bytes[3] = ((value >> 24) & 255) as u8;
    bytes[4] = ((value >> 32) & 255) as u8;
    bytes[5] = ((value >> 40) & 255) as u8;
    bytes[6] = ((value >> 48) & 255) as u8;
    bytes[7] = (value >> 56) as u8;
}

## The Adler-32 checksum (RFC 1950, the one zlib streams carry), computed
## over data given in one or more pieces.
##
## @example
##     import compress;
##
##     assert(compress.Adler32.of("Wikipedia".bytes()) == 0x11E60398, "the example");
export struct Adler32 {
    # The two running sums.
    var _a: uint;
    var _b: uint;

    ## Makes a checksum of no data yet (`value` is 1).
    construct() {
        _a = 1;
        _b = 0;
    }

    ## The checksum of everything given to `update` so far.
    var value: uint {
        get {
            return (_b << 16) | _a;
        }
    }

    ## Adds `data` to the checksum.
    ##
    ## @param data the next bytes of the data
    update(data: u8[]) {
        _update(data._data, data.count);
    }

    # Adds the `count` bytes at `data`.
    [Target(!BuildOption(USE_ZLIB))]
    _update(data: __ptr<u8>, count: ulong) {
        var a = _a;
        var b = _b;
        ulong index = 0;
        while (index < count) {
            # 5552 bytes is the most that cannot overflow before the modulo.
            var end = index + 5552;
            if (end > count) {
                end = count;
            }
            while (index < end) {
                a += data[index] as uint;
                b += a;
                index += 1;
            }
            a = a % 65521;
            b = b % 65521;
        }
        _a = a;
        _b = b;
    }

    # Adds the `count` bytes at `data`, with zlib.
    [BuildOption("USE_ZLIB")]
    _update(data: __ptr<u8>, count: ulong) {
        var adler = _compress_zlib_adler32((_b << 16) | _a, data, count);
        _a = adler & 0xFFFF;
        _b = adler >> 16;
    }

    ## Starts over, as if no data had been given.
    reset() {
        _a = 1;
        _b = 0;
    }

    ## Returns the Adler-32 of `data`.
    ##
    ## @param data the bytes to check
    ## @returns the checksum
    static of(data: u8[]): uint {
        var adler = Adler32();
        adler.update(data);
        return adler.value;
    }
}
