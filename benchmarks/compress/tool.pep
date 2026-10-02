# A small command-line driver for the compress module, for the benchmark
# and the zlib cross-check next to it:
#
#     tool <c|d|sc|sd> <raw|zlib|gzip> <level> <input> <output>
#
# `c` and `d` compress and decompress in one call; `sc` and `sd` stream
# through `CompressWriter` (7919-byte writes) and `DecompressReader`
# (5003-byte reads), sizes chosen to cross block and buffer boundaries.

import compress;
import io;

format_of(name: String): compress.Format {
    if (name == "raw") {
        return compress.Format.Raw;
    }
    if (name == "zlib") {
        return compress.Format.Zlib;
    }
    return compress.Format.Gzip;
}

compress_all(data: u8[], format: compress.Format, level: int): u8[] {
    if (format == compress.Format.Zlib) {
        return compress.Zlib.compress(data, level);
    }
    if (format == compress.Format.Gzip) {
        return compress.Gzip.compress(data, level);
    }
    return compress.Deflate.compress(data, level);
}

decompress_all(data: u8[], format: compress.Format): io.IoResult<u8[]> {
    if (format == compress.Format.Zlib) {
        return compress.Zlib.decompress(data);
    }
    if (format == compress.Format.Gzip) {
        return compress.Gzip.decompress(data);
    }
    return compress.Deflate.decompress(data);
}

main(args: String[]): int {
    if (args.count != 6) {
        print("usage: tool <c|d|sc|sd> <raw|zlib|gzip> <level> <input> <output>");
        return 1;
    }
    var mode = args[1];
    var format = format_of(args[2]);
    var level = int.parse(args[3]).value();
    var input = io.Path(args[4]);
    var output = io.Path(args[5]);
    if (mode == "c") {
        var data = io.File.read_bytes(input).value();
        io.File.write_bytes(output, compress_all(data, format, level));
    } else if (mode == "d") {
        var data = io.File.read_bytes(input).value();
        var result = decompress_all(data, format);
        if (result.is_err()) {
            print(result.error().message);
            return 2;
        }
        io.File.write_bytes(output, result.value());
    } else if (mode == "sc") {
        var source = io.File.open(input).value();
        var sink = io.File.create(output).value();
        var writer = compress.CompressWriter(sink, format, level);
        while (true) {
            var chunk = Array<u8>();
            var count = source.read(chunk, 7919).value();
            if (count == 0) {
                break;
            }
            writer.write_all(chunk).value();
        }
        writer.finish().value();
        sink.close();
    } else {
        var source = io.File.open(input).value();
        var reader = compress.DecompressReader(source, format);
        var sink = io.File.create(output).value();
        while (true) {
            var chunk = Array<u8>();
            var count = reader.read(chunk, 5003);
            if (count.is_err()) {
                print(count.error().message);
                return 2;
            }
            if (count.value() == 0) {
                break;
            }
            sink.write_all(chunk).value();
        }
        sink.close();
    }
    return 0;
}
