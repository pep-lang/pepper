<!-- Generated from runtime/compress/format.pep by `pep-doc reference`. Do not edit. -->

# Formats and streams

`Format`, the one-call `Deflate`, `Zlib` and `Gzip` functions, and the
streaming `DecompressReader` and `CompressWriter`.

Source: `runtime/compress/format.pep`

## Format

```pepper
enum Format
```

The framing around DEFLATE-compressed data.

**Example**
```pepper
import compress;

var packed = compress.Gzip.compress("hi".bytes());
var reader = compress.DecompressReader(io.ByteReader(packed), compress.Format.Gzip);
```

### Cases

#### Raw

```pepper
Raw
```

Raw DEFLATE (RFC 1951) with no header or checksum, as zip archives
and HTTP's `Content-Encoding: deflate` from some servers carry it.

#### Zlib

```pepper
Zlib
```

zlib (RFC 1950): a two-byte header, DEFLATE, then an Adler-32
checksum. PNG images and HTTP's `deflate` encoding use it.

#### Gzip

```pepper
Gzip
```

gzip (RFC 1952): a header, DEFLATE, then a CRC-32 and the length.
`.gz` files and HTTP's `gzip` encoding use it. Reading accepts
several members one after another, as `cat a.gz b.gz` makes.

## Deflate

```pepper
struct Deflate
```

Raw DEFLATE (RFC 1951) data, compressed or decompressed in one call.

**Example**
```pepper
import compress;

var data = "abcabcabcabc".bytes();
var packed = compress.Deflate.compress(data);
assert(compress.Deflate.decompress(packed).value() == data, "round trip");
```

### Static methods

#### compress

```pepper
static compress(data: u8[], level: int = 6): u8[]
```

Compresses `data` into raw DEFLATE data.

**Parameters**
- `data` — the bytes to compress
- `level` — from 0 (store without compressing) through 9 (smallest output, slowest); 6 balances the two, as zlib's default does

**Returns**
- the compressed bytes

**Panics**
- if `level` is not 0 through 9 ("compression level must be 0 through 9")

#### decompress

```pepper
static decompress(data: u8[]): io.IoResult<u8[]>
```

Decompresses raw DEFLATE data. Bytes after the end of the compressed
data are ignored.

**Parameters**
- `data` — the compressed bytes

**Returns**
- the decompressed bytes; an `is_invalid_input()` error when `data` is not valid DEFLATE data or ends too soon

## Zlib

```pepper
struct Zlib
```

zlib (RFC 1950) data, compressed or decompressed in one call.

**Example**
```pepper
import compress;

var packed = compress.Zlib.compress("hello".bytes());
assert(packed[0] == 0x78, "the zlib header");
assert(compress.Zlib.decompress(packed).value() == "hello".bytes(), "round trip");
```

### Static methods

#### compress

```pepper
static compress(data: u8[], level: int = 6): u8[]
```

Compresses `data` into a zlib stream.

**Parameters**
- `data` — the bytes to compress
- `level` — from 0 (store without compressing) through 9 (smallest output, slowest); 6 balances the two

**Returns**
- the compressed bytes

**Panics**
- if `level` is not 0 through 9 ("compression level must be 0 through 9")

#### compress

```pepper
static compress(data: u8[], dictionary: u8[], level: int = 6): u8[]
```

Compresses `data` into a zlib stream that starts from a preset
dictionary: bytes the data is likely to repeat, such as the common
keys of small JSON messages, which the stream can then refer back to
without carrying them. The header names the dictionary by its
Adler-32, and decompressing needs the same dictionary. Only its last
32 KiB are used.

**Parameters**
- `data` — the bytes to compress
- `dictionary` — the preset dictionary
- `level` — from 0 (store without compressing) through 9 (smallest output, slowest); 6 balances the two

**Returns**
- the compressed bytes

**Panics**
- if `level` is not 0 through 9 ("compression level must be 0 through 9")

**Example**
```pepper
import compress;

var dictionary = "{\"name\": \"\", \"email\": \"\"}".bytes();
var data = "{\"name\": \"Ada\", \"email\": \"ada@example.com\"}".bytes();
var packed = compress.Zlib.compress(data, dictionary);
assert(compress.Zlib.decompress(packed, dictionary).value() == data, "round trip");
```

#### decompress

```pepper
static decompress(data: u8[]): io.IoResult<u8[]>
```

Decompresses a zlib stream and checks its Adler-32 checksum. Bytes
after the stream are ignored. A stream made with a preset dictionary
needs the overload that takes one.

**Parameters**
- `data` — the compressed bytes

**Returns**
- the decompressed bytes; an `is_invalid_input()` error when `data` is not a valid zlib stream, ends too soon, fails its checksum, or needs a preset dictionary

#### decompress

```pepper
static decompress(data: u8[], dictionary: u8[]): io.IoResult<u8[]>
```

Decompresses a zlib stream that may need a preset dictionary, and
checks its Adler-32 checksum. A stream that does not ask for a
dictionary decompresses as without one.

**Parameters**
- `data` — the compressed bytes
- `dictionary` — the preset dictionary the stream was compressed with

**Returns**
- the decompressed bytes; an `is_invalid_input()` error when `data` is not a valid zlib stream, ends too soon, fails its checksum, or names a dictionary whose Adler-32 is not that of `dictionary`

## Gzip

```pepper
struct Gzip
```

gzip (RFC 1952) data, as in `.gz` files, compressed or decompressed in
one call.

**Example**
```pepper
import compress;
import io;

var packed = compress.Gzip.compress("hello".bytes());
io.File.write_bytes(io.Path("hello.txt.gz"), packed);
assert(compress.Gzip.decompress(packed).value() == "hello".bytes(), "round trip");
```

### Static methods

#### compress

```pepper
static compress(data: u8[], level: int = 6): u8[]
```

Compresses `data` into one gzip member with no file name and no
modification time.

**Parameters**
- `data` — the bytes to compress
- `level` — from 0 (store without compressing) through 9 (smallest output, slowest); 6 balances the two

**Returns**
- the compressed bytes

**Panics**
- if `level` is not 0 through 9 ("compression level must be 0 through 9")

#### decompress

```pepper
static decompress(data: u8[]): io.IoResult<u8[]>
```

Decompresses gzip data, checking each member's CRC-32 and length.
Several members one after another decompress to their contents
joined. The header's file name, comment and extra field are skipped.

**Parameters**
- `data` — the compressed bytes

**Returns**
- the decompressed bytes; an `is_invalid_input()` error when `data` is not valid gzip data, ends too soon, fails a check, or has bytes after the last member

## DecompressReader

```pepper
struct DecompressReader
```

A `Reader` that decompresses another stream as it is read, such as a
`.gz` file or an HTTP response body, without holding all of it in memory.

It reads its source in chunks of up to 64 KiB and keeps at most about
160 KiB of output, however large the data. Corrupt or truncated data is an
`is_invalid_input()` error from `read`, after the bytes decoded before
the problem; an error from the source is passed on.

**Example**
```pepper
import compress;
import io;

var file = io.File.open(io.Path("notes.txt.gz")).value();
var reader = compress.DecompressReader(file, compress.Format.Gzip);
for (var line in reader.lines()) {
    print(line.value());
}
```

### Constructors

#### DecompressReader()

```pepper
construct(source: io.Reader, format: Format)
```

Makes a reader of the decompressed contents of `source`.

**Parameters**
- `source` — the stream of compressed bytes
- `format` — the framing of the compressed data

#### DecompressReader()

```pepper
construct(source: io.Reader, format: Format, dictionary: u8[])
```

Makes a reader of the decompressed contents of `source`, which was
compressed with a preset dictionary (see `Zlib.compress`). A zlib
stream uses it when its header asks for it; raw DEFLATE data always
starts from it.

**Parameters**
- `source` — the stream of compressed bytes
- `format` — `Format.Zlib` or `Format.Raw`
- `dictionary` — the preset dictionary

**Panics**
- if `format` is `Format.Gzip` ("gzip data has no preset dictionary")

### Methods

#### read

```pepper
read(buffer: u8[], max: ulong): io.IoResult<ulong>
```

Decompresses up to `max` more bytes and appends them to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read

**Returns**
- the number of bytes appended, 0 at the end of the compressed data; an error when the data is invalid or the source fails

#### read_all

```pepper
read_all(): io.IoResult<u8[]>
```

Decompresses the rest of the stream.

**Returns**
- the decompressed bytes not read yet; an error as for `read`

## CompressWriter

```pepper
struct CompressWriter
```

A `Writer` that compresses what is written to it and writes the result
to another stream, such as a `.gz` file.

Compressed bytes reach the sink in pieces as blocks fill; `finish()`
writes the rest and the format's trailer, and must be called once at the
end, since dropping the writer does not. It does not close the sink.

**Example**
```pepper
import compress;
import io;

var file = io.File.create(io.Path("log.txt.gz")).value();
var writer = compress.CompressWriter(file, compress.Format.Gzip);
writer.print_line("first line");
writer.print_line("second line");
writer.finish();
file.close();
```

### Constructors

#### CompressWriter()

```pepper
construct(sink: io.Writer, format: Format, level: int = 6)
```

Makes a writer that compresses into `sink`.

**Parameters**
- `sink` — the stream the compressed bytes are written to
- `format` — the framing to write
- `level` — from 0 (store without compressing) through 9 (smallest output, slowest); 6 balances the two

**Panics**
- if `level` is not 0 through 9 ("compression level must be 0 through 9")

#### CompressWriter()

```pepper
construct(sink: io.Writer, format: Format, dictionary: u8[], level: int = 6)
```

Makes a writer that compresses into `sink`, starting from a preset
dictionary (see `Zlib.compress`). A zlib header names the dictionary
by its Adler-32; raw DEFLATE data carries no sign of it.

**Parameters**
- `sink` — the stream the compressed bytes are written to
- `format` — `Format.Zlib` or `Format.Raw`
- `dictionary` — the preset dictionary; only its last 32 KiB are used
- `level` — from 0 (store without compressing) through 9 (smallest output, slowest); 6 balances the two

**Panics**
- if `level` is not 0 through 9 ("compression level must be 0 through 9"), or if `format` is `Format.Gzip` ("gzip data has no preset dictionary")

### Methods

#### write

```pepper
write(data: u8[]): io.IoResult<ulong>
```

Compresses all of `data`.

**Parameters**
- `data` — the bytes to compress

**Returns**
- `data.count`; an error when writing to the sink fails

**Panics**
- if `finish()` was called ("CompressWriter used after finish()")

#### write_all

```pepper
write_all(data: u8[]): io.IoResult<void>
```

Compresses all of `data`.

**Parameters**
- `data` — the bytes to compress

**Returns**
- an Ok result; an error when writing to the sink fails

**Panics**
- if `finish()` was called ("CompressWriter used after finish()")

#### finish

```pepper
finish(): io.IoResult<void>
```

Compresses what is still buffered, writes the format's trailer, and
ends the stream. Later calls do nothing.

**Returns**
- an Ok result; an error when writing to the sink fails
