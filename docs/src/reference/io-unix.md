<!-- Generated from runtime/io/unix.pep by `pep-doc reference`. Do not edit. -->

# Unix domain sockets

Unix domain sockets: `UnixListener` accepts connections on a path in the
file system, `UnixStream` is one connection, and `UnixDatagram` sends and
receives datagrams.

They work like `TcpListener`, `TcpStream` and `UdpSocket`, for processes
on the same machine: a path names the socket instead of an IP address and
a port. Linux, macOS and Windows (10 version 1803 and later) all have the
stream sockets; `UnixDatagram` is Linux and macOS only.

Binding creates a socket file at the path, and closing the listener does
not remove it: remove it with `File.remove` when the server is done, and
before binding again, since binding to a path that exists fails with
`is_address_in_use()`.

Source: `runtime/io/unix.pep`

## UnixListener

```pepper
[NotCopyable("owns an operating-system socket and cannot be copied")] struct UnixListener
```

A Unix domain socket that listens for connections on a path.

`UnixListener.bind` creates the socket file and listens on it; each
`accept()` waits for the next connection and returns it as a
`UnixStream`.

Closing: the destructor closes the socket when the last reference goes;
`close()` closes it earlier and reports errors. Neither removes the socket
file. Every operation on a closed listener fails with an error no
`IoError` predicate identifies (`EBADF` on POSIX, `ERROR_INVALID_HANDLE`
on Windows).

**See also**
- `UnixStream`

**Example**
```pepper
import io;

var path = io.Directory.temp().join("server.sock");
io.File.remove(path);   # left over from an earlier run
var listener = io.UnixListener.bind(path).value();
while (true) {
    var stream = listener.accept().value();
    stream.write_all("hello");
}
```

### Constructor

#### UnixListener()

```pepper
construct()
```

Creates a closed listener: `is_open()` is false and every operation
fails. Use `UnixListener.bind` to get an open one.

### Static methods

#### bind

```pepper
static bind(path: Path): IoResult<UnixListener>
```

Creates a Unix domain socket at `path` and starts listening on it.

**Parameters**
- `path` — where to create the socket file: at most 107 bytes (103 on macOS)

**Returns**
- the listening socket; an error with `is_address_in_use()` when a file already exists at `path`, `is_invalid_input()` when the path is empty or too long, `is_not_found()` when its directory does not exist, `is_permission_denied()` when the directory cannot be written, or another platform error

### Methods

#### is_open

```pepper
is_open(): bool
```

Returns whether the listener is open.

**Returns**
- false after `close()` and for a `UnixListener()` never bound

#### path

```pepper
path(): Path
```

Returns the path the listener was bound to.

**Returns**
- the path given to `bind`; an empty path for a `UnixListener()` never bound

#### accept

```pepper
accept(): IoResult<UnixStream>
```

Waits for the next incoming connection and returns it.

**Returns**
- the connected stream; an error when the listener is closed, or another platform error

#### close

```pepper
close(): IoResult<void>
```

Closes the listener now. Closing a closed listener does nothing.
Connections already accepted stay open, and the socket file stays.

**Returns**
- an Ok result on success or when already closed; the platform error when closing fails

## SharedUnixListener

```pepper
[Shared] struct SharedUnixListener
```

A Unix domain listening socket that any thread can accept connections on:
the thread-safe counterpart of `UnixListener`, as `SharedTcpListener` is
of `TcpListener`. Each connection goes to one of the threads waiting in
`accept`, and the stream it returns belongs to that thread.

A `shared` function may capture it. There is no `close()`, since another
thread may be waiting on it: the socket closes when the last reference
goes. The socket file stays.

**See also**
- `UnixListener`

**Example**
```pepper
import async;
import io;

main(): int {
    async.run(() => {
        var listener = io.SharedUnixListener.bind(io.Path("/tmp/server.sock")).value();
        async.spawn_on_each_worker(() => {
            while (true) {
                var accepted = listener.accept();
                if (accepted.is_err()) {
                    return;
                }
                accepted.value().write_all("hello");
            }
        });
    });
    return 0;
}
```

### Constructor

#### SharedUnixListener()

```pepper
construct(handle: SocketHandle)
```

Wraps a listening socket. Use `SharedUnixListener.bind`.

**Parameters**
- `handle` — the listening socket, or an invalid handle for none

### Static methods

#### bind

```pepper
static bind(path: Path): IoResult<SharedUnixListener>
```

Creates a Unix domain socket at `path` and starts listening on it, as
`UnixListener.bind` does.

**Parameters**
- `path` — where to create the socket file

**Returns**
- the listening socket, or the errors `UnixListener.bind` returns

### Methods

#### accept

```pepper
accept(): IoResult<UnixStream>
```

Waits for the next incoming connection and returns it, as
`UnixListener.accept` does. Several threads may wait at once; each
connection wakes one of them (or, on some systems, several, and the
rest keep waiting).

**Returns**
- the connected stream, owned by the calling thread; an error when the waiting task is cancelled, or another platform error

## UnixStream

```pepper
[NotCopyable("owns an operating-system socket and cannot be copied")] struct UnixStream
```

A Unix domain stream connection: a reliable, ordered stream of bytes in
both directions between two processes (or threads) on this machine.

Get one from `UnixStream.connect` or `UnixListener.accept`. Reading and
writing work exactly as on a `TcpStream`: `read` appends what has arrived
and returns 0 once the peer has closed its side, `write` may send part of
the data, and `read_exact` and `write_all` loop until done. Sending never
raises `SIGPIPE`; writing to a connection the peer has closed fails with
`is_connection_reset()` (or a broken-pipe error no predicate matches, on
some systems).

Closing: the destructor closes the socket when the last reference goes;
`close()` closes it earlier and reports errors. Every operation on a
closed stream fails with an error no `IoError` predicate identifies.

**See also**
- `UnixListener`

**Example**
```pepper
import io;

var stream = io.UnixStream.connect(io.Path("/tmp/server.sock")).value();
stream.write_all("ping");
var reply = Array<u8>();
stream.read_exact(reply, 4).value();
```

### Constructor

#### UnixStream()

```pepper
construct()
```

Creates a closed stream: `is_open()` is false and every operation
fails. Use `UnixStream.connect` or `UnixListener.accept` to get an
open one.

### Static methods

#### connect

```pepper
static connect(path: Path): IoResult<UnixStream>
```

Connects to the listener at `path`.

**Parameters**
- `path` — the socket file a `UnixListener` is bound to

**Returns**
- the connected stream; an error with `is_not_found()` when no file exists at `path`, `is_connection_refused()` when the file is there but nothing listens on it, `is_invalid_input()` when the path is empty or too long, or another platform error

#### adopt

```pepper
static adopt(transfer: SocketTransfer): IoResult<UnixStream>
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
- false after `close()` and for a `UnixStream()` never connected

#### read

```pepper
read(buffer: u8[], max: ulong): IoResult<ulong>
```

Waits until data arrives, then appends up to `max` bytes of it to
`buffer` with a single system call, like `TcpStream.read`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read; 0 reads nothing and returns 0

**Returns**
- the number of bytes appended, 0 once the peer has closed its side of the connection; an error when the stream is closed, or another platform error

#### read_exact

```pepper
read_exact(buffer: u8[], count: ulong): IoResult<void>
```

Reads until exactly `count` more bytes are appended to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `count` — the number of bytes to read

**Returns**
- an Ok result once `count` bytes are appended; an error when the peer closes the connection first ("connection closed after n of count bytes"), or an error as for `read`. The bytes read before an error stay in `buffer`.

#### write

```pepper
write(data: u8[]): IoResult<ulong>
```

Sends bytes from `data` with a single system call, waiting until the
system can take at least some of them. The send may be partial; use
`write_all` to send everything.

**Parameters**
- `data` — the bytes to send

**Returns**
- the number of bytes sent, which may be less than `data.count`; an error when the peer has closed the connection, when the stream is closed, or another platform error

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

#### set_read_timeout

```pepper
set_read_timeout(milliseconds: ulong): IoResult<void>
```

Limits how long a read waits: when no data arrives for
`milliseconds`, the read fails with `is_timed_out()` and the stream
stays open for another try. Each wait counts on its own, so a
`read_exact` may take longer in all. 0, the default, waits as long as
it takes. It works outside a task and in one, where the task's
`async.timeout` can end the wait sooner.

**Parameters**
- `milliseconds` — the longest wait, at most 4294967295 (about 49 days); 0 for none

**Returns**
- an Ok result; an error with `is_invalid_input()` when `milliseconds` is too large, or an error when the stream is closed

**Example**
```pepper
stream.set_read_timeout(5000);   # give up after 5 seconds of silence
```

#### read_timeout

```pepper
read_timeout(): ulong
```

Returns the read timeout `set_read_timeout` set.

**Returns**
- the timeout in milliseconds, 0 for none

#### set_write_timeout

```pepper
set_write_timeout(milliseconds: ulong): IoResult<void>
```

Limits how long a write waits for the system to take more data: when
it can take none for `milliseconds` (the peer is not reading), the
write fails with `is_timed_out()`, possibly after sending part of the
data. Each wait counts on its own. 0, the default, waits as long as
it takes.

**Parameters**
- `milliseconds` — the longest wait, at most 4294967295 (about 49 days); 0 for none

**Returns**
- an Ok result; an error with `is_invalid_input()` when `milliseconds` is too large, or an error when the stream is closed

#### write_timeout

```pepper
write_timeout(): ulong
```

Returns the write timeout `set_write_timeout` set.

**Returns**
- the timeout in milliseconds, 0 for none

#### into_transfer

```pepper
into_transfer(): SocketTransfer
```

Moves the connection out of this stream, into a token another thread
can take it from with `UnixStream.adopt`, as
`TcpStream.into_transfer` does. The stream is closed afterwards.

**Returns**
- the token; for a closed stream, one that `adopt` fails on

#### close

```pepper
close(): IoResult<void>
```

Closes the connection now. Closing a closed stream does nothing.

**Returns**
- an Ok result on success or when already closed; the platform error when closing fails

## UnixDatagram

```pepper
[Target(OS(Linux) || OS(Mac))] [NotCopyable("owns an operating-system socket and cannot be copied")] struct UnixDatagram
```

A Unix domain datagram socket (`SOCK_DGRAM` on `AF_UNIX`): like a
`UdpSocket` for processes on the same machine, with a path in place of
an address. Linux and macOS only; Windows has no Unix datagram sockets.

Each `send_to` delivers one whole datagram, in order, and the system
never drops one silently. While the receiver's queue is full, a send
waits on Linux; on macOS it fails at once with the platform's "No buffer
space available" (`ENOBUFS`) and sends nothing, so try again later.
`UnixDatagram.bind` creates a socket file at a path, which closing
does not remove (as for `UnixListener`); `UnixDatagram.unbound` makes a
socket that can send but has no path for replies; `UnixDatagram.pair`
makes two connected sockets.

Closing: the destructor closes the socket when the last reference goes;
`close()` closes it earlier and reports errors. Every operation on a
closed socket fails with an error no `IoError` predicate identifies
(`EBADF`).

**See also**
- `UdpSocket`
- `UnixStream`

**Example**
```pepper
import io;

var path = io.Directory.temp().join("events.sock");
io.File.remove(path);   # left over from an earlier run
var server = io.UnixDatagram.bind(path).value();
var client = io.UnixDatagram.unbound().value();
client.send_to("ping".bytes(), path);
var buffer = Array<u8>();
var (n, from) = server.receive_from(buffer, 1024).value();   # 4, an empty path
```

### Constructor

#### UnixDatagram()

```pepper
construct()
```

Creates a closed socket: `is_open()` is false and every operation
fails. Use `UnixDatagram.bind`, `unbound` or `pair` to get an open
one.

### Static methods

#### bind

```pepper
static bind(path: Path): IoResult<UnixDatagram>
```

Creates a datagram socket at `path`, to receive datagrams sent there.

**Parameters**
- `path` — where to create the socket file: at most 107 bytes (103 on macOS)

**Returns**
- the bound socket; an error with `is_address_in_use()` when a file already exists at `path`, `is_invalid_input()` when the path is empty or too long, `is_not_found()` when its directory does not exist, `is_permission_denied()` when the directory cannot be written, or another platform error

#### unbound

```pepper
static unbound(): IoResult<UnixDatagram>
```

Creates a datagram socket with no path. It can send, but a receiver
sees an empty path as the sender and cannot reply.

**Returns**
- the socket; an error when the system is out of descriptors, or another platform error

#### pair

```pepper
static pair(): IoResult<(UnixDatagram, UnixDatagram)>
```

Creates two datagram sockets connected to each other, with no path
(`socketpair(2)`): what one sends with `send`, the other receives. A
common way to talk to a child thread or process.

**Returns**
- the two sockets; an error when the system is out of descriptors, or another platform error

**Example**
```pepper
var (a, b) = io.UnixDatagram.pair().value();
a.send("hi".bytes());
var buffer = Array<u8>();
b.receive(buffer, 16);   # buffer holds "hi"
```

### Methods

#### is_open

```pepper
is_open(): bool
```

Returns whether the socket is open.

**Returns**
- false after `close()` and for a `UnixDatagram()` never opened

#### path

```pepper
path(): Path
```

Returns the path the socket was bound to.

**Returns**
- the path given to `bind`; an empty path for an unbound or paired socket

#### send_to

```pepper
send_to(data: u8[], path: Path): IoResult<ulong>
```

Sends `data` as one datagram to the socket bound at `path`.

**Parameters**
- `data` — the datagram's bytes
- `path` — the socket file a `UnixDatagram` is bound to

**Returns**
- the number of bytes sent (all of `data`); an error with `is_not_found()` when no socket file exists at `path`, `is_connection_refused()` when nothing is bound to it any more, `is_invalid_input()` when the path is empty or too long, or another platform error (such as a datagram larger than the system allows)

#### receive_from

```pepper
receive_from(buffer: u8[], max: ulong): IoResult<(ulong, Path)>
```

Waits for the next datagram and appends up to `max` of its bytes to
`buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to keep; the rest of a longer datagram is lost. 0 reads nothing and returns at once.

**Returns**
- the number of bytes appended and the sender's path (empty when the sender is unbound); an error when the socket is closed, or another platform error

#### connect

```pepper
connect(path: Path): IoResult<void>
```

Sets the socket's default peer: `send` goes to the socket at `path`,
and `receive` and `receive_from` only take datagrams from it. No
datagram is sent.

**Parameters**
- `path` — the socket file a `UnixDatagram` is bound to

**Returns**
- an Ok result on success; an error with `is_not_found()` when no socket file exists at `path`, `is_connection_refused()` when nothing is bound to it, or another platform error

#### send

```pepper
send(data: u8[]): IoResult<ulong>
```

Sends `data` as one datagram to the connected peer (see `connect` and
`pair`).

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

#### set_read_timeout

```pepper
set_read_timeout(milliseconds: ulong): IoResult<void>
```

Limits how long a receive waits: when no datagram arrives for
`milliseconds`, `receive` or `receive_from` fails with
`is_timed_out()` and the socket stays open for another try. 0, the
default, waits as long as it takes. It works outside a task and in
one, where the task's `async.timeout` can end the wait sooner.

**Parameters**
- `milliseconds` — the longest wait, at most 4294967295 (about 49 days); 0 for none

**Returns**
- an Ok result; an error with `is_invalid_input()` when `milliseconds` is too large, or an error when the socket is closed

**Example**
```pepper
socket.set_read_timeout(5000);   # give up after 5 seconds of silence
```

#### read_timeout

```pepper
read_timeout(): ulong
```

Returns the read timeout `set_read_timeout` set.

**Returns**
- the timeout in milliseconds, 0 for none

#### set_write_timeout

```pepper
set_write_timeout(milliseconds: ulong): IoResult<void>
```

Limits how long a send waits for the receiver to take more: when its
queue stays full for `milliseconds` (it is not receiving), `send` or
`send_to` fails with `is_timed_out()` and sends nothing. 0, the
default, waits as long as it takes. On macOS a send to a full queue
fails at once instead (see `UnixDatagram`).

**Parameters**
- `milliseconds` — the longest wait, at most 4294967295 (about 49 days); 0 for none

**Returns**
- an Ok result; an error with `is_invalid_input()` when `milliseconds` is too large, or an error when the socket is closed

#### write_timeout

```pepper
write_timeout(): ulong
```

Returns the write timeout `set_write_timeout` set.

**Returns**
- the timeout in milliseconds, 0 for none

#### close

```pepper
close(): IoResult<void>
```

Closes the socket now. Closing a closed socket does nothing. The
socket file stays.

**Returns**
- an Ok result on success or when already closed; the platform error when closing fails
