# Preset dictionaries: zlib streams that name one by its Adler-32, raw DEFLATE
# primed with one, every level, and dictionaries longer than the window.

import compress;
import io;

expect_invalid(result: io.IoResult<u8[]>, text: String, location: __ptr<char> = __caller_location()) {
    expect_true(result.is_err(), location);
    if (result.is_err()) {
        expect_true(result.error().is_invalid_input(), location);
        expect_true(result.error().message.contains(text), location);
    }
}

# The value of the hexadecimal digit `c` (lower case).
digit(c: u8): u8 {
    return c <= 57 ? c - 48 : c - 87;
}

# The bytes `text` spells in hexadecimal.
from_hex(text: String): u8[] {
    var digits = text.bytes();
    var bytes = Array<u8>();
    ulong i = 0;
    while (i < digits.count) {
        bytes.append(digit(digits[i]) * 16 + digit(digits[i + 1]));
        i += 2;
    }
    return bytes;
}

[Test]
decodes_python_streams() {
    var dictionary = "the quick brown fox ".bytes();
    var data = "the quick brown fox jumps over the quick brown dog".bytes();
    # Made by Python's zlib with `zdict`: zlib framing, then raw DEFLATE.
    var python = from_hex("78f94ee207542bc12296559a5b50ac905f965a84219d929f0e00dbee129f");
    var raw = from_hex("2bc12296559a5b50ac905f965a84219d929f0e00");
    expect_true(compress.Zlib.decompress(python, dictionary).value() == data);
    var reader = compress.DecompressReader(io.ByteReader(raw), compress.Format.Raw, dictionary);
    expect_true(reader.read_all().value() == data);
}

[Test]
reports_a_missing_or_wrong_dictionary() {
    var python = from_hex("78f94ee207542bc12296559a5b50ac905f965a84219d929f0e00dbee129f");
    expect_invalid(compress.Zlib.decompress(python), "needs a preset dictionary");
    expect_invalid(compress.Zlib.decompress(python, "the slow".bytes()), "different preset dictionary");
}

# Every level round-trips, names the dictionary by its Adler-32 (0x4ee20754),
# and above level 0 comes out smaller than without it.
[Test]
round_trips_at_every_level() {
    var dictionary = "the quick brown fox ".bytes();
    var data = "the quick brown fox jumps over the quick brown dog".bytes();
    var level = 0;
    while (level <= 9) {
        var packed = compress.Zlib.compress(data, dictionary, level);
        expect_true((packed[1] & 32) != 0);
        expect_equal(packed[2], 0x4E as u8);
        expect_equal(packed[5], 0x54 as u8);
        expect_true(compress.Zlib.decompress(packed, dictionary).value() == data);
        if (level > 0) {
            expect_true(packed.count < compress.Zlib.compress(data, level).count);
        }
        var sink = io.ByteWriter();
        var writer = compress.CompressWriter(sink, compress.Format.Raw, dictionary, level);
        expect_true(writer.write_all(data).is_ok());
        expect_true(writer.finish().is_ok());
        var back = compress.DecompressReader(io.ByteReader(sink.bytes), compress.Format.Raw, dictionary);
        expect_true(back.read_all().value() == data);
        level += 1;
    }
}

[Test]
ignores_a_dictionary_the_stream_does_not_name() {
    var data = "the quick brown fox jumps over the quick brown dog".bytes();
    var dictionary = "the quick brown fox ".bytes();
    expect_true(compress.Zlib.decompress(compress.Zlib.compress(data), dictionary).value() == data);
}

# Only the last 32 KiB of a longer dictionary count.
[Test]
uses_the_last_window_of_a_long_dictionary() {
    var dictionary = Array<u8>();
    uint state = 11;
    while (dictionary.count < 50000) {
        state = state.wrapping_mul(1103515245).wrapping_add(12345);
        dictionary.append((state >> 16) as u8);
    }
    var tail = Array<u8>();
    ulong i = 30000;
    while (i < dictionary.count) {
        tail.append(dictionary[i]);
        i += 1;
    }
    var packed = compress.Zlib.compress(tail, dictionary, 9);
    expect_true(packed.count < 1000);
    expect_true(compress.Zlib.decompress(packed, dictionary).value() == tail);
}
