# Compress and decompress bytes in one call, or as streams.
import compress;
import io;

main(): int {
    var text = "the cat sat on the mat; ".repeat(100).bytes();

    # gzip, zlib and raw DEFLATE each have compress and decompress.
    var packed = compress.Gzip.compress(text);
    assert(packed.count < text.count / 10, "repetitive text shrinks");
    assert(compress.Gzip.decompress(packed).value() == text, "round trip");

    # Level 0 stores, 9 squeezes hardest; 6 is the default.
    var fast = compress.Zlib.compress(text, level = 1);
    assert(compress.Zlib.decompress(fast).value() == text, "any level reads back");

    # Corrupt data is an error, never a crash.
    packed[packed.count - 5] = packed[packed.count - 5] ^ 1;
    var bad = compress.Gzip.decompress(packed);
    assert(bad.is_err() && bad.error().is_invalid_input(), "the CRC-32 check fails");

    # Streams: a CompressWriter wraps any io.Writer, a DecompressReader any
    # io.Reader, such as a File. Here both are in memory.
    var sink = io.ByteWriter();
    var writer = compress.CompressWriter(sink, compress.Format.Gzip);
    writer.print_line("first line");
    writer.print_line("second line");
    writer.finish();

    var reader = compress.DecompressReader(io.ByteReader(sink.bytes), compress.Format.Gzip);
    var lines = 0;
    for (var line in reader.lines()) {
        lines += 1;
    }
    assert(lines == 2, "two lines");

    # The checksums are there on their own too.
    assert(compress.Crc32.of("123456789".bytes()) == 0xCBF43926, "CRC-32");
    return 0;
}
