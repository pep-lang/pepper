## `Crc32` and `Adler32`: the checksums gzip and zlib streams carry, for
## checking data as it is read or written.

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
    # The 256-entry lookup table, one byte of input at a time.
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
    _update(data: __ptr<u8>, count: ulong) {
        var state = _state;
        __ptr<uint> table = _table._data;
        ulong index = 0;
        while (index < count) {
            state = table[((state ^ (data[index] as uint)) & 255) as ulong] ^ (state >> 8);
            index += 1;
        }
        _state = state;
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

# The table of the reflected polynomial 0xEDB88320.
_compress_crc_table(): uint[] {
    var table = Array<uint>(256);
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
    return table;
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
