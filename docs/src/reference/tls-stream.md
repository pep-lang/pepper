<!-- Generated from runtime/tls/stream.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Connectors and streams

TLS connections: `TlsConnector` opens client connections, `TlsAcceptor`
accepts server connections, and `TlsStream` is one encrypted connection
over a `TcpStream`.

Source: `runtime/tls/stream.pep`

## TlsConnector

```pepper
[Shared] struct TlsConnector
```

Opens TLS client connections, checking each server's certificate.

A connector trusts the system's root certificates; `add_root_certificate`
trusts more, such as a test certificate authority. Each `connect` runs
the TLS handshake over a connected `TcpStream` and checks that the
server's certificate is valid and issued for the host name given. Only
TLS 1.2 and 1.3 are offered.

A connector is `[Shared]`: make one and use it from every thread and
task. Configure it (`add_root_certificate`) before the first `connect`.

**See also**
- `TlsStream`

**Example**
```pepper
import tls;

var connector = tls.TlsConnector.create().value();
var stream = connector.connect_host("localhost", 8443).value();
stream.write_all("ping");
```

### Constructor

#### TlsConnector()

```pepper
construct(context: __ptr<void>)
```

Wraps a platform context. Use `TlsConnector.create`.

**Parameters**
- `context` — the platform's client context, or null for none

### Static methods

#### create

```pepper
static create(): io.IoResult<TlsConnector>
```

Creates a connector that trusts the system's root certificates.

**Returns**
- the connector; an error when no TLS library is available (on Linux and macOS, OpenSSL 3: `libssl.so.3`, or Homebrew's or MacPorts' `libssl.3.dylib`)

### Methods

#### add_root_certificate

```pepper
add_root_certificate(path: io.Path): io.IoResult<void>
```

Also trusts the certificates in the PEM file at `path`, for servers
whose certificates the system does not trust, such as a private or
test certificate authority.

**Parameters**
- `path` — a file of one or more PEM certificates

**Returns**
- an Ok result; an error when the file cannot be read or holds no certificate

#### connect

```pepper
connect(stream: io.TcpStream, host: String): io.IoResult<TlsStream>
```

Runs the TLS handshake as the client over `stream` and checks the
server's certificate.

**Parameters**
- `stream` — a connected TCP stream; the `TlsStream` keeps it, and nothing else should read or write it afterwards
- `host` — the name the certificate must be for, also sent to the server as the requested name (SNI); an IP address is checked against the certificate's addresses instead

**Returns**
- the encrypted stream; an error when the handshake fails or the certificate is not trusted ("certificate verify failed: ..."), or an io error from the socket

#### connect_host

```pepper
connect_host(host: String, port: u16): io.IoResult<TlsStream>
```

Connects to `host` on `port` with `TcpStream.connect_host`, then runs
the handshake as `connect` does.

**Parameters**
- `host` — a host name or an IP address
- `port` — the port, usually 443

**Returns**
- the encrypted stream; the errors of `TcpStream.connect_host` and of `connect`

## TlsAcceptor

```pepper
[Shared] struct TlsAcceptor
```

Accepts TLS server connections with one certificate.

An acceptor presents a certificate chain and its private key, read from
PEM files. Each `accept` runs the TLS handshake over a `TcpStream` that a
`TcpListener` accepted. Clients are not asked for certificates.

An acceptor is `[Shared]`, so the accept loops of every worker can share
one.

**See also**
- `TlsStream`

**Example**
```pepper
import io;
import tls;

var acceptor = tls.TlsAcceptor.create(io.Path("cert.pem"), io.Path("key.pem")).value();
var listener = io.TcpListener.bind(io.SocketAddress.parse("0.0.0.0:8443").value()).value();
while (true) {
    var (tcp, peer) = listener.accept().value();
    var accepted = acceptor.accept(tcp);
    if (accepted.is_ok()) {
        accepted.value().write_all("hello over TLS");
    }
}
```

### Constructor

#### TlsAcceptor()

```pepper
construct(context: __ptr<void>)
```

Wraps a platform context. Use `TlsAcceptor.create`.

**Parameters**
- `context` — the platform's server context, or null for none

### Static methods

#### create

```pepper
static create(certificate_chain: io.Path, private_key: io.Path): io.IoResult<TlsAcceptor>
```

Creates an acceptor that presents the certificate chain in
`certificate_chain` with the private key in `private_key`.

**Parameters**
- `certificate_chain` — a PEM file: the server's certificate first, then any intermediate certificates
- `private_key` — a PEM file with the certificate's private key (on Windows, PKCS #8: `BEGIN PRIVATE KEY`)

**Returns**
- the acceptor; an error when a file cannot be read, the key does not match the certificate, or no TLS library is available (see `TlsConnector.create`)

### Methods

#### accept

```pepper
accept(stream: io.TcpStream): io.IoResult<TlsStream>
```

Runs the TLS handshake as the server over `stream`.

**Parameters**
- `stream` — a connection a `TcpListener` accepted; the `TlsStream` keeps it, and nothing else should read or write it afterwards

**Returns**
- the encrypted stream; an error when the handshake fails, or an io error from the socket

## TlsStream

```pepper
[NotCopyable("owns a TLS connection and cannot be copied")] struct TlsStream
```

An encrypted connection: TLS over a `TcpStream`.

Get one from `TlsConnector.connect` or `TlsAcceptor.accept`. Reading and
writing work as on a `TcpStream`, on the decrypted bytes: `read` appends
what has arrived and returns 0 once the peer has closed the connection,
`write` may send part of the data, and `read_exact` and `write_all` loop
until done. In a task, a call that has to wait parks only the task.

`shutdown()` tells the peer that nothing more is coming (a TLS
close_notify). A peer that closes the TCP connection without one also
ends the stream: `read` returns 0.

Closing: the destructor closes the connection when the last reference
goes; `close()` closes it earlier. Neither sends close_notify; call
`shutdown()` first for that.

**See also**
- `TlsConnector`
- `TlsAcceptor`

**Example**
```pepper
var stream = connector.connect_host("localhost", 8443).value();
stream.write_all("ping");
var reply = Array<u8>();
while (stream.read(reply, 4096).value() > 0) {
}
```

### Constructor

#### TlsStream()

```pepper
construct(tcp: io.TcpStream, session: __ptr<void>)
```

Wraps a finished handshake. Use `TlsConnector.connect` or
`TlsAcceptor.accept`.

**Parameters**
- `tcp` — the TCP connection
- `session` — the platform's session, or null for a closed stream

### Methods

#### is_open

```pepper
is_open(): bool
```

Returns whether the stream is open.

**Returns**
- false after `close()`

#### read

```pepper
read(buffer: u8[], max: ulong): io.IoResult<ulong>
```

Waits until data arrives, then appends up to `max` decrypted bytes of
it to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read; 0 reads nothing and returns 0

**Returns**
- the number of bytes appended, 0 once the peer has closed the connection; an error when the stream is closed, a TLS error, or an io error from the socket

#### read_exact

```pepper
read_exact(buffer: u8[], count: ulong): io.IoResult<void>
```

Reads until exactly `count` more bytes are appended to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `count` — the number of bytes to read

**Returns**
- an Ok result once `count` bytes are appended; an error when the connection ends first, or an error as for `read`. The bytes read before an error stay in `buffer`.

#### write

```pepper
write(data: u8[]): io.IoResult<ulong>
```

Encrypts and sends bytes from `data`. The send may be partial; use
`write_all` to send everything.

**Parameters**
- `data` — the bytes to send

**Returns**
- the number of bytes sent; an error when the stream is closed, a TLS error, or an io error from the socket

#### write_all

```pepper
write_all(data: u8[]): io.IoResult<void>
```

Sends all of `data`, repeating the send until every byte is sent.

**Parameters**
- `data` — the bytes to send

**Returns**
- an Ok result once every byte is sent; an error as for `write`

#### write_all

```pepper
write_all(text: String): io.IoResult<void>
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
[Deprecated("use 'write_all' instead", "write_all")] write_string(text: String): io.IoResult<void>
```

Deprecated: use `write_all` instead. Sends all of the UTF-8 bytes of
`text`, exactly like `write_all(text)`.

**Parameters**
- `text` — the text to send

**Returns**
- an Ok result once every byte is sent; an error as for `write_all`

**See also**
- `write_all`

#### shutdown

```pepper
shutdown(): io.IoResult<void>
```

Tells the peer that nothing more is coming (sends a TLS
close_notify). The peer's reads return 0 after the data sent before.

**Returns**
- an Ok result on success; an error when the stream is closed, or an io error from the socket

#### close

```pepper
close(): io.IoResult<void>
```

Closes the connection now, without a close_notify (see `shutdown`).
Closing a closed stream does nothing.

**Returns**
- an Ok result on success or when already closed; the platform error when closing the socket fails
