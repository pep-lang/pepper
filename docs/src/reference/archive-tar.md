<!-- Generated from runtime/archive/tar.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Tar archives

`TarReader` and `TarWriter`: tar archives (POSIX ustar, with the pax and
GNU extensions for long names), read entry by entry from a stream,
extracted safely into a directory, or written.

Source: `runtime/archive/tar.pep`

## EntryKind

```pepper
enum EntryKind
```

What a tar entry is.

### Cases

#### File

```pepper
File
```

A regular file, whose contents follow the entry's header.

#### Directory

```pepper
Directory
```

A directory.

#### Symlink

```pepper
Symlink
```

A symbolic link to `TarEntry.link_target`.

#### HardLink

```pepper
HardLink
```

A hard link to the earlier entry named `TarEntry.link_target`.

#### Other

```pepper
Other
```

Anything else: a device, a FIFO, or a type this reader does not know.

## TarEntry

```pepper
struct TarEntry
```

One entry of a tar archive: its header, without its contents.

**Example**
```pepper
import archive;

var entry = archive.TarEntry("bin/run.sh", archive.EntryKind.File);
entry.mode = 493;   # octal 755: rwxr-xr-x
```

### Fields

#### path

```pepper
var path: String
```

The path in the archive, with `/` between components, as stored (a
directory's may end with `/`).

#### kind

```pepper
var kind: EntryKind
```

What the entry is.

#### size

```pepper
var size: ulong
```

The length of the contents in bytes; 0 for anything but a file.

#### mode

```pepper
var mode: uint
```

The permission bits, such as 420 (octal 644, `rw-r--r--`).

#### modified

```pepper
var modified: long
```

The modification time, in seconds since 1970-01-01 UTC.

#### link_target

```pepper
var link_target: String
```

The target of a symlink or hard link; empty otherwise.

### Constructor

#### TarEntry()

```pepper
construct(path: String = "", kind: EntryKind = EntryKind.File)
```

Makes an entry with the given path and kind, mode 420 (octal 644) for
a file and 493 (octal 755) otherwise, size 0 and modification time 0.

**Parameters**
- `path` — the path in the archive
- `kind` — what the entry is

## TarReader

```pepper
struct TarReader
```

Reads a tar archive from a stream, one entry at a time: `next_entry()`
moves to the next entry and returns its header, then `read` (it is an
`io.Reader`) reads that entry's contents. Contents not read are skipped.

It reads POSIX ustar archives and the pax (`x`) and GNU (`L`, `K`)
extensions for long paths, link targets and sizes, which is what GNU tar,
bsdtar and Git (`git archive`, and the `.tar.gz` snapshots GitHub, GitLab
and Codeberg serve) write. Global pax headers (`g`) are skipped.
Wrap the source in a `compress.DecompressReader` to read a `.tar.gz`.

**Example**
```pepper
import archive;
import compress;
import io;

var file = io.File.open(io.Path("release.tar.gz")).value();
var tar = archive.TarReader(compress.DecompressReader(file, compress.Format.Gzip));
while (true) {
    var entry = tar.next_entry().value();
    if (entry.is_empty()) {
        break;
    }
    print(entry.value().path);
}
```

### Constructor

#### TarReader()

```pepper
construct(source: io.Reader)
```

Makes a reader of the archive in `source`, before its first entry.

**Parameters**
- `source` — the stream of the archive

### Methods

#### next_entry

```pepper
next_entry(): io.IoResult<TarEntry?>
```

Moves to the next entry, skipping what is left of the current one's
contents, and returns its header.

The archive ends at two zero blocks, as tar writes, or at the end of
the stream between entries.

**Returns**
- the next entry, or none at the end of the archive; an `is_invalid_input()` error for a damaged or truncated archive, or the source's error

#### read

```pepper
read(buffer: u8[], max: ulong): io.IoResult<ulong>
```

Reads up to `max` more bytes of the current entry's contents and
appends them to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read

**Returns**
- the number of bytes appended, 0 at the end of the entry's contents (or before the first `next_entry()`); an error when the archive is truncated or the source fails

#### read_all

```pepper
read_all(): io.IoResult<u8[]>
```

Reads the rest of the current entry's contents.

**Returns**
- the bytes not read yet; an error as for `read`

#### extract

```pepper
extract(target: io.Path, strip_components: ulong = 0): io.IoResult<void>
```

Extracts the rest of the archive into the directory `target`,
creating it and any directories the entries need.

Each entry's path is checked first, so that no archive can write
outside `target`: an absolute path, a `..` component, a `\` or a `:`
(which Windows would read as a separator or a drive) is an
`is_invalid_input()` error. Files are written (replacing a file
already there) and directories created; a hard link becomes a copy of
the file it names, which must be an earlier entry. Devices and FIFOs
are skipped.

Each file and directory gets the entry's modification time and, on
Linux and macOS, its permission bits less the process umask, as
`tar` gives them by default, so a script keeps its executable bit;
the setuid, setgid and sticky bits are never applied. A directory's
mode and time are set once everything inside it is written, so a
read-only directory can still be filled. A directory that already
exists keeps its own. On Windows and WASI permission bits are not
applied.

Symlinks are made after every other entry, so no file is ever
written through one, and only when they stay inside `target`: a link
whose target is absolute or climbs out of `target` with `..`, or that
would be made inside another symlink, is skipped. Windows, where
making a symlink needs Developer Mode or an administrator, skips them
all.

**Parameters**
- `target` — the directory to extract into
- `strip_components` — how many leading path components to drop from each entry, as tar's `--strip-components` does: 1 drops the `name-version/` directory that GitHub's snapshots put everything in. An entry with no components left is skipped.

**Returns**
- an Ok result once every entry is extracted; an `is_invalid_input()` error for an unsafe path or a damaged archive, or the error of a file that could not be written

**Example**
```pepper
import archive;
import compress;
import io;

var file = io.File.open(io.Path("pepper-main.tar.gz")).value();
var tar = archive.TarReader(compress.DecompressReader(file, compress.Format.Gzip));
tar.extract(io.Path(".pep/deps/pepper"), strip_components = 1).value();
```

## TarWriter

```pepper
struct TarWriter
```

Writes a tar archive to a stream: each `append` writes one entry's
header and contents, and `finish()` writes the end-of-archive marker.

It writes POSIX ustar headers, and a pax header before an entry whose
path or link target does not fit one (a path over 100 bytes that cannot
be split at a `/` into 155 and 100), so every path is kept whole. Owner
ids are 0 and owner names empty. Wrap the sink in a
`compress.CompressWriter` to write a `.tar.gz`.

**Example**
```pepper
import archive;
import io;

var out = io.ByteWriter();
var tar = archive.TarWriter(out);
tar.append_directory("docs");
tar.append_file("docs/readme.txt", "hello\n".bytes());
tar.finish();
assert(out.bytes.count == 4 * 512 + 2 * 512, "headers, contents, end marker");
```

### Constructor

#### TarWriter()

```pepper
construct(sink: io.Writer)
```

Makes a writer of a new archive into `sink`.

**Parameters**
- `sink` — the stream the archive is written to

### Methods

#### append_file

```pepper
append_file(path: String, data: u8[], mode: uint = 420): io.IoResult<void>
```

Appends a regular file holding `data`.

**Parameters**
- `path` — the file's path in the archive, with `/` between components
- `data` — the file's contents
- `mode` — the permission bits; 420 is octal 644 (`rw-r--r--`)

**Returns**
- an Ok result; an error when writing to the sink fails

**Panics**
- if `finish()` was called ("TarWriter used after finish()")

#### append_directory

```pepper
append_directory(path: String, mode: uint = 493): io.IoResult<void>
```

Appends a directory.

**Parameters**
- `path` — the directory's path in the archive; a final `/` is added when missing
- `mode` — the permission bits; 493 is octal 755 (`rwxr-xr-x`)

**Returns**
- an Ok result; an error when writing to the sink fails

**Panics**
- if `finish()` was called ("TarWriter used after finish()")

#### append_symlink

```pepper
append_symlink(path: String, target: String): io.IoResult<void>
```

Appends a symbolic link.

**Parameters**
- `path` — the link's path in the archive
- `target` — the path the link points to

**Returns**
- an Ok result; an error when writing to the sink fails

**Panics**
- if `finish()` was called ("TarWriter used after finish()")

#### append

```pepper
append(entry: TarEntry, data: u8[]): io.IoResult<void>
```

Appends an entry with the given header and contents. The size
written is `data.count` for a file and 0 for anything else, whatever
`entry.size` holds.

**Parameters**
- `entry` — the entry's header
- `data` — the contents of a file entry; ignored for other kinds

**Returns**
- an Ok result; an error when writing to the sink fails

**Panics**
- if `finish()` was called ("TarWriter used after finish()")

#### append_stream

```pepper
append_stream(entry: TarEntry, source: io.Reader): io.IoResult<void>
```

Appends a file entry whose contents are read from `source`: exactly
`entry.size` bytes, so a large file need not be in memory.

**Parameters**
- `entry` — the entry's header; its `kind` must be `File`
- `source` — the stream holding the contents

**Returns**
- an Ok result; an error when reading or writing fails, or an `is_invalid_input()` error when `source` ends before `entry.size` bytes (the archive is then incomplete)

**Panics**
- if `finish()` was called ("TarWriter used after finish()")
- if `entry.kind` is not `File` ("append_stream needs a file entry")

**Example**
```pepper
var file = io.File.open(io.Path("big.bin")).value();
var entry = archive.TarEntry("big.bin");
entry.size = file.metadata().value().size;
tar.append_stream(entry, file);
```

#### finish

```pepper
finish(): io.IoResult<void>
```

Writes the end-of-archive marker (two zero blocks). Later calls do
nothing. It does not close the sink.

**Returns**
- an Ok result; an error when writing to the sink fails
