# Compression and archives

The `compress` module compresses and decompresses DEFLATE data, plain or
in its zlib and gzip framings, and the `archive` module reads and writes
tar archives. Together they handle `.gz` and `.tar.gz` files. Both are
written in Pepper, so a program that uses them links no extra library,
unless it is built to use zlib (see [Using zlib](#using-zlib)).

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
  `gzip` command, and decompressing is a little faster than `gzip -d`.
- `decompress(data)` returns an `io.IoResult<u8[]>`. Damaged or truncated
  data is an error whose `is_invalid_input()` holds, and gzip and zlib
  data is checked against its CRC-32 or Adler-32 checksum.
- Gzip input may hold several members one after another (`cat a.gz b.gz`);
  they decompress to their contents joined. Bytes after the last member are
  an error. A gzip header's file name and comment are skipped, and a
  written header has neither.
- A zlib stream made with a preset dictionary needs it to decompress;
  see [Preset dictionaries](#preset-dictionaries).
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

## Preset dictionaries

A short message compresses poorly, since the stream has no earlier bytes to
refer back to. A *preset dictionary* gives it some: bytes that both sides
agree on beforehand, such as the keys and common values of a JSON protocol,
which the compressed data can then copy from as if they came just before
it.

```pepper
{{#include ../../examples/compression-dictionary.pep}}
```

- `Zlib.compress(data, dictionary, level = 6)` and
  `Zlib.decompress(data, dictionary)` take one. The zlib header names the
  dictionary by its Adler-32, so `decompress` without one, or with a
  different one, is an `is_invalid_input()` error. A stream made without a
  dictionary decompresses as usual when one is given.
- `CompressWriter(sink, format, dictionary, level = 6)` and
  `DecompressReader(source, format, dictionary)` take one for
  `Format.Zlib` or `Format.Raw`. Raw DEFLATE data carries no sign of it, so
  both sides must know to use it. Gzip has no dictionary, and asking for
  one panics.
- Only the last 32 KiB of a dictionary can be referred to, since that is
  how far back DEFLATE reaches; put the most common text at its end.

## Using zlib

Building with `-D USE_ZLIB` (see [Build options](build-options.md)) makes
`compress` use zlib, the reference DEFLATE library, for compressing,
decompressing, CRC-32 and Adler-32, in place of its Pepper code:

```sh
pep-build main.pep -D USE_ZLIB -o app
```

- The API is the same, and so are the errors for damaged data, worded as
  the Pepper code words them where zlib tells the causes apart. Compressed
  output can differ byte for byte (zlib's gzip header names the operating
  system), but each side decompresses the other's.
- Linux links `-lz`, from the development package (`zlib1g-dev`,
  `zlib-devel`). macOS has zlib already. Windows has none: install it
  (`vcpkg install zlib`) and name the folder holding `zlib.lib` with `-L`
  or `PEPPER_LIBRARY_PATH`.
- zlib compresses faster than the Pepper code at the same level, and
  makes output of about the same size.

## Tar archives

```pepper
{{#include ../../examples/compression-tar.pep}}
```

`archive.TarReader(source)` reads an archive from any `io.Reader`;
wrap the file in a `DecompressReader` to read a `.tar.gz`.

- `next_entry()` moves to the next entry and returns its `TarEntry`:
  `path`, `kind` (`File`, `Directory`, `Symlink`, `HardLink` or `Other`),
  `size`, `mode`, `modified` (seconds since 1970) and `link_target`. It
  returns Empty at the end of the archive.
- The reader is an `io.Reader` of the current entry's contents: `read`,
  `read_all()`, `lines()`. Contents not read are skipped.
- It reads ustar archives with the pax and GNU extensions for long paths,
  which covers GNU tar, bsdtar, and the `.tar.gz` snapshots that `git
  archive`, GitHub, GitLab and Codeberg make.

`extract(target, strip_components = 0)` writes the rest of the archive into
the directory `target`:

- It refuses, with an `is_invalid_input()` error, an entry whose path is
  absolute or holds a `..` component, a `\` or a `:`, so an archive cannot
  write outside `target`. `archive.safe_components(path)` is that check,
  for readers of other formats: it gives the path's components, or Empty
  for an unsafe path.
- `strip_components` drops leading path components, as tar's
  `--strip-components` does. A GitHub snapshot puts everything under
  `name-version/`, which `strip_components = 1` removes.
- Files and directories are created, replacing a file already there. A
  hard link becomes a copy of the file it names. Devices and FIFOs are
  skipped.
- Each file and directory gets the entry's modification time and, on Linux
  and macOS, its permission bits less the umask, as `tar` does, so a
  script keeps its executable bit. Setuid, setgid and sticky bits are
  never applied. A directory gets its mode and time after its contents are
  written, so a read-only directory can still be filled; one that already
  existed keeps its own. Windows and WASI apply no permission bits.
- Symlinks are made after everything else, so no file is written through
  one. A link whose target is absolute or climbs out of `target` with
  `..`, or that would be made inside another symlink, is skipped. Windows,
  where making a symlink needs Developer Mode or an administrator, skips
  every symlink.

`archive.TarWriter(sink)` writes an archive: `append_file(path, data)`,
`append_directory(path)`, `append_symlink(path, target)`, `append(entry,
data)` for any header, and `append_stream(entry, source)` to copy
`entry.size` bytes from a stream. `finish()` writes the end marker.
Paths longer than a ustar header holds get a pax header, so none is cut
short.

## Zip archives

`.zip` archives are read and written by the
[zip package](https://github.com/pep-lang/pepper-zip), which builds
on `compress` and `archive`. It is a package rather than part of the
runtime because the package manager needs only `.tar.gz`; add it with
`pepper package add pep-lang/pepper-zip --name zip`.

```pepper
import zip;

main(): int {
    var writer = zip.Writer.create("bundle.zip").value();
    writer.add("version.txt", "1.0.0".bytes()).value();
    writer.finish().value();

    var archive = zip.Archive.open("bundle.zip").value();
    for (var entry in archive.entries()) {
        print($"{entry.name}: {entry.size} bytes");
    }
    archive.extract_all("out").value();
    return 0;
}
```

- It reads and writes stored and DEFLATE entries, ZIP64 (archives and
  entries past 4 GiB, more than 65,535 entries), and UTF-8 names; names in
  older archives are decoded as code page 437 (`text.CodePage437`).
- Entries compressed another way (bzip2, LZMA, zstd) or encrypted are
  listed, and reading one is an error naming the entry and the method.
- `extract_all` checks every name with `archive.safe_components` before
  writing anything, and each entry's CRC-32 as it is written.
