# Compression and archives

The `compress` module compresses and decompresses DEFLATE data, plain or
in its zlib and gzip framings, and the `archive` module reads and writes
tar archives. Together they handle `.gz` and `.tar.gz` files. Both are
written in Pepper, so a program that uses them links no extra library.

```pepper
{{#include ../../examples/compression-basics.pep}}
```

## Formats

| Format | Struct | Where it is used |
|--------|--------|------------------|
| `Format.Gzip` | `compress.Gzip` | `.gz` files, HTTP `Content-Encoding: gzip` |
| `Format.Zlib` | `compress.Zlib` | PNG images, HTTP `deflate` |
| `Format.Raw` | `compress.Deflate` | zip entries, other containers with their own framing |

- `compress(data, level = 6)` returns the compressed bytes. The level runs
  from 0 (stored, no compression) to 9 (smallest, slowest). Each level
  searches for matches with zlib's settings for it, so the output is about
  the size zlib makes at the same level, at a similar speed: on 12 MB of
  source text, compressing at level 6 takes about 1.2 times as long as the
  `gzip` command, and decompressing is a little faster than `gzip -d`
  (`benchmarks/compress/bench.py` measures it).
- `decompress(data)` returns an `io.IoResult<u8[]>`. Damaged or truncated
  data is an error whose `is_invalid_input()` holds, and gzip and zlib
  data is checked against its CRC-32 or Adler-32 checksum.
- Gzip input may hold several members one after another (`cat a.gz b.gz`);
  they decompress to their contents joined. Bytes after the last member are
  an error. A gzip header's file name and comment are skipped, and a
  written header has neither.
- A zlib stream that needs a preset dictionary is not supported.
- `decompress` puts everything in memory. Use a `DecompressReader` for
  input from outside the program, so a small file that expands hugely
  cannot exhaust memory.

`compress.Crc32` and `compress.Adler32` compute the two checksums over
data given in pieces (`update`, then `value`), or in one call with `of`.

## Streams

`compress.DecompressReader(source, format)` is an `io.Reader` that
decompresses `source`, any `io.Reader`, as it is read, so `lines()`,
`chunks(size)` and `read_all()` work on it. It holds at most about
225 KiB of input and output, however large the data.

`compress.CompressWriter(sink, format, level = 6)` is an `io.Writer` that
compresses what is written and writes the result to `sink`. Call
`finish()` at the end: it writes the last block and the checksum. Dropping
the writer does not finish it, and `finish()` does not close the sink.

`io.ByteReader(bytes)` and `io.ByteWriter()` stand in for a stream when
the data is in memory.

## Tar archives

```pepper
{{#include ../../examples/compression-tar.pep}}
```

`archive.TarReader(source)` reads an archive from any `io.Reader`;
wrap the file in a `DecompressReader` to read a `.tar.gz`.

- `next_entry()` moves to the next entry and returns its `TarEntry`:
  `path`, `kind` (`File`, `Directory`, `Symlink`, `HardLink` or `Other`),
  `size`, `mode`, `modified` (seconds since 1970) and `link_target`. It
  returns none at the end of the archive.
- The reader is an `io.Reader` of the current entry's contents: `read`,
  `read_all()`, `lines()`. Contents not read are skipped.
- It reads ustar archives with the pax and GNU extensions for long paths,
  which covers GNU tar, bsdtar, and the `.tar.gz` snapshots that `git
  archive`, GitHub, GitLab and Codeberg make.

`extract(target, strip_components = 0)` writes the rest of the archive into
the directory `target`:

- It refuses, with an `is_invalid_input()` error, an entry whose path is
  absolute or holds a `..` component, a `\` or a `:`, so an archive cannot
  write outside `target`.
- `strip_components` drops leading path components, as tar's
  `--strip-components` does. A GitHub snapshot puts everything under
  `name-version/`, which `strip_components = 1` removes.
- Files and directories are created. A hard link becomes a copy of the
  file it names. Symlinks, devices and FIFOs are skipped.
- Permission bits and modification times are not applied yet: extracted
  files get the default permissions, so a script loses its executable bit.

`archive.TarWriter(sink)` writes an archive: `append_file(path, data)`,
`append_directory(path)`, `append_symlink(path, target)`, `append(entry,
data)` for any header, and `append_stream(entry, source)` to copy
`entry.size` bytes from a stream. `finish()` writes the end marker.
Paths longer than a ustar header holds get a pax header, so none is cut
short. `.zip` archives are not supported yet.
