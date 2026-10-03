# The compressor and decompressor of a build that defines `USE_ZLIB`: zlib
# itself in place of deflate.pep and inflate.pep, which format.pep and
# module.pep then do not import. `_Deflater` and `_Inflater` here have the
# members format.pep uses from the portable ones, and report corrupt data
# with the same messages where zlib tells the cause apart.
#
# Every declaration here carries `BuildOption(USE_ZLIB)`, so a build without
# it links no zlib. The library is `-lz` on Linux and macOS and `zlib.lib`
# (as vcpkg and zlib's CMake build name it) on Windows.

import io;
import "format";

# zlib's `uLong`: 64 bits on Linux and macOS, 32 on Windows.
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
type _ZlibLong = ulong;
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
type _ZlibLong = uint;

[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern int deflateInit2_(
    void* stream, int level, int method, int window_bits, int memory_level, int strategy, char* version, int stream_size
);
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern int deflate(void* stream, int flush);
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern int deflateEnd(void* stream);
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern int inflateInit2_(void* stream, int window_bits, char* version, int stream_size);
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern int inflate(void* stream, int flush);
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern int inflateReset(void* stream);
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern int inflateEnd(void* stream);
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern _ZlibLong crc32_z(_ZlibLong crc, u8* data, ulong size);
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
[Link("z")]
extern _ZlibLong adler32_z(_ZlibLong adler, u8* data, ulong size);

[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern int deflateInit2_(
    void* stream, int level, int method, int window_bits, int memory_level, int strategy, char* version, int stream_size
);
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern int deflate(void* stream, int flush);
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern int deflateEnd(void* stream);
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern int inflateInit2_(void* stream, int window_bits, char* version, int stream_size);
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern int inflate(void* stream, int flush);
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern int inflateReset(void* stream);
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern int inflateEnd(void* stream);
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern _ZlibLong crc32_z(_ZlibLong crc, u8* data, ulong size);
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
[Link("zlib")]
extern _ZlibLong adler32_z(_ZlibLong adler, u8* data, ulong size);

# Continues the CRC-32 `crc` over the `count` bytes at `data`.
[BuildOption("USE_ZLIB")]
export _compress_zlib_crc32(crc: uint, data: __ptr<u8>, count: ulong): uint {
    return crc32_z(crc as _ZlibLong, data, count) as uint;
}

# Continues the Adler-32 `adler` over the `count` bytes at `data`.
[BuildOption("USE_ZLIB")]
export _compress_zlib_adler32(adler: uint, data: __ptr<u8>, count: ulong): uint {
    return adler32_z(adler as _ZlibLong, data, count) as uint;
}

# Return codes and flush values (zlib.h).
[BuildOption("USE_ZLIB")]
const _ZLIB_OK = 0;
[BuildOption("USE_ZLIB")]
const _ZLIB_STREAM_END = 1;
[BuildOption("USE_ZLIB")]
const _ZLIB_NEED_DICT = 2;
[BuildOption("USE_ZLIB")]
const _ZLIB_BUF_ERROR = -5;
[BuildOption("USE_ZLIB")]
const _ZLIB_NO_FLUSH = 0;
[BuildOption("USE_ZLIB")]
const _ZLIB_FINISH = 4;

# The `z_stream` fields used here, as byte offsets: `next_in` @0,
# `avail_in` @8, then `next_out`, `avail_out` and `msg`, which move up on
# Windows, where `total_in` (a `uLong`) is 4 bytes. `zalloc`, `zfree` and
# `opaque` stay zero, for zlib's own malloc and free.
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
const _ZLIB_STREAM_SIZE: ulong = 112;
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
const _ZLIB_NEXT_OUT: ulong = 24;
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
const _ZLIB_AVAIL_OUT: ulong = 32;
[Target(BuildOption(USE_ZLIB) && !OS(Windows))]
const _ZLIB_MESSAGE: ulong = 48;
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
const _ZLIB_STREAM_SIZE: ulong = 88;
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
const _ZLIB_NEXT_OUT: ulong = 16;
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
const _ZLIB_AVAIL_OUT: ulong = 24;
[Target(BuildOption(USE_ZLIB) && OS(Windows))]
const _ZLIB_MESSAGE: ulong = 32;

# zlib checks only the first character of the version it was built for.
[BuildOption("USE_ZLIB")]
const _ZLIB_VERSION = "1";

# The `windowBits` that selects `format`'s framing, with a 32 KiB window.
[BuildOption("USE_ZLIB")]
_zlib_window_bits(format: Format): int {
    if (format == Format.Raw) {
        return -15;
    }
    if (format == Format.Gzip) {
        return 31;
    }
    return 15;
}

# A zeroed `z_stream`, ended with `end` and freed when the handle is.
[BuildOption("USE_ZLIB")]
_zlib_stream(end: extern (__ptr<void>) => int): Handle<__ptr<void>> {
    __ptr<u8> bytes = _pep_malloc(_ZLIB_STREAM_SIZE);
    ulong index = 0;
    while (index < _ZLIB_STREAM_SIZE) {
        bytes[index] = 0;
        index += 1;
    }
    return Handle<__ptr<void>>(bytes as __ptr<void>, (stream) => {
        end(stream);
        _pep_free(stream);
    });
}

# Points the stream's input at `size` bytes at `data`.
[BuildOption("USE_ZLIB")]
_zlib_set_input(stream: __ptr<void>, data: __ptr<u8>, size: uint) {
    unsafe_cast<__ptr<__ptr<u8>>>(stream)[0] = data;
    unsafe_cast<__ptr<uint>>((stream as __ptr<u8>) + 8)[0] = size;
}

# The input bytes the stream has not consumed.
[BuildOption("USE_ZLIB")]
_zlib_input_left(stream: __ptr<void>): uint {
    return unsafe_cast<__ptr<uint>>((stream as __ptr<u8>) + 8)[0];
}

# Points the stream's output at the room after `output`'s elements, making
# at least `room` bytes of it.
[BuildOption("USE_ZLIB")]
_zlib_set_output(stream: __ptr<void>, output: u8[], room: ulong) {
    output._reserve_extra(room);
    var bytes = stream as __ptr<u8>;
    unsafe_cast<__ptr<__ptr<u8>>>(bytes + _ZLIB_NEXT_OUT)[0] = output._data + output._size;
    unsafe_cast<__ptr<uint>>(bytes + _ZLIB_AVAIL_OUT)[0] = room as uint;
}

# Counts the bytes zlib wrote into `output` after `_zlib_set_output` made
# `room` bytes of room.
[BuildOption("USE_ZLIB")]
_zlib_take_output(stream: __ptr<void>, output: u8[], room: ulong) {
    var left = unsafe_cast<__ptr<uint>>((stream as __ptr<u8>) + _ZLIB_AVAIL_OUT)[0] as ulong;
    output._version += 1;
    output._size += room - left;
}

# zlib's message for the last error, or "" when it gave none.
[BuildOption("USE_ZLIB")]
_zlib_message(stream: __ptr<void>): String {
    var message = unsafe_cast<__ptr<__ptr<char>>>((stream as __ptr<u8>) + _ZLIB_MESSAGE)[0];
    if (message == __null) {
        return "";
    }
    return String(message);
}

# Output room made per call to deflate or inflate.
[BuildOption("USE_ZLIB")]
const _ZLIB_CHUNK: ulong = 65536;

[BuildOption("USE_ZLIB")]
export struct _Deflater {
    var _stream: Handle<__ptr<void>>;
    # The compressed bytes made so far; the caller takes them.
    var output: u8[];

    construct(format: Format, level: int) {
        _stream = _zlib_stream(deflateEnd);
        output = Array<u8>();
        var status = deflateInit2_(
            _stream.value, level, 8, _zlib_window_bits(format), 8, 0, _ZLIB_VERSION.c_str(), _ZLIB_STREAM_SIZE as int
        );
        assert(status == _ZLIB_OK, "zlib could not start compressing");
    }

    # Adds `data` to the stream, writing whatever blocks it completes.
    write(data: u8[]) {
        ulong done = 0;
        while (done < data.count) {
            var count = data.count - done;
            if (count > 0x40000000) {
                count = 0x40000000;
            }
            _run(data._data + done, count as uint, _ZLIB_NO_FLUSH);
            done += count;
        }
    }

    # Writes the rest of the stream and its trailer.
    finish() {
        _run(__null, 0, _ZLIB_FINISH);
    }

    # Runs deflate over `size` bytes at `data` until it has consumed them
    # all and, with `_ZLIB_FINISH`, ended the stream.
    _run(data: __ptr<u8>, size: uint, flush: int) {
        var stream = _stream.value;
        _zlib_set_input(stream, data, size);
        while (true) {
            _zlib_set_output(stream, output, _ZLIB_CHUNK);
            var status = deflate(stream, flush);
            _zlib_take_output(stream, output, _ZLIB_CHUNK);
            if (status == _ZLIB_STREAM_END) {
                return;
            }
            assert(status == _ZLIB_OK || status == _ZLIB_BUF_ERROR, "zlib failed while compressing");
            if (flush != _ZLIB_FINISH && _zlib_input_left(stream) == 0) {
                return;
            }
        }
    }
}

[BuildOption("USE_ZLIB")]
export struct _Inflater {
    var _format: Format;
    var _source: io.Reader;
    var _stream: Handle<__ptr<void>>;
    # The input not consumed yet: `_input` from `_position`.
    var _input: u8[];
    var _position: ulong;
    var _source_ended: bool;
    var _finished: bool;
    # The decoded bytes; the reader hands them out from `output_position`.
    var output: u8[];
    var output_position: ulong;

    var failed: bool;
    var error: io.IoError;

    construct(source: io.Reader, format: Format) {
        _init(source, format);
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
        output = Array<u8>();
        error = io.IoError();
        _stream = _zlib_stream(inflateEnd);
        var status = inflateInit2_(
            _stream.value, _zlib_window_bits(format), _ZLIB_VERSION.c_str(), _ZLIB_STREAM_SIZE as int
        );
        assert(status == _ZLIB_OK, "zlib could not start decompressing");
    }

    var finished: bool {
        get {
            return _finished;
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

    # Reads more input from the source when all of it was consumed. Returns
    # false at its end or on an error (recorded).
    _refill(): bool {
        if (_position < _input.count) {
            return true;
        }
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

    # Decodes until at least `want` bytes are available or the stream is
    # finished. Returns false on an error (in `error`).
    fill(want: ulong): bool {
        var stream = _stream.value;
        while (!failed && !_finished && available < want) {
            if (!_refill()) {
                if (!failed) {
                    _fail("unexpected end of compressed data");
                }
                return false;
            }
            var size = _input.count - _position;
            if (size > 0x40000000) {
                size = 0x40000000;
            }
            _zlib_set_input(stream, _input._data + _position, size as uint);
            # Room for what is wanted, but growing the output at most
            # twofold a call, since a one-shot decompression wants it all.
            var room = want - available;
            if (room > output.count) {
                room = output.count;
            }
            if (room < _ZLIB_CHUNK) {
                room = _ZLIB_CHUNK;
            }
            if (room > 0x40000000) {
                room = 0x40000000;
            }
            _zlib_set_output(stream, output, room);
            var status = inflate(stream, _ZLIB_NO_FLUSH);
            _zlib_take_output(stream, output, room);
            _position += size - (_zlib_input_left(stream) as ulong);
            if (status == _ZLIB_STREAM_END) {
                _end_member();
            } else if (status == _ZLIB_NEED_DICT) {
                _fail("zlib data needs a preset dictionary, which is not supported");
            } else if (status != _ZLIB_OK && status != _ZLIB_BUF_ERROR) {
                _fail(_describe(_zlib_message(stream)));
            }
        }
        return !failed;
    }

    # After a stream ends: for gzip, starts the next member when more input
    # follows (as `cat a.gz b.gz` makes) and rejects anything else after it.
    _end_member() {
        if (_format != Format.Gzip) {
            _finished = true;
            return;
        }
        if (!_refill()) {
            _finished = !failed;
            return;
        }
        # The next member's magic number, which may straddle a refill.
        var first = _input[_position];
        _position += 1;
        if (!_refill() || first != 31 || _input[_position] != 139) {
            _fail("not gzip data: bad magic number");
            return;
        }
        inflateReset(_stream.value);
        # Give the first byte back to zlib with the rest of the header.
        var header = Array<u8>(1);
        header.append(first);
        _zlib_set_input(_stream.value, header._data, 1);
        _zlib_set_output(_stream.value, output, 1);
        inflate(_stream.value, _ZLIB_NO_FLUSH);
        _zlib_take_output(_stream.value, output, 1);
    }

    # zlib's message for corrupt data in the portable decoder's words where
    # they differ.
    _describe(message: String): String {
        if (message == "incorrect data check") {
            if (_format == Format.Gzip) {
                return "gzip data is corrupt: CRC-32 mismatch";
            }
            return "zlib data is corrupt: Adler-32 checksum mismatch";
        }
        if (message == "incorrect length check") {
            return "gzip data is corrupt: length mismatch";
        }
        if (message == "incorrect header check" || message == "unknown compression method") {
            if (_format == Format.Gzip) {
                return "not gzip data: " + message;
            }
            return "not zlib data: " + message;
        }
        if (message == "invalid stored block lengths") {
            return "invalid stored block length";
        }
        if (message.is_empty) {
            return "invalid compressed data";
        }
        return message;
    }

    # Drops output that was handed out. zlib keeps its own window, so
    # nothing else needs to stay.
    compact() {
        if (output_position < 98304) {
            return;
        }
        var kept = Array<u8>(output.count - output_position + 65536);
        kept._append_raw(output._data + output_position, output.count - output_position);
        output = kept;
        output_position = 0;
    }
}
