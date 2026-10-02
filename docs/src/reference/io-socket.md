<!-- Generated from runtime/io/socket.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Sockets

TCP and UDP sockets: `TcpListener` accepts connections, `TcpStream` is
one connection, `UdpSocket` sends and receives datagrams.

Every call blocks the calling thread until it completes. Addresses are
`SocketAddress` values; `resolve` turns a host name into them.

Source: `runtime/io/socket.pep`

## TcpListener

```pepper
[NotCopyable("owns an operating-system socket and cannot be copied")] struct TcpListener
```

A TCP socket that listens for connections.

`TcpListener.bind` opens one on a local address; each `accept()` waits for
the next connection and returns it as a `TcpStream` together with the
peer's address. Binding to port 0 lets the system choose a free port;
`local_address()` tells which.

On POSIX the listener sets `SO_REUSEADDR`, so a server can restart while
connections from its previous run linger in `TIME_WAIT`. An IPv6 listener
keeps the system's default for accepting IPv4 too (on Linux and macOS it
does, on Windows it does not).

Closing: the destructor closes the socket when the last reference goes;
`close()` closes it earlier and reports errors. Every operation on a
closed listener fails with an error no `IoError` predicate identifies
(`EBADF` on POSIX, `ERROR_INVALID_HANDLE` on Windows).

**See also**
- `TcpStream`

**Example**
```pepper
    import io;

    var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
    print(listener.local_address().value().to_string());   # 127.0.0.1:<port>
    while (true) {
        var (stream, peer) = listener.accept().value();
        stream.write_all("hello " + peer.to_string());
    }
```

### Constructor

#### TcpListener()

```pepper
construct()
```

Creates a closed listener: `is_open()` is false and every operation
fails. Use `TcpListener.bind` to get an open one.

### Static methods

#### bind

```pepper
static bind(address: SocketAddress): IoResult<TcpListener>
```

Opens a TCP socket bound to `address` and starts listening on it.

**Parameters**
- `address` — the local address to listen on: a specific interface (`127.0.0.1:8080`), every interface (`0.0.0.0:8080`, `[::]:8080`), or port 0 for any free port

**Returns**
- the listening socket; an error with `is_address_in_use()` when another socket has the port, `is_address_not_available()` when the address is not one of this machine's, `is_permission_denied()` for a privileged port, or another platform error

### Methods

#### is_open

```pepper
is_open(): bool
```

Returns whether the listener is open.

**Returns**
- false after `close()` and for a `TcpListener()` never bound

#### accept

```pepper
accept(): IoResult<(TcpStream, SocketAddress)>
```

Waits for the next incoming connection and returns it.

**Returns**
- the connected stream and the peer's address; an error when the listener is closed, or another platform error

#### incoming

```pepper
incoming(): Incoming
```

Returns an iterator that accepts connections one at a time, for a
`for` loop over incoming streams.

Each step waits in `accept()` and yields the connected stream, or the
error `accept()` returned; an error does not end the iteration, so a
server can log it and keep going, or `break`. The iteration ends once
the listener is closed. Use `accept()` instead when the peer's address
is needed.

**Returns**
- a new `Incoming` positioned before the first connection

**Example**
```pepper
    import io;

    var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:8080").value()).value();
    for (var connection in listener.incoming()) {
        if (connection.is_err()) {
            print(connection.error().message);
            continue;
        }
        connection.value().write_all("hello");
    }
```

#### local_address

```pepper
local_address(): IoResult<SocketAddress>
```

Returns the address the listener is bound to, with the port the
system chose when it was bound to port 0.

**Returns**
- the local address; an error when the listener is closed, or another platform error

#### close

```pepper
close(): IoResult<void>
```

Closes the listener now. Closing a closed listener does nothing.
Connections already accepted stay open.

**Returns**
- an Ok result on success or when already closed; the platform error when closing fails

## Incoming

```pepper
struct Incoming
```

The iterator `TcpListener.incoming()` returns: each connection the
listener accepts, as an `IoResult<TcpStream>`.

`next()` waits for the next connection; an accept error is yielded as an
item rather than ending the iteration. The iteration ends once the
listener is closed. The iterator holds a reference to the listener, so
the listener stays open while the iterator lives.

### Constructor

#### Incoming()

```pepper
construct(listener: TcpListener)
```

Makes an iterator over the connections `listener` accepts.

**Parameters**
- `listener` — the listener to accept on

### Methods

#### next

```pepper
next(): bool
```

Waits for the next connection.

**Returns**
- true with the connection or the accept error as the current item; false once the listener is closed

#### current

```pepper
current(): IoResult<TcpStream>
```

Returns the item the last successful `next()` moved to.

**Returns**
- the accepted stream, or the error accepting it

**Panics**
- if `next()` was never called or returned false ("Incoming.current() without a connection")

## SharedTcpListener

```pepper
[Shared] struct SharedTcpListener
```

A TCP listening socket that any thread can accept connections on: the
thread-safe counterpart of `TcpListener`, for servers that accept on every
worker of `async.run` at once (see `async.spawn_on_each_worker`). Each
connection goes to one of the threads waiting in `accept`, and the stream
it returns belongs to that thread.

A `shared` function may capture it. There is no `close()`, since another
thread may be waiting on it: the socket closes when the last reference
goes, which, for accept loops in tasks, is once `async.run` has cancelled
them (`accept` then fails and the loop returns).

**See also**
- `TcpListener`

**Example**
```pepper
    import async;
    import io;

    main(): int {
        async.run(() => {
            var listener = io.SharedTcpListener.bind(io.SocketAddress.parse("0.0.0.0:7000").value()).value();
            async.spawn_on_each_worker(() => {
                while (true) {
                    var accepted = listener.accept();
                    if (accepted.is_err()) {
                        return;
                    }
                    var (stream, peer) = accepted.value();
                    stream.write_all("hello");
                }
            });
        });
        return 0;
    }
```

### Constructor

#### SharedTcpListener()

```pepper
construct(handle: SocketHandle)
```

Wraps a listening socket. Use `SharedTcpListener.bind`.

**Parameters**
- `handle` — the listening socket, or an invalid handle for none

### Static methods

#### bind

```pepper
static bind(address: SocketAddress): IoResult<SharedTcpListener>
```

Opens a TCP socket bound to `address` and starts listening on it, as
`TcpListener.bind` does.

**Parameters**
- `address` — the local address to listen on (port 0 for any free port)

**Returns**
- the listening socket, or the errors `TcpListener.bind` returns

### Methods

#### accept

```pepper
accept(): IoResult<(TcpStream, SocketAddress)>
```

Waits for the next incoming connection and returns it, as
`TcpListener.accept` does. Several threads may wait at once; each
connection wakes one of them (or, on some systems, several, and the
rest keep waiting).

**Returns**
- the connected stream, owned by the calling thread, and the peer's address; an error when the waiting task is cancelled, or another platform error

#### local_address

```pepper
local_address(): IoResult<SocketAddress>
```

Returns the address the listener is bound to, with the port the
system chose when it was bound to port 0.

**Returns**
- the local address, or a platform error

## TcpStream

```pepper
[NotCopyable("owns an operating-system socket and cannot be copied")] struct TcpStream
```

A TCP connection: a reliable, ordered stream of bytes in both directions.

Get one from `TcpStream.connect` (to an address), `TcpStream.connect_host`
(to a host name) or `TcpListener.accept`. `read` appends what has arrived
to a byte array and returns 0 once the peer has closed its side; `write`
sends bytes.

Each call is one system call and blocks until it can make progress: a
`read` returns as soon as some bytes are there, not when `max` bytes are,
and a `write` may send fewer bytes than given. `read_exact` and
`write_all` loop until done. Sending never raises `SIGPIPE`; writing to a
connection the peer has closed fails with `is_connection_reset()`.

Closing: the destructor closes the socket when the last reference goes;
`close()` closes it earlier and reports errors. Every operation on a
closed stream fails with an error no `IoError` predicate identifies
(`EBADF` on POSIX, `ERROR_INVALID_HANDLE` on Windows).

**See also**
- `TcpListener`

**Example**
```pepper
    import io;

    var stream = io.TcpStream.connect_host("example.com", 80).value();
    stream.write_all("HEAD / HTTP/1.0\r\n\r\n");
    var reply = Array<u8>();
    while (stream.read(reply, 4096).value() > 0) {
    }
```

### Constructor

#### TcpStream()

```pepper
construct()
```

Creates a closed stream: `is_open()` is false and every operation
fails. Use `TcpStream.connect` or `TcpListener.accept` to get an open
one.

### Static methods

#### connect

```pepper
static connect(address: SocketAddress): IoResult<TcpStream>
```

Opens a connection to `address`, waiting until it is established.

**Parameters**
- `address` — the address to connect to

**Returns**
- the connected stream; an error with `is_connection_refused()` when nothing listens there, `is_timed_out()` when the peer does not answer, or another platform error

#### connect_host

```pepper
static connect_host(host: String, port: u16): IoResult<TcpStream>
```

Resolves `host` with `resolve` and connects to the first of its
addresses that accepts, trying them in order.

**Parameters**
- `host` — a host name or an IP address
- `port` — the port to connect to

**Returns**
- the connected stream; the error from `resolve` when the name has no address, or the error from the last address tried

**Example**
```pepper
    var r = TcpStream.connect_host("localhost", 8080);
    if (r.is_err() && r.error().is_connection_refused()) {
        print("nothing is listening on 8080");
    }
```

#### adopt

```pepper
static adopt(transfer: SocketTransfer): IoResult<TcpStream>
```

Takes the connection out of `transfer` (see `into_transfer`) into a
new stream on the calling thread. Only the first `adopt` of a token
gets the connection.

**Parameters**
- `transfer` — the token from `into_transfer`

**Returns**
- the stream; an error when the token is empty (already adopted, or made from a closed stream)

### Methods

#### is_open

```pepper
is_open(): bool
```

Returns whether the stream is open.

**Returns**
- false after `close()` and for a `TcpStream()` never connected

#### read

```pepper
read(buffer: u8[], max: ulong): IoResult<ulong>
```

Waits until data arrives, then appends up to `max` bytes of it to
`buffer` with a single system call, like `File.read`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read; 0 reads nothing and returns 0

**Returns**
- the number of bytes appended, 0 once the peer has closed its side of the connection; an error with `is_connection_reset()` when the connection was reset, an error when the stream is closed, or another platform error

**Example**
```pepper
    var buffer = Array<u8>();
    var n = stream.read(buffer, 4096).value();   # buffer.count == n
```

#### read_exact

```pepper
read_exact(buffer: u8[], count: ulong): IoResult<void>
```

Reads until exactly `count` more bytes are appended to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `count` — the number of bytes to read

**Returns**
- an Ok result once `count` bytes are appended; an error when the peer closes the connection first ("connection closed after n of count bytes", code `EIO` on POSIX, `ERROR_HANDLE_EOF` on Windows, which no predicate matches), or an error as for `read`. The bytes read before an error stay in `buffer`.

#### write

```pepper
write(data: u8[]): IoResult<ulong>
```

Sends bytes from `data` with a single system call, waiting until the
system can take at least some of them.

The send may be partial: it can send fewer than `data.count` bytes.
Use `write_all` to send everything.

**Parameters**
- `data` — the bytes to send

**Returns**
- the number of bytes sent, which may be less than `data.count`; an error with `is_connection_reset()` when the peer has closed or reset the connection, an error when the stream is closed, or another platform error

#### write_all

```pepper
write_all(data: u8[]): IoResult<void>
```

Sends all of `data`, repeating the send until every byte is sent.

If an error occurs part of `data` may already have been sent.

**Parameters**
- `data` — the bytes to send

**Returns**
- an Ok result once every byte is sent; an error as for `write`

#### write_all

```pepper
write_all(text: String): IoResult<void>
```

Sends all of the UTF-8 bytes of `text`, as `write_all(u8[])` does.
No newline or terminator is added.

**Parameters**
- `text` — the text to send

**Returns**
- an Ok result once every byte is sent; an error as for `write`

**Example**
```pepper
    stream.write_all("ping");
```

#### write_string

```pepper
[Deprecated("use 'write_all' instead", "write_all")] write_string(text: String): IoResult<void>
```

Deprecated: use `write_all` instead. Sends all of the UTF-8 bytes of
`text`, exactly like `write_all(text)`.

**Parameters**
- `text` — the text to send

**Returns**
- an Ok result once every byte is sent; an error as for `write_all`

**See also**
- `write_all`

#### shutdown_write

```pepper
shutdown_write(): IoResult<void>
```

Closes the sending side of the connection: the peer's reads return 0
once it has read everything sent before. This side can still read.

**Returns**
- an Ok result on success; an error when the stream is closed, or another platform error

#### set_no_delay

```pepper
set_no_delay(enabled: bool): IoResult<void>
```

Turns Nagle's algorithm off (`true`) or on (`false`) with
`TCP_NODELAY`. With it off, small writes go out at once instead of
being held back to combine with later ones: lower latency for
request/response traffic, more packets.

**Parameters**
- `enabled` — true to send small writes immediately

**Returns**
- an Ok result on success; an error when the stream is closed, or another platform error

#### local_address

```pepper
local_address(): IoResult<SocketAddress>
```

Returns this side's address of the connection.

**Returns**
- the local address; an error when the stream is closed, or another platform error

#### peer_address

```pepper
peer_address(): IoResult<SocketAddress>
```

Returns the peer's address.

**Returns**
- the peer's address; an error when the stream is closed, or another platform error

#### into_transfer

```pepper
into_transfer(): SocketTransfer
```

Moves the connection out of this stream, into a token another thread
can take it from with `TcpStream.adopt`. The stream is closed
afterwards (`is_open()` is false), and a task waiting on it on this
worker wakes with an error.

Inside `async.run` a socket belongs to the worker that uses it; this
is how a task hands a connection to a task on another worker, such as
one started with `async.spawn`.

**Returns**
- the token; for a closed stream, one that `adopt` fails on

**Example**
```pepper
    import async;
    import io;

    serve(listener: io.TcpListener) {
        var (stream, peer) = listener.accept().value();
        var transfer = stream.into_transfer();
        async.spawn<void>(() => {
            var mine = io.TcpStream.adopt(transfer).value();
            mine.write_all("hello from another worker");
        });
    }
```

#### close

```pepper
close(): IoResult<void>
```

Closes the connection now. Closing a closed stream does nothing.

**Returns**
- an Ok result on success or when already closed; the platform error when closing fails

## SocketTransfer

```pepper
[Shared] struct SocketTransfer
```

A connection on its way from one thread to another: made by
`TcpStream.into_transfer` (or `UnixStream.into_transfer`), taken by
`TcpStream.adopt` (or `UnixStream.adopt`, for a Unix domain connection).
Unlike a stream, it is thread-safe, so a `shared` function (a body for
`async.spawn` or `Thread.spawn`) can capture it and a `Channel` can carry
it. If no one adopts it, the connection is closed when the last
reference goes.

### Constructor

#### SocketTransfer()

```pepper
construct(handle: SocketHandle)
```

Wraps a socket handle. `TcpStream.into_transfer` makes these; use it.

**Parameters**
- `handle` — the socket, or an invalid handle for an empty token

## UdpSocket

```pepper
[NotCopyable("owns an operating-system socket and cannot be copied")] struct UdpSocket
```

A UDP socket: sends and receives datagrams, each delivered whole or not at
all, in no guaranteed order.

`UdpSocket.bind` opens one on a local address (port 0 for any free port).
`send_to` and `receive_from` name the peer on each call; after `connect`,
`send` and `receive` use the connected peer and ignore datagrams from
anyone else.

Each receive takes one datagram. A datagram longer than `max` is
truncated to `max` bytes and the rest is lost, so size `max` for the
largest datagram expected (at most 65507 bytes over IPv4).

Closing: the destructor closes the socket when the last reference goes;
`close()` closes it earlier and reports errors.

**Example**
```pepper
    import io;

    var socket = io.UdpSocket.bind(io.SocketAddress.parse("0.0.0.0:9000").value()).value();
    var buffer = Array<u8>();
    var (n, from) = socket.receive_from(buffer, 65507).value();
    socket.send_to(buffer, from);   # echo it back
```

### Constructor

#### UdpSocket()

```pepper
construct()
```

Creates a closed socket: `is_open()` is false and every operation
fails. Use `UdpSocket.bind` to get an open one.

### Static methods

#### bind

```pepper
static bind(address: SocketAddress): IoResult<UdpSocket>
```

Opens a UDP socket bound to `address`.

**Parameters**
- `address` — the local address to receive on; port 0 for any free port

**Returns**
- the bound socket; an error with `is_address_in_use()` when another socket has the port, `is_address_not_available()` when the address is not one of this machine's, or another platform error

### Methods

#### is_open

```pepper
is_open(): bool
```

Returns whether the socket is open.

**Returns**
- false after `close()` and for a `UdpSocket()` never bound

#### send_to

```pepper
send_to(data: u8[], address: SocketAddress): IoResult<ulong>
```

Sends `data` as one datagram to `address`.

**Parameters**
- `data` — the datagram's bytes
- `address` — where to send it

**Returns**
- the number of bytes sent (all of `data`); an error when the datagram is too large, when the socket is closed, or another platform error

#### receive_from

```pepper
receive_from(buffer: u8[], max: ulong): IoResult<(ulong, SocketAddress)>
```

Waits for the next datagram and appends up to `max` of its bytes to
`buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to keep; the rest of a longer datagram is lost. 0 reads nothing and returns at once.

**Returns**
- the number of bytes appended and the sender's address; an error when the socket is closed, or another platform error

#### connect

```pepper
connect(address: SocketAddress): IoResult<void>
```

Sets the socket's default peer: `send` goes to `address`, and
`receive` and `receive_from` only take datagrams from it. No packet is
sent.

**Parameters**
- `address` — the peer

**Returns**
- an Ok result on success; an error when the socket is closed, or another platform error

#### send

```pepper
send(data: u8[]): IoResult<ulong>
```

Sends `data` as one datagram to the connected peer.

**Parameters**
- `data` — the datagram's bytes

**Returns**
- the number of bytes sent; an error when the socket is not connected or is closed, or another platform error

#### receive

```pepper
receive(buffer: u8[], max: ulong): IoResult<ulong>
```

Waits for the next datagram from the connected peer and appends up to
`max` of its bytes to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to keep; the rest of a longer datagram is lost. 0 reads nothing and returns at once.

**Returns**
- the number of bytes appended; an error when the socket is closed, or another platform error

#### set_broadcast

```pepper
set_broadcast(enabled: bool): IoResult<void>
```

Allows (`true`) or forbids (`false`) sending to a broadcast address
such as `255.255.255.255` (`SO_BROADCAST`).

**Parameters**
- `enabled` — true to allow broadcasts

**Returns**
- an Ok result on success; an error when the socket is closed, or another platform error

#### local_address

```pepper
local_address(): IoResult<SocketAddress>
```

Returns the address the socket is bound to, with the port the system
chose when it was bound to port 0.

**Returns**
- the local address; an error when the socket is closed, or another platform error

#### peer_address

```pepper
peer_address(): IoResult<SocketAddress>
```

Returns the connected peer's address.

**Returns**
- the peer's address; an error when the socket is not connected or is closed, or another platform error

#### close

```pepper
close(): IoResult<void>
```

Closes the socket now. Closing a closed socket does nothing.

**Returns**
- an Ok result on success or when already closed; the platform error when closing fails
