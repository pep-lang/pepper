<!-- Generated from runtime/http/server.pep by `pep-doc reference`. Do not edit. -->

# Server

The HTTP server: `Server` accepts HTTP/1.1 connections on every worker of
`async.run` and answers each request with a handler function.

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

An HTTP/1.1 server.

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
Large`; the connection then closes.

A client on plain TCP that starts with the HTTP/2 connection preface
(HTTP/2 with prior knowledge) is served HTTP/2: each stream is a request,
answered by the same handler in a task of its own.

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
certificate.

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

## reason_phrase

```pepper
reason_phrase(status: int): String
```

Returns the standard reason phrase for an HTTP status code.

**Parameters**
- `status` — the status code

**Returns**
- the phrase, such as `Not Found` for 404; an empty string for a code without one
