# Networking

The `io` module has TCP, UDP and Unix domain sockets, IP and socket
addresses, and host name lookup; the `tls` module encrypts TCP connections,
and the [`http`](http.md) module speaks HTTP over them.
In a plain program every call blocks the calling thread until it completes,
like `File`. To serve several connections at once, give each
one its own [thread](threads.md), or its own [task](tasks.md#sockets): in a
task, a call that has to wait parks only that task.

On WebAssembly (`--target wasm32-wasip1`) there are no sockets, host name
lookups or TLS: each of those calls returns an `IoError` saying it is not
supported on WASI (see [WebAssembly](platform-selection.md#webassembly)).

## Addresses

An `IpAddress` is an IPv4 or IPv6 address. A `SocketAddress` is an IP
address and a port:

```pepper
{{#include ../../examples/networking-addresses.pep}}
```

- `IpAddress.v4(a, b, c, d)` and `IpAddress.v6(a, ..., h)` build an address
  from its bytes or its eight 16-bit groups. `loopback_v4()`,
  `loopback_v6()`, `unspecified_v4()` (`0.0.0.0`) and `unspecified_v6()`
  (`::`) are the well-known ones. `IpAddress()` is `0.0.0.0`.
- `IpAddress.parse` reads dotted decimal IPv4 and the RFC 4291 text form of
  IPv6, and `to_string()` prints the RFC 5952 form: lowercase,
  zeros compressed, `::ffff:1.2.3.4` for an IPv4-mapped address. Parsing and
  printing are the same on every platform.
- `SocketAddress(address, port)` or `SocketAddress.parse("1.2.3.4:80")`
  make a socket address. IPv6 takes brackets: `[::1]:80`.
- `resolve(host, port)` looks a host name up with the system resolver (the
  hosts file and DNS) and returns every address it has, with `port` attached.
  An IP address is returned as is. A name with no address fails with
  `is_not_found()`.

## TCP

A `TcpListener` waits for connections. Each `TcpStream` is one connection:

```pepper
{{#include ../../examples/networking-tcp.pep}}
```

- `TcpListener.bind(address)` listens on a local address. Port 0 lets the
  system pick a free port, and `local_address()` says which one it picked.
  `accept()` waits for the next connection and returns the stream and the
  peer's address as a [tuple](tuples.md). `for (var connection in
  listener.incoming())` accepts one connection per step, yielding an
  `IoResult<TcpStream>` (see [Iteration](iteration.md#reading-files-and-directories)).
- `TcpStream.connect(address)` connects to an address.
  `TcpStream.connect_host(host, port)` resolves a name and tries each of its
  addresses in turn.
- `read(buffer, max)` waits until some data arrives, then appends up to `max`
  bytes of it to `buffer`, the same way `File.read` does. It returns 0 once
  the peer has closed its side. `read_exact(buffer, count)` loops until
  `count` bytes have arrived.
- `write(data)` sends what the system will take in one call.
  `write_all(data)` loops until everything is sent; `data` is a `u8[]` or a
  `String`.
- `shutdown_write()` tells the peer that nothing more is coming, while this
  side can still read.
- `set_no_delay(true)` sends small writes immediately instead of combining
  them.
- `local_address()` and `peer_address()` return the two ends of the
  connection.

## Reading and writing any stream

A `File`, a `TcpStream`, a `UnixStream` and a `tls.TlsStream` have the
`io.Reader` and `io.Writer` traits, so a function that takes an
`io.Reader` (or `<R: io.Reader>`) reads from any of them:

```pepper
{{#include ../../examples/networking-print.pep}}
```

- **`io.Reader`** needs `read(buffer, max)` and gives `lines()`, the
  stream's lines as `IoResult<String>`s, and `chunks(size)`, its bytes in
  arrays of at most `size`, both read as a `for` loop asks for them (see
  [Iteration](iteration.md#reading-files-and-directories)).
- **`io.Writer`** needs `write(data)` and `write_all(data: u8[])` and gives
  `print(value)` and `print_line(value)`. They write the text that
  `to_string` makes of any value, as the global `print` does on standard
  output; `print_line` adds a `\n`. Both return an `IoResult<void>`, like
  `write_all`.
- `io.ByteReader(bytes)` reads an array of bytes as a stream, and
  `io.ByteWriter()` collects what is written in its `bytes` array, for
  code that takes a stream when the data is in memory.
- `compress.DecompressReader` and `compress.CompressWriter` wrap another
  stream (see [Compression and archives](compression.md)).
- Another type gets them by providing those methods and declaring
  `extend MyStream with io.Reader;` or `extend MyStream with io.Writer;`.
- `io.Print`, which gave only `print` and `print_line`, is deprecated: use
  `io.Writer`.

## UDP

A `UdpSocket` sends and receives datagrams. Each one arrives whole or not
at all, and in no guaranteed order:

```pepper
{{#include ../../examples/networking-udp.pep}}
```

- `UdpSocket.bind(address)` opens a socket on a local address.
- `send_to(data, address)` sends one datagram.
  `receive_from(buffer, max)` waits for one datagram, appends it to
  `buffer`, and returns the byte count and the sender. The part of a
  datagram beyond `max` bytes is lost.
- After `connect(address)`, `send` and `receive` use that peer, and
  datagrams from anyone else are dropped.
- `set_broadcast(true)` allows sending to a broadcast address.

## Unix domain sockets

A Unix domain socket connects processes on the same machine through a path
in the file system instead of an IP address and port. `UnixListener` and
`UnixStream` work like `TcpListener` and `TcpStream`:

```pepper
{{#include ../../examples/networking-unix.pep}}
```

- `UnixListener.bind(path)` creates a socket file at `path` and listens on
  it. Binding fails with `is_address_in_use()` if a file is already there,
  and closing the listener does not remove the file, so a server removes it
  with `File.remove` before binding and when it is done.
- `UnixStream.connect(path)` connects to it. It fails with `is_not_found()`
  when there is no socket file, and with `is_connection_refused()` when the
  file is there but nothing listens on it.
- `accept()` returns just the stream: the client's end has no path.
- Reading, writing, `shutdown_write()`, `into_transfer()` and `adopt` are
  the same as on a `TcpStream`, and `SharedUnixListener` is the counterpart
  of `SharedTcpListener`.
- A path holds at most 107 bytes (103 on macOS); a longer or empty one
  fails with `is_invalid_input()`.

Only stream sockets are supported, since Windows (10 version 1803 and later)
has no Unix datagram sockets.

## TLS

The `tls` module encrypts a TCP connection with TLS 1.2 or 1.3. A
`TlsConnector` makes client connections and checks the server's
certificate. A `TlsAcceptor` serves them with a certificate and key. Both
produce a `TlsStream`, which reads and writes like a `TcpStream`:

```pepper
{{#include ../../examples/networking-tls/main.pep}}
```

- `TlsConnector.create()` trusts the system's root certificates, and
  `add_root_certificate(path)` adds more from a PEM file, such as a private
  certificate authority. Make one connector and share it: it is `[Shared]`.
- `connector.connect(tcp, host)` runs the handshake over a connected
  `TcpStream`. It checks that the certificate is valid and was issued for
  `host`, which is also sent to the server (SNI). `connect_host(host, port)`
  connects the TCP stream first. An IP address in `host` is checked against
  the certificate's addresses.
- `TlsAcceptor.create(certificate_chain, private_key)` reads PEM files, and
  `acceptor.accept(tcp)` runs the handshake over a connection a
  `TcpListener` accepted.
- `read`, `read_exact`, `write` and `write_all` work on the
  decrypted bytes. `shutdown()` sends the TLS close_notify, and `read`
  returns 0 once the peer has sent one or closed the connection.
- A failed handshake returns an error whose message says why, such as
  `certificate verify failed: self-signed certificate`.

On Linux and macOS the module uses OpenSSL 3, loaded when the first
connector or acceptor is made: install it with the system's package
manager, or `brew install openssl@3` on macOS. If it is missing,
`create()` returns an error. On Windows it uses the system's SChannel,
which needs nothing installed; a server's private key must be PKCS #8
(`BEGIN PRIVATE KEY`), and TLS 1.3 needs Windows 11 or Server 2022.

## Errors

Every operation returns an `IoResult`. Besides the file-system predicates,
`IoError` has these for networking:

| Predicate | When |
| --- | --- |
| `is_connection_refused()` | nothing listens at the address |
| `is_connection_reset()` | the peer reset or closed the connection (writing to a closed connection included) |
| `is_address_in_use()` | another socket already has the address and port |
| `is_address_not_available()` | the IP address is not one of this machine's |
| `is_timed_out()` | the peer never answered |
| `is_not_found()` | `resolve` found no address for the name, or `UnixStream.connect` found no socket file |

Writing to a closed connection never raises `SIGPIPE`, so it cannot kill
the process. The write returns an error instead.

## Closing

A socket closes when the last reference to it goes, like a `File`, and
`close()` closes it earlier and reports any error. A socket cannot be
copied, so it cannot go through a [channel](threads.md#channels) to another
thread. Use it on the thread that made it, or move it: `into_transfer()`
turns a `TcpStream` (or a `UnixStream`) into a thread-safe `SocketTransfer`
that `TcpStream.adopt` (or `UnixStream.adopt`) takes on another thread, and a `SharedTcpListener` is a
listener any thread can accept on (see
[Tasks](tasks.md#accepting-on-every-worker)).

On POSIX a listener sets `SO_REUSEADDR`, so a server can restart right
away. On Windows it does not, because there that option would let another
program take over the port.

## Current status

- Outside a task every call blocks its thread, with no timeout. In a task
  a call parks only the task, and [`async.timeout`](tasks.md#timeouts)
  limits how long it may wait.
- TLS clients cannot present certificates.
- Unix datagram sockets are not supported.
- IPv6 scope ids (`fe80::1%eth0`) are not supported.

The reference pages for [addresses](../reference/io-address.md),
[sockets](../reference/io-socket.md) and
[Unix domain sockets](../reference/io-unix.md) and
[TLS](../reference/tls-stream.md) document every method.
