<!-- Generated from runtime/io/file.pep by `pep-doc reference`. Do not edit. -->

# File

Source: `runtime/io/file.pep`

## OpenOptions

```pepper
struct OpenOptions
```

Describes how `File.open_with` (or `OpenOptions.open`) opens a file:
which access it asks for, and whether the file is created or truncated.

A builder in the style of Rust's `std::fs::OpenOptions`. A new
`OpenOptions` has every option off; each setter stores its flag and
returns this same `OpenOptions`, so calls chain. The rules, checked when
the file is opened:

- At least one of `read`, `write` or `append` must be set, or opening
  fails with `is_invalid_input()`.
- `create`, `create_new` and `truncate` need `write` or `append`, or
  opening fails with `is_invalid_input()`.
- `append` implies write access, and every write goes to the current end
  of the file whatever the position; it wins over `write`.
- `create` opens an existing file as it is (combine with `truncate` to
  empty it) and creates a missing one.
- `create_new` creates the file and fails with `is_already_exists()` when
  it already exists, atomically (`O_EXCL` on POSIX, `CREATE_NEW` on
  Windows); `create` is then irrelevant.
- `truncate` empties an existing file on open.
- Without `create` or `create_new`, a missing file fails with
  `is_not_found()`.

On POSIX a created file gets mode 0666 (or the `mode` set) less the
process umask, and the descriptor is opened close-on-exec. On Windows every file is opened
sharing read, write and delete access with other openers.

**See also**
- `File.open_with`

**Example**
```pepper
var r = OpenOptions().read(true).write(true).create(true).open(Path("data.bin"));
if (r.is_err()) {
    return 1;
}
var f = r.value();
```

### Constructor

#### OpenOptions()

```pepper
construct()
```

Creates an `OpenOptions` with every option off. Set at least one of
`read`, `write` or `append` before opening.

### Methods

#### read

```pepper
read(v: bool): OpenOptions
```

Sets whether the file is opened for reading.

**Parameters**
- `v` — true to request read access

**Returns**
- this `OpenOptions`, for chaining

#### write

```pepper
write(v: bool): OpenOptions
```

Sets whether the file is opened for writing. Writes go to the
current position and overwrite what is there.

**Parameters**
- `v` — true to request write access

**Returns**
- this `OpenOptions`, for chaining

#### append

```pepper
append(v: bool): OpenOptions
```

Sets append mode: the file is opened for writing and every write
goes to the current end of the file, whatever the position (seeking
still moves the position for reads). Implies write access, and takes
precedence over `write`.

**Parameters**
- `v` — true to open in append mode

**Returns**
- this `OpenOptions`, for chaining

#### truncate

```pepper
truncate(v: bool): OpenOptions
```

Sets whether an existing file is truncated to 0 bytes when it is
opened. Requires `write` or `append`.

**Parameters**
- `v` — true to truncate an existing file

**Returns**
- this `OpenOptions`, for chaining

#### create

```pepper
create(v: bool): OpenOptions
```

Sets whether a missing file is created. An existing file is opened as
it is unless `truncate` is also set. Requires `write` or `append`.

**Parameters**
- `v` — true to create the file when it is missing

**Returns**
- this `OpenOptions`, for chaining

#### create_new

```pepper
create_new(v: bool): OpenOptions
```

Sets whether the file must be newly created: opening fails with
`is_already_exists()` when the path already exists. The check and the
creation are one atomic step. Requires `write` or `append`.

**Parameters**
- `v` — true to require that the file does not exist yet

**Returns**
- this `OpenOptions`, for chaining

#### mode

```pepper
mode(mode: Mode): OpenOptions
```

Sets the permission bits a file gets when this open creates it, so it
never exists with the default mode: on POSIX the `mode_t` bits passed
to `open`, less the process umask, as `Metadata.permissions` reports
them (493, octal 755, for `rwxr-xr-x`). An existing file keeps its
mode. Ignored on Windows and WASI; use `File.set_read_only` there.

**Parameters**
- `mode` — the permission bits for a new file; 438 (octal 666) by default

**Returns**
- this `OpenOptions`, for chaining

**Example**
```pepper
var script = OpenOptions().write(true).create_new(true).mode(493).open(Path("run.sh"));
```

#### open

```pepper
open(path: Path): IoResult<File>
```

Opens `path` with these options. The same as
`File.open_with(path, this)`.

**Parameters**
- `path` — the file to open

**Returns**
- the open `File`, positioned at the start; an error when the options break a rule (`is_invalid_input()`), the path is empty or missing (`is_not_found()`), it exists under `create_new` (`is_already_exists()`), or the system refuses (`is_permission_denied()` and others)

**See also**
- `File.open_with`

**Example**
```pepper
var log = OpenOptions().append(true).create(true).open(Path("log.txt")).value();
log.write_all("started");
```

## FileType

```pepper
enum FileType
```

The kind of a file system object, as `Metadata.file_type` and
`DirEntry.file_type` report it.

A symlink is reported as `Symlink` only where links are not followed
(`Path.symlink_metadata()` and directory listings); on Windows that is any
reparse point, junctions included, even one that points to a directory.

**See also**
- `Metadata`

**Example**
```pepper
import io;

var m = io.Path("notes.txt").metadata();
if (m.is_ok()) {
    match (m.value().file_type) {
        File => { print("a file"); }
        Directory => { print("a directory"); }
        Symlink, Other => { print("something else"); }
    }
}
```

### Cases

#### File

```pepper
File
```

A regular file. On Windows, anything that is neither a directory nor
a reparse point.

#### Directory

```pepper
Directory
```

A directory.

#### Symlink

```pepper
Symlink
```

A symbolic link itself (on Windows, any reparse point).

#### Other

```pepper
Other
```

Anything else, such as a FIFO, socket or device on POSIX.

## SeekFrom

```pepper
enum SeekFrom
```

Where `File.seek` measures its offset from, with the offset itself.

**See also**
- `File.seek`

**Example**
```pepper
var f = File.open(Path("data.bin")).value();
var length = f.seek(SeekFrom.End(0)).value();     # at the end
f.seek(SeekFrom.Start(4));                        # 4 bytes in
var at = f.seek(SeekFrom.Current(-2)).value();    # 2
```

### Cases

#### Start

```pepper
Start(offset: Offset)
```

`offset` bytes from the start of the file.

**Parameters**
- `offset` — the new position; negative is an error

#### Current

```pepper
Current(offset: Offset)
```

`offset` bytes from the current position.

**Parameters**
- `offset` — the distance to move; negative moves back

#### End

```pepper
End(offset: Offset)
```

`offset` bytes from the end of the file.

**Parameters**
- `offset` — the distance from the end; negative moves back from it

## StdStream

```pepper
enum StdStream
```

One of the process's standard streams, as `File.std_file` takes it.

**See also**
- `File.std_file`

### Cases

#### Input

```pepper
Input
```

Standard input: file descriptor 0 on POSIX, `STD_INPUT_HANDLE` on
Windows.

#### Output

```pepper
Output
```

Standard output: file descriptor 1 on POSIX, `STD_OUTPUT_HANDLE` on
Windows.

#### Error

```pepper
Error
```

Standard error: file descriptor 2 on POSIX, `STD_ERROR_HANDLE` on
Windows.

## Metadata

```pepper
struct Metadata
```

Describes a file system object: its kind, size, read-only flag,
permission bits and timestamps, as a snapshot taken when it was queried.

Returned by `File.metadata()`, `Path.metadata()` (which follows
symlinks), `Path.symlink_metadata()` (which does not) and
`DirEntry.metadata()`. The timestamps are nanoseconds since the Unix
epoch (1970-01-01 00:00:00 UTC). On POSIX the metadata comes from
`statx` (Linux) or `stat` (macOS); on Windows from
`GetFileInformationByHandle`.

**Example**
```pepper
var m = Path("notes.txt").metadata();
if (m.is_ok() && m.value().is_file) {
    var bytes = m.value().size;
}
```

### Fields

#### size

```pepper
ulong size
```

The file's length in bytes.

#### file_type

```pepper
FileType file_type
```

The kind of object: `File`, `Directory`, `Symlink` or `Other`. It
agrees with `is_file`, `is_directory` and `is_symlink`, except that a
Windows reparse point to a directory is `Symlink` with both
`is_directory` and `is_symlink` set.

#### is_file

```pepper
bool is_file
```

Whether this is a regular file. On Windows, anything that is neither
a directory nor a reparse point (symlink) counts as a file.

#### is_directory

```pepper
bool is_directory
```

Whether this is a directory.

#### is_symlink

```pepper
bool is_symlink
```

Whether this is a symbolic link itself. Only metadata that does not
follow links (`Path.symlink_metadata()`) can report one. On Windows
this is any reparse point (`FILE_ATTRIBUTE_REPARSE_POINT`), which
includes junctions.

#### read_only

```pepper
bool read_only
```

Whether the file is read-only: on POSIX, no write permission bit
(0222) is set for anyone; on Windows, `FILE_ATTRIBUTE_READONLY` is set.

#### modified

```pepper
long modified
```

The time of the last modification of the contents, in nanoseconds since the Unix epoch.

#### accessed

```pepper
long accessed
```

The time of the last access, in nanoseconds since the Unix epoch (file systems mounted with `noatime` or `relatime` update it rarely or never).

#### created

```pepper
long? created
```

The creation (birth) time, in nanoseconds since the Unix epoch; none
where the platform does not report one, such as on Linux file systems
that do not record it.

#### permissions

```pepper
Mode permissions
```

The raw permission bits: on POSIX the `mode_t` permission bits
(`mode & 07777`, for example 256 for owner read); on Windows the
`FILE_ATTRIBUTE_*` bits.

### Constructor

#### Metadata()

```pepper
construct()
```

Creates a `Metadata` with every number zero, every flag false,
`file_type` `Other` and `created` none. Metadata is normally obtained
from a query such as `File.metadata()`.

## File

```pepper
[NotCopyable( "owns an operating-system handle and cannot be copied; send its path, and open the file again on the receiving thread" )] struct File
```

An open file, or a standard stream, read and written through its
platform handle (a file descriptor on POSIX, a `HANDLE` on Windows).

Open one with `File.open` (read-only), `File.create` (write-only,
created or truncated), or `File.open_with` / `OpenOptions.open` for
anything else. The static conveniences `read_bytes`, `read_to_string`,
`write_bytes`, `write_text`, `copy`, `rename` and `remove` work on a
whole file by path.

I/O is unbuffered: each `read` and `write` is one system call. Reads and
writes start at the current position and move it forward; the `seek_*`
methods move it explicitly. A write to a standard stream first flushes
the output `print` has buffered, so the two never come out of order.

Closing: the File's destructor closes an owned handle when the last
reference to the File is released, and ignores any error. Call `close()`
to close earlier or to observe the error. The standard streams
(`stdin()`, `stdout()`, `stderr()`) are never closed by a File. Every
operation on a closed File fails with an error that none of the
`IoError` predicates identify (`EBADF` on POSIX, `ERROR_INVALID_HANDLE`
on Windows).

Errors are `IoError` values carrying the platform's code; use its
predicates (`is_not_found()`, `is_permission_denied()`, ...) to tell
kinds apart portably.

**Example**
```pepper
var f = File.create(Path("out.txt")).value();
f.write_all("hello");
f.close();
var text = File.read_to_string(Path("out.txt")).value();   # "hello"
```

### Fields

#### path

```pepper
Path path
```

The path the File was opened with; `<stdin>`, `<stdout>` or
`<stderr>` for a standard stream, and empty for a `File()` never
opened.

### Constructor

#### File()

```pepper
construct()
```

Creates a closed File that owns nothing yet: `is_open()` is false and
every I/O method fails. Use `File.open`, `File.create` or
`File.open_with` to get an open one.

### Static methods

#### open

```pepper
static open(path: Path): IoResult<File>
```

Opens an existing file for reading only. The position starts at 0.

A directory can be opened this way too, but reading it fails with
`is_is_a_directory()`.

**Parameters**
- `path` — the file to open

**Returns**
- the open `File`; an error with `is_not_found()` when the path is empty or does not exist, `is_permission_denied()` when access is refused, or another platform error

**Example**
```pepper
var r = File.open(Path("config.txt"));
if (r.is_err() && r.error().is_not_found()) {
    return 0;
}
var text = r.value().read_string();
```

#### create

```pepper
static create(path: Path): IoResult<File>
```

Opens a file for writing only, creating it if it is missing and
truncating it to 0 bytes if it exists.

On POSIX a created file gets mode 0666 less the process umask.

**Parameters**
- `path` — the file to create or truncate

**Returns**
- the open `File`, empty and positioned at 0; an error with `is_not_found()` when the path is empty or its parent directory does not exist, `is_permission_denied()` when access is refused, or another platform error (on POSIX, `is_is_a_directory()` when the path is a directory)

**Example**
```pepper
var f = File.create(Path("report.txt")).value();
f.write_all("done");
```

#### open_with

```pepper
static open_with(path: Path, options: OpenOptions): IoResult<File>
```

Opens `path` as `options` describe. `OpenOptions.open` is the same
call written as a builder.

The options are checked first, as in Rust: at least one of read,
write or append is required, and create, create_new or truncate
require write or append. The position starts at 0 (append mode
still writes at the end).

**Parameters**
- `path` — the file to open
- `options` — the access mode and creation behavior

**Returns**
- the open `File`; an error with `is_invalid_input()` when no access mode is set or create, create_new or truncate is set without write or append; `is_not_found()` when the path is empty, or the file (or a parent directory) is missing and neither create nor create_new is set; `is_already_exists()` when create_new is set and the path exists; `is_permission_denied()` when access is refused; or another platform error

**Example**
```pepper
var opts = OpenOptions().write(true).create_new(true);
var r = File.open_with(Path("lock"), opts);
if (r.is_err() && r.error().is_already_exists()) {
    return 1;
}
```

#### std_file

```pepper
static std_file(stream: StdStream, name: String): File
```

Returns a File for one of the process's standard streams. The File
does not own the handle, so neither `close()` nor the destructor
closes the stream. `stdin()`, `stdout()` and `stderr()` are the usual
way to call this.

On Windows a process without a console or redirection may get a null
handle, and the File is then not open.

**Parameters**
- `stream` — the stream
- `name` — the display name stored in the File's `path`, such as `<stdout>`

**Returns**
- a File on that stream, that does not close the stream when released

**Example**
```pepper
var err = File.std_file(StdStream.Error, "<stderr>");
err.write_all("warning");
```

#### std_file

```pepper
[Deprecated("use 'std_file' with a 'StdStream' instead")] static std_file(which: int, name: String): File
```

Deprecated: use `std_file(StdStream, String)` instead. Returns a File
for the standard stream numbered `which`, as `std_file` does for the
matching `StdStream`.

**Parameters**
- `which` — the stream: 0 for standard input, 1 for standard output, 2 for standard error
- `name` — the display name stored in the File's `path`

**Returns**
- a File on that stream; a File that is not open for any other `which`

#### stdin

```pepper
static stdin(): File
```

Returns a File reading the process's standard input. Each call
returns a new File on the same stream; the stream is never closed by
a File. A read returns 0 at end of input (on Windows, also when the
writing end of a pipe has closed).

**Returns**
- a File on standard input, named `<stdin>`

#### stdout

```pepper
static stdout(): File
```

Returns a File writing to the process's standard output. Each call
returns a new File on the same stream, and `close()` only marks that
File closed: the stream stays usable. Writes are unbuffered, and each
one first flushes what `print` has buffered, so output from `print`
and from this File comes out in program order.

**Returns**
- a File on standard output, named `<stdout>`

**Example**
```pepper
var out = File.stdout();
out.write_all("hello");
```

#### stderr

```pepper
static stderr(): File
```

Returns a File writing to the process's standard error. Each call
returns a new File on the same stream, and `close()` only marks that
File closed: the stream stays usable. Writes are unbuffered, and each
one first flushes what `print` has buffered.

**Returns**
- a File on standard error, named `<stderr>`

#### read_bytes

```pepper
static read_bytes(path: Path): IoResult<u8[]>
```

Reads the whole file at `path` into a byte array (Rust's
`fs::read`).

**Parameters**
- `path` — the file to read

**Returns**
- the file's bytes; an error as for `File.open` (such as `is_not_found()`) or `read_all`

**Example**
```pepper
var r = File.read_bytes(Path("image.png"));
if (r.is_ok()) {
    var n = r.value().count;
}
```

#### read_to_string

```pepper
static read_to_string(path: Path): IoResult<String>
```

Reads the whole file at `path` as UTF-8 text (Rust's
`fs::read_to_string`).

**Parameters**
- `path` — the file to read

**Returns**
- the file's text; an error with `is_invalid_input()` when it is not valid UTF-8, or an error as for `File.open` (such as `is_not_found()`) or `read_all`

**Example**
```pepper
var r = File.read_to_string(Path("notes.txt"));
if (r.is_err()) {
    return 1;
}
var text = r.value();
```

#### write_bytes

```pepper
static write_bytes(path: Path, data: u8[]): IoResult<void>
```

Writes `data` as the whole contents of the file at `path`, creating
it or replacing what it held (Rust's `fs::write`), then closes it.

Not atomic: the file is truncated first, so a failure part way
leaves it truncated or partly written.

**Parameters**
- `path` — the file to write
- `data` — the new contents

**Returns**
- an Ok result once the data is written and the file closed; an error as for `File.create` (such as `is_not_found()` for a missing parent directory), `write_all`, or `close`

**Example**
```pepper
var data = Array<u8>();
data.append(1 as u8);
File.write_bytes(Path("one.bin"), data);
```

#### write_text

```pepper
static write_text(path: Path, s: String): IoResult<void>
```

Writes `s` as UTF-8 as the whole contents of the file at `path`,
creating it or replacing what it held, then closes it. No newline is
added.

Not atomic: the file is truncated first, so a failure part way
leaves it truncated or partly written.

**Parameters**
- `path` — the file to write
- `s` — the new contents

**Returns**
- an Ok result once the text is written and the file closed; an error as for `File.create` (such as `is_not_found()` for a missing parent directory), `write_all`, or `close`

**Note**
- this is the design proposal's `write_to_string`; a static `write` would clash with the instance `write`

**Example**
```pepper
var r = File.write_text(Path("hello.txt"), "hello, world");
if (r.is_err()) {
    return 1;
}
```

#### copy

```pepper
static copy(from: Path, to: Path): IoResult<ulong>
```

Copies the contents of the file `from` to `to`, creating `to` or
truncating it first, in 64 KiB chunks.

Only the contents are copied: `to` keeps its own permissions and
timestamps (a new file gets the defaults of `File.create`). A failure
part way leaves `to` partly written.

**Parameters**
- `from` — the file to copy
- `to` — the destination file

**Returns**
- the number of bytes copied; `is_invalid_input()` when `from` and `to` are the same file (after resolving symlinks), which truncating `to` would empty before it was read; otherwise an error as for `File.open` on `from` (such as `is_not_found()`), `File.create` on `to`, or a read, write or close failure

**Example**
```pepper
var n = File.copy(Path("a.txt"), Path("b.txt")).value();
```

#### rename

```pepper
static rename(from: Path, to: Path): IoResult<void>
```

Renames or moves `from` to `to`, replacing an existing file at `to`
(`rename` on POSIX, `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING` on
Windows).

Works for directories too. Moving between file systems (volumes)
fails rather than copying.

**Parameters**
- `from` — the existing path
- `to` — the new path

**Returns**
- an Ok result on success; an error with `is_not_found()` when `from` (or the parent of `to`) does not exist or, on POSIX, either path is empty, `is_permission_denied()` when access is refused, or another platform error

**Example**
```pepper
File.rename(Path("draft.txt"), Path("final.txt"));
```

#### symlink

```pepper
static symlink(target: Path, link: Path): IoResult<void>
```

Creates a symbolic link at `link` that points to the file `target`
(`symlink` on POSIX, `CreateSymbolicLinkW` on Windows). Use
`Directory.symlink` for a link to a directory: Windows makes the two
kinds differently, and a file link to a directory does not open
there. POSIX makes the same link either way.

`target` is stored as given and need not exist; a relative target is
resolved against the directory that holds the link, not the current
directory. On Windows, making a symlink needs Developer Mode or an
administrator, and fails with `is_permission_denied()` otherwise.

**Parameters**
- `target` — the path the link points to
- `link` — where to create the link

**Returns**
- an Ok result once the link exists; an error with `is_already_exists()` when something is already at `link`, `is_not_found()` when its parent is missing or a path is empty, `is_permission_denied()`, or another platform error

**See also**
- `Path.read_link`

**Example**
```pepper
File.symlink(Path("app-1.2.so"), Path("lib/app.so"));
```

#### remove

```pepper
static remove(path: Path): IoResult<void>
```

Deletes the file at `path`. A symlink is removed itself, not its
target. Directories are not removed: use `Directory.remove` or
`Directory.remove_all`.

**Parameters**
- `path` — the file to delete

**Returns**
- an Ok result on success; an error with `is_not_found()` when the path does not exist (on POSIX, also when it is empty); when it is a directory, `is_is_a_directory()` on Linux and `is_permission_denied()` on macOS and Windows; `is_permission_denied()` when access is refused (on Windows also for a read-only file); or another platform error

**Example**
```pepper
var r = File.remove(Path("old.txt"));
if (r.is_err() && !r.error().is_not_found()) {
    return 1;
}
```

### Methods

#### is_open

```pepper
is_open(): bool
```

Returns whether the File holds a valid handle: true after a
successful open, false after `close()` and for a `File()` never
opened.

**Returns**
- true while the File is open

#### check_open

```pepper
check_open(): IoResult<void>
```

Checks that the File is open, for use before an operation.

**Returns**
- an Ok result when the File is open; an error with the message "file is closed" otherwise (code `EBADF` on POSIX, `ERROR_INVALID_HANDLE` on Windows; no `IoError` predicate holds)

#### read

```pepper
read(buffer: u8[], max: ulong): IoResult<ulong>
```

Reads up to `max` bytes from the current position and appends them
to `buf`, growing it; the bytes already in `buf` are kept. Advances
the position by the count read.

One system call: the read may be partial, returning fewer than `max`
bytes before the end of the file (always so for pipes and terminals),
and a single call moves at most about 2 GiB on POSIX or 1 GiB on
Windows. Loop until it returns 0 to read everything, or use
`read_all`. On POSIX an interrupted read (`EINTR`) is retried. On
failure `buffer` keeps its previous contents.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read; 0 reads nothing and returns 0

**Returns**
- the number of bytes appended, 0 at end of file; an error when the File is closed, or `is_is_a_directory()` when it is a directory, or another platform error

**Example**
```pepper
var buf = Array<u8>();
while (true) {
    var r = f.read(buf, 4096);
    if (r.is_err() || r.value() == 0) {
        break;
    }
}
```

#### read_all

```pepper
read_all(): IoResult<u8[]>
```

Reads everything from the current position to the end of the file,
in 64 KiB chunks, leaving the position at the end.

**Returns**
- a new array of the bytes read (empty at end of file); an error when the File is closed, `is_is_a_directory()` when it is a directory, or another platform error, in which case the bytes read so far are discarded

#### read_string

```pepper
read_string(): IoResult<String>
```

Reads everything from the current position to the end of the file,
as `read_all` does, and returns it as UTF-8 text.

The bytes must be strictly valid UTF-8 (RFC 3629: no overlong forms,
surrogates, or code points past U+10FFFF). A byte-order mark is kept
as part of the text.

**Returns**
- the text read (empty at end of file); an error with `is_invalid_input()` when the bytes are not valid UTF-8, or any error `read_all` returns

#### write

```pepper
write(data: u8[]): IoResult<ulong>
```

Writes bytes from `data` at the current position (or at the end, in
append mode) with a single system call, and advances the position.

The write may be partial: it can write fewer than `data.count`
bytes, and one call moves at most about 2 GiB on POSIX or 1 GiB on
Windows. Use `write_all` to write everything. On POSIX an interrupted
write (`EINTR`) is retried.

**Parameters**
- `data` — the bytes to write

**Returns**
- the number of bytes written, which may be less than `data.count`; an error when the File is closed or was not opened for writing, or another platform error

#### write_all

```pepper
write_all(data: u8[]): IoResult<void>
```

Writes all of `data`, repeating the write until every byte is
written. Advances the position by `data.count`.

If an error occurs part of `data` may already have been written.

**Parameters**
- `data` — the bytes to write

**Returns**
- an Ok result once every byte is written; an error when the File is closed or was not opened for writing, when a write makes no progress ("failed to write the whole buffer", with code `EIO` on POSIX or `ERROR_WRITE_FAULT` on Windows), or another platform error

#### write_all

```pepper
write_all(s: String): IoResult<void>
```

Writes all of the UTF-8 bytes of `s`, as `write_all` does for bytes.
No newline or terminator is added.

**Parameters**
- `s` — the text to write

**Returns**
- an Ok result once every byte is written; an error as for `write_all(u8[])`

**Example**
```pepper
var f = File.create(Path("greeting.txt")).value();
var r = f.write_all("hello, world");
if (r.is_err()) {
    return 1;
}
```

#### write_string

```pepper
[Deprecated("use 'write_all' instead", "write_all")] write_string(s: String): IoResult<void>
```

Deprecated: use `write_all` instead. Writes all of the UTF-8 bytes of
`s`, exactly like `write_all(s)`.

**Parameters**
- `s` — the text to write

**Returns**
- an Ok result once every byte is written; an error as for `write_all`

**See also**
- `write_all`

#### seek

```pepper
seek(from: SeekFrom): IoResult<Offset>
```

Moves the position as `from` says: to an offset from the start, from
the current position, or from the end of the file.

Seeking past the end is allowed; a later write there fills the gap
with zeros. A position before the start of the file is an error.
Seeking a stream that has no position (a pipe or a terminal) fails on
POSIX and has platform-defined results on Windows.

**Parameters**
- `from` — the origin and the offset from it

**Returns**
- the new position, in bytes from the start of the file; an error when the File is closed, the resulting position would be negative (on POSIX, with `is_invalid_input()`), or the stream cannot seek

**Example**
```pepper
var f = File.open(Path("data.bin")).value();
var length = f.seek(SeekFrom.End(0)).value();
f.seek(SeekFrom.Start(0));
```

#### seek_start

```pepper
seek_start(pos: Offset): IoResult<Offset>
```

Moves the position to `pos` bytes from the start of the file, like
`seek(SeekFrom.Start(pos))` without allocating the `SeekFrom`.

Seeking past the end is allowed; a later write there fills the gap
with zeros.

**Parameters**
- `pos` — the new position, in bytes from the start

**Returns**
- the new position, in bytes from the start of the file; an error as for `seek`

**See also**
- `seek`

#### seek_end

```pepper
seek_end(delta: Offset): IoResult<Offset>
```

Moves the position to `delta` bytes from the end of the file, like
`seek(SeekFrom.End(delta))`. `seek_end(0)` moves to the end and
returns the file's length.

**Parameters**
- `delta` — the offset from the end of the file, in bytes; negative moves back from the end

**Returns**
- the new position, in bytes from the start of the file; an error as for `seek`

**See also**
- `seek`

#### seek_current

```pepper
seek_current(delta: Offset): IoResult<Offset>
```

Moves the position by `delta` bytes from where it is, like
`seek(SeekFrom.Current(delta))`. `seek_current(0)` returns the
current position without moving it.

**Parameters**
- `delta` — the offset from the current position, in bytes; negative moves back

**Returns**
- the new position, in bytes from the start of the file; an error as for `seek`

**See also**
- `seek`

#### seek

```pepper
[Deprecated("use 'seek' with a 'SeekFrom' instead")] seek(offset: Offset, whence: int): IoResult<Offset>
```

Deprecated: use `seek(SeekFrom)` instead. Moves the position by
`offset` relative to the origin `whence`.

**Parameters**
- `offset` — the offset in bytes from the origin; may be negative
- `whence` — the origin: 0 the start of the file, 1 the current position, 2 the end of the file

**Returns**
- the new position, in bytes from the start of the file; an error as for `seek(SeekFrom)`, or when `whence` is not 0, 1 or 2

#### set_length

```pepper
set_length(size: ulong): IoResult<void>
```

Truncates or extends the file to exactly `size` bytes; bytes added
are zeros. The position is kept, even when it is now past the end.

The File must have been opened for writing.

**Parameters**
- `size` — the new length, in bytes

**Returns**
- an Ok result on success; an error when the File is closed, was not opened for writing, or the system refuses the size

#### set_len

```pepper
[Deprecated("use 'set_length' instead", "set_length")] set_len(size: ulong): IoResult<void>
```

Deprecated: use `set_length` instead. Truncates or extends the file to
exactly `size` bytes.

**Parameters**
- `size` — the new length, in bytes

**Returns**
- the same as `set_length(size)`

#### sync

```pepper
sync(): IoResult<void>
```

Flushes the file's contents and metadata to the storage device,
waiting until they are written (`fsync` on POSIX,
`FlushFileBuffers` on Windows). Writes are already unbuffered in the
process; this forces them out of the operating system's cache.

On Windows the File must have been opened with write access.

**Returns**
- an Ok result once the data is durable; an error when the File is closed or the device reports a failure, or another platform error

#### lock

```pepper
lock(): IoResult<void>
```

Takes an exclusive advisory lock on the whole file, waiting until no
other holder has a lock on it, shared or exclusive. Modeled on Rust's
`File::lock`.

The lock belongs to this File: another File opened on the same path
(in this process or another) contends with it, and it is released by
`unlock`, by `close`, or when the File is destroyed. Taking a lock
while this File already holds one is platform-defined, as in Rust:
POSIX converts the lock, Windows may wait forever. The lock is
advisory on POSIX (`flock(LOCK_EX)`): it binds only those who also
lock. On Windows (`LockFileEx`) it also stops other handles from
reading or writing the file while held. The wait blocks the calling
thread, also inside a task. WASI has no file locks.

**Returns**
- an Ok result once the lock is held; an error when the File is closed, on WASI, or another platform error

**See also**
- `try_lock`
- `unlock`

**Example**
```pepper
var f = OpenOptions().write(true).create(true).open(Path(".pep/fetch.lock")).value();
if (f.lock().is_ok()) {
    # ... work no other locker does at the same time ...
    f.unlock();
}
```

#### lock_shared

```pepper
lock_shared(): IoResult<void>
```

Takes a shared advisory lock on the whole file, waiting until no
other holder has an exclusive lock on it. Any number of Files can
hold a shared lock at once. Modeled on Rust's `File::lock_shared`;
otherwise as `lock` (`flock(LOCK_SH)` on POSIX, `LockFileEx` without
`LOCKFILE_EXCLUSIVE_LOCK` on Windows).

**Returns**
- an Ok result once the lock is held; an error as for `lock`

**See also**
- `lock`

#### try_lock

```pepper
try_lock(): IoResult<bool>
```

Takes an exclusive advisory lock on the whole file if no other
holder has a lock on it, without waiting. Modeled on Rust's
`File::try_lock`; otherwise as `lock`.

**Returns**
- true when the lock is now held, false when another holder has a lock on the file (Rust's `TryLockError::WouldBlock`); an error as for `lock`

**See also**
- `lock`

**Example**
```pepper
var held = f.try_lock();
if (held.is_ok() && !held.value()) {
    print("another process holds the lock\n");
}
```

#### try_lock_shared

```pepper
try_lock_shared(): IoResult<bool>
```

Takes a shared advisory lock on the whole file if no other holder
has an exclusive lock on it, without waiting. Modeled on Rust's
`File::try_lock_shared`; otherwise as `lock_shared`.

**Returns**
- true when the lock is now held, false when another holder has an exclusive lock on the file; an error as for `lock`

**See also**
- `lock_shared`

#### unlock

```pepper
unlock(): IoResult<void>
```

Releases the lock this File holds, shared or exclusive. Releasing a
File that holds none is not an error. Closing or destroying the File
releases its lock too. Modeled on Rust's `File::unlock`.

**Returns**
- an Ok result once the lock is released; an error when the File is closed, on WASI, or another platform error

**See also**
- `lock`

#### metadata

```pepper
metadata(): IoResult<Metadata>
```

Queries the metadata of the open file itself (the target, when it
was opened through a symlink): size, kind, read-only flag,
permission bits and timestamps.

**Returns**
- the file's `Metadata`; an error when the File is closed, or another platform error

**Example**
```pepper
var size = f.metadata().value().size;
```

#### set_permissions

```pepper
set_permissions(mode: Mode): IoResult<void>
```

Sets the permission bits of the open file (`fchmod` on POSIX).

`mode` holds the raw platform bits, as `Metadata.permissions` reports
them: on POSIX the `mode_t` bits `mode & 07777` (493, octal 755, for
`rwxr-xr-x`). On Windows it is the `FILE_ATTRIBUTE_*` word, and only
`FILE_ATTRIBUTE_READONLY` (1) is applied; the File needs write access
there. WASI has no permission bits, and this fails. `set_read_only`
and `set_executable` change one property portably.

**Parameters**
- `mode` — the new permission bits

**Returns**
- an Ok result once they are set; an error when the File is closed, `is_permission_denied()` when the caller does not own the file (or on Windows the File was opened without write access), or another platform error

**See also**
- `Path.set_permissions`

**Example**
```pepper
var f = File.create(Path("run.sh")).value();
f.set_permissions(493);   # octal 755: rwxr-xr-x
```

#### set_read_only

```pepper
set_read_only(read_only: bool): IoResult<void>
```

Makes the open file read-only, or writable again: the portable part
of `set_permissions`.

On POSIX, read-only clears every write bit (octal 222), and writable
sets only the owner's (octal 200), so a file never becomes writable
by group or others this way. On Windows it sets or clears
`FILE_ATTRIBUTE_READONLY`, and the File needs write access. Fails on
WASI, which has no permission bits.

**Parameters**
- `read_only` — true to make the file read-only, false to make it writable by its owner

**Returns**
- an Ok result once the file is changed; an error as for `metadata()` or `set_permissions`

**See also**
- `Metadata.read_only`

#### set_executable

```pepper
set_executable(executable: bool): IoResult<void>
```

Makes the open file executable, or not, without raw permission bits.

On POSIX, executable adds an execute bit for each class (owner, group,
others) that may read the file, as `chmod +x` does with the usual
umask; not executable clears all three. Windows has no execute bit
(an extension such as `.exe` decides) and WASI no permission bits, so
there this does nothing and succeeds.

**Parameters**
- `executable` — true to make the file executable, false to stop it

**Returns**
- an Ok result once the file is changed; an error as for `metadata()` or `set_permissions`

**Example**
```pepper
var f = File.create(Path("run.sh")).value();
f.write_all("#!/bin/sh\necho hi\n");
f.set_executable(true);
```

#### set_modified

```pepper
set_modified(time: long): IoResult<void>
```

Sets the open file's modification time, leaving its access time
alone (`futimens` on POSIX, `SetFileTime` on Windows).

On Windows the File needs write access, and the time is kept to 100
ns. A later write to the file sets its modification time again, so
call this after the last write.

**Parameters**
- `time` — the new time, in nanoseconds since the Unix epoch, as `Metadata.modified` reports it

**Returns**
- an Ok result once the time is set; an error when the File is closed, `is_permission_denied()` when the caller does not own the file (or on Windows the File was opened without write access), or another platform error

**See also**
- `Path.set_modified`

#### set_accessed

```pepper
set_accessed(time: long): IoResult<void>
```

Sets the open file's access time, leaving its modification time
alone (`futimens` on POSIX, `SetFileTime` on Windows).

On Windows the File needs write access, and the time is kept to 100
ns.

**Parameters**
- `time` — the new time, in nanoseconds since the Unix epoch, as `Metadata.accessed` reports it

**Returns**
- an Ok result once the time is set; an error as for `set_modified`

**See also**
- `Path.set_accessed`

#### close

```pepper
close(): IoResult<void>
```

Closes the File now, to observe the error the system reports (for
example a deferred write failure). Without it the destructor closes
the handle and ignores errors.

Idempotent: closing a closed File succeeds. The File counts as
closed afterwards even when closing reports an error, so the handle
is never closed twice. A standard stream is only marked closed: the
stream stays open, and `File.stdout()` and the like still work.

**Returns**
- an Ok result on success or when already closed; the platform error when closing an owned handle fails

**Example**
```pepper
var f = File.create(Path("out.bin")).value();
f.write_all("data");
if (f.close().is_err()) {
    return 1;
}
```
