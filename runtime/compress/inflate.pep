# The decompressor: a DEFLATE (RFC 1951) decoder with the zlib (RFC 1950)
# and gzip (RFC 1952) framing around it. It pulls input from an io.Reader as
# it needs it and decodes into one output array, which the streaming reader
# trims to the last 32 KiB (the most a back-reference can reach) as it hands
# bytes out.

import io;
import "checksum";
import "format";

# Where the decoder is in the stream.
const _INFLATE_STREAM_START = 0;
const _INFLATE_BLOCK_HEADER = 1;
const _INFLATE_STORED = 2;
const _INFLATE_CODES = 3;
const _INFLATE_STREAM_END = 4;
const _INFLATE_FINISHED = 5;

# Codes up to this many bits are decoded with one table lookup.
const _INFLATE_FAST_BITS: ulong = 10;

# A canonical Huffman code, for decoding.
export struct _HuffmanDecoder {
    # Indexed by the next `_INFLATE_FAST_BITS` bits of input (first bit
    # lowest): `symbol << 4 | length` for a code that short, 0 otherwise.
    var fast: uint[];
    # The number of codes of each length, 0 through 15.
    var counts: uint[];
    # The symbols in canonical order: by code length, then by symbol.
    var symbols: uint[];

    construct() {
        fast = Array<uint>(1024);
        counts = Array<uint>(16);
        symbols = Array<uint>();
    }

    # Builds the code from the lengths `lengths[start..start + count]`.
    # Returns false when the lengths describe more codes than fit
    # (over-subscribed); an incomplete code is accepted, and decoding one of
    # its unused codes fails.
    build(lengths: u8[], start: ulong, count: ulong): bool {
        counts.clear();
        var bits = 0;
        while (bits < 16) {
            counts.append(0);
            bits += 1;
        }
        ulong symbol = 0;
        while (symbol < count) {
            counts[lengths[start + symbol] as ulong] += 1;
            symbol += 1;
        }
        counts[0] = 0;
        long left = 1;
        ulong length = 1;
        while (length < 16) {
            left = left * 2 - (counts[length] as long);
            if (left < 0) {
                return false;
            }
            length += 1;
        }
        # Where each length's symbols start in `symbols`, and its first code.
        var offsets = Array<uint>(16);
        var next_code = Array<uint>(16);
        offsets.append(0);
        next_code.append(0);
        uint offset = 0;
        uint code = 0;
        length = 1;
        while (length < 16) {
            offsets.append(offset);
            offset += counts[length];
            code = (code + counts[length - 1]) << 1;
            next_code.append(code);
            length += 1;
        }
        symbols.clear();
        var index = 0;
        while (index < offset) {
            symbols.append(0);
            index += 1;
        }
        fast.clear();
        index = 0;
        while (index < 1024) {
            fast.append(0);
            index += 1;
        }
        symbol = 0;
        while (symbol < count) {
            var size = lengths[start + symbol] as ulong;
            if (size != 0) {
                symbols[offsets[size] as ulong] = symbol as uint;
                offsets[size] += 1;
                var assigned = next_code[size];
                next_code[size] = assigned + 1;
                if (size <= _INFLATE_FAST_BITS) {
                    var reversed = _compress_reverse_bits(assigned, size) as ulong;
                    var entry = ((symbol as uint) << 4) | (size as uint);
                    var step = (1 as ulong) << size;
                    while (reversed < 1024) {
                        fast[reversed] = entry;
                        reversed += step;
                    }
                }
            }
            symbol += 1;
        }
        return true;
    }
}

# Returns the low `count` bits of `code` in reverse order.
export _compress_reverse_bits(code: uint, count: ulong): uint {
    uint result = 0;
    ulong index = 0;
    while (index < count) {
        result = (result << 1) | ((code >> (index as uint)) & 1);
        index += 1;
    }
    return result;
}

# Decodes one compressed stream of a `Format`.
export struct _Inflater {
    var _format: Format;
    var _source: io.Reader;
    # Input read from `_source`, and the index of the next unused byte.
    var _input: u8[];
    var _position: ulong;
    var _source_ended: bool;
    # Bits taken from the input but not used yet, first bit lowest.
    var _bit_buffer: ulong;
    var _bit_count: ulong;

    var _state: int;
    var _final_block: bool;
    var _stored_left: ulong;
    var _literals: _HuffmanDecoder;
    var _distances: _HuffmanDecoder;
    var _code_lengths: _HuffmanDecoder;
    var _lengths: u8[];
    # The base value and extra bits of each length and distance code.
    var _length_base: uint[];
    var _length_extra: uint[];
    var _distance_base: uint[];
    var _distance_extra: uint[];

    # The decoded bytes: everything since the last `_compact`, at least the
    # last 32 KiB of output.
    var output: u8[];
    # The index in `output` of the first byte not handed out yet.
    var output_position: ulong;
    # The index in `output` of the first byte not checksummed yet.
    var _checked: ulong;
    var _crc: Crc32;
    var _adler: Adler32;
    # The bytes decoded in the current gzip member, modulo 2^32.
    var _member_size: uint;

    # The preset dictionary, when one was given (`set_dictionary`).
    var _dictionary: u8[];
    var _has_dictionary: bool;

    var failed: bool;
    var error: io.IoError;

    construct(source: io.Reader, format: Format) {
        _init(source, format);
    }

    # Gives the preset dictionary (RFC 1950 section 2.2) before decoding
    # starts: a zlib stream that asks for one gets it, and raw DEFLATE data
    # always starts with it in the window.
    set_dictionary(dictionary: u8[]) {
        _dictionary = dictionary;
        _has_dictionary = true;
    }

    # Puts the last 32 KiB of the dictionary in front of the output, already
    # handed out and checksummed, so back-references can reach it.
    _prime() {
        var start = _dictionary.count > 32768 ? _dictionary.count - 32768 : 0;
        output._append_raw(_dictionary._data + start, _dictionary.count - start);
        output_position = output.count;
        _checked = output.count;
    }

    # Decodes the array `data` directly, without a stream.
    construct(data: u8[], format: Format) {
        _init(io.ByteReader(Array<u8>()), format);
        _input = data;
        _source_ended = true;
    }

    _init(source: io.Reader, format: Format) {
        _format = format;
        _source = source;
        _input = Array<u8>();
        _literals = _HuffmanDecoder();
        _distances = _HuffmanDecoder();
        _code_lengths = _HuffmanDecoder();
        _lengths = Array<u8>(320);
        _length_base = [
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            13,
            15,
            17,
            19,
            23,
            27,
            31,
            35,
            43,
            51,
            59,
            67,
            83,
            99,
            115,
            131,
            163,
            195,
            227,
            258
        ];
        _length_extra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
        _distance_base = [
            1,
            2,
            3,
            4,
            5,
            7,
            9,
            13,
            17,
            25,
            33,
            49,
            65,
            97,
            129,
            193,
            257,
            385,
            513,
            769,
            1025,
            1537,
            2049,
            3073,
            4097,
            6145,
            8193,
            12289,
            16385,
            24577
        ];
        _distance_extra = [
            0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
        ];
        output = Array<u8>();
        _dictionary = Array<u8>();
        _crc = Crc32();
        _adler = Adler32();
        error = io.IoError();
        _state = _INFLATE_STREAM_START;
    }

    var finished: bool {
        get {
            return _state == _INFLATE_FINISHED;
        }
    }

    # The number of decoded bytes not handed out yet.
    var available: ulong {
        get {
            return output.count - output_position;
        }
    }

    # Records `message` as the error, as invalid data; returns false.
    _fail(message: String): bool {
        if (!failed) {
            failed = true;
            error = io.IoError(io._io_sys_code_invalid_input(), message);
        }
        return false;
    }

    # Reads more input from the source. Returns false at its end or on an
    # error (recorded).
    _refill(): bool {
        if (_source_ended) {
            return false;
        }
        _input.clear();
        _position = 0;
        var read = _source.read(_input, 65536);
        if (read.is_err()) {
            failed = true;
            error = read.error();
            _source_ended = true;
            return false;
        }
        if (read.value() == 0) {
            _source_ended = true;
            return false;
        }
        return true;
    }

    # Returns the next input byte, taking whole bytes left in the bit buffer
    # first; -1 at the end of the input (with no error recorded unless the
    # source failed).
    _byte(): long {
        if (_bit_count >= 8) {
            var value = (_bit_buffer & 255) as long;
            _bit_buffer = _bit_buffer >> 8;
            _bit_count -= 8;
            return value;
        }
        if (_position == _input.count && !_refill()) {
            return -1;
        }
        var value = _input[_position] as long;
        _position += 1;
        return value;
    }

    # Returns the next input byte; at the end of the input, fails.
    _require_byte(): long {
        var value = _byte();
        if (value < 0) {
            _fail("unexpected end of compressed data");
        }
        return value;
    }

    # Returns the next `count` bytes as a little-endian number; -1 when the
    # input ends.
    _little_endian(count: ulong): long {
        long value = 0;
        ulong index = 0;
        while (index < count) {
            var next = _require_byte();
            if (next < 0) {
                return -1;
            }
            value = value | (next << ((index * 8) as long));
            index += 1;
        }
        return value;
    }

    # Makes at least `count` bits (at most 32) available in the bit buffer.
    _need(count: ulong): bool {
        while (_bit_count < count) {
            if (_position == _input.count && !_refill()) {
                return _fail("unexpected end of compressed data");
            }
            _bit_buffer = _bit_buffer | ((_input[_position] as ulong) << _bit_count);
            _position += 1;
            _bit_count += 8;
        }
        return true;
    }

    # Takes the next `count` bits; -1 when the input ends.
    _take(count: ulong): long {
        if (!_need(count)) {
            return -1;
        }
        var value = (_bit_buffer & (((1 as ulong) << count) - 1)) as long;
        _bit_buffer = _bit_buffer >> count;
        _bit_count -= count;
        return value;
    }

    # Drops the bits up to the next byte boundary.
    _align() {
        var extra = _bit_count % 8;
        _bit_buffer = _bit_buffer >> extra;
        _bit_count -= extra;
    }

    # Decodes one symbol of `code`; -1 on bad or missing input.
    _decode(code: _HuffmanDecoder): long {
        # Fill the buffer for a table lookup, without failing at the end of
        # the input: the last code of a stream may be shorter.
        while (_bit_count < _INFLATE_FAST_BITS) {
            if (_position == _input.count && !_refill()) {
                break;
            }
            _bit_buffer = _bit_buffer | ((_input[_position] as ulong) << _bit_count);
            _position += 1;
            _bit_count += 8;
        }
        var entry = code.fast[(_bit_buffer & 1023) as ulong];
        var size = (entry & 15) as ulong;
        if (entry != 0 && size <= _bit_count) {
            _bit_buffer = _bit_buffer >> size;
            _bit_count -= size;
            return (entry >> 4) as long;
        }
        # A long code: walk the canonical code one bit at a time.
        long value = 0;
        long first = 0;
        long index = 0;
        ulong length = 1;
        while (length < 16) {
            var bit = _take(1);
            if (bit < 0) {
                return -1;
            }
            value = value | bit;
            var count = code.counts[length] as long;
            if (value - count < first) {
                return code.symbols[(index + (value - first)) as ulong] as long;
            }
            index += count;
            first = (first + count) << 1;
            value = value << 1;
            length += 1;
        }
        _fail("invalid Huffman code");
        return -1;
    }

    # Decodes until at least `want` bytes are available or the stream is
    # finished. Returns false on an error (in `error`).
    fill(want: ulong): bool {
        while (!failed && _state != _INFLATE_FINISHED && available < want) {
            if (_state == _INFLATE_STREAM_START) {
                _start_stream();
            } else if (_state == _INFLATE_BLOCK_HEADER) {
                _block_header();
            } else if (_state == _INFLATE_STORED) {
                _stored(want);
            } else if (_state == _INFLATE_CODES) {
                _codes(want);
            } else if (_state == _INFLATE_STREAM_END) {
                _end_stream();
            }
        }
        return !failed;
    }

    # Drops output that was handed out, keeping the last 32 KiB of it for
    # back-references.
    compact() {
        if (output_position < 98304) {
            return;
        }
        _checksum();
        var drop = output_position - 32768;
        var kept = Array<u8>(output.count - drop + 65536);
        kept._append_raw(output._data + drop, output.count - drop);
        output = kept;
        output_position -= drop;
        _checked -= drop;
    }

    # Adds the output not checksummed yet to the stream's checksum.
    _checksum() {
        var count = output.count - _checked;
        if (count == 0) {
            return;
        }
        if (_format == Format.Gzip) {
            _crc._update(output._data + _checked, count);
            _member_size += count as uint;
        } else if (_format == Format.Zlib) {
            _adler._update(output._data + _checked, count);
        }
        _checked = output.count;
    }

    # Reads the zlib or gzip header, if the format has one.
    _start_stream() {
        if (_format == Format.Zlib) {
            var method = _require_byte();
            var flags = _require_byte();
            if (flags < 0) {
                return;
            }
            if ((method & 15) != 8 || (method >> 4) > 7) {
                _fail("not zlib data: unknown compression method");
                return;
            }
            if ((method * 256 + flags) % 31 != 0) {
                _fail("not zlib data: bad header check");
                return;
            }
            if ((flags & 32) != 0) {
                # The dictionary's Adler-32, most significant byte first.
                long id = 0;
                var index = 0;
                while (index < 4) {
                    var next = _require_byte();
                    if (next < 0) {
                        return;
                    }
                    id = (id << 8) | next;
                    index += 1;
                }
                if (!_has_dictionary) {
                    _fail("zlib data needs a preset dictionary; pass it to decompress");
                    return;
                }
                if ((id as uint) != Adler32.of(_dictionary)) {
                    _fail("zlib data needs a different preset dictionary");
                    return;
                }
                _prime();
            }
        } else if (_format == Format.Gzip) {
            if (!_gzip_header()) {
                return;
            }
        } else if (_has_dictionary) {
            _prime();
        }
        _state = _INFLATE_BLOCK_HEADER;
    }

    # Reads a gzip member header (RFC 1952 section 2.3).
    _gzip_header(): bool {
        var first = _require_byte();
        if (first < 0) {
            return false;
        }
        if (first != 31 || _require_byte() != 139) {
            return _fail("not gzip data: bad magic number");
        }
        if (_require_byte() != 8) {
            return _fail("not gzip data: unknown compression method");
        }
        var flags = _require_byte();
        if (flags < 0) {
            return false;
        }
        if ((flags & 224) != 0) {
            return _fail("not gzip data: reserved flags set");
        }
        # The modification time, extra flags and operating system.
        if (_little_endian(6) < 0) {
            return false;
        }
        if ((flags & 4) != 0) {
            var extra = _little_endian(2);
            if (extra < 0) {
                return false;
            }
            while (extra > 0) {
                if (_require_byte() < 0) {
                    return false;
                }
                extra -= 1;
            }
        }
        # The file name, then the comment: each ends with a zero byte.
        var field = 8;
        while (field <= 16) {
            if ((flags & field) != 0) {
                while (true) {
                    var value = _require_byte();
                    if (value < 0) {
                        return false;
                    }
                    if (value == 0) {
                        break;
                    }
                }
            }
            field += 8;
        }
        if ((flags & 2) != 0 && _little_endian(2) < 0) {
            return false;
        }
        _crc.reset();
        _member_size = 0;
        return true;
    }

    # Reads the trailer after the last block, then any further gzip member.
    _end_stream() {
        _align();
        _checksum();
        if (_format == Format.Zlib) {
            long value = 0;
            var index = 0;
            while (index < 4) {
                var next = _require_byte();
                if (next < 0) {
                    return;
                }
                value = (value << 8) | next;
                index += 1;
            }
            if ((value as uint) != _adler.value) {
                _fail("zlib data is corrupt: Adler-32 checksum mismatch");
                return;
            }
        } else if (_format == Format.Gzip) {
            var crc = _little_endian(4);
            var size = _little_endian(4);
            if (size < 0) {
                return;
            }
            if ((crc as uint) != _crc.value) {
                _fail("gzip data is corrupt: CRC-32 mismatch");
                return;
            }
            if ((size as uint) != _member_size) {
                _fail("gzip data is corrupt: length mismatch");
                return;
            }
            # Another member may follow (as `cat a.gz b.gz` makes).
            var next = _byte();
            if (next >= 0) {
                _bit_buffer = (next as ulong) | (_bit_buffer << 8);
                _bit_count += 8;
                if (!_gzip_header()) {
                    return;
                }
                _state = _INFLATE_BLOCK_HEADER;
                return;
            }
            if (failed) {
                return;
            }
        }
        _state = _INFLATE_FINISHED;
    }

    # Reads a block header (RFC 1951 section 3.2.3) and the codes of a
    # compressed block.
    _block_header() {
        var header = _take(3);
        if (header < 0) {
            return;
        }
        _final_block = (header & 1) != 0;
        var kind = header >> 1;
        if (kind == 0) {
            _align();
            var length = _little_endian(2);
            var check = _little_endian(2);
            if (check < 0) {
                return;
            }
            if ((length ^ 65535) != check) {
                _fail("invalid stored block length");
                return;
            }
            _stored_left = length as ulong;
            _state = _INFLATE_STORED;
        } else if (kind == 1) {
            _fixed_codes();
            _state = _INFLATE_CODES;
        } else if (kind == 2) {
            if (_dynamic_codes()) {
                _state = _INFLATE_CODES;
            }
        } else {
            _fail("invalid block type");
        }
    }

    # The state after a block ends.
    _block_done() {
        if (_final_block) {
            _state = _INFLATE_STREAM_END;
        } else {
            _state = _INFLATE_BLOCK_HEADER;
        }
    }

    # Sets up the fixed codes of block type 1 (RFC 1951 section 3.2.6).
    _fixed_codes() {
        _lengths.clear();
        var symbol = 0;
        while (symbol < 288) {
            if (symbol < 144) {
                _lengths.append(8);
            } else if (symbol < 256) {
                _lengths.append(9);
            } else if (symbol < 280) {
                _lengths.append(7);
            } else {
                _lengths.append(8);
            }
            symbol += 1;
        }
        _literals.build(_lengths, 0, 288);
        _lengths.clear();
        symbol = 0;
        while (symbol < 30) {
            _lengths.append(5);
            symbol += 1;
        }
        _distances.build(_lengths, 0, 30);
    }

    # Reads the code descriptions of a dynamic block (RFC 1951 section
    # 3.2.7).
    _dynamic_codes(): bool {
        var literal_count = _take(5);
        var distance_count = _take(5);
        var length_count = _take(4);
        if (length_count < 0) {
            return false;
        }
        var literals = (literal_count + 257) as ulong;
        var distances = (distance_count + 1) as ulong;
        if (literals > 286 || distances > 30) {
            return _fail("too many length or distance codes");
        }
        var order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
        _lengths.clear();
        var index = 0;
        while (index < 19) {
            _lengths.append(0);
            index += 1;
        }
        index = 0;
        while (index < (length_count + 4) as int) {
            var size = _take(3);
            if (size < 0) {
                return false;
            }
            _lengths[order[index] as ulong] = size as u8;
            index += 1;
        }
        if (!_code_lengths.build(_lengths, 0, 19)) {
            return _fail("invalid code lengths code");
        }
        _lengths.clear();
        var total = literals + distances;
        while (_lengths.count < total) {
            var symbol = _decode(_code_lengths);
            if (symbol < 0) {
                return false;
            }
            if (symbol < 16) {
                _lengths.append(symbol as u8);
                continue;
            }
            u8 repeated = 0;
            long times = 0;
            if (symbol == 16) {
                if (_lengths.is_empty) {
                    return _fail("repeated code length with no previous length");
                }
                repeated = _lengths.last();
                times = 3 + _take(2);
            } else if (symbol == 17) {
                times = 3 + _take(3);
            } else {
                times = 11 + _take(7);
            }
            if (failed) {
                return false;
            }
            if (_lengths.count + (times as ulong) > total) {
                return _fail("too many code lengths");
            }
            while (times > 0) {
                _lengths.append(repeated);
                times -= 1;
            }
        }
        if (_lengths[256] == 0) {
            return _fail("missing end-of-block code");
        }
        if (!_literals.build(_lengths, 0, literals)) {
            return _fail("invalid literal/length code lengths");
        }
        if (!_distances.build(_lengths, literals, distances)) {
            return _fail("invalid distance code lengths");
        }
        return true;
    }

    # Copies stored bytes until the block ends or `want` bytes are
    # available.
    _stored(want: ulong) {
        while (_stored_left > 0 && available < want) {
            if (_bit_count >= 8) {
                output.append(_byte() as u8);
                _stored_left -= 1;
                continue;
            }
            if (_position == _input.count && !_refill()) {
                _fail("unexpected end of compressed data");
                return;
            }
            var count = _input.count - _position;
            if (count > _stored_left) {
                count = _stored_left;
            }
            output._append_raw(_input._data + _position, count);
            _position += count;
            _stored_left -= count;
        }
        if (_stored_left == 0) {
            _block_done();
        }
    }

    # Decodes symbols until the block ends or `want` bytes are available.
    _codes(want: ulong) {
        while (available < want) {
            if (_codes_fast(want)) {
                return;
            }
            if (available >= want) {
                return;
            }
            var symbol = _decode(_literals);
            if (symbol < 0) {
                return;
            }
            if (symbol < 256) {
                output.append(symbol as u8);
                continue;
            }
            if (symbol == 256) {
                _block_done();
                return;
            }
            var code = (symbol - 257) as ulong;
            if (code >= 29) {
                _fail("invalid length code");
                return;
            }
            var length = _length_base[code] as ulong;
            var extra = _length_extra[code] as ulong;
            if (extra > 0) {
                var bits = _take(extra);
                if (bits < 0) {
                    return;
                }
                length += bits as ulong;
            }
            var distance_code = _decode(_distances);
            if (distance_code < 0) {
                return;
            }
            if (distance_code >= 30) {
                _fail("invalid distance code");
                return;
            }
            var distance = _distance_base[distance_code as ulong] as ulong;
            extra = _distance_extra[distance_code as ulong] as ulong;
            if (extra > 0) {
                var bits = _take(extra);
                if (bits < 0) {
                    return;
                }
                distance += bits as ulong;
            }
            if (distance > output.count) {
                _fail("invalid distance: before the start of the data");
                return;
            }
            _compress_copy_match(output, distance, length);
        }
    }

    # Decodes symbols the fast way (as zlib's `inflate_fast` does) while at
    # least 8 bytes of input are left: one 8-byte refill of the bit buffer
    # covers a whole length/distance pair, and the output has room for the
    # longest match plus 8 bytes, so no symbol checks for the end of either.
    # Returns true when the block ended or decoding failed; false when the
    # slow path must take over (near the end of the input, or once `want`
    # bytes are available).
    _codes_fast(want: ulong): bool {
        var input_count = _input.count;
        if (_position + 8 > input_count) {
            return false;
        }
        __ptr<u8> input = _input._data;
        var position = _position;
        var bits = _bit_buffer;
        var count = _bit_count;
        var out_count = output.count;
        var capacity = output.capacity;
        __ptr<u8> out = output._data;
        var first = output_position;
        __ptr<uint> literal_fast = _literals.fast._data;
        __ptr<uint> distance_fast = _distances.fast._data;
        __ptr<uint> length_base = _length_base._data;
        __ptr<uint> length_extra = _length_extra._data;
        __ptr<uint> distance_base = _distance_base._data;
        __ptr<uint> distance_extra = _distance_extra._data;
        var stop = false;
        while (position + 8 <= input_count && out_count - first < want) {
            if (out_count + 266 > capacity) {
                output._size = out_count;
                var next = capacity * 2;
                if (next < out_count + 65536) {
                    next = out_count + 65536;
                }
                output.reserve(next);
                out = output._data;
                capacity = output.capacity;
            }
            # Refill to at least 56 bits. The bits loaded past `count` are
            # the stream's next bits, so loading them again later is
            # harmless.
            bits = bits | (_compress_load_64(input, position) << count);
            position += (63 - count) >> 3;
            count = count | 56;

            var entry = literal_fast[bits & 1023];
            if (entry == 0) {
                entry = _inflate_decode_long(_literals, bits);
                if (entry == 0) {
                    _fail("invalid Huffman code");
                    stop = true;
                    break;
                }
            }
            var size = (entry & 15) as ulong;
            bits = bits >> size;
            count -= size;
            var symbol = (entry >> 4) as ulong;
            if (symbol < 256) {
                out[out_count] = symbol as u8;
                out_count += 1;
                continue;
            }
            if (symbol == 256) {
                _block_done();
                stop = true;
                break;
            }
            var code = symbol - 257;
            if (code >= 29) {
                _fail("invalid length code");
                stop = true;
                break;
            }
            var extra = length_extra[code] as ulong;
            var length = (length_base[code] as ulong) + (bits & (((1 as ulong) << extra) - 1));
            bits = bits >> extra;
            count -= extra;

            entry = distance_fast[bits & 1023];
            if (entry == 0) {
                entry = _inflate_decode_long(_distances, bits);
                if (entry == 0) {
                    _fail("invalid Huffman code");
                    stop = true;
                    break;
                }
            }
            size = (entry & 15) as ulong;
            bits = bits >> size;
            count -= size;
            var distance_code = (entry >> 4) as ulong;
            if (distance_code >= 30) {
                _fail("invalid distance code");
                stop = true;
                break;
            }
            extra = distance_extra[distance_code] as ulong;
            var distance = (distance_base[distance_code] as ulong) + (bits & (((1 as ulong) << extra) - 1));
            bits = bits >> extra;
            count -= extra;
            if (distance > out_count) {
                _fail("invalid distance: before the start of the data");
                stop = true;
                break;
            }
            var from = out_count - distance;
            if (distance >= 8) {
                # Eight bytes at a time; each load reads only bytes already
                # written, and the copy may run up to 7 bytes past the match.
                ulong index = 0;
                while (index < length) {
                    _compress_store_64(out, out_count + index, _compress_load_64(out, from + index));
                    index += 8;
                }
            } else {
                ulong index = 0;
                while (index < length) {
                    out[out_count + index] = out[from + index];
                    index += 1;
                }
            }
            out_count += length;
        }
        output._size = out_count;
        output._version += 1;
        # Keep only the bits counted, so the slow path sees a clean buffer.
        _bit_buffer = bits & (((1 as ulong) << count) - 1);
        _bit_count = count;
        _position = position;
        return stop;
    }
}

# Decodes a code longer than the fast table covers from the low bits of
# `bits` (which holds at least 15), walking the canonical code one bit at a
# time. Returns `symbol << 4 | length` as the fast table does, or 0 for a
# code the decoder does not have.
_inflate_decode_long(code: _HuffmanDecoder, bits: ulong): uint {
    __ptr<uint> counts = code.counts._data;
    ulong value = 0;
    ulong first = 0;
    ulong index = 0;
    ulong length = 1;
    while (length < 16) {
        value = value | ((bits >> (length - 1)) & 1);
        var count = counts[length] as ulong;
        if (value < first + count) {
            return (code.symbols[index + (value - first)] << 4) | (length as uint);
        }
        index += count;
        first = (first + count) << 1;
        value = value << 1;
        length += 1;
    }
    return 0;
}

# Appends `length` bytes to `output`, copied from `distance` bytes back; the
# two ranges may overlap, which repeats the bytes in between.
export _compress_copy_match(output: u8[], distance: ulong, length: ulong) {
    var at = output.count;
    if (at + length > output.capacity) {
        var next = output.capacity * 2;
        if (next < at + length) {
            next = at + length;
        }
        output.reserve(next);
    }
    __ptr<u8> data = output._data;
    var from = at - distance;
    ulong index = 0;
    while (index < length) {
        data[at + index] = data[from + index];
        index += 1;
    }
    output._size = at + length;
    output._version += 1;
}
