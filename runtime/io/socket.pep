## TCP and UDP sockets: `TcpListener` accepts connections, `TcpStream` is
## one connection, `UdpSocket` sends and receives datagrams.
##
## Every call blocks the calling thread until it completes. Addresses are
## `SocketAddress` values; `resolve` turns a host name into them.

# The sockets call a private `_io_sys_socket_*` layer declared once per
# platform (socket_posix.pep, socket_windows.pep), as File does with
# `_io_sys_*`. The sockaddr encoding below is shared; only its header (the
# family field) differs per platform.

import "address";
import "socket_posix";
import "socket_windows";
import "sys_posix";
import "sys_windows";
import "types";
import "wait";

# The listen backlog: how many connections the system queues before
# `accept` takes them (the system may cap it lower).
export _io_listen_backlog(): int {
    return 1024;
}

export _io_socket_closed_error(): IoError {
    return IoError(_io_sys_code_bad_handle(), "socket is closed");
}

# ── sockaddr ─────────────────────────────────────────────────────────────────
# sockaddr_in: header @0, port (big-endian) @2, address @4; 16 bytes.
# sockaddr_in6: header @0, port @2, flow info @4, address @8, scope id @24;
# 28 bytes. The header is platform-specific (_io_sys_sockaddr_header).

# Bytes to allocate for any sockaddr (sizeof(struct sockaddr_storage)).
export _io_sockaddr_capacity(): ulong {
    return 128;
}

# Writes `address` into the zeroed `buffer`; returns the sockaddr's length.
export _io_sockaddr_write(buffer: __ptr<u8>, address: SocketAddress): int {
    var ip = address._address;
    var port = address._port as ulong;
    buffer[2] = ((port >> 8) & 255) as u8;
    buffer[3] = (port & 255) as u8;
    if (!ip._is_v6) {
        _io_sys_sockaddr_header(buffer, false, 16);
        ulong i = 0;
        while (i < 4) {
            buffer[4 + i] = ip._byte(12 + i) as u8;
            i = i + 1;
        }
        return 16;
    }
    _io_sys_sockaddr_header(buffer, true, 28);
    ulong j = 0;
    while (j < 16) {
        buffer[8 + j] = ip._byte(j) as u8;
        j = j + 1;
    }
    return 28;
}

# The address in a sockaddr the system wrote; `0.0.0.0:0` for a family
# other than IPv4 and IPv6.
export _io_sockaddr_read(buffer: __ptr<u8>): SocketAddress {
    var family = _io_sys_sockaddr_family(buffer);
    var port = ((buffer[2] as ulong) << 8) | (buffer[3] as ulong);
    var ip = IpAddress();
    if (family == 4) {
        ip._low = _io_big_endian(buffer + 4, 4);
    } else {
        if (family != 6) {
            return SocketAddress();
        }
        ip._is_v6 = true;
        ip._high = _io_big_endian(buffer + 8, 8);
        ip._low = _io_big_endian(buffer + 16, 8);
    }
    return SocketAddress(ip, port as u16);
}

# The `count` bytes at `p` as a big-endian number.
export _io_big_endian(p: __ptr<u8>, count: ulong): ulong {
    ulong value = 0;
    ulong i = 0;
    while (i < count) {
        value = (value << 8) | (p[i] as ulong);
        i = i + 1;
    }
    return value;
}

# ── TcpListener ──────────────────────────────────────────────────────────────

## A TCP socket that listens for connections.
##
## `TcpListener.bind` opens one on a local address; each `accept()` waits for
## the next connection and returns it as a `TcpStream` together with the
## peer's address. Binding to port 0 lets the system choose a free port;
## `local_address()` tells which.
##
## On POSIX the listener sets `SO_REUSEADDR`, so a server can restart while
## connections from its previous run linger in `TIME_WAIT`. An IPv6 listener
## keeps the system's default for accepting IPv4 too (on Linux and macOS it
## does, on Windows it does not).
##
## Closing: the destructor closes the socket when the last reference goes;
## `close()` closes it earlier and reports errors. Every operation on a
## closed listener fails with an error no `IoError` predicate identifies
## (`EBADF` on POSIX, `ERROR_INVALID_HANDLE` on Windows).
##
## @example
##     import io;
##
##     var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
##     print(listener.local_address().value().to_string());   # 127.0.0.1:<port>
##     while (true) {
##         var (stream, peer) = listener.accept().value();
##         stream.write_string("hello " + peer.to_string());
##     }
## @see TcpStream
[NotCopyable("owns an operating-system socket and cannot be copied")]
export struct TcpListener {
    ## The socket: a descriptor on POSIX (-1 when closed), a `SOCKET` on
    ## Windows (`INVALID_SOCKET` when closed).
    SocketHandle _handle;

    ## Creates a closed listener: `is_open()` is false and every operation
    ## fails. Use `TcpListener.bind` to get an open one.
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

    ## Opens a TCP socket bound to `address` and starts listening on it.
    ##
    ## @param address the local address to listen on: a specific interface
    ##   (`127.0.0.1:8080`), every interface (`0.0.0.0:8080`, `[::]:8080`),
    ##   or port 0 for any free port
    ## @returns the listening socket; an error with `is_address_in_use()`
    ##   when another socket has the port, `is_address_not_available()` when
    ##   the address is not one of this machine's, `is_permission_denied()`
    ##   for a privileged port, or another platform error
    static bind(address: SocketAddress): IoResult<TcpListener> {
        var opened = _io_sys_socket_open(address.is_v6(), true);
        if (opened.is_err()) {
            return IoResult<TcpListener>.err(opened.error());
        }
        var listener = TcpListener();
        listener._handle = opened.value();
        var reuse = _io_sys_socket_set_reuse_address(listener._handle);
        if (reuse.is_err()) {
            return IoResult<TcpListener>.err(reuse.error());
        }
        var bound = _io_sys_socket_bind(listener._handle, address);
        if (bound.is_err()) {
            return IoResult<TcpListener>.err(bound.error());
        }
        var listening = _io_sys_socket_listen(listener._handle, _io_listen_backlog());
        if (listening.is_err()) {
            return IoResult<TcpListener>.err(listening.error());
        }
        return IoResult<TcpListener>.ok(listener);
    }

    ## Returns whether the listener is open.
    ##
    ## @returns false after `close()` and for a `TcpListener()` never bound
    is_open(): bool {
        return _io_sys_socket_valid(_handle);
    }

    ## Waits for the next incoming connection and returns it.
    ##
    ## @returns the connected stream and the peer's address; an error when
    ##   the listener is closed, or another platform error
    accept(): IoResult<(TcpStream, SocketAddress)> {
        if (!is_open()) {
            return IoResult<(TcpStream, SocketAddress)>.err(_io_socket_closed_error());
        }
        var accepted = _io_sys_socket_accept(_handle);
        if (accepted.is_err()) {
            return IoResult<(TcpStream, SocketAddress)>.err(accepted.error());
        }
        var (handle, peer) = accepted.value();
        var stream = TcpStream();
        stream._handle = handle;
        return IoResult<(TcpStream, SocketAddress)>.ok((stream, peer));
    }

    ## Returns the address the listener is bound to, with the port the
    ## system chose when it was bound to port 0.
    ##
    ## @returns the local address; an error when the listener is closed, or
    ##   another platform error
    local_address(): IoResult<SocketAddress> {
        if (!is_open()) {
            return IoResult<SocketAddress>.err(_io_socket_closed_error());
        }
        return _io_sys_socket_local_address(_handle);
    }

    ## Closes the listener now. Closing a closed listener does nothing.
    ## Connections already accepted stay open.
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

## A TCP listening socket that any thread can accept connections on: the
## thread-safe counterpart of `TcpListener`, for servers that accept on every
## worker of `async.run` at once (see `async.spawn_on_each_worker`). Each
## connection goes to one of the threads waiting in `accept`, and the stream
## it returns belongs to that thread.
##
## A `shared` function may capture it. There is no `close()`, since another
## thread may be waiting on it: the socket closes when the last reference
## goes, which, for accept loops in tasks, is once `async.run` has cancelled
## them (`accept` then fails and the loop returns).
##
## @example
##     import async;
##     import io;
##
##     main(): int {
##         async.run(() => {
##             var listener = io.SharedTcpListener.bind(io.SocketAddress.parse("0.0.0.0:7000").value()).value();
##             async.spawn_on_each_worker(() => {
##                 while (true) {
##                     var accepted = listener.accept();
##                     if (accepted.is_err()) {
##                         return;
##                     }
##                     var (stream, peer) = accepted.value();
##                     stream.write_string("hello");
##                 }
##             });
##         });
##         return 0;
##     }
## @see TcpListener
[Shared]
export struct SharedTcpListener {
    # The socket (`SocketHandle` widened to `long`; -1 for none).
    const _handle: long;

    ## Wraps a listening socket. Use `SharedTcpListener.bind`.
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

    ## Opens a TCP socket bound to `address` and starts listening on it, as
    ## `TcpListener.bind` does.
    ##
    ## @param address the local address to listen on (port 0 for any free
    ##   port)
    ## @returns the listening socket, or the errors `TcpListener.bind`
    ##   returns
    static bind(address: SocketAddress): IoResult<SharedTcpListener> {
        var bound = TcpListener.bind(address);
        if (bound.is_err()) {
            return IoResult<SharedTcpListener>.err(bound.error());
        }
        var listener = bound.value();
        var h = listener._handle;
        listener._handle = _io_sys_socket_invalid();
        return IoResult<SharedTcpListener>.ok(SharedTcpListener(h));
    }

    ## Waits for the next incoming connection and returns it, as
    ## `TcpListener.accept` does. Several threads may wait at once; each
    ## connection wakes one of them (or, on some systems, several, and the
    ## rest keep waiting).
    ##
    ## @returns the connected stream, owned by the calling thread, and the
    ##   peer's address; an error when the waiting task is cancelled, or
    ##   another platform error
    accept(): IoResult<(TcpStream, SocketAddress)> {
        var h = _handle as SocketHandle;
        if (!_io_sys_socket_valid(h)) {
            return IoResult<(TcpStream, SocketAddress)>.err(_io_socket_closed_error());
        }
        var accepted = _io_sys_socket_accept(h);
        # Another thread may close the socket once this one stops using it.
        _io_socket_release_idle(h);
        if (accepted.is_err()) {
            return IoResult<(TcpStream, SocketAddress)>.err(accepted.error());
        }
        var (handle, peer) = accepted.value();
        var stream = TcpStream();
        stream._handle = handle;
        return IoResult<(TcpStream, SocketAddress)>.ok((stream, peer));
    }

    ## Returns the address the listener is bound to, with the port the
    ## system chose when it was bound to port 0.
    ##
    ## @returns the local address, or a platform error
    local_address(): IoResult<SocketAddress> {
        var h = _handle as SocketHandle;
        if (!_io_sys_socket_valid(h)) {
            return IoResult<SocketAddress>.err(_io_socket_closed_error());
        }
        return _io_sys_socket_local_address(h);
    }
}

# ── TcpStream ────────────────────────────────────────────────────────────────

## A TCP connection: a reliable, ordered stream of bytes in both directions.
##
## Get one from `TcpStream.connect` (to an address), `TcpStream.connect_host`
## (to a host name) or `TcpListener.accept`. `read` appends what has arrived
## to a byte array and returns 0 once the peer has closed its side; `write`
## sends bytes.
##
## Each call is one system call and blocks until it can make progress: a
## `read` returns as soon as some bytes are there, not when `max` bytes are,
## and a `write` may send fewer bytes than given. `read_exact` and
## `write_all` loop until done. Sending never raises `SIGPIPE`; writing to a
## connection the peer has closed fails with `is_connection_reset()`.
##
## Closing: the destructor closes the socket when the last reference goes;
## `close()` closes it earlier and reports errors. Every operation on a
## closed stream fails with an error no `IoError` predicate identifies
## (`EBADF` on POSIX, `ERROR_INVALID_HANDLE` on Windows).
##
## @example
##     import io;
##
##     var stream = io.TcpStream.connect_host("example.com", 80).value();
##     stream.write_string("HEAD / HTTP/1.0\r\n\r\n");
##     var reply = Array<u8>();
##     while (stream.read(reply, 4096).value() > 0) {
##     }
## @see TcpListener
[NotCopyable("owns an operating-system socket and cannot be copied")]
export struct TcpStream {
    ## The socket: a descriptor on POSIX (-1 when closed), a `SOCKET` on
    ## Windows (`INVALID_SOCKET` when closed).
    SocketHandle _handle;

    ## Creates a closed stream: `is_open()` is false and every operation
    ## fails. Use `TcpStream.connect` or `TcpListener.accept` to get an open
    ## one.
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

    ## Opens a connection to `address`, waiting until it is established.
    ##
    ## @param address the address to connect to
    ## @returns the connected stream; an error with `is_connection_refused()`
    ##   when nothing listens there, `is_timed_out()` when the peer does not
    ##   answer, or another platform error
    static connect(address: SocketAddress): IoResult<TcpStream> {
        var opened = _io_sys_socket_open(address.is_v6(), true);
        if (opened.is_err()) {
            return IoResult<TcpStream>.err(opened.error());
        }
        var stream = TcpStream();
        stream._handle = opened.value();
        var connected = _io_sys_socket_connect(stream._handle, address);
        if (connected.is_err()) {
            return IoResult<TcpStream>.err(connected.error());
        }
        return IoResult<TcpStream>.ok(stream);
    }

    ## Resolves `host` with `resolve` and connects to the first of its
    ## addresses that accepts, trying them in order.
    ##
    ## @param host a host name or an IP address
    ## @param port the port to connect to
    ## @returns the connected stream; the error from `resolve` when the name
    ##   has no address, or the error from the last address tried
    ## @example
    ##     var r = TcpStream.connect_host("localhost", 8080);
    ##     if (r.is_err() && r.error().is_connection_refused()) {
    ##         print("nothing is listening on 8080");
    ##     }
    static connect_host(host: String, port: u16): IoResult<TcpStream> {
        var addresses = resolve(host, port);
        if (addresses.is_err()) {
            return IoResult<TcpStream>.err(addresses.error());
        }
        var last = IoResult<TcpStream>.err(IoError(_io_sys_code_not_found(), "no address found for '" + host + "'"));
        for (var address in addresses.value()) {
            var attempt = TcpStream.connect(address);
            if (attempt.is_ok()) {
                return attempt;
            }
            last = attempt;
        }
        return last;
    }

    ## Returns whether the stream is open.
    ##
    ## @returns false after `close()` and for a `TcpStream()` never connected
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
    ## `buffer` with a single system call, like `File.read`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read; 0 reads nothing and returns 0
    ## @returns the number of bytes appended, 0 once the peer has closed its
    ##   side of the connection; an error with `is_connection_reset()` when
    ##   the connection was reset, an error when the stream is closed, or
    ##   another platform error
    ## @example
    ##     var buffer = Array<u8>();
    ##     var n = stream.read(buffer, 4096).value();   # buffer.count() == n
    read(buffer: u8[], max: ulong): IoResult<ulong> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        if (max == 0) {
            return IoResult<ulong>.ok(0);
        }
        buffer.reserve(buffer._size + max);
        var r = _io_sys_socket_receive(_handle, buffer._data + buffer._size, max);
        if (r.is_ok()) {
            buffer._size = buffer._size + r.value();
        }
        return r;
    }

    ## Reads until exactly `count` more bytes are appended to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param count the number of bytes to read
    ## @returns an Ok result once `count` bytes are appended; an error when
    ##   the peer closes the connection first ("connection closed after n of
    ##   count bytes", code `EIO` on POSIX, `ERROR_HANDLE_EOF` on Windows,
    ##   which no predicate matches), or an error as for `read`. The bytes
    ##   read before an error stay in `buffer`.
    read_exact(buffer: u8[], count: ulong): IoResult<void> {
        ulong done = 0;
        while (done < count) {
            var r = read(buffer, count - done);
            if (r.is_err()) {
                return IoResult<void>.err(r.error());
            }
            if (r.value() == 0) {
                var out = Array<u8>();
                _io_append_text(out, "connection closed after ");
                _io_append_decimal(out, done);
                _io_append_text(out, " of ");
                _io_append_decimal(out, count);
                _io_append_text(out, " bytes");
                return IoResult<void>.err(IoError(_io_sys_code_unexpected_end(), _io_string_from_bytes(out)));
            }
            done = done + r.value();
        }
        return _io_ok_void();
    }

    ## Sends bytes from `data` with a single system call, waiting until the
    ## system can take at least some of them.
    ##
    ## The send may be partial: it can send fewer than `data.count()` bytes.
    ## Use `write_all` to send everything.
    ##
    ## @param data the bytes to send
    ## @returns the number of bytes sent, which may be less than
    ##   `data.count()`; an error with `is_connection_reset()` when the peer
    ##   has closed or reset the connection, an error when the stream is
    ##   closed, or another platform error
    write(data: u8[]): IoResult<ulong> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        return _io_sys_socket_send(_handle, data._data, data._size);
    }

    ## Sends all of `data`, repeating the send until every byte is sent.
    ##
    ## If an error occurs part of `data` may already have been sent.
    ##
    ## @param data the bytes to send
    ## @returns an Ok result once every byte is sent; an error as for `write`
    write_all(data: u8[]): IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_socket_send_all(_handle, data._data, data._size);
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
        return _io_socket_send_all(_handle, text.c_str() as __ptr<u8>, text.size());
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

    ## Turns Nagle's algorithm off (`true`) or on (`false`) with
    ## `TCP_NODELAY`. With it off, small writes go out at once instead of
    ## being held back to combine with later ones: lower latency for
    ## request/response traffic, more packets.
    ##
    ## @param enabled true to send small writes immediately
    ## @returns an Ok result on success; an error when the stream is closed,
    ##   or another platform error
    set_no_delay(enabled: bool): IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_socket_set_no_delay(_handle, enabled);
    }

    ## Returns this side's address of the connection.
    ##
    ## @returns the local address; an error when the stream is closed, or
    ##   another platform error
    local_address(): IoResult<SocketAddress> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<SocketAddress>.err(c.error());
        }
        return _io_sys_socket_local_address(_handle);
    }

    ## Returns the peer's address.
    ##
    ## @returns the peer's address; an error when the stream is closed, or
    ##   another platform error
    peer_address(): IoResult<SocketAddress> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<SocketAddress>.err(c.error());
        }
        return _io_sys_socket_peer_address(_handle);
    }

    ## Moves the connection out of this stream, into a token another thread
    ## can take it from with `TcpStream.adopt`. The stream is closed
    ## afterwards (`is_open()` is false), and a task waiting on it on this
    ## worker wakes with an error.
    ##
    ## Inside `async.run` a socket belongs to the worker that uses it; this
    ## is how a task hands a connection to a task on another worker, such as
    ## one started with `async.spawn`.
    ##
    ## @returns the token; for a closed stream, one that `adopt` fails on
    ## @example
    ##     import async;
    ##     import io;
    ##
    ##     serve(listener: io.TcpListener) {
    ##         var (stream, peer) = listener.accept().value();
    ##         var transfer = stream.into_transfer();
    ##         async.spawn<void>(() => {
    ##             var mine = io.TcpStream.adopt(transfer).value();
    ##             mine.write_string("hello from another worker");
    ##         });
    ##     }
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
    static adopt(transfer: SocketTransfer): IoResult<TcpStream> {
        var h = transfer._take();
        if (!_io_sys_socket_valid(h)) {
            return IoResult<TcpStream>.err(_io_socket_closed_error());
        }
        var stream = TcpStream();
        stream._handle = h;
        return IoResult<TcpStream>.ok(stream);
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

## A TCP connection on its way from one thread to another: made by
## `TcpStream.into_transfer`, taken by `TcpStream.adopt`. Unlike a
## `TcpStream`, it is thread-safe, so a `shared` function (a body for
## `async.spawn` or `Thread.spawn`) can capture it and a `Channel` can carry
## it. If no one adopts it, the connection is closed when the last
## reference goes.
[Shared]
export struct SocketTransfer {
    # The socket as a number (`SocketHandle` widened to `long`), or -1 once
    # taken; `INVALID_SOCKET` on Windows is -1 too.
    const _handle: Atomic<long>;

    ## Wraps a socket handle. `TcpStream.into_transfer` makes these; use it.
    ##
    ## @param handle the socket, or an invalid handle for an empty token
    construct(handle: SocketHandle) {
        _handle = Atomic<long>(handle as long);
    }

    ## Closes the connection if no one adopted it.
    destruct {
        var h = _take();
        if (_io_sys_socket_valid(h)) {
            _io_sys_socket_close(h);
        }
    }

    # Takes the handle out, leaving the token empty.
    _take(): SocketHandle {
        return _handle.exchange(-1) as SocketHandle;
    }
}

# Sends all `n` bytes at `p`, looping over partial sends.
export _io_socket_send_all(h: SocketHandle, p: __ptr<u8>, n: ulong): IoResult<void> {
    ulong done = 0;
    while (done < n) {
        var r = _io_sys_socket_send(h, p + done, n - done);
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

# ── UdpSocket ────────────────────────────────────────────────────────────────

## A UDP socket: sends and receives datagrams, each delivered whole or not at
## all, in no guaranteed order.
##
## `UdpSocket.bind` opens one on a local address (port 0 for any free port).
## `send_to` and `receive_from` name the peer on each call; after `connect`,
## `send` and `receive` use the connected peer and ignore datagrams from
## anyone else.
##
## Each receive takes one datagram. A datagram longer than `max` is
## truncated to `max` bytes and the rest is lost, so size `max` for the
## largest datagram expected (at most 65507 bytes over IPv4).
##
## Closing: the destructor closes the socket when the last reference goes;
## `close()` closes it earlier and reports errors.
##
## @example
##     import io;
##
##     var socket = io.UdpSocket.bind(io.SocketAddress.parse("0.0.0.0:9000").value()).value();
##     var buffer = Array<u8>();
##     var (n, from) = socket.receive_from(buffer, 65507).value();
##     socket.send_to(buffer, from);   # echo it back
[NotCopyable("owns an operating-system socket and cannot be copied")]
export struct UdpSocket {
    ## The socket: a descriptor on POSIX (-1 when closed), a `SOCKET` on
    ## Windows (`INVALID_SOCKET` when closed).
    SocketHandle _handle;

    ## Creates a closed socket: `is_open()` is false and every operation
    ## fails. Use `UdpSocket.bind` to get an open one.
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

    ## Opens a UDP socket bound to `address`.
    ##
    ## @param address the local address to receive on; port 0 for any free
    ##   port
    ## @returns the bound socket; an error with `is_address_in_use()` when
    ##   another socket has the port, `is_address_not_available()` when the
    ##   address is not one of this machine's, or another platform error
    static bind(address: SocketAddress): IoResult<UdpSocket> {
        var opened = _io_sys_socket_open(address.is_v6(), false);
        if (opened.is_err()) {
            return IoResult<UdpSocket>.err(opened.error());
        }
        var socket = UdpSocket();
        socket._handle = opened.value();
        var bound = _io_sys_socket_bind(socket._handle, address);
        if (bound.is_err()) {
            return IoResult<UdpSocket>.err(bound.error());
        }
        return IoResult<UdpSocket>.ok(socket);
    }

    ## Returns whether the socket is open.
    ##
    ## @returns false after `close()` and for a `UdpSocket()` never bound
    is_open(): bool {
        return _io_sys_socket_valid(_handle);
    }

    _check_open(): IoResult<void> {
        if (!is_open()) {
            return IoResult<void>.err(_io_socket_closed_error());
        }
        return _io_ok_void();
    }

    ## Sends `data` as one datagram to `address`.
    ##
    ## @param data the datagram's bytes
    ## @param address where to send it
    ## @returns the number of bytes sent (all of `data`); an error when the
    ##   datagram is too large, when the socket is closed, or another
    ##   platform error
    send_to(data: u8[], address: SocketAddress): IoResult<ulong> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        return _io_sys_socket_send_to(_handle, data._data, data._size, address);
    }

    ## Waits for the next datagram and appends up to `max` of its bytes to
    ## `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to keep; the rest of a longer datagram is
    ##   lost. 0 reads nothing and returns at once.
    ## @returns the number of bytes appended and the sender's address; an
    ##   error when the socket is closed, or another platform error
    receive_from(buffer: u8[], max: ulong): IoResult<(ulong, SocketAddress)> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<(ulong, SocketAddress)>.err(c.error());
        }
        if (max == 0) {
            return IoResult<(ulong, SocketAddress)>.ok((0 as ulong, SocketAddress()));
        }
        buffer.reserve(buffer._size + max);
        var r = _io_sys_socket_receive_from(_handle, buffer._data + buffer._size, max);
        if (r.is_ok()) {
            buffer._size = buffer._size + r.value().0;
        }
        return r;
    }

    ## Sets the socket's default peer: `send` goes to `address`, and
    ## `receive` and `receive_from` only take datagrams from it. No packet is
    ## sent.
    ##
    ## @param address the peer
    ## @returns an Ok result on success; an error when the socket is closed,
    ##   or another platform error
    connect(address: SocketAddress): IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_socket_connect(_handle, address);
    }

    ## Sends `data` as one datagram to the connected peer.
    ##
    ## @param data the datagram's bytes
    ## @returns the number of bytes sent; an error when the socket is not
    ##   connected or is closed, or another platform error
    send(data: u8[]): IoResult<ulong> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.error());
        }
        return _io_sys_socket_send(_handle, data._data, data._size);
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

    ## Allows (`true`) or forbids (`false`) sending to a broadcast address
    ## such as `255.255.255.255` (`SO_BROADCAST`).
    ##
    ## @param enabled true to allow broadcasts
    ## @returns an Ok result on success; an error when the socket is closed,
    ##   or another platform error
    set_broadcast(enabled: bool): IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_socket_set_broadcast(_handle, enabled);
    }

    ## Returns the address the socket is bound to, with the port the system
    ## chose when it was bound to port 0.
    ##
    ## @returns the local address; an error when the socket is closed, or
    ##   another platform error
    local_address(): IoResult<SocketAddress> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<SocketAddress>.err(c.error());
        }
        return _io_sys_socket_local_address(_handle);
    }

    ## Returns the connected peer's address.
    ##
    ## @returns the peer's address; an error when the socket is not
    ##   connected or is closed, or another platform error
    peer_address(): IoResult<SocketAddress> {
        var c = _check_open();
        if (c.is_err()) {
            return IoResult<SocketAddress>.err(c.error());
        }
        return _io_sys_socket_peer_address(_handle);
    }

    ## Closes the socket now. Closing a closed socket does nothing.
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
