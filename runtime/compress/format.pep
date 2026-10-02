## `Format`, the one-call `Deflate`, `Zlib` and `Gzip` functions, and the
## streaming `DecompressReader` and `CompressWriter`.

import io;
import "deflate";
import "inflate";

## The framing around DEFLATE-compressed data.
##
## @example
##     import compress;
##
##     var packed = compress.Gzip.compress("hi".bytes());
##     var reader = compress.DecompressReader(io.ByteReader(packed), compress.Format.Gzip);
export enum Format {
    ## Raw DEFLATE (RFC 1951) with no header or checksum, as zip archives
    ## and HTTP's `Content-Encoding: deflate` from some servers carry it.
    Raw,
    ## zlib (RFC 1950): a two-byte header, DEFLATE, then an Adler-32
    ## checksum. PNG images and HTTP's `deflate` encoding use it.
    Zlib,
    ## gzip (RFC 1952): a header, DEFLATE, then a CRC-32 and the length.
    ## `.gz` files and HTTP's `gzip` encoding use it. Reading accepts
    ## several members one after another, as `cat a.gz b.gz` makes.
    Gzip,
}

# Checks a compression level.
_compress_check_level(level: int) {
    assert(level >= 0 && level <= 9, "compression level must be 0 through 9");
}

# Compresses all of `data` in `format`.
_compress_all(data: u8[], format: Format, level: int): u8[] {
    _compress_check_level(level);
    var deflater = _Deflater(format, level);
    deflater.write(data);
    deflater.finish();
    return deflater.output;
}

# Decompresses all of `data` in `format`.
_decompress_all(data: u8[], format: Format): io.IoResult<u8[]> {
    var inflater = _Inflater(data, format);
    if (!inflater.fill(0xFFFFFFFFFFFFFFFF)) {
        return io.IoResult<u8[]>.err(inflater.error);
    }
    return io.IoResult<u8[]>.ok(inflater.output);
}

## Raw DEFLATE (RFC 1951) data, compressed or decompressed in one call.
##
## @example
##     import compress;
##
##     var data = "abcabcabcabc".bytes();
##     var packed = compress.Deflate.compress(data);
##     assert(compress.Deflate.decompress(packed).value() == data, "round trip");
export struct Deflate {
    ## Compresses `data` into raw DEFLATE data.
    ##
    ## @param data the bytes to compress
    ## @param level from 0 (store without compressing) through 9 (smallest
    ##   output, slowest); 6 balances the two, as zlib's default does
    ## @returns the compressed bytes
    ## @panics if `level` is not 0 through 9 ("compression level must be 0
    ##   through 9")
    static compress(data: u8[], level: int = 6): u8[] {
        return _compress_all(data, Format.Raw, level);
    }

    ## Decompresses raw DEFLATE data. Bytes after the end of the compressed
    ## data are ignored.
    ##
    ## @param data the compressed bytes
    ## @returns the decompressed bytes; an `is_invalid_input()` error when
    ##   `data` is not valid DEFLATE data or ends too soon
    static decompress(data: u8[]): io.IoResult<u8[]> {
        return _decompress_all(data, Format.Raw);
    }
}

## zlib (RFC 1950) data, compressed or decompressed in one call.
##
## @example
##     import compress;
##
##     var packed = compress.Zlib.compress("hello".bytes());
##     assert(packed[0] == 0x78, "the zlib header");
##     assert(compress.Zlib.decompress(packed).value() == "hello".bytes(), "round trip");
export struct Zlib {
    ## Compresses `data` into a zlib stream.
    ##
    ## @param data the bytes to compress
    ## @param level from 0 (store without compressing) through 9 (smallest
    ##   output, slowest); 6 balances the two
    ## @returns the compressed bytes
    ## @panics if `level` is not 0 through 9 ("compression level must be 0
    ##   through 9")
    static compress(data: u8[], level: int = 6): u8[] {
        return _compress_all(data, Format.Zlib, level);
    }

    ## Decompresses a zlib stream and checks its Adler-32 checksum. Bytes
    ## after the stream are ignored. A stream that needs a preset
    ## dictionary is not supported.
    ##
    ## @param data the compressed bytes
    ## @returns the decompressed bytes; an `is_invalid_input()` error when
    ##   `data` is not a valid zlib stream, ends too soon, or fails its
    ##   checksum
    static decompress(data: u8[]): io.IoResult<u8[]> {
        return _decompress_all(data, Format.Zlib);
    }
}

## gzip (RFC 1952) data, as in `.gz` files, compressed or decompressed in
## one call.
##
## @example
##     import compress;
##     import io;
##
##     var packed = compress.Gzip.compress("hello".bytes());
##     io.File.write_bytes(io.Path("hello.txt.gz"), packed);
##     assert(compress.Gzip.decompress(packed).value() == "hello".bytes(), "round trip");
export struct Gzip {
    ## Compresses `data` into one gzip member with no file name and no
    ## modification time.
    ##
    ## @param data the bytes to compress
    ## @param level from 0 (store without compressing) through 9 (smallest
    ##   output, slowest); 6 balances the two
    ## @returns the compressed bytes
    ## @panics if `level` is not 0 through 9 ("compression level must be 0
    ##   through 9")
    static compress(data: u8[], level: int = 6): u8[] {
        return _compress_all(data, Format.Gzip, level);
    }

    ## Decompresses gzip data, checking each member's CRC-32 and length.
    ## Several members one after another decompress to their contents
    ## joined. The header's file name, comment and extra field are skipped.
    ##
    ## @param data the compressed bytes
    ## @returns the decompressed bytes; an `is_invalid_input()` error when
    ##   `data` is not valid gzip data, ends too soon, fails a check, or has
    ##   bytes after the last member
    static decompress(data: u8[]): io.IoResult<u8[]> {
        return _decompress_all(data, Format.Gzip);
    }
}

## A `Reader` that decompresses another stream as it is read, such as a
## `.gz` file or an HTTP response body, without holding all of it in memory.
##
## It reads its source in chunks of up to 64 KiB and keeps at most about
## 160 KiB of output, however large the data. Corrupt or truncated data is an
## `is_invalid_input()` error from `read`, after the bytes decoded before
## the problem; an error from the source is passed on.
##
## @example
##     import compress;
##     import io;
##
##     var file = io.File.open(io.Path("notes.txt.gz")).value();
##     var reader = compress.DecompressReader(file, compress.Format.Gzip);
##     for (var line in reader.lines()) {
##         print(line.value());
##     }
export struct DecompressReader {
    # The decoder, which reads the source.
    var _inflater: _Inflater;

    ## Makes a reader of the decompressed contents of `source`.
    ##
    ## @param source the stream of compressed bytes
    ## @param format the framing of the compressed data
    construct(source: io.Reader, format: Format) {
        _inflater = _Inflater(source, format);
    }

    ## Decompresses up to `max` more bytes and appends them to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read
    ## @returns the number of bytes appended, 0 at the end of the compressed
    ##   data; an error when the data is invalid or the source fails
    read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        if (max == 0) {
            return io.IoResult<ulong>.ok(0);
        }
        if (_inflater.available == 0) {
            if (_inflater.failed) {
                return io.IoResult<ulong>.err(_inflater.error);
            }
            _inflater.compact();
            var want = max;
            if (want > 65536) {
                want = 65536;
            }
            _inflater.fill(want);
            if (_inflater.available == 0 && _inflater.failed) {
                return io.IoResult<ulong>.err(_inflater.error);
            }
        }
        var count = _inflater.available;
        if (count > max) {
            count = max;
        }
        buffer._append_raw(_inflater.output._data + _inflater.output_position, count);
        _inflater.output_position += count;
        return io.IoResult<ulong>.ok(count);
    }

    ## Decompresses the rest of the stream.
    ##
    ## @returns the decompressed bytes not read yet; an error as for `read`
    read_all(): io.IoResult<u8[]> {
        var result = Array<u8>();
        while (true) {
            var read = read(result, 65536);
            if (read.is_err()) {
                return io.IoResult<u8[]>.err(read.error());
            }
            if (read.value() == 0) {
                return io.IoResult<u8[]>.ok(result);
            }
        }
        return io.IoResult<u8[]>.ok(result);
    }
}

extend DecompressReader with io.Reader;

## A `Writer` that compresses what is written to it and writes the result
## to another stream, such as a `.gz` file.
##
## Compressed bytes reach the sink in pieces as blocks fill; `finish()`
## writes the rest and the format's trailer, and must be called once at the
## end, since dropping the writer does not. It does not close the sink.
##
## @example
##     import compress;
##     import io;
##
##     var file = io.File.create(io.Path("log.txt.gz")).value();
##     var writer = compress.CompressWriter(file, compress.Format.Gzip);
##     writer.print_line("first line");
##     writer.print_line("second line");
##     writer.finish();
##     file.close();
export struct CompressWriter {
    # Where the compressed bytes go.
    var _sink: io.Writer;
    var _deflater: _Deflater;
    var _finished: bool;

    ## Makes a writer that compresses into `sink`.
    ##
    ## @param sink the stream the compressed bytes are written to
    ## @param format the framing to write
    ## @param level from 0 (store without compressing) through 9 (smallest
    ##   output, slowest); 6 balances the two
    ## @panics if `level` is not 0 through 9 ("compression level must be 0
    ##   through 9")
    construct(sink: io.Writer, format: Format, level: int = 6) {
        _compress_check_level(level);
        _sink = sink;
        _deflater = _Deflater(format, level);
    }

    ## Compresses all of `data`.
    ##
    ## @param data the bytes to compress
    ## @returns `data.count`; an error when writing to the sink fails
    ## @panics if `finish()` was called ("CompressWriter used after finish()")
    write(data: u8[]): io.IoResult<ulong> {
        var written = write_all(data);
        if (written.is_err()) {
            return io.IoResult<ulong>.err(written.error());
        }
        return io.IoResult<ulong>.ok(data.count);
    }

    ## Compresses all of `data`.
    ##
    ## @param data the bytes to compress
    ## @returns an Ok result; an error when writing to the sink fails
    ## @panics if `finish()` was called ("CompressWriter used after finish()")
    write_all(data: u8[]): io.IoResult<void> {
        assert(!_finished, "CompressWriter used after finish()");
        _deflater.write(data);
        return _drain();
    }

    ## Compresses what is still buffered, writes the format's trailer, and
    ## ends the stream. Later calls do nothing.
    ##
    ## @returns an Ok result; an error when writing to the sink fails
    finish(): io.IoResult<void> {
        if (_finished) {
            return io.IoResult<void>.ok();
        }
        _finished = true;
        _deflater.finish();
        return _drain();
    }

    # Writes the compressed bytes made so far to the sink.
    _drain(): io.IoResult<void> {
        if (_deflater.output.is_empty) {
            return io.IoResult<void>.ok();
        }
        var bytes = _deflater.output;
        _deflater.output = Array<u8>();
        return _sink.write_all(bytes);
    }
}

extend CompressWriter with io.Writer;
