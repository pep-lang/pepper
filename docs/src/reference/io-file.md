<!-- Generated from runtime/io/file.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

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

On POSIX a created file gets mode 0666 less the process umask, and the
descriptor is opened close-on-exec. On Windows every file is opened
sharing read, write and delete access with other openers.

**See also**
- `File.open_with`

**Example**
```pepper
    var r = OpenOptions().read(true).write(true).create(true).open(Path("data.bin"));
    if (r.is_err()) {
        return 1;
    }
    var f = r.Value;
```

### Fields

#### Read

```pepper
bool Read
```

Whether the file is opened for reading. Off by default.

#### Write

```pepper
bool Write
```

Whether the file is opened for writing at the current position. Off by default.

#### Append

```pepper
bool Append
```

Whether the file is opened for writing at its end only; implies write access. Off by default.

#### Truncate

```pepper
bool Truncate
```

Whether an existing file is emptied to 0 bytes when opened; needs write or append. Off by default.

#### Create

```pepper
bool Create
```

Whether a missing file is created (an existing one is opened as it is); needs write or append. Off by default.

#### CreateNew

```pepper
bool CreateNew
```

Whether the file must be newly created: opening fails if it exists (`O_EXCL` on POSIX, `CREATE_NEW` on Windows); needs write or append. Off by default.

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
OpenOptions read(bool v)
```

Sets whether the file is opened for reading.

**Parameters**
- `v` — true to request read access

**Returns**
- this `OpenOptions`, for chaining

#### write

```pepper
OpenOptions write(bool v)
```

Sets whether the file is opened for writing. Writes go to the
current position and overwrite what is there.

**Parameters**
- `v` — true to request write access

**Returns**
- this `OpenOptions`, for chaining

#### append

```pepper
OpenOptions append(bool v)
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
OpenOptions truncate(bool v)
```

Sets whether an existing file is truncated to 0 bytes when it is
opened. Requires `write` or `append`.

**Parameters**
- `v` — true to truncate an existing file

**Returns**
- this `OpenOptions`, for chaining

#### create

```pepper
OpenOptions create(bool v)
```

Sets whether a missing file is created. An existing file is opened as
it is unless `truncate` is also set. Requires `write` or `append`.

**Parameters**
- `v` — true to create the file when it is missing

**Returns**
- this `OpenOptions`, for chaining

#### create_new

```pepper
OpenOptions create_new(bool v)
```

Sets whether the file must be newly created: opening fails with
`is_already_exists()` when the path already exists. The check and the
creation are one atomic step. Requires `write` or `append`.

**Parameters**
- `v` — true to require that the file does not exist yet

**Returns**
- this `OpenOptions`, for chaining

#### open

```pepper
IoResult<File> open(Path path)
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
    var log = OpenOptions().append(true).create(true).open(Path("log.txt")).unwrap();
    log.write_string("started");
```

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
    if (m.is_ok() && m.Value.IsFile) {
        var bytes = m.Value.Size;
    }
```

### Fields

#### Size

```pepper
ulong Size
```

The file's length in bytes.

#### IsFile

```pepper
bool IsFile
```

Whether this is a regular file. On Windows, anything that is neither
a directory nor a reparse point (symlink) counts as a file.

#### IsDir

```pepper
bool IsDir
```

Whether this is a directory.

#### IsSymlink

```pepper
bool IsSymlink
```

Whether this is a symbolic link itself. Only metadata that does not
follow links (`Path.symlink_metadata()`) can report one. On Windows
this is any reparse point (`FILE_ATTRIBUTE_REPARSE_POINT`), which
includes junctions.

#### ReadOnly

```pepper
bool ReadOnly
```

Whether the file is read-only: on POSIX, no write permission bit
(0222) is set for anyone; on Windows, `FILE_ATTRIBUTE_READONLY` is set.

#### Modified

```pepper
long Modified
```

The time of the last modification of the contents, in nanoseconds since the Unix epoch.

#### Accessed

```pepper
long Accessed
```

The time of the last access, in nanoseconds since the Unix epoch (file systems mounted with `noatime` or `relatime` update it rarely or never).

#### Created

```pepper
long Created
```

The creation (birth) time, in nanoseconds since the Unix epoch; 0
where unavailable, such as on Linux file systems that do not record
one.

#### Permissions

```pepper
Mode Permissions
```

The raw permission bits: on POSIX the `mode_t` permission bits
(`mode & 07777`, for example 256 for owner read); on Windows the
`FILE_ATTRIBUTE_*` bits.

### Constructor

#### Metadata()

```pepper
construct()
```

Creates a `Metadata` with every field zero or false. Metadata is
normally obtained from a query such as `File.metadata()`.

## File

```pepper
struct File
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
methods move it explicitly.

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
    var f = File.create(Path("out.txt")).unwrap();
    f.write_string("hello");
    f.close();
    var text = File.read_to_string(Path("out.txt")).unwrap();   # "hello"
```

### Fields

#### Handle

```pepper
FileHandle Handle
```

The platform handle: a file descriptor on POSIX (-1 when closed), a
`HANDLE` on Windows (null when closed).

#### Path

```pepper
Path Path
```

The path the File was opened with; `<stdin>`, `<stdout>` or
`<stderr>` for a standard stream, and empty for a `File()` never
opened.

#### Owned

```pepper
bool Owned
```

Whether the File owns its handle and closes it. False for the
standard streams (stdin, stdout, stderr), which a File never closes.

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
static IoResult<File> open(Path path)
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
    if (r.is_err() && r.Error.is_not_found()) {
        return 0;
    }
    var text = r.Value.read_string();
```

#### create

```pepper
static IoResult<File> create(Path path)
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
    var f = File.create(Path("report.txt")).unwrap();
    f.write_string("done");
```

#### open_with

```pepper
static IoResult<File> open_with(Path path, OpenOptions options)
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
    if (r.is_err() && r.Error.is_already_exists()) {
        return 1;
    }
```

#### std_file

```pepper
static File std_file(int which, String name)
```

Returns a File for one of the process's standard streams. The File
does not own the handle, so neither `close()` nor the destructor
closes the stream. `stdin()`, `stdout()` and `stderr()` are the usual
way to call this.

On POSIX `which` is used directly as the file descriptor. On Windows
it selects `GetStdHandle(STD_INPUT_HANDLE - which)`, so only 0, 1
and 2 are meaningful there; a process without a console or
redirection may get a null handle, and the File is then not open.

**Parameters**
- `which` — the stream: 0 for standard input, 1 for standard output, 2 for standard error
- `name` — the display name stored in the File's `Path`, such as `<stdout>`

**Returns**
- a File on that stream, with `Owned` false

#### stdin

```pepper
static File stdin()
```

Returns a File reading the process's standard input. Each call
returns a new File on the same stream; the stream is never closed by
a File. A read returns 0 at end of input (on Windows, also when the
writing end of a pipe has closed).

**Returns**
- a File on standard input, named `<stdin>`

#### stdout

```pepper
static File stdout()
```

Returns a File writing to the process's standard output. Each call
returns a new File on the same stream, and `close()` only marks that
File closed: the stream stays usable. Writes are unbuffered.

**Returns**
- a File on standard output, named `<stdout>`

**Example**
```pepper
    var out = File.stdout();
    out.write_string("hello");
```

#### stderr

```pepper
static File stderr()
```

Returns a File writing to the process's standard error. Each call
returns a new File on the same stream, and `close()` only marks that
File closed: the stream stays usable. Writes are unbuffered.

**Returns**
- a File on standard error, named `<stderr>`

#### read_bytes

```pepper
static IoResult<u8[]> read_bytes(Path path)
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
        var n = r.Value.count();
    }
```

#### read_to_string

```pepper
static IoResult<String> read_to_string(Path path)
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
    var text = r.Value;
```

#### write_bytes

```pepper
static IoResult<None> write_bytes(Path path, u8[] data)
```

Writes `data` as the whole contents of the file at `path`, creating
it or replacing what it held (Rust's `fs::write`), then closes it.

Not atomic: the file is truncated first, so a failure part way
leaves it truncated or partly written.

**Parameters**
- `path` — the file to write
- `data` — the new contents

**Returns**
- `None` once the data is written and the file closed; an error as for `File.create` (such as `is_not_found()` for a missing parent directory), `write_all`, or `close`

**Example**
```pepper
    var data = Array<u8>();
    data.append(1 as u8);
    File.write_bytes(Path("one.bin"), data);
```

#### write_text

```pepper
static IoResult<None> write_text(Path path, String s)
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
- `None` once the text is written and the file closed; an error as for `File.create` (such as `is_not_found()` for a missing parent directory), `write_all`, or `close`

**Note**
- this is the design proposal's `write_to_string`, renamed because `write_string` is the instance method's name and methods do not overload

**Example**
```pepper
    var r = File.write_text(Path("hello.txt"), "hello, world");
    if (r.is_err()) {
        return 1;
    }
```

#### copy

```pepper
static IoResult<ulong> copy(Path from, Path to)
```

Copies the contents of the file `from` to `to`, creating `to` or
truncating it first, in 64 KiB chunks.

Only the contents are copied: `to` keeps its own permissions and
timestamps (a new file gets the defaults of `File.create`). A failure
part way leaves `to` partly written. `from` and `to` must be
different files: `to` is truncated before `from` is read.

**Parameters**
- `from` — the file to copy
- `to` — the destination file

**Returns**
- the number of bytes copied; an error as for `File.open` on `from` (such as `is_not_found()`), `File.create` on `to`, or a read, write or close failure

**Example**
```pepper
    var n = File.copy(Path("a.txt"), Path("b.txt")).unwrap();
```

#### rename

```pepper
static IoResult<None> rename(Path from, Path to)
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
- `None` on success; an error with `is_not_found()` when `from` (or the parent of `to`) does not exist or, on POSIX, either path is empty, `is_permission_denied()` when access is refused, or another platform error

**Example**
```pepper
    File.rename(Path("draft.txt"), Path("final.txt"));
```

#### remove

```pepper
static IoResult<None> remove(Path path)
```

Deletes the file at `path`. A symlink is removed itself, not its
target. Directories are not removed: use `Directory.remove` or
`Directory.remove_all`.

**Parameters**
- `path` — the file to delete

**Returns**
- `None` on success; an error with `is_not_found()` when the path does not exist (on POSIX, also when it is empty); when it is a directory, `is_is_a_directory()` on Linux and `is_permission_denied()` on macOS and Windows; `is_permission_denied()` when access is refused (on Windows also for a read-only file); or another platform error

**Example**
```pepper
    var r = File.remove(Path("old.txt"));
    if (r.is_err() && !r.Error.is_not_found()) {
        return 1;
    }
```

### Methods

#### is_open

```pepper
bool is_open()
```

Returns whether the File holds a valid handle: true after a
successful open, false after `close()` and for a `File()` never
opened.

**Returns**
- true while the File is open

#### check_open

```pepper
IoResult<None> check_open()
```

Checks that the File is open, for use before an operation.

**Returns**
- `None` when the File is open; an error with the message "file is closed" otherwise (code `EBADF` on POSIX, `ERROR_INVALID_HANDLE` on Windows; no `IoError` predicate holds)

#### read

```pepper
IoResult<ulong> read(u8[] buf, ulong max)
```

Reads up to `max` bytes from the current position and appends them
to `buf`, growing it; the bytes already in `buf` are kept. Advances
the position by the count read.

One system call: the read may be partial, returning fewer than `max`
bytes before the end of the file (always so for pipes and terminals),
and a single call moves at most about 2 GiB on POSIX or 1 GiB on
Windows. Loop until it returns 0 to read everything, or use
`read_all`. On POSIX an interrupted read (`EINTR`) is retried. On
failure `buf` keeps its previous contents.

**Parameters**
- `buf` — the array the bytes are appended to
- `max` — the most bytes to read; 0 reads nothing and returns 0

**Returns**
- the number of bytes appended, 0 at end of file; an error when the File is closed, or `is_is_a_directory()` when it is a directory, or another platform error

**Example**
```pepper
    var buf = Array<u8>();
    while (true) {
        var r = f.read(buf, 4096);
        if (r.is_err() || r.Value == 0) {
            break;
        }
    }
```

#### read_all

```pepper
IoResult<u8[]> read_all()
```

Reads everything from the current position to the end of the file,
in 64 KiB chunks, leaving the position at the end.

**Returns**
- a new array of the bytes read (empty at end of file); an error when the File is closed, `is_is_a_directory()` when it is a directory, or another platform error, in which case the bytes read so far are discarded

#### read_string

```pepper
IoResult<String> read_string()
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
IoResult<ulong> write(u8[] data)
```

Writes bytes from `data` at the current position (or at the end, in
append mode) with a single system call, and advances the position.

The write may be partial: it can write fewer than `data.count()`
bytes, and one call moves at most about 2 GiB on POSIX or 1 GiB on
Windows. Use `write_all` to write everything. On POSIX an interrupted
write (`EINTR`) is retried.

**Parameters**
- `data` — the bytes to write

**Returns**
- the number of bytes written, which may be less than `data.count()`; an error when the File is closed or was not opened for writing, or another platform error

#### write_all

```pepper
IoResult<None> write_all(u8[] data)
```

Writes all of `data`, repeating the write until every byte is
written. Advances the position by `data.count()`.

If an error occurs part of `data` may already have been written.

**Parameters**
- `data` — the bytes to write

**Returns**
- `None` once every byte is written; an error when the File is closed or was not opened for writing, when a write makes no progress ("failed to write the whole buffer", with code `EIO` on POSIX or `ERROR_WRITE_FAULT` on Windows), or another platform error

#### write_string

```pepper
IoResult<None> write_string(String s)
```

Writes all of the UTF-8 bytes of `s`, as `write_all` does. No newline
or terminator is added.

**Parameters**
- `s` — the text to write

**Returns**
- `None` once every byte is written; an error as for `write_all`

**Example**
```pepper
    var f = File.create(Path("greeting.txt")).unwrap();
    var r = f.write_string("hello, world");
    if (r.is_err()) {
        return 1;
    }
```

#### seek_start

```pepper
IoResult<Offset> seek_start(Offset pos)
```

Moves the position to `pos` bytes from the start of the file.

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
IoResult<Offset> seek_end(Offset delta)
```

Moves the position to `delta` bytes from the end of the file.
`seek_end(0)` moves to the end and returns the file's length.

**Parameters**
- `delta` — the offset from the end of the file, in bytes; negative moves back from the end

**Returns**
- the new position, in bytes from the start of the file; an error as for `seek`

**See also**
- `seek`

#### seek_current

```pepper
IoResult<Offset> seek_current(Offset delta)
```

Moves the position by `delta` bytes from where it is.
`seek_current(0)` returns the current position without moving it.

**Parameters**
- `delta` — the offset from the current position, in bytes; negative moves back

**Returns**
- the new position, in bytes from the start of the file; an error as for `seek`

**See also**
- `seek`

#### seek

```pepper
IoResult<Offset> seek(Offset offset, int whence)
```

Moves the position by `offset` relative to the origin `whence`.
`seek_start`, `seek_end` and `seek_current` name the three origins.

A position before the start of the file is an error. Seeking a
stream that has no position (a pipe or a terminal) fails on POSIX
and has platform-defined results on Windows.

**Parameters**
- `offset` — the offset in bytes from the origin; may be negative
- `whence` — the origin: 0 the start of the file, 1 the current position, 2 the end of the file (`SEEK_SET`, `SEEK_CUR`, `SEEK_END` on POSIX; `FILE_BEGIN`, `FILE_CURRENT`, `FILE_END` on Windows)

**Returns**
- the new position, in bytes from the start of the file; an error when the File is closed, `whence` is not 0, 1 or 2, the resulting position would be negative (on POSIX, with `is_invalid_input()`), or the stream cannot seek

#### set_len

```pepper
IoResult<None> set_len(ulong size)
```

Truncates or extends the file to exactly `size` bytes; bytes added
are zeros. The position is kept, even when it is now past the end.

The File must have been opened for writing.

**Parameters**
- `size` — the new length, in bytes

**Returns**
- `None` on success; an error when the File is closed, was not opened for writing, or the system refuses the size

#### sync

```pepper
IoResult<None> sync()
```

Flushes the file's contents and metadata to the storage device,
waiting until they are written (`fsync` on POSIX,
`FlushFileBuffers` on Windows). Writes are already unbuffered in the
process; this forces them out of the operating system's cache.

On Windows the File must have been opened with write access.

**Returns**
- `None` once the data is durable; an error when the File is closed or the device reports a failure, or another platform error

#### metadata

```pepper
IoResult<Metadata> metadata()
```

Queries the metadata of the open file itself (the target, when it
was opened through a symlink): size, kind, read-only flag,
permission bits and timestamps.

**Returns**
- the file's `Metadata`; an error when the File is closed, or another platform error

**Example**
```pepper
    var size = f.metadata().Value.Size;
```

#### close

```pepper
IoResult<None> close()
```

Closes the File now, to observe the error the system reports (for
example a deferred write failure). Without it the destructor closes
the handle and ignores errors.

Idempotent: closing a closed File succeeds. The File counts as
closed afterwards even when closing reports an error, so the handle
is never closed twice. A standard stream is only marked closed: the
stream stays open, and `File.stdout()` and the like still work.

**Returns**
- `None` on success or when already closed; the platform error when closing an owned handle fails

**Example**
```pepper
    var f = File.create(Path("out.bin")).unwrap();
    f.write_string("data");
    if (f.close().is_err()) {
        return 1;
    }
```
