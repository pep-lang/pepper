# compress: CRC-32 and Adler-32, DEFLATE with its zlib and gzip framings at
# every level, streams made by zlib and Python's gzip, the streaming reader
# and writer, and corrupt input. They also run with `-D USE_ZLIB` (#370),
# so every test checks zlib as well.

import compress;
import io;

[Test]
computes_checksums() {
    expect_equal(compress.Crc32.of("123456789".bytes()), 0xCBF43926);
    expect_equal(compress.Crc32.of(Array<u8>()), 0);
    expect_equal(compress.Adler32.of("Wikipedia".bytes()), 0x11E60398);
    expect_equal(compress.Adler32.of(Array<u8>()), 1);
    var crc = compress.Crc32();
    var adler = compress.Adler32();
    crc.update("1234".bytes());
    crc.update("56789".bytes());
    adler.update("Wiki".bytes());
    adler.update("pedia".bytes());
    expect_equal(crc.value, 0xCBF43926);
    expect_equal(adler.value, 0x11E60398);
    crc.reset();
    adler.reset();
    expect_equal(crc.value, 0);
    expect_equal(adler.value, 1);
    # More than the 5552 bytes Adler-32 sums before reducing.
    var big = Array<u8>();
    while (big.count < 100000) {
        big.append(255);
    }
    expect_equal(compress.Adler32.of(big), 0x149A302C);
}

# Bytes from a linear congruential generator: `unique` distinct values,
# so the data ranges from compressible to not at all.
noise(count: ulong, unique: uint): u8[] {
    var data = Array<u8>(count);
    uint state = 12345;
    while (data.count < count) {
        state = state.wrapping_mul(1103515245).wrapping_add(12345);
        data.append(((state >> 16) % unique) as u8);
    }
    return data;
}

# Round-trips `data` through each format at levels 0, 3, 6 and 9.
expect_round_trips(data: u8[]) {
    var level = 0;
    while (level <= 9) {
        expect_true(compress.Deflate.decompress(compress.Deflate.compress(data, level)).value() == data);
        expect_true(compress.Zlib.decompress(compress.Zlib.compress(data, level)).value() == data);
        expect_true(compress.Gzip.decompress(compress.Gzip.compress(data, level)).value() == data);
        level += 3;
    }
}

[Test]
round_trips_every_format_and_level() {
    expect_round_trips(Array<u8>());
    expect_round_trips("a".bytes());
    expect_round_trips("abcabcabcabcabcabcabcabcabcabcabc".bytes());
    var text = "the cat sat on the mat; the cat sat on the hat; ".repeat(400).bytes();
    expect_round_trips(text);
    expect_round_trips(noise(70000, 256));
    expect_round_trips(noise(150000, 4));
    expect_round_trips(noise(66000, 1));
}

[Test]
repetitive_text_shrinks_and_level_zero_only_frames() {
    var text = "the cat sat on the mat; the cat sat on the hat; ".repeat(400).bytes();
    expect_true(compress.Gzip.compress(text).count * 20 <= text.count);
    expect_equal(compress.Deflate.compress(text, 0).count, text.count + 5);
    var zlib = compress.Zlib.compress(text);
    expect_equal(zlib[0], 0x78);
    expect_equal(((zlib[0] as uint) * 256 + (zlib[1] as uint)) % 31, 0);
    var gzip = compress.Gzip.compress(text);
    expect_equal(gzip[0], 31);
    expect_equal(gzip[1], 139);
    expect_equal(gzip[2], 8);
}

[Test]
decodes_streams_from_other_encoders() {
    # zlib.compress at level 9: dynamic Huffman codes.
    u8[] dynamic = [
        120,
        218,
        237,
        203,
        201,
        1,
        128,
        32,
        12,
        5,
        209,
        86,
        126,
        5,
        214,
        226,
        129,
        6,
        80,
        131,
        68,
        133,
        8,
        10,
        46,
        213,
        155,
        34,
        60,
        114,
        158,
        55,
        198,
        19,
        82,
        225,
        113,
        197,
        144,
        229,
        138,
        112,
        114,
        99,
        41,
        97,
        63,
        32,
        149,
        50,
        78,
        205,
        155,
        125,
        31,
        76,
        50,
        119,
        48,
        13,
        55,
        220,
        240,
        223,
        184,
        183,
        234,
        194,
        131,
        65,
        209,
        197,
        167,
        135,
        227,
        74,
        154,
        94,
        138,
        216,
        56,
        21,
        201,
        250,
        206,
        71,
        247,
        1,
        235,
        114,
        81,
        179
    ];
    var text = "The quick brown fox jumps over the lazy dog. ".repeat(20) + "Pack my box with five dozen liquor jugs.";
    expect_true(compress.Zlib.decompress(dynamic).value() == text.bytes());
    # Raw DEFLATE with the fixed codes, and a stored block.
    u8[] fixed = [75, 203, 172, 72, 77, 81, 200, 40, 77, 75, 203, 77, 204, 83, 72, 67, 230, 1, 0];
    expect_true(compress.Deflate.decompress(fixed).value() == "fixed huffman fixed huffman".bytes());
    u8[] stored = [1, 6, 0, 249, 255, 115, 116, 111, 114, 101, 100];
    expect_true(compress.Deflate.decompress(stored).value() == "stored".bytes());
    # A gzip member with a file name and modification time in its header.
    u8[] named = [
        31,
        139,
        8,
        8,
        0,
        241,
        83,
        101,
        2,
        255,
        110,
        111,
        116,
        101,
        115,
        46,
        116,
        120,
        116,
        0,
        203,
        75,
        204,
        77,
        77,
        81,
        200,
        77,
        205,
        77,
        74,
        45,
        226,
        2,
        0,
        231,
        210,
        244,
        237,
        13,
        0,
        0,
        0
    ];
    expect_true(compress.Gzip.decompress(named).value() == "named member\n".bytes());
    # Two members one after another.
    u8[] multi = [
        31,
        139,
        8,
        0,
        0,
        0,
        0,
        0,
        2,
        3,
        203,
        207,
        75,
        85,
        0,
        0,
        73,
        97,
        172,
        35,
        4,
        0,
        0,
        0,
        31,
        139,
        8,
        0,
        0,
        0,
        0,
        0,
        2,
        3,
        43,
        41,
        207,
        7,
        0,
        102,
        138,
        202,
        17,
        3,
        0,
        0,
        0
    ];
    expect_true(compress.Gzip.decompress(multi).value() == "one two".bytes());
}

# Checks that `result` is an invalid-input error whose message contains `text`.
expect_invalid(result: io.IoResult<u8[]>, text: String, location: __ptr<char> = __caller_location()) {
    if (result.is_ok()) {
        panic($"expected an error containing '{text}'", location);
    }
    if (!result.error().is_invalid_input() or !result.error().message.contains(text)) {
        panic($"expected an invalid-input error containing '{text}', have '{result.error().message}'", location);
    }
}

[Test]
reports_corrupt_data() {
    var data = "hello hello hello hello".bytes();
    var gzip = compress.Gzip.compress(data);

    var truncated = gzip.clone();
    truncated.truncate(gzip.count - 6);
    expect_invalid(compress.Gzip.decompress(truncated), "unexpected end");

    var bad_crc = gzip.clone();
    bad_crc[gzip.count - 8] = bad_crc[gzip.count - 8] ^ 1;
    expect_invalid(compress.Gzip.decompress(bad_crc), "CRC-32");

    var bad_size = gzip.clone();
    bad_size[gzip.count - 4] = bad_size[gzip.count - 4] ^ 1;
    expect_invalid(compress.Gzip.decompress(bad_size), "length");

    expect_invalid(compress.Gzip.decompress(data), "not gzip data");

    var trailing = gzip.clone();
    trailing.append(0);
    expect_invalid(compress.Gzip.decompress(trailing), "not gzip data");

    var zlib = compress.Zlib.compress(data);
    var bad_adler = zlib.clone();
    bad_adler[zlib.count - 1] = bad_adler[zlib.count - 1] ^ 1;
    expect_invalid(compress.Zlib.decompress(bad_adler), "Adler-32");
    expect_invalid(compress.Zlib.decompress(gzip), "not zlib data");

    # Block type 3 does not exist.
    u8[] reserved = [7];
    expect_invalid(compress.Deflate.decompress(reserved), "invalid block type");
    # A stored block whose length check does not match.
    u8[] stored = [1, 5, 0, 0, 0];
    expect_invalid(compress.Deflate.decompress(stored), "stored block length");
    # A fixed block that copies from 1 byte back with no output yet.
    u8[] far = [3, 2, 0];
    expect_invalid(compress.Deflate.decompress(far), "invalid distance");
    expect_invalid(compress.Deflate.decompress(Array<u8>()), "unexpected end");
}

[Test]
streams_through_readers_and_writers() {
    # Enough output that the reader drops what it handed out.
    var data = Array<u8>();
    uint state = 7;
    while (data.count < 400000) {
        state = state.wrapping_mul(1103515245).wrapping_add(12345);
        data.append(97 + ((state >> 16) % 8) as u8);
    }
    var formats = [compress.Format.Raw, compress.Format.Zlib, compress.Format.Gzip];
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
            expect_equal(writer.write(part).value(), size);
            at += size;
            piece = piece * 3 + 1;
        }
        writer.finish().value();
        writer.finish().value();

        var reader = compress.DecompressReader(io.ByteReader(sink.bytes), format);
        var back = Array<u8>();
        while (reader.read(back, 1000).value() != 0) {}
        expect_true(back == data);
    }
}

[Test]
reads_lines_from_a_gzip_stream() {
    var text = compress.Gzip.compress("one\ntwo\nthree\n".bytes());
    var lines = Array<String>();
    for (var line in compress.DecompressReader(io.ByteReader(text), compress.Format.Gzip).lines()) {
        lines.append(line.value());
    }
    expect_equal(lines.count, 3);
    expect_equal(lines[2], "three");
}

[Test]
prints_into_a_zlib_stream() {
    var sink = io.ByteWriter();
    var writer = compress.CompressWriter(sink, compress.Format.Zlib);
    writer.print_line(42);
    writer.finish();
    expect_true(compress.Zlib.decompress(sink.bytes).value() == "42\n".bytes());
}

[Test]
reports_a_read_error_after_the_bytes_decoded_before_it() {
    var data = Array<u8>();
    uint state = 7;
    while (data.count < 400000) {
        state = state.wrapping_mul(1103515245).wrapping_add(12345);
        data.append(97 + ((state >> 16) % 8) as u8);
    }
    var cut = compress.Gzip.compress(data);
    cut.truncate(cut.count / 2);
    var partial = compress.DecompressReader(io.ByteReader(cut), compress.Format.Gzip).read_all();
    expect_true(partial.is_err());
    expect_true(partial.error().is_invalid_input());
}

[Test]
reads_and_writes_bytes_in_memory() {
    var reader = io.ByteReader("hello".bytes());
    var out = Array<u8>();
    expect_equal(reader.read(out, 2).value(), 2);
    expect_equal(reader.remaining, 3);
    expect_equal(reader.read(out, 10).value(), 3);
    expect_true(out == "hello".bytes());
    expect_equal(reader.read(out, 10).value(), 0);
    var writer = io.ByteWriter();
    writer.write("ab".bytes());
    writer.write_all("cd".bytes());
    writer.print(1);
    expect_true(writer.bytes == "abcd1".bytes());
}
