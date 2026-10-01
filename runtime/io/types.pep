# Platform aliases and the io error type.
#
# The raw types differ per platform; everything above the `_io_sys_*` layer
# is written against these names only.

import "socket_posix";
import "socket_windows";
import "sys_posix";
import "sys_windows";

# POSIX

## The raw operating-system handle of an open file: a POSIX file descriptor.
##
## `File.Handle` holds one. A valid descriptor is `>= 0`; a `File` that is
## closed (or was never opened) holds `-1`. The standard streams are
## descriptors 0, 1 and 2. On Windows this is a `HANDLE` instead.
##
## @note code that must build for every target should not rely on this being
## an `int`
## @see File
[Target(!OS(Windows))]
export type FileHandle = int;

## The raw operating-system handle of a socket: a POSIX file descriptor.
##
## `TcpListener`, `TcpStream` and `UdpSocket` hold one. A valid descriptor
## is `>= 0`; a closed socket holds `-1`. On Windows this is a `SOCKET`
## instead.
##
## @note code that must build for every target should not rely on this being
## an `int`
## @see TcpStream
[Target(!OS(Windows))]
export type SocketHandle = int;

## The raw platform error code carried by `IoError.code`: a POSIX `errno`
## value such as `ENOENT` (2). On Windows this is a `DWORD` from
## `GetLastError()` instead.
##
## The numbers differ between platforms (and a few between Linux and
## macOS), so portable code classifies an error with `IoError.kind()` or
## its predicates (`is_not_found()`, ...) rather than comparing codes.
##
## @see IoError
[Target(!OS(Windows))]
export type ErrorCode = int;

## File mode bits as reported in `Metadata.Permissions`: on POSIX the
## `mode_t` permission bits `mode & 07777` (the `rwx` bits for owner, group
## and others plus setuid, setgid and sticky; the file-type bits are
## removed). On Windows the same field holds `FILE_ATTRIBUTE_*` bits
## instead.
##
## @see Metadata
[Target(!OS(Windows))]
export type Mode = uint;

# Windows

## The raw operating-system handle of an open file: a Windows `HANDLE`.
##
## `File.Handle` holds one. A `File` that is closed (or was never opened)
## holds null; neither null nor `INVALID_HANDLE_VALUE` (-1) is a valid
## handle. The standard streams are the handles from `GetStdHandle`. On
## POSIX this is an `int` file descriptor instead.
##
## @note code that must build for every target should not rely on this being
## a `__ptr<void>`
## @see File
[Target(OS(Windows))]
export type FileHandle = __ptr<void>;

## The raw operating-system handle of a socket: a Winsock `SOCKET`, an
## unsigned pointer-sized integer.
##
## `TcpListener`, `TcpStream` and `UdpSocket` hold one. A closed socket
## holds `INVALID_SOCKET` (all bits set). On POSIX this is an `int` file
## descriptor instead.
##
## @note code that must build for every target should not rely on this being
## a `ulong`
## @see TcpStream
[Target(OS(Windows))]
export type SocketHandle = ulong;

## The raw platform error code carried by `IoError.code`: a Windows
## `DWORD` error code from `GetLastError()`, such as `ERROR_FILE_NOT_FOUND`
## (2). On POSIX this is an `errno` value instead.
##
## The numbers differ between platforms, so portable code classifies an
## error with `IoError.kind()` or its predicates (`is_not_found()`, ...)
## rather than comparing codes.
##
## @see IoError
[Target(OS(Windows))]
export type ErrorCode = uint;

## File attribute bits as reported in `Metadata.Permissions`: on Windows the
## whole `FILE_ATTRIBUTE_*` word of the file (`FILE_ATTRIBUTE_READONLY` is
## 1, `FILE_ATTRIBUTE_DIRECTORY` 16, `FILE_ATTRIBUTE_REPARSE_POINT` 1024,
## ...). On POSIX the same field holds `mode_t` permission bits instead.
##
## @see Metadata
[Target(OS(Windows))]
export type Mode = uint;

## A byte position or distance within a file, as taken and returned by the
## `File.seek*` methods: a signed 64-bit integer on every target (`off_t` on
## POSIX, `LARGE_INTEGER` on Windows), so files larger than 4 GiB work
## everywhere.
export type Offset = long;

## The portable kind of an `IoError`, as `IoError.kind()` returns it: the
## platform's error code sorted into the cases a program usually handles.
##
## Each case except `Other` has a matching `IoError` predicate
## (`NotFound` and `is_not_found()`, ...), whose documentation lists the
## codes it covers on each platform. A code that fits none of them, such as
## the `EIO` of a short write or the `EBADF` of a closed `File`, is `Other`.
##
## @example
##     import io;
##
##     var r = io.File.open(io.Path("settings.txt"));
##     if (r.is_err()) {
##         match (r.error().kind()) {
##             NotFound => { print("no settings file"); }
##             PermissionDenied => { print("settings file is not readable"); }
##             else => { print(r.error().message); }
##         }
##     }
## @see IoError.kind
export enum ErrorKind {
    ## The file, directory or host name does not exist (`is_not_found()`).
    NotFound,
    ## Access was denied (`is_permission_denied()`).
    PermissionDenied,
    ## The target already exists (`is_already_exists()`).
    AlreadyExists,
    ## A directory was expected but something else was found
    ## (`is_not_a_directory()`).
    NotADirectory,
    ## A file was expected but a directory was found (`is_is_a_directory()`).
    IsADirectory,
    ## A directory to remove still has entries (`is_directory_not_empty()`).
    DirectoryNotEmpty,
    ## An argument or the data was invalid (`is_invalid_input()`).
    InvalidInput,
    ## The operation was interrupted before it finished (`is_interrupted()`).
    Interrupted,
    ## Nothing accepted the connection (`is_connection_refused()`).
    ConnectionRefused,
    ## The peer reset, aborted or closed the connection
    ## (`is_connection_reset()`).
    ConnectionReset,
    ## Another socket already uses the address (`is_address_in_use()`).
    AddressInUse,
    ## The address cannot be used on this machine
    ## (`is_address_not_available()`).
    AddressNotAvailable,
    ## The operation timed out (`is_timed_out()`).
    TimedOut,
    ## Cancelling the task ended the operation (`is_cancelled()`).
    Cancelled,
    ## Any other code, including 0 (no error).
    Other,
}

## An I/O failure: the raw platform error code plus a human-readable
## message.
##
## `kind()` sorts the code into an `ErrorKind`, and a predicate per kind
## (`is_not_found()`, `is_permission_denied()`, ...) tests for one of them;
## each knows the matching codes on the current platform. Test with those
## rather than comparing `code` against numbers. Failures that Pepper detects
## itself (invalid UTF-8, an empty path, a short write, a closed `File`)
## use the platform's own code for the kind they are (`EINVAL` /
## `ERROR_INVALID_PARAMETER` for invalid input, `ENOENT` /
## `ERROR_FILE_NOT_FOUND` for an empty path, ...), so the kinds hold
## for them too. A short write uses `EIO` / `ERROR_WRITE_FAULT` and a closed
## `File` uses `EBADF` / `ERROR_INVALID_HANDLE`; those are `ErrorKind.Other`.
##
## @example
##     import io;
##
##     var r = io.File.open(io.Path("settings.txt"));
##     if (r.is_err()) {
##         if (r.error().is_not_found()) {
##             print("no settings file");
##         } else {
##             print(r.error().message);
##         }
##     }
## @see IoResult
## @see ErrorKind
export struct IoError {
    ## The raw platform error code: an `errno` value on POSIX, a
    ## `GetLastError()` code on Windows; 0 means no error.
    ErrorCode code;
    ## A human-readable description: the platform's text for `code`
    ## (`strerror` on POSIX, `FormatMessageW` on Windows, without its
    ## trailing period and line break), or Pepper's own text such as
    ## `"empty path"` for errors it detects itself.
    String message;

    ## Creates an error from a platform code and a message.
    ##
    ## The default, `IoError()`, has code 0 and an empty message; no
    ## predicate holds for it.
    ##
    ## @param code the raw platform error code (`errno` on POSIX,
    ## `GetLastError()` on Windows)
    ## @param message the human-readable description
    construct(code: ErrorCode = 0, message: String = "") {
        this.code = code;
        this.message = message;
    }

    ## Captures the calling thread's last platform error now: `errno` on
    ## POSIX, `GetLastError()` on Windows, with the platform's message for
    ## it.
    ##
    ## Call it immediately after the failing system call; any call in
    ## between (including one that allocates) may overwrite the code.
    ##
    ## @returns an error holding the current `errno` / `GetLastError()` code
    ## and its message
    static last(): IoError {
        var code = _io_sys_last_error();
        return IoError(code, _io_sys_error_message(code));
    }

    ## Returns the portable kind of the error: `code` sorted by the codes the
    ## current platform uses for each kind. Each predicate below is
    ## `kind() == ErrorKind.X` for its kind.
    ##
    ## @returns the kind of `code`; `ErrorKind.Other` for a code that fits no
    ##   kind, and for 0
    ## @example
    ##     import io;
    ##
    ##     var r = io.File.open(io.Path("missing.txt"));
    ##     if (r.is_err() && r.error().kind() == io.ErrorKind.NotFound) {
    ##         print("no such file");
    ##     }
    kind(): ErrorKind { return _io_sys_error_kind(code); }

    ## Returns whether the error means the file or directory does not exist.
    ##
    ## Matches `ENOENT` on POSIX, and `ERROR_FILE_NOT_FOUND` or
    ## `ERROR_PATH_NOT_FOUND` on Windows. An empty path fails with this kind
    ## on POSIX (with the message `"empty path"`), and in `File.open_with`
    ## on every platform.
    ##
    ## `resolve` and `TcpStream.connect_host` fail with this kind too when a
    ## host name has no address.
    ##
    ## @returns true when a path, or a directory on the way to it, is missing,
    ##   or a host name has no address
    is_not_found(): bool { return kind() == ErrorKind.NotFound; }

    ## Returns whether the operation was refused for lack of permission.
    ##
    ## Matches `EACCES` or `EPERM` on POSIX, and `ERROR_ACCESS_DENIED` on
    ## Windows (which Windows also reports for, among others, deleting a
    ## read-only file).
    ##
    ## @returns true when access was denied
    is_permission_denied(): bool { return kind() == ErrorKind.PermissionDenied; }

    ## Returns whether the operation failed because its target already
    ## exists, such as `Directory.create` on an existing path or opening with
    ## `create_new`.
    ##
    ## Matches `EEXIST` on POSIX, and `ERROR_FILE_EXISTS` or
    ## `ERROR_ALREADY_EXISTS` on Windows.
    ##
    ## @returns true when the target already exists
    is_already_exists(): bool { return kind() == ErrorKind.AlreadyExists; }

    ## Returns whether a path that had to name a directory names something
    ## else, such as `Directory.open` or `Directory.remove` on a file (or,
    ## on POSIX, a file used as a directory in the middle of a path).
    ##
    ## Matches `ENOTDIR` on POSIX, and `ERROR_DIRECTORY` (267, "the directory
    ## name is invalid") on Windows.
    ##
    ## @returns true when a directory was expected
    is_not_a_directory(): bool { return kind() == ErrorKind.NotADirectory; }

    ## Returns whether an operation that needs a file was given a directory,
    ## such as reading from a directory opened as a `File`.
    ##
    ## Matches `EISDIR` on POSIX, and `ERROR_DIRECTORY_NOT_SUPPORTED` on
    ## Windows (which `File` reads report for a directory handle).
    ##
    ## @returns true when a directory was given where a file was expected
    is_is_a_directory(): bool { return kind() == ErrorKind.IsADirectory; }

    ## Returns whether a directory could not be removed because it still has
    ## entries (`Directory.remove` on a non-empty directory).
    ##
    ## Matches `ENOTEMPTY` on POSIX (39 on Linux, 66 on macOS) and
    ## `ERROR_DIR_NOT_EMPTY` on Windows.
    ##
    ## @returns true when the directory is not empty
    is_directory_not_empty(): bool { return kind() == ErrorKind.DirectoryNotEmpty; }

    ## Returns whether an argument was invalid: bad options (such as opening
    ## with no access mode), data that is not valid UTF-8 where text was
    ## expected, or a malformed path.
    ##
    ## Matches `EINVAL` on POSIX, and `ERROR_INVALID_PARAMETER` or
    ## `ERROR_INVALID_NAME` on Windows.
    ##
    ## @returns true when the input was invalid
    is_invalid_input(): bool { return kind() == ErrorKind.InvalidInput; }

    ## Returns whether the operation was interrupted before it finished.
    ##
    ## Matches `EINTR` on POSIX and `WSAEINTR` on Windows. An aborted
    ## Windows operation (`ERROR_OPERATION_ABORTED`) is `is_cancelled()`
    ## instead. The io functions retry interrupted POSIX opens, reads and writes
    ## themselves, so callers rarely see this.
    ##
    ## @returns true when the operation was interrupted
    is_interrupted(): bool { return kind() == ErrorKind.Interrupted; }

    ## Returns whether a connection attempt was refused: nothing listens on
    ## that port (the peer answered with a reset).
    ##
    ## Matches `ECONNREFUSED` on POSIX and `WSAECONNREFUSED` on Windows.
    ##
    ## @returns true when the connection was refused
    is_connection_refused(): bool { return kind() == ErrorKind.ConnectionRefused; }

    ## Returns whether an established connection was broken by the peer:
    ## reset, aborted, or (when writing) already closed.
    ##
    ## Matches `ECONNRESET`, `ECONNABORTED` or `EPIPE` on POSIX, and
    ## `WSAECONNRESET` or `WSAECONNABORTED` on Windows.
    ##
    ## @returns true when the connection was reset or closed by the peer
    is_connection_reset(): bool { return kind() == ErrorKind.ConnectionReset; }

    ## Returns whether binding failed because another socket already uses
    ## the address and port.
    ##
    ## Matches `EADDRINUSE` on POSIX and `WSAEADDRINUSE` on Windows.
    ##
    ## @returns true when the address is in use
    is_address_in_use(): bool { return kind() == ErrorKind.AddressInUse; }

    ## Returns whether an address cannot be used here: binding to an IP
    ## address that is not one of this machine's, or connecting to port 0.
    ##
    ## Matches `EADDRNOTAVAIL` on POSIX and `WSAEADDRNOTAVAIL` on Windows.
    ##
    ## @returns true when the address is not available
    is_address_not_available(): bool { return kind() == ErrorKind.AddressNotAvailable; }

    ## Returns whether an operation gave up because the peer did not answer
    ## in time, such as a connection attempt to an unreachable host, or
    ## because an `async.timeout` scope around it expired.
    ##
    ## Matches `ETIMEDOUT` on POSIX and `WSAETIMEDOUT` on Windows.
    ##
    ## @returns true when the operation timed out
    is_timed_out(): bool { return kind() == ErrorKind.TimedOut; }

    ## Returns whether an operation stopped because the task waiting for it
    ## was cancelled (see `async.Task.cancel`).
    ##
    ## Matches `ECANCELED` on POSIX, and `ERROR_OPERATION_ABORTED` or
    ## `ERROR_CANCELLED` on Windows.
    ##
    ## @returns true when cancellation ended the operation
    is_cancelled(): bool { return kind() == ErrorKind.Cancelled; }
}

## The result of an io operation: a value on success, an `IoError` on
## failure. Check `is_ok()` / `is_err()` before calling `value()` or `error()`;
## operations that produce nothing return `IoResult<void>`.
##
## @typeParam T the value an operation produces on success
## @example
##     import io;
##
##     var cwd = io.Directory.current();
##     if (cwd.is_ok()) {
##         print(cwd.value().to_string());
##     } else {
##         print(cwd.error().message);
##     }
## @see IoError
export type IoResult<T> = Result<T, IoError>;

# ── Module-private helpers shared by the io files ───────────────────────────

# A String holding a copy of `n` bytes at `p`; `n == 0` must not reach the
# constructor, which would read `p` as a NUL-terminated C string. (For a C
# string, `String(p)` measures it and takes a null `p` as empty.)
export _io_string_from(p: __ptr<char>, n: ulong): String {
    if (p == __null || n == 0) {
        return String();
    }
    return String(p, n);
}

extern void memcpy(void* dest, void* src, ulong n);

# A new buffer (free it with `_pep_free`) holding a copy of `text`'s bytes,
# for a write that may wait while another task changes `text`.
export _io_text_copy(text: String): __ptr<u8> {
    __ptr<u8> bytes = _pep_malloc(text.size() + 1);
    memcpy(bytes, text.c_str(), text.size());
    return bytes;
}

# Byte `i` of the `n` bytes at `p`, or 0 past the end: a bounds-checked read
# for scanning a String's bytes (an empty String has no buffer at all).
export _io_byte(p: __ptr<u8>, n: ulong, i: ulong): int {
    if (i >= n) {
        return 0;
    }
    return p[i];
}

export _io_ok_void(): IoResult<void> {
    return IoResult<void>.ok();
}

export _io_err_void(e: IoError): IoResult<void> {
    return IoResult<void>.err(e);
}

export _io_last_void(): IoResult<void> {
    return IoResult<void>.err(IoError.last());
}
