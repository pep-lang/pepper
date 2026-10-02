//! The `compress` module: CRC-32 and Adler-32, DEFLATE with its zlib and
//! gzip framings at every level, streams made by zlib and Python's gzip,
//! the streaming reader and writer, and corrupt input. Each check returns 0
//! on success or a distinct negative code per check, and must leave no
//! allocation behind.

use crate::support;

const PROGRAM: &str = r##"
import compress;
import io;

computes_checksums(): int {
    if (compress.Crc32.of("123456789".bytes()) != 0xCBF43926) { return -1; }
    if (compress.Crc32.of(Array<u8>()) != 0) { return -2; }
    if (compress.Adler32.of("Wikipedia".bytes()) != 0x11E60398) { return -3; }
    if (compress.Adler32.of(Array<u8>()) != 1) { return -4; }
    var crc = compress.Crc32();
    var adler = compress.Adler32();
    crc.update("1234".bytes());
    crc.update("56789".bytes());
    adler.update("Wiki".bytes());
    adler.update("pedia".bytes());
    if (crc.value != 0xCBF43926 || adler.value != 0x11E60398) { return -5; }
    crc.reset();
    adler.reset();
    if (crc.value != 0 || adler.value != 1) { return -6; }
    # More than the 5552 bytes Adler-32 sums before reducing.
    var big = Array<u8>();
    var index = 0;
    while (index < 100000) {
        big.append(255);
        index += 1;
    }
    if (compress.Adler32.of(big) != 0x149A302C) { return -7; }
    return 0;
}

# Bytes from a linear congruential generator: `unique` distinct values,
# so the data ranges from compressible to not at all.
noise(count: ulong, unique: uint): u8[] {
    var data = Array<u8>(count);
    uint state = 12345;
    ulong index = 0;
    while (index < count) {
        state = state.wrapping_mul(1103515245).wrapping_add(12345);
        data.append(((state >> 16) % unique) as u8);
        index += 1;
    }
    return data;
}

check(data: u8[]): int {
    var level = 0;
    while (level <= 9) {
        if (compress.Deflate.decompress(compress.Deflate.compress(data, level)).value() != data) { return -1 - level; }
        if (compress.Zlib.decompress(compress.Zlib.compress(data, level)).value() != data) { return -20 - level; }
        if (compress.Gzip.decompress(compress.Gzip.compress(data, level)).value() != data) { return -40 - level; }
        level += 3;
    }
    return 0;
}

round_trips_every_format_and_level(): int {
    var inputs = Array<u8[]>();
    inputs.append(Array<u8>());
    inputs.append("a".bytes());
    inputs.append("abcabcabcabcabcabcabcabcabcabcabc".bytes());
    inputs.append("the cat sat on the mat; the cat sat on the hat; ".repeat(400).bytes());
    inputs.append(noise(70000, 256));
    inputs.append(noise(150000, 4));
    inputs.append(noise(66000, 1));
    var number = 0;
    for (var data in inputs) {
        var failed = check(data);
        if (failed != 0) {
            return failed - number * 100;
        }
        number += 1;
    }
    # Repetitive text shrinks; level 0 only adds framing.
    var text = inputs[3];
    if (compress.Gzip.compress(text).count * 20 > text.count) { return -1000; }
    if (compress.Deflate.compress(text, 0).count != text.count + 5) { return -1001; }
    var zlib = compress.Zlib.compress(text);
    if (zlib[0] != 0x78 || ((zlib[0] as uint) * 256 + (zlib[1] as uint)) % 31 != 0) { return -1002; }
    var gzip = compress.Gzip.compress(text);
    if (gzip[0] != 31 || gzip[1] != 139 || gzip[2] != 8) { return -1003; }
    return 0;
}

decodes_streams_from_other_encoders(): int {
    # zlib.compress at level 9: dynamic Huffman codes.
    u8[] dynamic = [120, 218, 237, 203, 201, 1, 128, 32, 12, 5, 209, 86, 126, 5, 214, 226, 129, 6, 80, 131, 68, 133, 8, 10, 46, 213, 155, 34, 60, 114, 158, 55, 198, 19, 82, 225, 113, 197, 144, 229, 138, 112, 114, 99, 41, 97, 63, 32, 149, 50, 78, 205, 155, 125, 31, 76, 50, 119, 48, 13, 55, 220, 240, 223, 184, 183, 234, 194, 131, 65, 209, 197, 167, 135, 227, 74, 154, 94, 138, 216, 56, 21, 201, 250, 206, 71, 247, 1, 235, 114, 81, 179];
    var text = "The quick brown fox jumps over the lazy dog. ".repeat(20) + "Pack my box with five dozen liquor jugs.";
    if (compress.Zlib.decompress(dynamic).value() != text.bytes()) { return -1; }
    # Raw DEFLATE with the fixed codes, and a stored block.
    u8[] fixed = [75, 203, 172, 72, 77, 81, 200, 40, 77, 75, 203, 77, 204, 83, 72, 67, 230, 1, 0];
    if (compress.Deflate.decompress(fixed).value() != "fixed huffman fixed huffman".bytes()) { return -2; }
    u8[] stored = [1, 6, 0, 249, 255, 115, 116, 111, 114, 101, 100];
    if (compress.Deflate.decompress(stored).value() != "stored".bytes()) { return -3; }
    # A gzip member with a file name and modification time in its header.
    u8[] named = [31, 139, 8, 8, 0, 241, 83, 101, 2, 255, 110, 111, 116, 101, 115, 46, 116, 120, 116, 0, 203, 75, 204, 77, 77, 81, 200, 77, 205, 77, 74, 45, 226, 2, 0, 231, 210, 244, 237, 13, 0, 0, 0];
    if (compress.Gzip.decompress(named).value() != "named member\n".bytes()) { return -4; }
    # Two members one after another.
    u8[] multi = [31, 139, 8, 0, 0, 0, 0, 0, 2, 3, 203, 207, 75, 85, 0, 0, 73, 97, 172, 35, 4, 0, 0, 0, 31, 139, 8, 0, 0, 0, 0, 0, 2, 3, 43, 41, 207, 7, 0, 102, 138, 202, 17, 3, 0, 0, 0];
    if (compress.Gzip.decompress(multi).value() != "one two".bytes()) { return -5; }
    return 0;
}

# 0 when `result` is an invalid-input error whose message contains `text`.
invalid(result: io.IoResult<u8[]>, text: String): int {
    if (result.is_ok()) { return 1; }
    if (!result.error().is_invalid_input()) { return 2; }
    if (!result.error().message.contains(text)) { return 3; }
    return 0;
}

reports_corrupt_data(): int {
    var data = "hello hello hello hello".bytes();
    var gzip = compress.Gzip.compress(data);

    var truncated = gzip.clone();
    truncated.truncate(gzip.count - 6);
    if (invalid(compress.Gzip.decompress(truncated), "unexpected end") != 0) { return -1; }

    var bad_crc = gzip.clone();
    bad_crc[gzip.count - 8] = bad_crc[gzip.count - 8] ^ 1;
    if (invalid(compress.Gzip.decompress(bad_crc), "CRC-32") != 0) { return -2; }

    var bad_size = gzip.clone();
    bad_size[gzip.count - 4] = bad_size[gzip.count - 4] ^ 1;
    if (invalid(compress.Gzip.decompress(bad_size), "length") != 0) { return -3; }

    if (invalid(compress.Gzip.decompress(data), "not gzip data") != 0) { return -4; }

    var trailing = gzip.clone();
    trailing.append(0);
    if (invalid(compress.Gzip.decompress(trailing), "not gzip data") != 0) { return -5; }

    var zlib = compress.Zlib.compress(data);
    var bad_adler = zlib.clone();
    bad_adler[zlib.count - 1] = bad_adler[zlib.count - 1] ^ 1;
    if (invalid(compress.Zlib.decompress(bad_adler), "Adler-32") != 0) { return -6; }
    if (invalid(compress.Zlib.decompress(gzip), "not zlib data") != 0) { return -7; }

    # Block type 3 does not exist.
    u8[] reserved = [7];
    if (invalid(compress.Deflate.decompress(reserved), "invalid block type") != 0) { return -8; }
    # A stored block whose length check does not match.
    u8[] stored = [1, 5, 0, 0, 0];
    if (invalid(compress.Deflate.decompress(stored), "stored block length") != 0) { return -9; }
    # A fixed block that copies from 1 byte back with no output yet.
    u8[] far = [3, 2, 0];
    if (invalid(compress.Deflate.decompress(far), "invalid distance") != 0) { return -10; }
    if (invalid(compress.Deflate.decompress(Array<u8>()), "unexpected end") != 0) { return -11; }
    return 0;
}

streams_through_readers_and_writers(): int {
    # Enough output that the reader drops what it handed out.
    var data = Array<u8>();
    uint state = 7;
    while (data.count < 400000) {
        state = state.wrapping_mul(1103515245).wrapping_add(12345);
        data.append(97 + ((state >> 16) % 8) as u8);
    }
    var formats = [compress.Format.Raw, compress.Format.Zlib, compress.Format.Gzip];
    var number = 0;
    for (var format in formats) {
        var sink = io.ByteWriter();
        var writer = compress.CompressWriter(sink, format, 6);
        ulong at = 0;
        ulong piece = 1;
        while (at < data.count) {
            var size = piece;
            if (size > data.count - at) {
                size = data.count - at;
            }
            var part = Array<u8>(size);
            part._append_raw(data._data + at, size);
            if (writer.write(part).value() != size) { return -1 - number; }
            at += size;
            piece = piece * 3 + 1;
        }
        writer.finish().value();
        writer.finish().value();

        var reader = compress.DecompressReader(io.ByteReader(sink.bytes), format);
        var back = Array<u8>();
        while (true) {
            var read = reader.read(back, 1000);
            if (read.is_err()) { return -10 - number; }
            if (read.value() == 0) { break; }
        }
        if (back != data) { return -20 - number; }
        number += 1;
    }

    # The Reader trait's lines(), over a gzip stream.
    var text = compress.Gzip.compress("one\ntwo\nthree\n".bytes());
    var count = 0;
    for (var line in compress.DecompressReader(io.ByteReader(text), compress.Format.Gzip).lines()) {
        if (line.is_err()) { return -30; }
        count += 1;
    }
    if (count != 3) { return -31; }

    # The Writer trait's print_line, into a zlib stream.
    var sink = io.ByteWriter();
    var writer = compress.CompressWriter(sink, compress.Format.Zlib);
    writer.print_line(42);
    writer.finish();
    if (compress.Zlib.decompress(sink.bytes).value() != "42\n".bytes()) { return -32; }

    # A read error comes after the bytes decoded before it.
    var cut = compress.Gzip.compress(data);
    cut.truncate(cut.count / 2);
    var partial = compress.DecompressReader(io.ByteReader(cut), compress.Format.Gzip).read_all();
    if (partial.is_ok() || !partial.error().is_invalid_input()) { return -33; }
    return 0;
}

reads_and_writes_bytes_in_memory(): int {
    var reader = io.ByteReader("hello".bytes());
    var out = Array<u8>();
    if (reader.read(out, 2).value() != 2 || reader.remaining != 3) { return -1; }
    if (reader.read(out, 10).value() != 3 || out != "hello".bytes()) { return -2; }
    if (reader.read(out, 10).value() != 0) { return -3; }
    var writer = io.ByteWriter();
    writer.write("ab".bytes());
    writer.write_all("cd".bytes());
    writer.print(1);
    if (writer.bytes != "abcd1".bytes()) { return -4; }
    return 0;
}
"##;

/// Each check is a function of one program, compiled once.
#[test]
fn compression() {
    support::jit_cases(PROGRAM, &["computes_checksums", "round_trips_every_format_and_level", "decodes_streams_from_other_encoders", "reports_corrupt_data", "streams_through_readers_and_writers", "reads_and_writes_bytes_in_memory"]);
}
