## Compression: DEFLATE (RFC 1951) with its zlib and gzip framings, in one
## call or as streams, and the CRC-32 and Adler-32 checksums.
##
## Bring it in with `import compress`. It is written in Pepper, so it needs
## no zlib. Corrupt data is an `io.IoError` whose `is_invalid_input()` holds.
##
## - [Formats and streams](compress-format.md): `Format`, `Deflate`, `Zlib`,
##   `Gzip`, `DecompressReader`, `CompressWriter`
## - [Checksums](compress-checksum.md): `Crc32`, `Adler32`
##
## @example
##     import compress;
##
##     main(): int {
##         var data = "to be or not to be, that is the question".bytes();
##         var packed = compress.Gzip.compress(data);
##         assert(compress.Gzip.decompress(packed).value() == data, "round trip");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "checksum";
import "deflate";
import "format";
import "inflate";

export Format;
export Deflate;
export Zlib;
export Gzip;
export DecompressReader;
export CompressWriter;
export Crc32;
export Adler32;
