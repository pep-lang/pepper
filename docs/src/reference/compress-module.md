<!-- Generated from runtime/compress/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The compress module

Compression: DEFLATE (RFC 1951) with its zlib and gzip framings, in one
call or as streams, and the CRC-32 and Adler-32 checksums.

Bring it in with `import compress`. It is written in Pepper, so it needs
no zlib, unless the program is built with `-D USE_ZLIB`, which makes it
use zlib with the same API. Corrupt data is an `io.IoError` whose
`is_invalid_input()` holds.

- [Formats and streams](compress-format.md): `Format`, `Deflate`, `Zlib`,
  `Gzip`, `DecompressReader`, `CompressWriter`
- [Checksums](compress-checksum.md): `Crc32`, `Adler32`

**Example**
```pepper
import compress;

main(): int {
    var data = "to be or not to be, that is the question".bytes();
    var packed = compress.Gzip.compress(data);
    assert(compress.Gzip.decompress(packed).value() == data, "round trip");
    return 0;
}
```

Source: `runtime/compress/module.pep`
