# OpenOptions, Metadata, File.

import async;
import text;
import "lock_posix";
import "lock_wasi";
import "lock_windows";
import "path";
import "sys_posix";
import "sys_windows";
import "types";
import "wait";

extern int fflush(void* stream);

# Rust's OpenOptions as a plain builder: each setter returns this.
## Describes how `File.open_with` (or `OpenOptions.open`) opens a file:
## which access it asks for, and whether the file is created or truncated.
##
## A builder in the style of Rust's `std::fs::OpenOptions`. A new
## `OpenOptions` has every option off; each setter stores its flag and
## returns this same `OpenOptions`, so calls chain. The rules, checked when
## the file is opened:
##
## - At least one of `read`, `write` or `append` must be set, or opening
##   fails with `is_invalid_input()`.
## - `create`, `create_new` and `truncate` need `write` or `append`, or
##   opening fails with `is_invalid_input()`.
## - `append` implies write access, and every write goes to the current end
##   of the file whatever the position; it wins over `write`.
## - `create` opens an existing file as it is (combine with `truncate` to
##   empty it) and creates a missing one.
## - `create_new` creates the file and fails with `is_already_exists()` when
##   it already exists, atomically (`O_EXCL` on POSIX, `CREATE_NEW` on
##   Windows); `create` is then irrelevant.
## - `truncate` empties an existing file on open.
## - Without `create` or `create_new`, a missing file fails with
##   `is_not_found()`.
##
## On POSIX a created file gets mode 0666 (or the `mode` set) less the
## process umask, and the descriptor is opened close-on-exec. On Windows every file is opened
## sharing read, write and delete access with other openers.
##
## @see File.open_with
## @example
##     var r = OpenOptions().read(true).write(true).create(true).open(Path("data.bin"));
##     if (r.is_err()) {
##         return 1;
##     }
##     var f = r.value();
export struct OpenOptions {
    ## Whether the file is opened for reading. Off by default.
    bool _read;
    ## Whether the file is opened for writing at the current position. Off by default.
    bool _write;
    ## Whether the file is opened for writing at its end only; implies write access. Off by default.
    bool _append;
    ## Whether an existing file is emptied to 0 bytes when opened; needs write or append. Off by default.
    bool _truncate;
    ## Whether a missing file is created (an existing one is opened as it is); needs write or append. Off by default.
    bool _create;
    ## Whether the file must be newly created: opening fails if it exists (`O_EXCL` on POSIX, `CREATE_NEW` on Windows); needs write or append. Off by default.
    bool _create_new;
    ## The permission bits a newly created file gets on POSIX, less the umask. 438 (octal 666) by default.
    Mode _mode;

    ## Creates an `OpenOptions` with every option off. Set at least one of
    ## `read`, `write` or `append` before opening.
    construct() {
        _mode = 438;  # 0666
    }

    ## Sets whether the file is opened for reading.
    ##
    ## @param v true to request read access
    ## @returns this `OpenOptions`, for chaining
    read(v: bool): OpenOptions {
        _read = v;
        return this;
    }

    ## Sets whether the file is opened for writing. Writes go to the
    ## current position and overwrite what is there.
    ##
    ## @param v true to request write access
    ## @returns this `OpenOptions`, for chaining
    write(v: bool): OpenOptions {
        _write = v;
        return this;
    }

    ## Sets append mode: the file is opened for writing and every write
    ## goes to the current end of the file, whatever the position (seeking
    ## still moves the position for reads). Implies write access, and takes
    ## precedence over `write`.
    ##
    ## @param v true to open in append mode
    ## @returns this `OpenOptions`, for chaining
    append(v: bool): OpenOptions {
        _append = v;
        return this;
    }

    ## Sets whether an existing file is truncated to 0 bytes when it is
    ## opened. Requires `write` or `append`.
    ##
    ## @param v true to truncate an existing file
    ## @returns this `OpenOptions`, for chaining
    truncate(v: bool): OpenOptions {
        _truncate = v;
        return this;
    }

    ## Sets whether a missing file is created. An existing file is opened as
    ## it is unless `truncate` is also set. Requires `write` or `append`.
    ##
    ## @param v true to create the file when it is missing
    ## @returns this `OpenOptions`, for chaining
    create(v: bool): OpenOptions {
        _create = v;
        return this;
    }

    ## Sets whether the file must be newly created: opening fails with
    ## `is_already_exists()` when the path already exists. The check and the
    ## creation are one atomic step. Requires `write` or `append`.
    ##
    ## @param v true to require that the file does not exist yet
    ## @returns this `OpenOptions`, for chaining
    create_new(v: bool): OpenOptions {
        _create_new = v;
        return this;
    }

    ## Sets the permission bits a file gets when this open creates it, so it
    ## never exists with the default mode: on POSIX the `mode_t` bits passed
    ## to `open`, less the process umask, as `Metadata.permissions` reports
    ## them (493, octal 755, for `rwxr-xr-x`). An existing file keeps its
    ## mode. Ignored on Windows and WASI; use `File.set_read_only` there.
    ##
    ## @param mode the permission bits for a new file; 438 (octal 666) by
    ##   default
    ## @returns this `OpenOptions`, for chaining
    ## @example
    ##     var script = OpenOptions().write(true).create_new(true).mode(493).open(Path("run.sh"));
    mode(mode: Mode): OpenOptions {
        _mode = mode;
        return this;
    }

    ## Opens `path` with these options. The same as
    ## `File.open_with(path, this)`.
    ##
    ## @param path the file to open
    ## @returns the open `File`, positioned at the start; an error when the
    ##   options break a rule (`is_invalid_input()`), the path is empty or
    ##   missing (`is_not_found()`), it exists under `create_new`
    ##   (`is_already_exists()`), or the system refuses
    ##   (`is_permission_denied()` and others)
    ## @see File.open_with
    ## @example
    ##     var log = OpenOptions().append(true).create(true).open(Path("log.txt")).value();
    ##     log.write_all("started");
    open(path: Path): IoResult<File> {
        return File.open_with(path, this);
    }
}

## The kind of a file system object, as `Metadata.file_type` and
## `DirEntry.file_type` report it.
##
## A symlink is reported as `Symlink` only where links are not followed
## (`Path.symlink_metadata()` and directory listings); on Windows that is any
## reparse point, junctions included, even one that points to a directory.
##
## @example
##     import io;
##
##     var m = io.Path("notes.txt").metadata();
##     if (m.is_ok()) {
##         match (m.value().file_type) {
##             File => { print("a file"); }
##             Directory => { print("a directory"); }
##             Symlink, Other => { print("something else"); }
##         }
##     }
## @see Metadata
export enum FileType {
    ## A regular file. On Windows, anything that is neither a directory nor
    ## a reparse point.
    File,
    ## A directory.
    Directory,
    ## A symbolic link itself (on Windows, any reparse point).
    Symlink,
    ## Anything else, such as a FIFO, socket or device on POSIX.
    Other,
}

## Where `File.seek` measures its offset from, with the offset itself.
##
## @example
##     var f = File.open(Path("data.bin")).value();
##     var length = f.seek(SeekFrom.End(0)).value();     # at the end
##     f.seek(SeekFrom.Start(4));                        # 4 bytes in
##     var at = f.seek(SeekFrom.Current(-2)).value();    # 2
## @see File.seek
export enum SeekFrom {
    ## `offset` bytes from the start of the file.
    ##
    ## @param offset the new position; negative is an error
    Start(offset: Offset),
    ## `offset` bytes from the current position.
    ##
    ## @param offset the distance to move; negative moves back
    Current(offset: Offset),
    ## `offset` bytes from the end of the file.
    ##
    ## @param offset the distance from the end; negative moves back from it
    End(offset: Offset),
}

## One of the process's standard streams, as `File.std_file` takes it.
##
## @see File.std_file
export enum StdStream {
    ## Standard input: file descriptor 0 on POSIX, `STD_INPUT_HANDLE` on
    ## Windows.
    Input,
    ## Standard output: file descriptor 1 on POSIX, `STD_OUTPUT_HANDLE` on
    ## Windows.
    Output,
    ## Standard error: file descriptor 2 on POSIX, `STD_ERROR_HANDLE` on
    ## Windows.
    Error,
}

## Describes a file system object: its kind, size, read-only flag,
## permission bits and timestamps, as a snapshot taken when it was queried.
##
## Returned by `File.metadata()`, `Path.metadata()` (which follows
## symlinks), `Path.symlink_metadata()` (which does not) and
## `DirEntry.metadata()`. The timestamps are nanoseconds since the Unix
## epoch (1970-01-01 00:00:00 UTC). On POSIX the metadata comes from
## `statx` (Linux) or `stat` (macOS); on Windows from
## `GetFileInformationByHandle`.
##
## @example
##     var m = Path("notes.txt").metadata();
##     if (m.is_ok() && m.value().is_file) {
##         var bytes = m.value().size;
##     }
export struct Metadata {
    ## The file's length in bytes.
    ulong size;
    ## The kind of object: `File`, `Directory`, `Symlink` or `Other`. It
    ## agrees with `is_file`, `is_directory` and `is_symlink`, except that a
    ## Windows reparse point to a directory is `Symlink` with both
    ## `is_directory` and `is_symlink` set.
    FileType file_type;
    ## Whether this is a regular file. On Windows, anything that is neither
    ## a directory nor a reparse point (symlink) counts as a file.
    bool is_file;
    ## Whether this is a directory.
    bool is_directory;
    ## Whether this is a symbolic link itself. Only metadata that does not
    ## follow links (`Path.symlink_metadata()`) can report one. On Windows
    ## this is any reparse point (`FILE_ATTRIBUTE_REPARSE_POINT`), which
    ## includes junctions.
    bool is_symlink;
    ## Whether the file is read-only: on POSIX, no write permission bit
    ## (0222) is set for anyone; on Windows, `FILE_ATTRIBUTE_READONLY` is set.
    bool read_only;
    ## The time of the last modification of the contents, in nanoseconds since the Unix epoch.
    long modified;
    ## The time of the last access, in nanoseconds since the Unix epoch (file systems mounted with `noatime` or `relatime` update it rarely or never).
    long accessed;
    ## The creation (birth) time, in nanoseconds since the Unix epoch; none
    ## where the platform does not report one, such as on Linux file systems
    ## that do not record it.
    long? created;
    ## The raw permission bits: on POSIX the `mode_t` permission bits
    ## (`mode & 07777`, for example 256 for owner read); on Windows the
    ## `FILE_ATTRIBUTE_*` bits.
    Mode permissions;

    ## Creates a `Metadata` with every number zero, every flag false,
    ## `file_type` `Other` and `created` none. Metadata is normally obtained
    ## from a query such as `File.metadata()`.
    construct() {
        file_type = FileType.Other;
    }
}

# The FileType of an object with these kind flags; a symlink wins over the
# directory flag Windows also sets for a link to a directory.
_io_file_type(is_file: bool, is_directory: bool, is_symlink: bool): FileType {
    if (is_symlink) {
        return FileType.Symlink;
    }
    if (is_directory) {
        return FileType.Directory;
    }
    if (is_file) {
        return FileType.File;
    }
    return FileType.Other;
}

# Bytes per read when a whole file or stream is read.
_io_chunk_size(): ulong {
    return 65536;
}

# Write all `n` bytes at `p`, looping over partial writes.
_io_write_all_raw(h: FileHandle, p: __ptr<u8>, n: ulong): IoResult<void> {
    ulong done = 0;
    while (done < n) {
        var r = _io_file_transfer(h, p + done, n - done, true);
        if (r.is_err()) {
            return IoResult<void>.err(r.error());
        }
        if (r.value() == 0) {
            return IoResult<void>.err(IoError(_io_sys_code_write_zero(), "failed to write the whole buffer"));
        }
        done = done + r.value();
    }
    return _io_ok_void();
}

## An open file, or a standard stream, read and written through its
## platform handle (a file descriptor on POSIX, a `HANDLE` on Windows).
##
## Open one with `File.open` (read-only), `File.create` (write-only,
## created or truncated), or `File.open_with` / `OpenOptions.open` for
## anything else. The static conveniences `read_bytes`, `read_to_string`,
## `write_bytes`, `write_text`, `copy`, `rename` and `remove` work on a
## whole file by path.
##
## I/O is unbuffered: each `read` and `write` is one system call. Reads and
## writes start at the current position and move it forward; the `seek_*`
## methods move it explicitly. A write to a standard stream first flushes
## the output `print` has buffered, so the two never come out of order.
##
## Closing: the File's destructor closes an owned handle when the last
## reference to the File is released, and ignores any error. Call `close()`
## to close earlier or to observe the error. The standard streams
## (`stdin()`, `stdout()`, `stderr()`) are never closed by a File. Every
## operation on a closed File fails with an error that none of the
## `IoError` predicates identify (`EBADF` on POSIX, `ERROR_INVALID_HANDLE`
## on Windows).
##
## Errors are `IoError` values carrying the platform's code; use its
## predicates (`is_not_found()`, `is_permission_denied()`, ...) to tell
## kinds apart portably.
##
## @example
##     var f = File.create(Path("out.txt")).value();
##     f.write_all("hello");
##     f.close();
##     var text = File.read_to_string(Path("out.txt")).value();   # "hello"
[NotCopyable(
    "owns an operating-system handle and cannot be copied; send its path, and open the file again on the receiving thread"
)]
export struct File {
    ## The platform handle: a file descriptor on POSIX (-1 when closed), a
    ## `HANDLE` on Windows (null when closed).
    FileHandle _handle;
    ## The path the File was opened with; `<stdin>`, `<stdout>` or
    ## `<stderr>` for a standard stream, and empty for a `File()` never
    ## opened.
    Path path;
    ## Whether the File owns its handle and closes it. False for the
    ## standard streams (stdin, stdout, stderr), which a File never closes.
    bool _owned;

    ## Creates a closed File that owns nothing yet: `is_open()` is false and
    ## every I/O method fails. Use `File.open`, `File.create` or
    ## `File.open_with` to get an open one.
    construct() {
        _handle = _io_sys_invalid_handle();
        _owned = true;
    }

    ## Closes the handle if it is still open and owned when the last
    ## reference goes. Errors from closing are ignored; call `close()` to
    ## see them.
    destruct {
        if (_owned && _io_sys_handle_valid(_handle)) {
            _io_sys_close(_handle);
        }
    }

    ## Opens an existing file for reading only. The position starts at 0.
    ##
    ## A directory can be opened this way too, but reading it fails with
    ## `is_is_a_directory()`.
    ##
    ## @param path the file to open
    ## @returns the open `File`; an error with `is_not_found()` when the path
    ##   is empty or does not exist, `is_permission_denied()` when access is
    ##   refused, or another platform error
    ## @example
    ##     var r = File.open(Path("config.txt"));
    ##     if (r.is_err() && r.error().is_not_found()) {
    ##         return 0;
    ##     }
    ##     var text = r.value().read_string();
    static open(path: Path): IoResult<File> {
        return open_with(path, OpenOptions().read(true));
    }

    ## Opens a file for writing only, creating it if it is missing and
    ## truncating it to 0 bytes if it exists.
    ##
    ## On POSIX a created file gets mode 0666 less the process umask.
    ##
    ## @param path the file to create or truncate
    ## @returns the open `File`, empty and positioned at 0; an error with
    ##   `is_not_found()` when the path is empty or its parent directory does
    ##   not exist, `is_permission_denied()` when access is refused, or
    ##   another platform error (on POSIX, `is_is_a_directory()` when the path
    ##   is a directory)
    ## @example
    ##     var f = File.create(Path("report.txt")).value();
    ##     f.write_all("done");
    static create(path: Path): IoResult<File> {
        return open_with(path, OpenOptions().write(true).create(true).truncate(true));
    }

    ## Opens `path` as `options` describe. `OpenOptions.open` is the same
    ## call written as a builder.
    ##
    ## The options are checked first, as in Rust: at least one of read,
    ## write or append is required, and create, create_new or truncate
    ## require write or append. The position starts at 0 (append mode
    ## still writes at the end).
    ##
    ## @param path the file to open
    ## @param options the access mode and creation behavior
    ## @returns the open `File`; an error with `is_invalid_input()` when no
    ##   access mode is set or create, create_new or truncate is set without
    ##   write or append; `is_not_found()` when the path is empty, or the file
    ##   (or a parent directory) is missing and neither create nor create_new
    ##   is set; `is_already_exists()` when create_new is set and the path
    ##   exists; `is_permission_denied()` when access is refused; or another
    ##   platform error
    ## @example
    ##     var opts = OpenOptions().write(true).create_new(true);
    ##     var r = File.open_with(Path("lock"), opts);
    ##     if (r.is_err() && r.error().is_already_exists()) {
    ##         return 1;
    ##     }
    static open_with(path: Path, options: OpenOptions): IoResult<File> {
        # As Rust: some access is required, and creating or truncating needs
        # write access.
        var writes = options._write || options._append;
        if (!options._read && !writes) {
            return IoResult<File>.err(
                IoError(_io_sys_code_invalid_input(), "no access mode: set read, write or append")
            );
        }
        if ((options._create || options._create_new || options._truncate) && !writes) {
            return IoResult<File>.err(
                IoError(_io_sys_code_invalid_input(), "create and truncate need write or append")
            );
        }
        if (path._value.size == 0) {
            return IoResult<File>.err(IoError(_io_sys_code_not_found(), "empty path"));
        }
        var h = _io_sys_open(path, options);
        if (h.is_err()) {
            return IoResult<File>.err(h.error());
        }
        var f = File();
        f._handle = h.value();
        f.path = path;
        return IoResult<File>.ok(f);
    }

    ## Returns a File for one of the process's standard streams. The File
    ## does not own the handle, so neither `close()` nor the destructor
    ## closes the stream. `stdin()`, `stdout()` and `stderr()` are the usual
    ## way to call this.
    ##
    ## On Windows a process without a console or redirection may get a null
    ## handle, and the File is then not open.
    ##
    ## @param stream the stream
    ## @param name the display name stored in the File's `path`, such as
    ##   `<stdout>`
    ## @returns a File on that stream, that does not close the stream when released
    ## @example
    ##     var err = File.std_file(StdStream.Error, "<stderr>");
    ##     err.write_all("warning");
    static std_file(stream: StdStream, name: String): File {
        var f = File();
        f._handle = _io_sys_std_handle(stream);
        f.path = Path(name);
        f._owned = false;
        return f;
    }

    ## Deprecated: use `std_file(StdStream, String)` instead. Returns a File
    ## for the standard stream numbered `which`, as `std_file` does for the
    ## matching `StdStream`.
    ##
    ## @param which the stream: 0 for standard input, 1 for standard
    ##   output, 2 for standard error
    ## @param name the display name stored in the File's `path`
    ## @returns a File on that stream; a File that is not open for any other
    ##   `which`
    [Deprecated("use 'std_file' with a 'StdStream' instead")]
    static std_file(which: int, name: String): File {
        return match (which) {
            0 => std_file(StdStream.Input, name),
            1 => std_file(StdStream.Output, name),
            2 => std_file(StdStream.Error, name),
            else => File(),
        };
    }

    ## Returns a File reading the process's standard input. Each call
    ## returns a new File on the same stream; the stream is never closed by
    ## a File. A read returns 0 at end of input (on Windows, also when the
    ## writing end of a pipe has closed).
    ##
    ## @returns a File on standard input, named `<stdin>`
    static stdin(): File {
        return std_file(StdStream.Input, "<stdin>");
    }

    ## Returns a File writing to the process's standard output. Each call
    ## returns a new File on the same stream, and `close()` only marks that
    ## File closed: the stream stays usable. Writes are unbuffered, and each
    ## one first flushes what `print` has buffered, so output from `print`
    ## and from this File comes out in program order.
    ##
    ## @returns a File on standard output, named `<stdout>`
    ## @example
    ##     var out = File.stdout();
    ##     out.write_all("hello");
    static stdout(): File {
        return std_file(StdStream.Output, "<stdout>");
    }

    ## Returns a File writing to the process's standard error. Each call
    ## returns a new File on the same stream, and `close()` only marks that
    ## File closed: the stream stays usable. Writes are unbuffered, and each
    ## one first flushes what `print` has buffered.
    ##
    ## @returns a File on standard error, named `<stderr>`
    static stderr(): File {
        return std_file(StdStream.Error, "<stderr>");
    }

    ## Returns whether the File holds a valid handle: true after a
    ## successful open, false after `close()` and for a `File()` never
    ## opened.
    ##
    ## @returns true while the File is open
    is_open(): bool {
        return _io_sys_handle_valid(_handle);
    }

    ## Checks that the File is open, for use before an operation.
    ##
    ## @returns an Ok result when the File is open; an error with the message
    ##   "file is closed" otherwise (code `EBADF` on POSIX,
    ##   `ERROR_INVALID_HANDLE` on Windows; no `IoError` predicate holds)
    check_open(): IoResult<void> {
        if (!_io_sys_handle_valid(_handle)) {
            return IoResult<void>.err(IoError(_io_sys_code_bad_handle(), "file is closed"));
        }
        return _io_ok_void();
    }

    # Before writing to a stream the File does not own (a standard stream),
    # flush C stdio, where `print` buffers its output, so text printed
    # earlier reaches the stream before these bytes.
    _check_writable(): IoResult<void> {
        var c = check_open();
        if (c.is_ok() && !_owned) {
            fflush(__null);
        }
        return c;
    }

    ## Reads up to `max` bytes from the current position and appends them
    ## to `buf`, growing it; the bytes already in `buf` are kept. Advances
    ## the position by the count read.
    ##
    ## One system call: the read may be partial, returning fewer than `max`
    ## bytes before the end of the file (always so for pipes and terminals),
    ## and a single call moves at most about 2 GiB on POSIX or 1 GiB on
    ## Windows. Loop until it returns 0 to read everything, or use
    ## `read_all`. On POSIX an interrupted read (`EINTR`) is retried. On
    ## failure `buffer` keeps its previous contents.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read; 0 reads nothing and returns 0
    ## @returns the number of bytes appended, 0 at end of file; an error when
    ##   the File is closed, or `is_is_a_directory()` when it is a directory,
    ##   or another platform error
    ## @example
    ##     var buf = Array<u8>();
    ##     while (true) {
    ##         var r = f.read(buf, 4096);
    ##         if (r.is_err() || r.value() == 0) {
    ##             break;
    ##         }
    ##     }
    read(buffer: u8[], max: ulong): IoResult<ulong> {
        var c = check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        if (max == 0) {
            return IoResult<ulong>.ok(0);
        }
        buffer.reserve(buffer._size + max);
        buffer._pins = buffer._pins + 1;
        var r = _io_file_transfer(_handle, buffer._data + buffer._size, max, false);
        buffer._pins = buffer._pins - 1;
        if (r.is_ok()) {
            buffer._size = buffer._size + r.value();
        }
        return r;
    }

    ## Reads everything from the current position to the end of the file,
    ## in 64 KiB chunks, leaving the position at the end.
    ##
    ## @returns a new array of the bytes read (empty at end of file); an
    ##   error when the File is closed, `is_is_a_directory()` when it is a
    ##   directory, or another platform error, in which case the bytes read
    ##   so far are discarded
    read_all(): IoResult<u8[]> {
        var buf = Array<u8>();
        while (true) {
            var r = read(buf, _io_chunk_size());
            if (r.is_err()) {
                return IoResult<u8[]>.err(r.error());
            }
            if (r.value() == 0) {
                break;
            }
        }
        return IoResult<u8[]>.ok(buf);
    }

    ## Reads everything from the current position to the end of the file,
    ## as `read_all` does, and returns it as UTF-8 text.
    ##
    ## The bytes must be strictly valid UTF-8 (RFC 3629: no overlong forms,
    ## surrogates, or code points past U+10FFFF). A byte-order mark is kept
    ## as part of the text.
    ##
    ## @returns the text read (empty at end of file); an error with
    ##   `is_invalid_input()` when the bytes are not valid UTF-8, or any error
    ##   `read_all` returns
    read_string(): IoResult<String> {
        var r = read_all();
        if (r.is_err()) {
            return IoResult<String>.err(r.error());
        }
        var decoded = text.Utf8.decode(r.value());
        if (decoded.is_empty()) {
            return IoResult<String>.err(IoError(_io_sys_code_invalid_input(), "stream did not contain valid UTF-8"));
        }
        return IoResult<String>.ok(decoded.value());
    }

    ## Writes bytes from `data` at the current position (or at the end, in
    ## append mode) with a single system call, and advances the position.
    ##
    ## The write may be partial: it can write fewer than `data.count`
    ## bytes, and one call moves at most about 2 GiB on POSIX or 1 GiB on
    ## Windows. Use `write_all` to write everything. On POSIX an interrupted
    ## write (`EINTR`) is retried.
    ##
    ## @param data the bytes to write
    ## @returns the number of bytes written, which may be less than
    ##   `data.count`; an error when the File is closed or was not opened
    ##   for writing, or another platform error
    write(data: u8[]): IoResult<ulong> {
        var c = _check_writable();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        data._pins = data._pins + 1;
        var r = _io_file_transfer(_handle, data._data, data._size, true);
        data._pins = data._pins - 1;
        return r;
    }

    ## Writes all of `data`, repeating the write until every byte is
    ## written. Advances the position by `data.count`.
    ##
    ## If an error occurs part of `data` may already have been written.
    ##
    ## @param data the bytes to write
    ## @returns an Ok result once every byte is written; an error when the File is
    ##   closed or was not opened for writing, when a write makes no
    ##   progress ("failed to write the whole buffer", with code `EIO` on
    ##   POSIX or `ERROR_WRITE_FAULT` on Windows), or another platform error
    write_all(data: u8[]): IoResult<void> {
        var c = _check_writable();
        if (c.is_err()) {
            return c;
        }
        data._pins = data._pins + 1;
        var r = _io_write_all_raw(_handle, data._data, data._size);
        data._pins = data._pins - 1;
        return r;
    }

    ## Writes all of the UTF-8 bytes of `s`, as `write_all` does for bytes.
    ## No newline or terminator is added.
    ##
    ## @param s the text to write
    ## @returns an Ok result once every byte is written; an error as for
    ##   `write_all(u8[])`
    ## @example
    ##     var f = File.create(Path("greeting.txt")).value();
    ##     var r = f.write_all("hello, world");
    ##     if (r.is_err()) {
    ##         return 1;
    ##     }
    write_all(s: String): IoResult<void> {
        var c = _check_writable();
        if (c.is_err()) {
            return c;
        }
        if (!_io_in_task()) {
            return _io_write_all_raw(_handle, unsafe_cast<__ptr<u8>>(s.c_str()), s.size);
        }
        # Another task could change `s` while the write waits, so write a
        # copy.
        var bytes = _io_text_copy(s);
        var r = _io_write_all_raw(_handle, bytes, s.size);
        _pep_free(bytes);
        return r;
    }

    ## Deprecated: use `write_all` instead. Writes all of the UTF-8 bytes of
    ## `s`, exactly like `write_all(s)`.
    ##
    ## @param s the text to write
    ## @returns an Ok result once every byte is written; an error as for `write_all`
    ## @see write_all
    [Deprecated("use 'write_all' instead", "write_all")]
    write_string(s: String): IoResult<void> {
        return write_all(s);
    }

    ## Moves the position as `from` says: to an offset from the start, from
    ## the current position, or from the end of the file.
    ##
    ## Seeking past the end is allowed; a later write there fills the gap
    ## with zeros. A position before the start of the file is an error.
    ## Seeking a stream that has no position (a pipe or a terminal) fails on
    ## POSIX and has platform-defined results on Windows.
    ##
    ## @param from the origin and the offset from it
    ## @returns the new position, in bytes from the start of the file; an
    ##   error when the File is closed, the resulting position would be
    ##   negative (on POSIX, with `is_invalid_input()`), or the stream cannot
    ##   seek
    ## @example
    ##     var f = File.open(Path("data.bin")).value();
    ##     var length = f.seek(SeekFrom.End(0)).value();
    ##     f.seek(SeekFrom.Start(0));
    seek(from: SeekFrom): IoResult<Offset> {
        return match (from) {
            Start(offset) => _seek(offset, 0),
            Current(offset) => _seek(offset, 1),
            End(offset) => _seek(offset, 2),
        };
    }

    ## Moves the position to `pos` bytes from the start of the file, like
    ## `seek(SeekFrom.Start(pos))` without allocating the `SeekFrom`.
    ##
    ## Seeking past the end is allowed; a later write there fills the gap
    ## with zeros.
    ##
    ## @param pos the new position, in bytes from the start
    ## @returns the new position, in bytes from the start of the file; an
    ##   error as for `seek`
    ## @see seek
    seek_start(pos: Offset): IoResult<Offset> {
        return _seek(pos, 0);
    }

    ## Moves the position to `delta` bytes from the end of the file, like
    ## `seek(SeekFrom.End(delta))`. `seek_end(0)` moves to the end and
    ## returns the file's length.
    ##
    ## @param delta the offset from the end of the file, in bytes; negative
    ##   moves back from the end
    ## @returns the new position, in bytes from the start of the file; an
    ##   error as for `seek`
    ## @see seek
    seek_end(delta: Offset): IoResult<Offset> {
        return _seek(delta, 2);
    }

    ## Moves the position by `delta` bytes from where it is, like
    ## `seek(SeekFrom.Current(delta))`. `seek_current(0)` returns the
    ## current position without moving it.
    ##
    ## @param delta the offset from the current position, in bytes; negative
    ##   moves back
    ## @returns the new position, in bytes from the start of the file; an
    ##   error as for `seek`
    ## @see seek
    seek_current(delta: Offset): IoResult<Offset> {
        return _seek(delta, 1);
    }

    ## Deprecated: use `seek(SeekFrom)` instead. Moves the position by
    ## `offset` relative to the origin `whence`.
    ##
    ## @param offset the offset in bytes from the origin; may be negative
    ## @param whence the origin: 0 the start of the file, 1 the current
    ##   position, 2 the end of the file
    ## @returns the new position, in bytes from the start of the file; an
    ##   error as for `seek(SeekFrom)`, or when `whence` is not 0, 1 or 2
    [Deprecated("use 'seek' with a 'SeekFrom' instead")]
    seek(offset: Offset, whence: int): IoResult<Offset> {
        return _seek(offset, whence);
    }

    # whence: 0 the start, 1 the current position, 2 the end (the POSIX
    # SEEK_* values, which Windows' FILE_* origins share).
    _seek(offset: Offset, whence: int): IoResult<Offset> {
        var c = check_open();
        if (c.is_err()) {
            return IoResult<Offset>.err(c.error());
        }
        return _io_sys_seek(_handle, offset, whence);
    }

    ## Truncates or extends the file to exactly `size` bytes; bytes added
    ## are zeros. The position is kept, even when it is now past the end.
    ##
    ## The File must have been opened for writing.
    ##
    ## @param size the new length, in bytes
    ## @returns an Ok result on success; an error when the File is closed, was not
    ##   opened for writing, or the system refuses the size
    set_length(size: ulong): IoResult<void> {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_truncate(_handle, size);
    }

    ## Deprecated: use `set_length` instead. Truncates or extends the file to
    ## exactly `size` bytes.
    ##
    ## @param size the new length, in bytes
    ## @returns the same as `set_length(size)`
    [Deprecated("use 'set_length' instead", "set_length")]
    set_len(size: ulong): IoResult<void> {
        return set_length(size);
    }

    ## Flushes the file's contents and metadata to the storage device,
    ## waiting until they are written (`fsync` on POSIX,
    ## `FlushFileBuffers` on Windows). Writes are already unbuffered in the
    ## process; this forces them out of the operating system's cache.
    ##
    ## On Windows the File must have been opened with write access.
    ##
    ## @returns an Ok result once the data is durable; an error when the File is
    ##   closed or the device reports a failure, or another platform error
    sync(): IoResult<void> {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_sync(_handle);
    }

    ## Takes an exclusive advisory lock on the whole file, waiting until no
    ## other holder has a lock on it, shared or exclusive. Modeled on Rust's
    ## `File::lock`.
    ##
    ## The lock belongs to this File: another File opened on the same path
    ## (in this process or another) contends with it, and it is released by
    ## `unlock`, by `close`, or when the File is destroyed. Taking a lock
    ## while this File already holds one is platform-defined, as in Rust:
    ## POSIX converts the lock, Windows may wait forever. The lock is
    ## advisory on POSIX (`flock(LOCK_EX)`): it binds only those who also
    ## lock. On Windows (`LockFileEx`) it also stops other handles from
    ## reading or writing the file while held. The wait blocks the calling
    ## thread, also inside a task. WASI has no file locks.
    ##
    ## @returns an Ok result once the lock is held; an error when the File
    ##   is closed, on WASI, or another platform error
    ## @see try_lock
    ## @see unlock
    ## @example
    ##     var f = OpenOptions().write(true).create(true).open(Path(".pep/fetch.lock")).value();
    ##     if (f.lock().is_ok()) {
    ##         # ... work no other locker does at the same time ...
    ##         f.unlock();
    ##     }
    lock(): IoResult<void> {
        return _lock(true);
    }

    ## Takes a shared advisory lock on the whole file, waiting until no
    ## other holder has an exclusive lock on it. Any number of Files can
    ## hold a shared lock at once. Modeled on Rust's `File::lock_shared`;
    ## otherwise as `lock` (`flock(LOCK_SH)` on POSIX, `LockFileEx` without
    ## `LOCKFILE_EXCLUSIVE_LOCK` on Windows).
    ##
    ## @returns an Ok result once the lock is held; an error as for `lock`
    ## @see lock
    lock_shared(): IoResult<void> {
        return _lock(false);
    }

    ## Takes an exclusive advisory lock on the whole file if no other
    ## holder has a lock on it, without waiting. Modeled on Rust's
    ## `File::try_lock`; otherwise as `lock`.
    ##
    ## @returns true when the lock is now held, false when another holder
    ##   has a lock on the file (Rust's `TryLockError::WouldBlock`); an error
    ##   as for `lock`
    ## @see lock
    ## @example
    ##     var held = f.try_lock();
    ##     if (held.is_ok() && !held.value()) {
    ##         print("another process holds the lock\n");
    ##     }
    try_lock(): IoResult<bool> {
        return _try_lock(true);
    }

    ## Takes a shared advisory lock on the whole file if no other holder
    ## has an exclusive lock on it, without waiting. Modeled on Rust's
    ## `File::try_lock_shared`; otherwise as `lock_shared`.
    ##
    ## @returns true when the lock is now held, false when another holder
    ##   has an exclusive lock on the file; an error as for `lock`
    ## @see lock_shared
    try_lock_shared(): IoResult<bool> {
        return _try_lock(false);
    }

    ## Releases the lock this File holds, shared or exclusive. Releasing a
    ## File that holds none is not an error. Closing or destroying the File
    ## releases its lock too. Modeled on Rust's `File::unlock`.
    ##
    ## @returns an Ok result once the lock is released; an error when the
    ##   File is closed, on WASI, or another platform error
    ## @see lock
    unlock(): IoResult<void> {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_unlock(_handle);
    }

    _lock(exclusive: bool): IoResult<void> {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        var r = _io_sys_lock(_handle, exclusive, true);
        if (r.is_err()) {
            return IoResult<void>.err(r.error());
        }
        return _io_ok_void();
    }

    _try_lock(exclusive: bool): IoResult<bool> {
        var c = check_open();
        if (c.is_err()) {
            return IoResult<bool>.err(c.error());
        }
        return _io_sys_lock(_handle, exclusive, false);
    }

    ## Queries the metadata of the open file itself (the target, when it
    ## was opened through a symlink): size, kind, read-only flag,
    ## permission bits and timestamps.
    ##
    ## @returns the file's `Metadata`; an error when the File is closed, or
    ##   another platform error
    ## @example
    ##     var size = f.metadata().value().size;
    metadata(): IoResult<Metadata> {
        var c = check_open();
        if (c.is_err()) {
            return IoResult<Metadata>.err(c.error());
        }
        return _io_sys_fstat(_handle);
    }

    ## Sets the permission bits of the open file (`fchmod` on POSIX).
    ##
    ## `mode` holds the raw platform bits, as `Metadata.permissions` reports
    ## them: on POSIX the `mode_t` bits `mode & 07777` (493, octal 755, for
    ## `rwxr-xr-x`). On Windows it is the `FILE_ATTRIBUTE_*` word, and only
    ## `FILE_ATTRIBUTE_READONLY` (1) is applied; the File needs write access
    ## there. WASI has no permission bits, and this fails. `set_read_only`
    ## and `set_executable` change one property portably.
    ##
    ## @param mode the new permission bits
    ## @returns an Ok result once they are set; an error when the File is
    ##   closed, `is_permission_denied()` when the caller does not own the
    ##   file (or on Windows the File was opened without write access), or
    ##   another platform error
    ## @example
    ##     var f = File.create(Path("run.sh")).value();
    ##     f.set_permissions(493);   # octal 755: rwxr-xr-x
    ## @see Path.set_permissions
    set_permissions(mode: Mode): IoResult<void> {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_fchmod(_handle, mode);
    }

    ## Makes the open file read-only, or writable again: the portable part
    ## of `set_permissions`.
    ##
    ## On POSIX, read-only clears every write bit (octal 222), and writable
    ## sets only the owner's (octal 200), so a file never becomes writable
    ## by group or others this way. On Windows it sets or clears
    ## `FILE_ATTRIBUTE_READONLY`, and the File needs write access. Fails on
    ## WASI, which has no permission bits.
    ##
    ## @param read_only true to make the file read-only, false to make it
    ##   writable by its owner
    ## @returns an Ok result once the file is changed; an error as for
    ##   `metadata()` or `set_permissions`
    ## @see Metadata.read_only
    set_read_only(read_only: bool): IoResult<void> {
        var m = metadata();
        if (m.is_err()) {
            return IoResult<void>.err(m.error());
        }
        return _io_sys_fchmod(_handle, _io_sys_read_only_mode(m.value().permissions, read_only));
    }

    ## Makes the open file executable, or not, without raw permission bits.
    ##
    ## On POSIX, executable adds an execute bit for each class (owner, group,
    ## others) that may read the file, as `chmod +x` does with the usual
    ## umask; not executable clears all three. Windows has no execute bit
    ## (an extension such as `.exe` decides) and WASI no permission bits, so
    ## there this does nothing and succeeds.
    ##
    ## @param executable true to make the file executable, false to stop it
    ## @returns an Ok result once the file is changed; an error as for
    ##   `metadata()` or `set_permissions`
    ## @example
    ##     var f = File.create(Path("run.sh")).value();
    ##     f.write_all("#!/bin/sh\necho hi\n");
    ##     f.set_executable(true);
    set_executable(executable: bool): IoResult<void> {
        var m = metadata();
        if (m.is_err()) {
            return IoResult<void>.err(m.error());
        }
        var mode = _io_sys_executable_mode(m.value().permissions, executable);
        if (mode == m.value().permissions) {
            return _io_ok_void();
        }
        return _io_sys_fchmod(_handle, mode);
    }

    ## Sets the open file's modification time, leaving its access time
    ## alone (`futimens` on POSIX, `SetFileTime` on Windows).
    ##
    ## On Windows the File needs write access, and the time is kept to 100
    ## ns. A later write to the file sets its modification time again, so
    ## call this after the last write.
    ##
    ## @param time the new time, in nanoseconds since the Unix epoch, as
    ##   `Metadata.modified` reports it
    ## @returns an Ok result once the time is set; an error when the File is
    ##   closed, `is_permission_denied()` when the caller does not own the
    ##   file (or on Windows the File was opened without write access), or
    ##   another platform error
    ## @see Path.set_modified
    set_modified(time: long): IoResult<void> {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_fset_times(_handle, Optional<long>.Empty, Optional<long>.Value(time));
    }

    ## Sets the open file's access time, leaving its modification time
    ## alone (`futimens` on POSIX, `SetFileTime` on Windows).
    ##
    ## On Windows the File needs write access, and the time is kept to 100
    ## ns.
    ##
    ## @param time the new time, in nanoseconds since the Unix epoch, as
    ##   `Metadata.accessed` reports it
    ## @returns an Ok result once the time is set; an error as for
    ##   `set_modified`
    ## @see Path.set_accessed
    set_accessed(time: long): IoResult<void> {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_fset_times(_handle, Optional<long>.Value(time), Optional<long>.Empty);
    }

    ## Closes the File now, to observe the error the system reports (for
    ## example a deferred write failure). Without it the destructor closes
    ## the handle and ignores errors.
    ##
    ## Idempotent: closing a closed File succeeds. The File counts as
    ## closed afterwards even when closing reports an error, so the handle
    ## is never closed twice. A standard stream is only marked closed: the
    ## stream stays open, and `File.stdout()` and the like still work.
    ##
    ## @returns an Ok result on success or when already closed; the platform
    ##   error when closing an owned handle fails
    ## @example
    ##     var f = File.create(Path("out.bin")).value();
    ##     f.write_all("data");
    ##     if (f.close().is_err()) {
    ##         return 1;
    ##     }
    close(): IoResult<void> {
        if (!_io_sys_handle_valid(_handle)) {
            return _io_ok_void();
        }
        var h = _handle;
        _handle = _io_sys_invalid_handle();
        if (!_owned) {
            return _io_ok_void();
        }
        return _io_sys_close(h);
    }

    ## Moves the file's handle into a `FileTransfer`, which another thread
    ## takes with `File.adopt`, and leaves this File closed. A File is not
    ## thread-safe, so this is how a thread hands one to another, such as
    ## the pipe from a child process's standard output to the thread that
    ## reads it while this one writes to the child.
    ##
    ## @returns the token; for a closed File, one that `adopt` fails on
    ## @example
    ##     import async;
    ##     import [File, Path] from io;
    ##
    ##     var transfer = File.open(Path("notes.txt")).value().into_transfer();
    ##     var reader = async.Thread.spawn(() => {
    ##         var mine = File.adopt(transfer).value();
    ##         var text = mine.read_all();
    ##     });
    ##     reader.join();
    into_transfer(): FileTransfer {
        var h = _handle;
        _handle = _io_sys_invalid_handle();
        return FileTransfer(h, _owned);
    }

    ## Takes the handle out of `transfer` (see `into_transfer`) into a new
    ## File on the calling thread, whose `path` is empty. Only the first
    ## `adopt` of a token gets the handle.
    ##
    ## @param transfer the token from `into_transfer`
    ## @returns the File; an error when the token is empty (already adopted,
    ##   or made from a closed File)
    static adopt(transfer: FileTransfer): IoResult<File> {
        var h = transfer._take();
        if (!_io_sys_handle_valid(h)) {
            return IoResult<File>.err(IoError(_io_sys_code_not_found(), "the file was adopted already, or closed"));
        }
        var file = File();
        file._handle = h;
        file._owned = transfer._owned;
        return IoResult<File>.ok(file);
    }

    # ── Whole-file conveniences (Rust fs::read, fs::write, ...) ─────────────

    ## Reads the whole file at `path` into a byte array (Rust's
    ## `fs::read`).
    ##
    ## @param path the file to read
    ## @returns the file's bytes; an error as for `File.open` (such as
    ##   `is_not_found()`) or `read_all`
    ## @example
    ##     var r = File.read_bytes(Path("image.png"));
    ##     if (r.is_ok()) {
    ##         var n = r.value().count;
    ##     }
    static read_bytes(path: Path): IoResult<u8[]> {
        var f = open(path);
        if (f.is_err()) {
            return IoResult<u8[]>.err(f.error());
        }
        return f.value().read_all();
    }

    ## Reads the whole file at `path` as UTF-8 text (Rust's
    ## `fs::read_to_string`).
    ##
    ## @param path the file to read
    ## @returns the file's text; an error with `is_invalid_input()` when it
    ##   is not valid UTF-8, or an error as for `File.open` (such as
    ##   `is_not_found()`) or `read_all`
    ## @example
    ##     var r = File.read_to_string(Path("notes.txt"));
    ##     if (r.is_err()) {
    ##         return 1;
    ##     }
    ##     var text = r.value();
    static read_to_string(path: Path): IoResult<String> {
        var f = open(path);
        if (f.is_err()) {
            return IoResult<String>.err(f.error());
        }
        return f.value().read_string();
    }

    ## Writes `data` as the whole contents of the file at `path`, creating
    ## it or replacing what it held (Rust's `fs::write`), then closes it.
    ##
    ## Not atomic: the file is truncated first, so a failure part way
    ## leaves it truncated or partly written.
    ##
    ## @param path the file to write
    ## @param data the new contents
    ## @returns an Ok result once the data is written and the file closed; an error
    ##   as for `File.create` (such as `is_not_found()` for a missing parent
    ##   directory), `write_all`, or `close`
    ## @example
    ##     var data = Array<u8>();
    ##     data.append(1 as u8);
    ##     File.write_bytes(Path("one.bin"), data);
    static write_bytes(path: Path, data: u8[]): IoResult<void> {
        var f = create(path);
        if (f.is_err()) {
            return IoResult<void>.err(f.error());
        }
        var file = f.value();
        var w = file.write_all(data);
        if (w.is_err()) {
            return w;
        }
        return file.close();
    }

    ## Writes `s` as UTF-8 as the whole contents of the file at `path`,
    ## creating it or replacing what it held, then closes it. No newline is
    ## added.
    ##
    ## Not atomic: the file is truncated first, so a failure part way
    ## leaves it truncated or partly written.
    ##
    ## @param path the file to write
    ## @param s the new contents
    ## @returns an Ok result once the text is written and the file closed; an error
    ##   as for `File.create` (such as `is_not_found()` for a missing parent
    ##   directory), `write_all`, or `close`
    ## @note this is the design proposal's `write_to_string`; a static
    ##   `write` would clash with the instance `write`
    ## @example
    ##     var r = File.write_text(Path("hello.txt"), "hello, world");
    ##     if (r.is_err()) {
    ##         return 1;
    ##     }
    static write_text(path: Path, s: String): IoResult<void> {
        var f = create(path);
        if (f.is_err()) {
            return IoResult<void>.err(f.error());
        }
        var file = f.value();
        var w = file.write_all(s);
        if (w.is_err()) {
            return w;
        }
        return file.close();
    }

    ## Copies the contents of the file `from` to `to`, creating `to` or
    ## truncating it first, in 64 KiB chunks.
    ##
    ## Only the contents are copied: `to` keeps its own permissions and
    ## timestamps (a new file gets the defaults of `File.create`). A failure
    ## part way leaves `to` partly written.
    ##
    ## @param from the file to copy
    ## @param to the destination file
    ## @returns the number of bytes copied; `is_invalid_input()` when `from`
    ##   and `to` are the same file (after resolving symlinks), which
    ##   truncating `to` would empty before it was read; otherwise an error
    ##   as for `File.open` on `from` (such as `is_not_found()`),
    ##   `File.create` on `to`, or a read, write or close failure
    ## @example
    ##     var n = File.copy(Path("a.txt"), Path("b.txt")).value();
    static copy(from: Path, to: Path): IoResult<ulong> {
        var src = open(from);
        if (src.is_err()) {
            return IoResult<ulong>.err(src.error());
        }
        var from_real = from.canonicalize();
        var to_real = to.canonicalize();
        if (from_real.is_ok() && to_real.is_ok() && from_real.value()._value == to_real.value()._value) {
            return IoResult<ulong>.err(
                IoError(_io_sys_code_invalid_input(), "source and destination are the same file")
            );
        }
        var dst = create(to);
        if (dst.is_err()) {
            return IoResult<ulong>.err(dst.error());
        }
        var input = src.value();
        var output = dst.value();
        var buf = Array<u8>();
        ulong total = 0;
        while (true) {
            buf.clear();
            var r = input.read(buf, _io_chunk_size());
            if (r.is_err()) {
                return IoResult<ulong>.err(r.error());
            }
            if (r.value() == 0) {
                break;
            }
            var w = output.write_all(buf);
            if (w.is_err()) {
                return IoResult<ulong>.err(w.error());
            }
            total = total + r.value();
        }
        var c = output.close();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        return IoResult<ulong>.ok(total);
    }

    ## Renames or moves `from` to `to`, replacing an existing file at `to`
    ## (`rename` on POSIX, `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING` on
    ## Windows).
    ##
    ## Works for directories too. Moving between file systems (volumes)
    ## fails rather than copying.
    ##
    ## @param from the existing path
    ## @param to the new path
    ## @returns an Ok result on success; an error with `is_not_found()` when `from`
    ##   (or the parent of `to`) does not exist or, on POSIX, either path is
    ##   empty,
    ##   `is_permission_denied()` when access is refused, or another
    ##   platform error
    ## @example
    ##     File.rename(Path("draft.txt"), Path("final.txt"));
    static rename(from: Path, to: Path): IoResult<void> {
        return _io_sys_rename(from, to);
    }

    ## Creates a hard link at `to` to the file `from` (`link` on POSIX,
    ## `CreateHardLinkW` on Windows): a second name for the same file, which
    ## keeps its contents when `from` is renamed or removed.
    ##
    ## Both names must be on one file system (volume); across two it fails
    ## rather than copying, and so do directories.
    ##
    ## @param from the existing file
    ## @param to the new name
    ## @returns an Ok result once `to` names the file; an error with
    ##   `is_not_found()` when `from` (or the parent of `to`) does not exist
    ##   or a path is empty, `is_already_exists()` when something is already
    ##   at `to`, `is_permission_denied()`, or another platform error
    ## @example
    ##     File.hard_link(Path("build/app.o"), Path("pinned/app.o"));
    static hard_link(from: Path, to: Path): IoResult<void> {
        return _io_sys_hard_link(from, to);
    }

    ## Creates a symbolic link at `link` that points to the file `target`
    ## (`symlink` on POSIX, `CreateSymbolicLinkW` on Windows). Use
    ## `Directory.symlink` for a link to a directory: Windows makes the two
    ## kinds differently, and a file link to a directory does not open
    ## there. POSIX makes the same link either way.
    ##
    ## `target` is stored as given and need not exist; a relative target is
    ## resolved against the directory that holds the link, not the current
    ## directory. On Windows, making a symlink needs Developer Mode or an
    ## administrator, and fails with `is_permission_denied()` otherwise.
    ##
    ## @param target the path the link points to
    ## @param link where to create the link
    ## @returns an Ok result once the link exists; an error with
    ##   `is_already_exists()` when something is already at `link`,
    ##   `is_not_found()` when its parent is missing or a path is empty,
    ##   `is_permission_denied()`, or another platform error
    ## @example
    ##     File.symlink(Path("app-1.2.so"), Path("lib/app.so"));
    ## @see Path.read_link
    static symlink(target: Path, link: Path): IoResult<void> {
        return _io_sys_symlink(target, link, false);
    }

    ## Deletes the file at `path`. A symlink is removed itself, not its
    ## target. Directories are not removed: use `Directory.remove` or
    ## `Directory.remove_all`.
    ##
    ## @param path the file to delete
    ## @returns an Ok result on success; an error with `is_not_found()` when the
    ##   path does not exist (on POSIX, also when it is empty); when it is a
    ##   directory,
    ##   `is_is_a_directory()` on Linux and `is_permission_denied()` on macOS
    ##   and Windows; `is_permission_denied()` when access is refused (on
    ##   Windows also for a read-only file); or another platform error
    ## @example
    ##     var r = File.remove(Path("old.txt"));
    ##     if (r.is_err() && !r.error().is_not_found()) {
    ##         return 1;
    ##     }
    static remove(path: Path): IoResult<void> {
        return _io_sys_unlink(path);
    }
}

## A file's handle on its way from one thread to another: made by
## `File.into_transfer`, taken by `File.adopt`. Unlike a File, it is
## thread-safe, so a `shared` function (a body for `async.spawn` or
## `Thread.spawn`) can capture it and a `Channel` can carry it. If no one
## adopts it, the handle is closed when the last reference goes, unless it
## is one the File did not own (a standard stream).
[Shared]
export struct FileTransfer {
    # The handle as a number (`_io_sys_handle_bits`), or the invalid
    # handle's once taken.
    const _handle: async.Atomic<long>;
    # Whether the File owned the handle and closed it.
    const _owned: bool;

    ## Wraps a file handle. `File.into_transfer` makes these; use it.
    ##
    ## @param handle the handle, or an invalid one for an empty token
    ## @param owned whether the File the token came from closed its handle
    construct(handle: FileHandle, owned: bool) {
        _handle = async.Atomic<long>(_io_sys_handle_bits(handle));
        _owned = owned;
    }

    ## Closes the handle if no one adopted it and the File owned it.
    destruct {
        var h = _take();
        if (_owned and _io_sys_handle_valid(h)) {
            _io_sys_close(h);
        }
    }

    # Takes the handle out, leaving the token empty.
    _take(): FileHandle {
        return _io_sys_handle_from_bits(_handle.exchange(_io_sys_handle_bits(_io_sys_invalid_handle())));
    }
}
