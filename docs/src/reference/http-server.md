<!-- Generated from runtime/http/server.pep by `pep-doc reference`. Do not edit. -->

# Server

The HTTP server: `Server` accepts HTTP/1.1 and HTTP/2 connections on
every worker of `async.run` and answers each request with a handler
function.

Source: `runtime/http/server.pep`

## MAX_REQUEST_BODY

```pepper
const MAX_REQUEST_BODY: ulong = 16777216
```

The largest request body a `Server` reads: 16 MiB. A larger one gets
`413 Content Too Large`.

## Server

```pepper
[Shared] struct Server
```

An HTTP/1.1 and HTTP/2 server.

`Server.bind` listens on an address (`Server.bind_tls` serves HTTPS);
`serve` then accepts connections on every worker of the running
`async.run` and serves each connection in a task of its own, calling the
handler for every request. Connections are kept open between requests
unless the client asks to close (or speaks HTTP/1.0).

The handler gets the `Request` with its body read in full and returns the
`Response`; the server adds `Content-Length` (and `Connection: close`
when it will close). A request the server cannot parse gets `400 Bad
Request`, one with header fields over 64 KiB `431 Request Header Fields
Too Large`, and one with a body over `MAX_REQUEST_BODY` `413 Content Too
Large`; the connection then closes. A response whose reason phrase or
field value holds CR, LF or NUL, or whose field name is not an RFC 9110
token, is sent as `500 Internal Server Error` instead, since those
characters would split the response.

HTTP/2 is served to a client that chooses it through ALPN (see
`bind_tls`) or that starts a plain TCP connection with the HTTP/2
preface (prior knowledge): each stream is a request, answered by the same
handler in a task of its own.

**Example**
```pepper
import async;
import http;
import io;

hello(request: http.Request): http.Response {
    var response = http.Response(200).set_text("hello from " + request.path());
    response.headers["Content-Type"] = "text/plain";
    return response;
}

main(): int {
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse("0.0.0.0:8080").value()).value();
        server.serve(hello);
    });
    return 0;
}
```

### Constructor

#### Server()

```pepper
construct(listener: io.SharedTcpListener, secure: bool, acceptor: tls.TlsAcceptor)
```

Wraps a listening socket. Use `Server.bind` or `Server.bind_tls`.

**Parameters**
- `listener` — the listening socket
- `secure` — whether to serve HTTPS with `acceptor`
- `acceptor` — the certificate for HTTPS; ignored for HTTP

### Static methods

#### bind

```pepper
static bind(address: io.SocketAddress): io.IoResult<Server>
```

Listens for HTTP connections on `address`.

**Parameters**
- `address` — the local address (port 0 for any free port)

**Returns**
- the server; the errors of `io.TcpListener.bind`

#### bind_tls

```pepper
static bind_tls(address: io.SocketAddress, acceptor: tls.TlsAcceptor): io.IoResult<Server>
```

Listens for HTTPS connections on `address`, presenting `acceptor`'s
certificate. It sets the acceptor's ALPN protocols to `h2` and
`http/1.1`, so clients that offer HTTP/2 get it.

**Parameters**
- `address` — the local address (port 0 for any free port)
- `acceptor` — the certificate and key to serve with

**Returns**
- the server; the errors of `io.TcpListener.bind`

### Methods

#### local_address

```pepper
local_address(): io.IoResult<io.SocketAddress>
```

Returns the address the server listens on, with the port the system
chose for port 0.

**Returns**
- the local address, or a platform error

#### serve

```pepper
serve(handler: shared (Request) => Response)
```

Serves connections until the task is cancelled (when `async.run`
ends): accepts on every worker and serves each connection in a task
on the worker that accepted it.

**Parameters**
- `handler` — answers one request; it runs in the connection's task, so it may wait (on sockets, files, locks) without holding up other connections

**Panics**
- outside `async.run`

## Connection

```pepper
struct Connection
```

A connection a `Server` handler took over by answering with
`Response.upgrade`: the raw stream after the `101 Switching Protocols`
head, TCP or (under `Server.bind_tls`) TLS, as an `io.Reader` and an
`io.Writer`.

Reads return first the bytes the server had already read past the
request (a client may send its first message right after the request),
then what arrives. Like the handler, it belongs to the connection's task.

**Example**
```pepper
upgraded(request: http.Request): http.Response {
    return http.Response().upgrade("echo", (connection) => {
        var data = Array<u8>();
        while (connection.read(data, 4096).value() > 0) {
            connection.write_all(data);
            data.clear();
        }
    });
}
```

### Constructor

#### Connection()

```pepper
construct(reader: _HttpReader)
```

Wraps the connection `reader` reads. The server makes one for
`Response.upgrade`.

**Parameters**
- `reader` — the connection and the bytes it buffered

### Methods

#### read

```pepper
read(buffer: u8[], max: ulong): io.IoResult<ulong>
```

Waits until some bytes are available, then appends up to `max` of
them to `buffer`: the ones buffered past the request first.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read

**Returns**
- the number of bytes appended, 0 at the end of the stream; an error when the stream fails

#### write

```pepper
write(data: u8[]): io.IoResult<ulong>
```

Writes what the stream takes in one call, which may be less than all
of `data`.

**Parameters**
- `data` — the bytes to write

**Returns**
- the number of bytes written; an error when the stream fails

#### write_all

```pepper
write_all(data: u8[]): io.IoResult<void>
```

Writes all of `data`.

**Parameters**
- `data` — the bytes to write

**Returns**
- an Ok result once every byte is written; an error when the stream fails

#### close

```pepper
close()
```

Closes the connection, sending TLS close_notify first under TLS. The
server also closes it when the `takeover` function returns; closing
again does nothing.

## reason_phrase

```pepper
reason_phrase(status: int): String
```

Returns the standard reason phrase for an HTTP status code.

**Parameters**
- `status` — the status code

**Returns**
- the phrase, such as `Not Found` for 404; an empty string for a code without one
