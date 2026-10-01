## Unix domain sockets: `UnixListener` accepts connections on a path in the
## file system, `UnixStream` is one connection.
##
## They work like `TcpListener` and `TcpStream`, for processes on the same
## machine: a path names the socket instead of an IP address and a port.
## Linux, macOS and Windows (10 version 1803 and later) all have them; only
## stream sockets are supported.
##
## Binding creates a socket file at the path, and closing the listener does
## not remove it: remove it with `File.remove` when the server is done, and
## before binding again, since binding to a path that exists fails with
## `is_address_in_use()`.

# The listener and stream use the same `_io_sys_socket_*` layer as TCP; only
# opening the socket and the sockaddr (sockaddr_un) differ.

import "address";
import "path";
import "socket";
import "socket_posix";
import "socket_windows";
import "sys_posix";
import "sys_windows";
import "types";
import "wait";

# Writes a sockaddr_un for `path` into `buffer` (at least
# `_io_sockaddr_capacity()` bytes); returns its length.
export _io_sockaddr_unix_write(buffer: __ptr<u8>, path: Path): IoResult<int> {
    var text = path._value;
    var n = text.size();
    var capacity = _io_sys_unix_path_capacity();
    if (n == 0 || n + 1 > capacity) {
        var message = $"a Unix socket path must be 1 to {capacity - 1} bytes: '{text}'";
        return IoResult<int>.err(IoError(_io_sys_code_invalid_input(), message));
    }
    var p = text.c_str() as __ptr<u8>;
    ulong i = 0;
    while (i < n) {
        buffer[2 + i] = p[i];
        i = i + 1;
    }
    buffer[2 + n] = 0;
    var length = (2 + n + 1) as int;
    _io_sys_sockaddr_unix_header(buffer, length);
    return IoResult<int>.ok(length);
}

# Binds the socket `h` to `path`.
export _io_unix_bind(h: SocketHandle, path: Path): IoResult<void> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _io_sockaddr_unix_write(buffer, path);
    if (length.is_err()) {
        _pep_free(buffer);
        return IoResult<void>.err(length.error());
    }
    var result = _io_sys_socket_bind_raw(h, buffer, length.value());
    _pep_free(buffer);
    return result;
}

# Connects the socket `h` to the listener at `path`.
export _io_unix_connect(h: SocketHandle, path: Path): IoResult<void> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _io_sockaddr_unix_write(buffer, path);
    if (length.is_err()) {
        _pep_free(buffer);
        return IoResult<void>.err(length.error());
    }
    var result = _io_sys_socket_connect_raw(h, buffer, length.value());
    _pep_free(buffer);
    if (result.is_err() && !result.error().is_not_found()) {
        # Windows reports a missing socket file as WSAECONNREFUSED (the same
        # as a file nobody listens on) and a missing directory as
        # WSAENETDOWN; look at the path to report it as not found.
        var file = _io_sys_stat(path, false);
        if (file.is_err() && file.error().is_not_found()) {
            return IoResult<void>.err(file.error());
        }
    }
    return result;
}

# ── UnixListener ─────────────────────────────────────────────────────────────

## A Unix domain socket that listens for connections on a path.
##
## `UnixListener.bind` creates the socket file and listens on it; each
## `accept()` waits for the next connection and returns it as a
## `UnixStream`.
##
## Closing: the destructor closes the socket when the last reference goes;
## `close()` closes it earlier and reports errors. Neither removes the socket
## file. Every operation on a closed listener fails with an error no
## `IoError` predicate identifies (`EBADF` on POSIX, `ERROR_INVALID_HANDLE`
## on Windows).
##
## @example
##     import io;
##
##     var path = io.Directory.temp().join("server.sock");
##     io.File.remove(path);   # left over from an earlier run
##     var listener = io.UnixListener.bind(path).value();
##     while (true) {
##         var stream = listener.accept().value();
##         stream.write_string("hello");
##     }
## @see UnixStream
[NotCopyable("owns an operating-system socket and cannot be copied")]
export struct UnixListener {
    ## The socket: a descriptor on POSIX (-1 when closed), a `SOCKET` on
    ## Windows (`INVALID_SOCKET` when closed).
    SocketHandle _handle;
    ## The path the listener was bound to.
    Path _path;

    ## Creates a closed listener: `is_open()` is false and every operation
    ## fails. Use `UnixListener.bind` to get an open one.
    construct() {
        _handle = _io_sys_socket_invalid();
        _path = Path();
    }

    ## Closes the socket if it is still open when the last reference goes.
    ## Errors are ignored; call `close()` to see them. The socket file stays.
    destruct {
        if (_io_sys_socket_valid(_handle)) {
            _io_sys_socket_close(_handle);
        }
    }

    ## Creates a Unix domain socket at `path` and starts listening on it.
    ##
    ## @param path where to create the socket file: at most 107 bytes (103
    ##   on macOS)
    ## @returns the listening socket; an error with `is_address_in_use()`
    ##   when a file already exists at `path`, `is_invalid_input()` when the
    ##   path is empty or too long, `is_not_found()` when its directory does
    ##   not exist, `is_permission_denied()` when the directory cannot be
    ##   written, or another platform error
    static bind(path: Path): IoResult<UnixListener> {
        var opened = _io_sys_socket_open_unix();
        if (opened.is_err()) {
            return IoResult<UnixListener>.err(opened.error());
        }
        var listener = UnixListener();
        listener._handle = opened.value();
        var bound = _io_unix_bind(listener._handle, path);
        if (bound.is_err()) {
            return IoResult<UnixListener>.err(bound.error());
        }
        var listening = _io_sys_socket_listen(listener._handle, _io_listen_backlog());
        if (listening.is_err()) {
            return IoResult<UnixListener>.err(listening.error());
        }
        listener._path = path;
        return IoResult<UnixListener>.ok(listener);
    }

    ## Returns whether the listener is open.
    ##
    ## @returns false after `close()` and for a `UnixListener()` never bound
    is_open(): bool {
        return _io_sys_socket_valid(_handle);
    }

    ## Returns the path the listener was bound to.
    ##
    ## @returns the path given to `bind`; an empty path for a
    ##   `UnixListener()` never bound
    path(): Path {
        return _path;
    }

    ## Waits for the next incoming connection and returns it.
    ##
    ## @returns the connected stream; an error when the listener is closed,
    ##   or another platform error
    accept(): IoResult<UnixStream> {
        if (!is_open()) {
            return IoResult<UnixStream>.err(_io_socket_closed_error());
        }
        var accepted = _io_sys_socket_accept(_handle);
        if (accepted.is_err()) {
            return IoResult<UnixStream>.err(accepted.error());
        }
        var stream = UnixStream();
        stream._handle = accepted.value().0;
        return IoResult<UnixStream>.ok(stream);
    }

    ## Closes the listener now. Closing a closed listener does nothing.
    ## Connections already accepted stay open, and the socket file stays.
    ##
    ## @returns an Ok result on success or when already closed; the platform
    ##   error when closing fails
    close(): IoResult<void> {
        if (!is_open()) {
            return _io_ok_void();
        }
        var h = _handle;
        _handle = _io_sys_socket_invalid();
        return _io_sys_socket_close(h);
    }
}

## A Unix domain listening socket that any thread can accept connections on:
## the thread-safe counterpart of `UnixListener`, as `SharedTcpListener` is
## of `TcpListener`. Each connection goes to one of the threads waiting in
## `accept`, and the stream it returns belongs to that thread.
##
## A `shared` function may capture it. There is no `close()`, since another
## thread may be waiting on it: the socket closes when the last reference
## goes. The socket file stays.
##
## @example
##     import async;
##     import io;
##
##     main(): int {
##         async.run(() => {
##             var listener = io.SharedUnixListener.bind(io.Path("/tmp/server.sock")).value();
##             async.spawn_on_each_worker(() => {
##                 while (true) {
##                     var accepted = listener.accept();
##                     if (accepted.is_err()) {
##                         return;
##                     }
##                     accepted.value().write_string("hello");
##                 }
##             });
##         });
##         return 0;
##     }
## @see UnixListener
[Shared]
export struct SharedUnixListener {
    # The socket (`SocketHandle` widened to `long`; -1 for none).
    const _handle: long;

    ## Wraps a listening socket. Use `SharedUnixListener.bind`.
    ##
    ## @param handle the listening socket, or an invalid handle for none
    construct(handle: SocketHandle) {
        _handle = handle as long;
    }

    ## Closes the socket when the last reference goes.
    destruct {
        var h = _handle as SocketHandle;
        if (_io_sys_socket_valid(h)) {
            _io_sys_socket_close(h);
        }
    }

    ## Creates a Unix domain socket at `path` and starts listening on it, as
    ## `UnixListener.bind` does.
    ##
    ## @param path where to create the socket file
    ## @returns the listening socket, or the errors `UnixListener.bind`
    ##   returns
    static bind(path: Path): IoResult<SharedUnixListener> {
        var bound = UnixListener.bind(path);
        if (bound.is_err()) {
            return IoResult<SharedUnixListener>.err(bound.error());
        }
        var listener = bound.value();
        var h = listener._handle;
        listener._handle = _io_sys_socket_invalid();
        return IoResult<SharedUnixListener>.ok(SharedUnixListener(h));
    }

    ## Waits for the next incoming connection and returns it, as
    ## `UnixListener.accept` does. Several threads may wait at once; each
    ## connection wakes one of them (or, on some systems, several, and the
    ## rest keep waiting).
    ##
    ## @returns the connected stream, owned by the calling thread; an error
    ##   when the waiting task is cancelled, or another platform error
    accept(): IoResult<UnixStream> {
        var h = _handle as SocketHandle;
        if (!_io_sys_socket_valid(h)) {
            return IoResult<UnixStream>.err(_io_socket_closed_error());
        }
        var accepted = _io_sys_socket_accept(h);
        # Another thread may close the socket once this one stops using it.
        _io_socket_release_idle(h);
        if (accepted.is_err()) {
            return IoResult<UnixStream>.err(accepted.error());
        }
        var stream = UnixStream();
        stream._handle = accepted.value().0;
        return IoResult<UnixStream>.ok(stream);
    }
}

# ── UnixStream ───────────────────────────────────────────────────────────────

## A Unix domain stream connection: a reliable, ordered stream of bytes in
## both directions between two processes (or threads) on this machine.
##
## Get one from `UnixStream.connect` or `UnixListener.accept`. Reading and
## writing work exactly as on a `TcpStream`: `read` appends what has arrived
## and returns 0 once the peer has closed its side, `write` may send part of
## the data, and `read_exact` and `write_all` loop until done. Sending never
## raises `SIGPIPE`; writing to a connection the peer has closed fails with
## `is_connection_reset()` (or a broken-pipe error no predicate matches, on
## some systems).
##
## Closing: the destructor closes the socket when the last reference goes;
## `close()` closes it earlier and reports errors. Every operation on a
## closed stream fails with an error no `IoError` predicate identifies.
##
## @example
##     import io;
##
##     var stream = io.UnixStream.connect(io.Path("/tmp/server.sock")).value();
##     stream.write_string("ping");
##     var reply = Array<u8>();
##     stream.read_exact(reply, 4).value();
## @see UnixListener
[NotCopyable("owns an operating-system socket and cannot be copied")]
export struct UnixStream {
    ## The socket: a descriptor on POSIX (-1 when closed), a `SOCKET` on
    ## Windows (`INVALID_SOCKET` when closed).
    SocketHandle _handle;

    ## Creates a closed stream: `is_open()` is false and every operation
    ## fails. Use `UnixStream.connect` or `UnixListener.accept` to get an
    ## open one.
    construct() {
        _handle = _io_sys_socket_invalid();
    }

    ## Closes the socket if it is still open when the last reference goes.
    ## Errors are ignored; call `close()` to see them.
    destruct {
        if (_io_sys_socket_valid(_handle)) {
            _io_sys_socket_close(_handle);
        }
    }

    ## Connects to the listener at `path`.
    ##
    ## @param path the socket file a `UnixListener` is bound to
    ## @returns the connected stream; an error with `is_not_found()` when no
    ##   file exists at `path`, `is_connection_refused()` when the file is
    ##   there but nothing listens on it, `is_invalid_input()` when the path
    ##   is empty or too long, or another platform error
    static connect(path: Path): IoResult<UnixStream> {
        var opened = _io_sys_socket_open_unix();
        if (opened.is_err()) {
            return IoResult<UnixStream>.err(opened.error());
        }
        var stream = UnixStream();
        stream._handle = opened.value();
        var connected = _io_unix_connect(stream._handle, path);
        if (connected.is_err()) {
            return IoResult<UnixStream>.err(connected.error());
        }
        return IoResult<UnixStream>.ok(stream);
    }

    ## Returns whether the stream is open.
    ##
    ## @returns false after `close()` and for a `UnixStream()` never connected
    is_open(): bool {
        return _io_sys_socket_valid(_handle);
    }

    _check_open(): IoResult<void> {
        if (!is_open()) {
            return IoResult<void>.err(_io_socket_closed_error());
        }
        return _io_ok_void();
    }

    ## Waits until data arrives, then appends up to `max` bytes of it to
    ## `buffer` with a single system call, like `TcpStream.read`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read; 0 reads nothing and returns 0
    ## @returns the number of bytes appended, 0 once the peer has closed its
    ##   side of the connection; an error when the stream is closed, or
    ##   another platform error
    read(buffer: u8[], max: ulong): IoResult<ulong> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        return _io_socket_read(_handle, buffer, max);
    }

    ## Reads until exactly `count` more bytes are appended to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param count the number of bytes to read
    ## @returns an Ok result once `count` bytes are appended; an error when
    ##   the peer closes the connection first ("connection closed after n of
    ##   count bytes"), or an error as for `read`. The bytes read before an
    ##   error stay in `buffer`.
    read_exact(buffer: u8[], count: ulong): IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_socket_read_exact(_handle, buffer, count);
    }

    ## Sends bytes from `data` with a single system call, waiting until the
    ## system can take at least some of them. The send may be partial; use
    ## `write_all` to send everything.
    ##
    ## @param data the bytes to send
    ## @returns the number of bytes sent, which may be less than
    ##   `data.count()`; an error when the peer has closed the connection,
    ##   when the stream is closed, or another platform error
    write(data: u8[]): IoResult<ulong> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        return _io_sys_socket_send(_handle, data._data, data._size);
    }

    ## Sends all of `data`, repeating the send until every byte is sent.
    ## If an error occurs part of `data` may already have been sent.
    ##
    ## @param data the bytes to send
    ## @returns an Ok result once every byte is sent; an error as for `write`
    write_all(data: u8[]): IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_socket_send_bytes(_handle, data);
    }

    ## Sends all of the UTF-8 bytes of `text`, as `write_all` does. No
    ## newline or terminator is added.
    ##
    ## @param text the text to send
    ## @returns an Ok result once every byte is sent; an error as for `write`
    write_string(text: String): IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_socket_send_text(_handle, text);
    }

    ## Closes the sending side of the connection: the peer's reads return 0
    ## once it has read everything sent before. This side can still read.
    ##
    ## @returns an Ok result on success; an error when the stream is closed,
    ##   or another platform error
    shutdown_write(): IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_socket_shutdown(_handle, 1);
    }

    ## Moves the connection out of this stream, into a token another thread
    ## can take it from with `UnixStream.adopt`, as
    ## `TcpStream.into_transfer` does. The stream is closed afterwards.
    ##
    ## @returns the token; for a closed stream, one that `adopt` fails on
    into_transfer(): SocketTransfer {
        var h = _handle;
        _handle = _io_sys_socket_invalid();
        if (_io_sys_socket_valid(h)) {
            _io_socket_release(h);
        }
        return SocketTransfer(h);
    }

    ## Takes the connection out of `transfer` (see `into_transfer`) into a
    ## new stream on the calling thread. Only the first `adopt` of a token
    ## gets the connection.
    ##
    ## @param transfer the token from `into_transfer`
    ## @returns the stream; an error when the token is empty (already
    ##   adopted, or made from a closed stream)
    static adopt(transfer: SocketTransfer): IoResult<UnixStream> {
        var h = transfer._take();
        if (!_io_sys_socket_valid(h)) {
            return IoResult<UnixStream>.err(_io_socket_closed_error());
        }
        var stream = UnixStream();
        stream._handle = h;
        return IoResult<UnixStream>.ok(stream);
    }

    ## Closes the connection now. Closing a closed stream does nothing.
    ##
    ## @returns an Ok result on success or when already closed; the platform
    ##   error when closing fails
    close(): IoResult<void> {
        if (!is_open()) {
            return _io_ok_void();
        }
        var h = _handle;
        _handle = _io_sys_socket_invalid();
        return _io_sys_socket_close(h);
    }
}
