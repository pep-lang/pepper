## Unix domain sockets: `UnixListener` accepts connections on a path in the
## file system, `UnixStream` is one connection, and `UnixDatagram` sends and
## receives datagrams.
##
## They work like `TcpListener`, `TcpStream` and `UdpSocket`, for processes
## on the same machine: a path names the socket instead of an IP address and
## a port. Linux, macOS and Windows (10 version 1803 and later) all have the
## stream sockets; `UnixDatagram` is Linux and macOS only.
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
import "socket_wasi";
import "socket_windows";
import "sys_posix";
import "sys_windows";
import "types";
import "wait";

# `path` as a sockaddr_un.
_io_sockaddr_unix_write(path: Path): IoResult<_SockAddr> {
    var text = path._value;
    var n = text.size;
    var capacity = _io_sys_unix_path_capacity();
    if (n == 0 || n + 1 > capacity) {
        var message = $"a Unix socket path must be 1 to {capacity - 1} bytes: '{text}'";
        return IoResult<_SockAddr>.err(IoError(_io_sys_code_invalid_input(), message));
    }
    var sockaddr = _SockAddr();
    var buffer = sockaddr._bytes;
    var p = unsafe_cast<__ptr<u8>>(text.c_str());
    ulong i = 0;
    while (i < n) {
        buffer[2 + i] = p[i];
        i = i + 1;
    }
    buffer[2 + n] = 0;
    sockaddr._length = (2 + n + 1) as int;
    _io_sys_sockaddr_unix_header(buffer, sockaddr._length);
    return IoResult<_SockAddr>.ok(sockaddr);
}

# Binds the socket `h` to `path`.
_io_unix_bind(h: SocketHandle, path: Path): IoResult<void> {
    var sockaddr = _io_sockaddr_unix_write(path);
    if (sockaddr.is_err()) {
        return IoResult<void>.err(sockaddr.error());
    }
    var address = sockaddr.value();
    return _io_sys_socket_bind_raw(h, address._bytes, address._length);
}

# Connects the socket `h` to the listener at `path`.
_io_unix_connect(h: SocketHandle, path: Path): IoResult<void> {
    var sockaddr = _io_sockaddr_unix_write(path);
    if (sockaddr.is_err()) {
        return IoResult<void>.err(sockaddr.error());
    }
    var address = sockaddr.value();
    var result = _io_sys_socket_connect_raw(h, address._bytes, address._length);
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
##         stream.write_all("hello");
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
        _io_socket_close_taken(_handle);
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
        return UnixStream._accepted(_io_listener_accept(_handle, false));
    }

    ## Closes the listener now. Closing a closed listener does nothing.
    ## Connections already accepted stay open, and the socket file stays.
    ##
    ## @returns an Ok result on success or when already closed; the platform
    ##   error when closing fails
    close(): IoResult<void> {
        var h = _handle;
        _handle = _io_sys_socket_invalid();
        return _io_socket_close_taken(h);
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
##                     accepted.value().write_all("hello");
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
        _io_socket_close_taken(_handle as SocketHandle);
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
        return UnixStream._accepted(_io_listener_accept(_handle as SocketHandle, true));
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
##     stream.write_all("ping");
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
        _io_socket_close_taken(_handle);
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

    ## Waits until data arrives, then appends up to `max` bytes of it to
    ## `buffer` with a single system call, like `TcpStream.read`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read; 0 reads nothing and returns 0
    ## @returns the number of bytes appended, 0 once the peer has closed its
    ##   side of the connection; an error when the stream is closed, or
    ##   another platform error
    read(buffer: u8[], max: ulong): IoResult<ulong> {
        return _io_stream_read(_handle, buffer, max);
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
        return _io_stream_read_exact(_handle, buffer, count);
    }

    ## Sends bytes from `data` with a single system call, waiting until the
    ## system can take at least some of them. The send may be partial; use
    ## `write_all` to send everything.
    ##
    ## @param data the bytes to send
    ## @returns the number of bytes sent, which may be less than
    ##   `data.count`; an error when the peer has closed the connection,
    ##   when the stream is closed, or another platform error
    write(data: u8[]): IoResult<ulong> {
        return _io_stream_write(_handle, data);
    }

    ## Sends all of `data`, repeating the send until every byte is sent.
    ## If an error occurs part of `data` may already have been sent.
    ##
    ## @param data the bytes to send
    ## @returns an Ok result once every byte is sent; an error as for `write`
    write_all(data: u8[]): IoResult<void> {
        return _io_stream_write_all(_handle, data);
    }

    ## Sends all of the UTF-8 bytes of `text`, as `write_all(u8[])` does.
    ## No newline or terminator is added.
    ##
    ## @param text the text to send
    ## @returns an Ok result once every byte is sent; an error as for `write`
    ## @example
    ##     stream.write_all("ping");
    write_all(text: String): IoResult<void> {
        return _io_stream_write_string(_handle, text);
    }

    ## Deprecated: use `write_all` instead. Sends all of the UTF-8 bytes of
    ## `text`, exactly like `write_all(text)`.
    ##
    ## @param text the text to send
    ## @returns an Ok result once every byte is sent; an error as for `write_all`
    ## @see write_all
    [Deprecated("use 'write_all' instead", "write_all")]
    write_string(text: String): IoResult<void> {
        return write_all(text);
    }

    ## Closes the sending side of the connection: the peer's reads return 0
    ## once it has read everything sent before. This side can still read.
    ##
    ## @returns an Ok result on success; an error when the stream is closed,
    ##   or another platform error
    shutdown_write(): IoResult<void> {
        return _io_stream_shutdown_write(_handle);
    }

    ## Moves the connection out of this stream, into a token another thread
    ## can take it from with `UnixStream.adopt`, as
    ## `TcpStream.into_transfer` does. The stream is closed afterwards.
    ##
    ## @returns the token; for a closed stream, one that `adopt` fails on
    into_transfer(): SocketTransfer {
        var h = _handle;
        _handle = _io_sys_socket_invalid();
        return _io_socket_transfer(h);
    }

    ## Takes the connection out of `transfer` (see `into_transfer`) into a
    ## new stream on the calling thread. Only the first `adopt` of a token
    ## gets the connection.
    ##
    ## @param transfer the token from `into_transfer`
    ## @returns the stream; an error when the token is empty (already
    ##   adopted, or made from a closed stream)
    static adopt(transfer: SocketTransfer): IoResult<UnixStream> {
        var h = _io_socket_adopt(transfer);
        if (h.is_err()) {
            return IoResult<UnixStream>.err(h.error());
        }
        return IoResult<UnixStream>.ok(_of(h.value()));
    }

    # A stream owning the open socket `h`.
    static _of(h: SocketHandle): UnixStream {
        var stream = UnixStream();
        stream._handle = h;
        return stream;
    }

    # What a listener's `accept` returns, for the socket it accepted.
    static _accepted(accepted: IoResult<(SocketHandle, SocketAddress)>): IoResult<UnixStream> {
        if (accepted.is_err()) {
            return IoResult<UnixStream>.err(accepted.error());
        }
        return IoResult<UnixStream>.ok(_of(accepted.value().0));
    }

    ## Closes the connection now. Closing a closed stream does nothing.
    ##
    ## @returns an Ok result on success or when already closed; the platform
    ##   error when closing fails
    close(): IoResult<void> {
        var h = _handle;
        _handle = _io_sys_socket_invalid();
        return _io_socket_close_taken(h);
    }
}

# The path in a sockaddr_un the system wrote, or an empty path for an
# unnamed (unbound) socket or a Linux abstract address.
[Target(OS(Linux) || OS(Mac))]
_io_sockaddr_unix_read(sockaddr: _SockAddr): Path {
    var buffer = sockaddr._bytes;
    ulong end = 2;
    var limit = sockaddr._length as ulong;
    while (end < limit && buffer[end] != 0) {
        end = end + 1;
    }
    if (end == 2) {
        return Path();
    }
    return Path(_io_string_from(unsafe_cast<__ptr<char>>(buffer + 2), end - 2));
}

# ── UnixDatagram ─────────────────────────────────────────────────────────────

## A Unix domain datagram socket (`SOCK_DGRAM` on `AF_UNIX`): like a
## `UdpSocket` for processes on the same machine, with a path in place of
## an address. Linux and macOS only; Windows has no Unix datagram sockets.
##
## Each `send_to` delivers one whole datagram, in order, and the system
## never drops one silently: a send waits while the receiver's queue is
## full. `UnixDatagram.bind` creates a socket file at a path, which closing
## does not remove (as for `UnixListener`); `UnixDatagram.unbound` makes a
## socket that can send but has no path for replies; `UnixDatagram.pair`
## makes two connected sockets.
##
## Closing: the destructor closes the socket when the last reference goes;
## `close()` closes it earlier and reports errors. Every operation on a
## closed socket fails with an error no `IoError` predicate identifies
## (`EBADF`).
##
## @example
##     import io;
##
##     var path = io.Directory.temp().join("events.sock");
##     io.File.remove(path);   # left over from an earlier run
##     var server = io.UnixDatagram.bind(path).value();
##     var client = io.UnixDatagram.unbound().value();
##     client.send_to("ping".bytes(), path);
##     var buffer = Array<u8>();
##     var (n, from) = server.receive_from(buffer, 1024).value();   # 4, an empty path
## @see UdpSocket
## @see UnixStream
[Target(OS(Linux) || OS(Mac))]
[NotCopyable("owns an operating-system socket and cannot be copied")]
export struct UnixDatagram {
    ## The socket's descriptor, -1 when closed.
    SocketHandle _handle;
    ## The path the socket was bound to; empty when it is unbound.
    Path _path;

    ## Creates a closed socket: `is_open()` is false and every operation
    ## fails. Use `UnixDatagram.bind`, `unbound` or `pair` to get an open
    ## one.
    construct() {
        _handle = _io_sys_socket_invalid();
        _path = Path();
    }

    ## Closes the socket if it is still open when the last reference goes.
    ## Errors are ignored; call `close()` to see them. The socket file stays.
    destruct {
        _io_socket_close_taken(_handle);
    }

    ## Creates a datagram socket at `path`, to receive datagrams sent there.
    ##
    ## @param path where to create the socket file: at most 107 bytes (103
    ##   on macOS)
    ## @returns the bound socket; an error with `is_address_in_use()` when a
    ##   file already exists at `path`, `is_invalid_input()` when the path is
    ##   empty or too long, `is_not_found()` when its directory does not
    ##   exist, `is_permission_denied()` when the directory cannot be
    ##   written, or another platform error
    static bind(path: Path): IoResult<UnixDatagram> {
        var opened = unbound();
        if (opened.is_err()) {
            return opened;
        }
        var socket = opened.value();
        var bound = _io_unix_bind(socket._handle, path);
        if (bound.is_err()) {
            return IoResult<UnixDatagram>.err(bound.error());
        }
        socket._path = path;
        return IoResult<UnixDatagram>.ok(socket);
    }

    ## Creates a datagram socket with no path. It can send, but a receiver
    ## sees an empty path as the sender and cannot reply.
    ##
    ## @returns the socket; an error when the system is out of descriptors,
    ##   or another platform error
    static unbound(): IoResult<UnixDatagram> {
        var opened = _io_sys_socket_open_unix_datagram();
        if (opened.is_err()) {
            return IoResult<UnixDatagram>.err(opened.error());
        }
        var socket = UnixDatagram();
        socket._handle = opened.value();
        return IoResult<UnixDatagram>.ok(socket);
    }

    ## Creates two datagram sockets connected to each other, with no path
    ## (`socketpair(2)`): what one sends with `send`, the other receives. A
    ## common way to talk to a child thread or process.
    ##
    ## @returns the two sockets; an error when the system is out of
    ##   descriptors, or another platform error
    ## @example
    ##     var (a, b) = io.UnixDatagram.pair().value();
    ##     a.send("hi".bytes());
    ##     var buffer = Array<u8>();
    ##     b.receive(buffer, 16);   # buffer holds "hi"
    static pair(): IoResult<(UnixDatagram, UnixDatagram)> {
        var opened = _io_sys_socket_pair_unix_datagram();
        if (opened.is_err()) {
            return IoResult<(UnixDatagram, UnixDatagram)>.err(opened.error());
        }
        var first = UnixDatagram();
        first._handle = opened.value().0;
        var second = UnixDatagram();
        second._handle = opened.value().1;
        return IoResult<(UnixDatagram, UnixDatagram)>.ok((first, second));
    }

    ## Returns whether the socket is open.
    ##
    ## @returns false after `close()` and for a `UnixDatagram()` never opened
    is_open(): bool {
        return _io_sys_socket_valid(_handle);
    }

    ## Returns the path the socket was bound to.
    ##
    ## @returns the path given to `bind`; an empty path for an unbound or
    ##   paired socket
    path(): Path {
        return _path;
    }

    ## Sends `data` as one datagram to the socket bound at `path`.
    ##
    ## @param data the datagram's bytes
    ## @param path the socket file a `UnixDatagram` is bound to
    ## @returns the number of bytes sent (all of `data`); an error with
    ##   `is_not_found()` when no socket file exists at `path`,
    ##   `is_connection_refused()` when nothing is bound to it any more,
    ##   `is_invalid_input()` when the path is empty or too long, or another
    ##   platform error (such as a datagram larger than the system allows)
    send_to(data: u8[], path: Path): IoResult<ulong> {
        var c = _io_socket_require_open(_handle);
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        var sockaddr = _io_sockaddr_unix_write(path);
        if (sockaddr.is_err()) {
            return IoResult<ulong>.err(sockaddr.error());
        }
        return _io_sys_socket_send_to_raw(_handle, data._data, data._size, sockaddr.value());
    }

    ## Waits for the next datagram and appends up to `max` of its bytes to
    ## `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to keep; the rest of a longer datagram is
    ##   lost. 0 reads nothing and returns at once.
    ## @returns the number of bytes appended and the sender's path (empty
    ##   when the sender is unbound); an error when the socket is closed, or
    ##   another platform error
    receive_from(buffer: u8[], max: ulong): IoResult<(ulong, Path)> {
        var c = _io_socket_require_open(_handle);
        if (c.is_err()) {
            return IoResult<(ulong, Path)>.err(c.error());
        }
        if (max == 0) {
            return IoResult<(ulong, Path)>.ok((0 as ulong, Path()));
        }
        buffer.reserve(buffer._size + max);
        var from = _SockAddr();
        var r = _io_sys_socket_receive_from_raw(_handle, buffer._data + buffer._size, max, from);
        if (r.is_err()) {
            return IoResult<(ulong, Path)>.err(r.error());
        }
        buffer._size = buffer._size + r.value();
        return IoResult<(ulong, Path)>.ok((r.value(), _io_sockaddr_unix_read(from)));
    }

    ## Sets the socket's default peer: `send` goes to the socket at `path`,
    ## and `receive` and `receive_from` only take datagrams from it. No
    ## datagram is sent.
    ##
    ## @param path the socket file a `UnixDatagram` is bound to
    ## @returns an Ok result on success; an error with `is_not_found()` when
    ##   no socket file exists at `path`, `is_connection_refused()` when
    ##   nothing is bound to it, or another platform error
    connect(path: Path): IoResult<void> {
        var c = _io_socket_require_open(_handle);
        if (c.is_err()) {
            return c;
        }
        return _io_unix_connect(_handle, path);
    }

    ## Sends `data` as one datagram to the connected peer (see `connect` and
    ## `pair`).
    ##
    ## @param data the datagram's bytes
    ## @returns the number of bytes sent; an error when the socket is not
    ##   connected or is closed, or another platform error
    send(data: u8[]): IoResult<ulong> {
        return _io_stream_write(_handle, data);
    }

    ## Waits for the next datagram from the connected peer and appends up to
    ## `max` of its bytes to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to keep; the rest of a longer datagram is
    ##   lost. 0 reads nothing and returns at once.
    ## @returns the number of bytes appended; an error when the socket is
    ##   closed, or another platform error
    receive(buffer: u8[], max: ulong): IoResult<ulong> {
        var r = receive_from(buffer, max);
        if (r.is_err()) {
            return IoResult<ulong>.err(r.error());
        }
        return IoResult<ulong>.ok(r.value().0);
    }

    ## Closes the socket now. Closing a closed socket does nothing. The
    ## socket file stays.
    ##
    ## @returns an Ok result on success or when already closed; the platform
    ##   error when closing fails
    close(): IoResult<void> {
        var h = _handle;
        _handle = _io_sys_socket_invalid();
        return _io_socket_close_taken(h);
    }
}
