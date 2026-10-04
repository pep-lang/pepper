## Files, directories, paths, and sockets, modeled on Rust's `std::fs`,
## `std::path` and `std::net`.
##
## Unlike the rest of the standard library, `io` is a module: bring it in with
## `import io` (and write `io.File`, `io.Path`) or import names directly with
## `import [File, Path] from io`. Every fallible operation returns an
## [`IoResult<T>`](io-types.md#ioresult), a `Result` whose error is an
## [`IoError`](io-types.md#ioerror).
##
## - [Path](io-path.md): building, splitting, and inspecting paths
## - [File](io-file.md): opening, reading, and writing files, and whole-file helpers
## - [Directory](io-directory.md): listing, creating, and removing directories
## - [Network addresses](io-address.md): `IpAddress`, `SocketAddress`, and `resolve`
## - [Sockets](io-socket.md): `TcpListener`, `Incoming`, `SharedTcpListener`, `TcpStream`, `SocketTransfer`, and `UdpSocket`
## - [Unix domain sockets](io-unix.md): `UnixListener`, `SharedUnixListener`, and `UnixStream`
## - [Streams](io-stream.md): the `Reader` and `Writer` traits, `lines()` and `chunks()`
## - [Streams in memory](io-memory.md): `ByteReader` and `ByteWriter`
## - [Print](io-print.md): deprecated; use `Writer`
## - [Errors and platform types](io-types.md): `IoError`, `ErrorKind`, `IoResult`, and handle types
##
## @example
##     import io;
##
##     main(): int {
##         var path = io.Directory.temp().join("greeting.txt");
##         assert(io.File.write_text(path, "hello").is_ok(), "write");
##         assert(io.File.read_to_string(path).value() == "hello", "read back");
##         io.File.remove(path);
##         return 0;
##     }

# This file only gathers the module's public API from its other files. The
# platform layer (`_io_sys_*` in sys_posix.pep / sys_windows.pep) and the
# `_io_*` helpers are exported between the io files but not from the module.

import "address";
import "directory";
import "file";
import "memory";
import "path";
import "print";
import "socket";
import "socket_posix";
import "socket_wasi";
import "socket_windows";
import "stream";
import "sys_posix";
import "sys_windows";
import "types";
import "unix";
import "wait";

export FileHandle;
export ErrorCode;
export Mode;
export Offset;
export ErrorKind;
export IoError;
export IoResult;
export SocketHandle;

export Path;

export OpenOptions;
export FileType;
export Metadata;
export SeekFrom;
export StdStream;
export File;
export Print;
export Reader;
export Writer;
export Lines;
export Chunks;
export ByteReader;
export ByteWriter;

export DirEntry;
export DirectoryIterator;
export Directory;

export IpAddress;
export SocketAddress;
export resolve;

export TcpListener;
export Incoming;
export SharedTcpListener;
export TcpStream;
export SocketTransfer;
export UdpSocket;

export UnixListener;
export SharedUnixListener;
export UnixStream;

# For the async module's task runtime only (see wait.pep); not public API.
export _IoWaiter;
export _io_set_waiter;
export _io_clear_waiter;
export _IO_READABLE;
export _IO_WRITABLE;
export _IoWait;
export _FileTransfer;
export _IO_TRANSFER_DECLINED;
export _IO_TRANSFER_CANCELLED;
export _IO_TRANSFER_TIMED_OUT;
export _IO_TRANSFER_CLOSED;

# For the tls and async modules only: UTF-16 names for Windows calls.
[Target(OS(Windows))]
export _io_win_wide;
[Target(OS(Windows))]
export _io_win_wide_len;

# For the tls module only: the socket calls its BIO makes.
export _io_sys_socket_receive;
export _io_sys_socket_send;
export _io_socket_send_all;
export _io_sys_code_write_zero;
export _io_in_task;
export _io_text_copy;

# For the compress and archive modules only: the code of invalid data.
export _io_sys_code_invalid_input;

# For the process module only: error text and Windows UTF-16 conversion.
export _io_sys_error_message;
[Target(OS(Windows))]
export _io_win_wide;
[Target(OS(Windows))]
export _io_win_narrow;
[Target(OS(Windows))]
export _io_win_wide_len;
