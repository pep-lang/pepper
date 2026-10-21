<!-- Generated from runtime/http/client.pep by `pep-doc reference`. Do not edit. -->

# Client

The HTTP client: `Client` sends a `Request` over HTTP or HTTPS and
returns the `Response`.

Source: `runtime/http/client.pep`

## MAX_RESPONSE_BODY

```pepper
const MAX_RESPONSE_BODY: ulong = 67108864
```

The largest response body a `Client` reads: 64 MiB.

## Client

```pepper
[Shared] struct Client
```

Sends HTTP/1.1 and HTTP/2 requests and reads their responses.

Each request opens a new connection (plain TCP for `http://`, TLS for
`https://`), sends the request with `Connection: close`, and reads the
response: `send` reads the whole body into memory, and `open` returns
once the header fields arrive, with the body to read as a stream. To
send requests on connections kept open between them, use a `Session`
(`client.session()`).

For `https://` the client offers HTTP/2 and HTTP/1.1 through ALPN and
speaks the one the server chooses; the request and response are the same
either way. Over HTTP/2 the response's `reason` is the standard phrase
for its status. Plain `http://` uses HTTP/1.1.

Redirects (301, 302, 303, 307 and 308 with a `Location`) are followed,
up to `max_redirects` of them, as RFC 9110 describes: 303, and 301 or
302 after a `POST`, become a `GET` without the body; 307 and 308 repeat
the method and body. A request whose body comes from
`Request.set_reader` cannot be repeated, so its 307 or 308 is returned
as it is. When a redirect leaves the origin (scheme, host and port),
`Authorization`, `Proxy-Authorization` and `Cookie` are dropped. Make a
client with `max_redirects` 0 to get every redirect back as it is.

A client is `[Shared]`: make one and use it from every thread and task.
In a task, a request parks only the task while it waits.

**Example**
```pepper
import http;

main(): int {
    var client = http.Client();
    var response = client.get("https://example.com/").value();
    print(to_string(response.status));   # 200
    print(response.text());
    return 0;
}
```

### Fields

#### max_redirects

```pepper
const max_redirects: int
```

The most redirects one request follows; 0 follows none.

### Constructors

#### Client()

```pepper
construct(max_redirects: int = 10)
```

Creates a client that trusts the system's root certificates for
`https://` URLs. Where TLS is not available (Linux or macOS without
OpenSSL 3), `http://` URLs still work and `https://` ones fail.

**Parameters**
- `max_redirects` — the most redirects one request follows; 0 returns every redirect as it is

#### Client()

```pepper
construct(connector: tls.TlsConnector, max_redirects: int = 10)
```

Creates a client whose `https://` connections use `connector`, for
instance one that trusts a private certificate authority. The client
sets the connector's ALPN protocols to `h2` and `http/1.1`.

**Parameters**
- `connector` — the TLS connector to open `https://` connections with
- `max_redirects` — the most redirects one request follows; 0 returns every redirect as it is

### Methods

#### get

```pepper
get(url: String): io.IoResult<Response>
```

Sends a `GET` request for `url`.

**Parameters**
- `url` — an absolute `http://` or `https://` URL

**Returns**
- the response; the errors of `send`

#### post

```pepper
post(url: String, content_type: String, body: String): io.IoResult<Response>
```

Sends a `POST` request for `url` with `body` as a
`Content-Type` of `content_type`.

**Parameters**
- `url` — an absolute `http://` or `https://` URL
- `content_type` — the body's media type, such as `application/json`
- `body` — the body

**Returns**
- the response; the errors of `send`

#### send

```pepper
send(request: Request): io.IoResult<Response>
```

Sends `request` and reads the response, body and all.

The client adds `Host`, `Content-Length` (when there is a body, or
for `POST`, `PUT` and `PATCH`; `Transfer-Encoding: chunked` for a body
from `Request.set_reader` of unknown length) and `Connection: close`,
replacing any the request has.

**Parameters**
- `request` — the request; its `url` must be absolute

**Returns**
- the response after any redirects, whatever its status; an error with `is_invalid_input()` for a URL that is not `http://` or `https://`, a method or field name that is not an RFC 9110 token, or a field value holding CR, LF or NUL (which would split the request), the errors of `io.TcpStream.connect_host` and `tls.TlsConnector.connect`, or an error when the response is not valid HTTP/1.x, its body is larger than `MAX_RESPONSE_BODY`, or there are more than `max_redirects` redirects

#### open

```pepper
open(request: Request): io.IoResult<Response>
```

Sends `request` and returns the response as soon as its header fields
arrive, with the body still to read: `response.reader()` returns it
as a `BodyReader`, which reads it from the connection as it arrives,
with no limit on its size. Use it for a large download, writing each
chunk to a file or through a `compress.DecompressReader`.

The connection closes when the body has been read to its end, when
the `BodyReader` is closed, or when the last reference to it goes.
The request goes out, and redirects are followed, as for `send`.

**Parameters**
- `request` — the request; its `url` must be absolute

**Returns**
- the response with its body unread; the errors of `send`, except that the body may be any size. Errors reading the body come from the `BodyReader`.

**Example**
```pepper
var response = client.open(http.Request("GET", "https://example.com/large.tar.gz")).value();
var archive = compress.DecompressReader(response.reader(), compress.Format.Gzip);
var file = io.File.create(io.Path("large.tar")).value();
for (var chunk in archive.chunks(65536)) {
    file.write_all(chunk.value());
}
```

#### session

```pepper
session(): Session
```

Returns a new `Session` that sends requests with this client's
settings and keeps their connections open for the requests after
them.

**Returns**
- the session, with no connections yet

## Session

```pepper
struct Session
```

A run of requests that share connections: each connection stays open
after its response (HTTP/1.1 keep-alive) and the next request to the same
scheme, host and port uses it again, saving the TCP and TLS handshakes.
Make one with `client.session()`; it sends requests and follows redirects
with that client's settings.

A connection goes back to the session once its response body has been
read to its end (which `send` does), unless the server asked to close it.
Up to `max_idle_per_host` connections wait for each scheme, host and
port; one idle for longer than `idle_timeout` is closed instead of used.
A request that finds its reused connection closed by the server is sent
again on a new one, unless its body came from `Request.set_reader`.

Over HTTP/2 the session keeps one connection per origin, which every
request to that origin shares at once on a stream of its own, so tasks
started with `spawn_local` can send through one session concurrently.

A session is not `[Shared]`: use it from one thread or task. Its
connections close when the last reference to it (and to the
`BodyReader`s it returned) goes, or at `close()`.

**Example**
```pepper
var session = http.Client().session();
for (var page in 1..>3) {
    var response = session.get($"https://example.com/items?page={page}").value();
    print(response.text());
}
# One connection carried all three requests.
```

### Fields

#### client

```pepper
var client: Client
```

The client whose settings the session uses: its TLS connector and
`max_redirects`.

### Properties

#### idle_timeout

```pepper
var idle_timeout: os.Duration { get; set; }
```

How long a connection may wait unused before the session closes it
rather than send on it: 90 seconds unless changed. Servers close idle
connections too, often sooner.

#### max_idle_per_host

```pepper
var max_idle_per_host: ulong { get; set; }
```

The most idle connections kept for one scheme, host and port: 4
unless changed. 0 keeps none, so every request uses a new connection.

#### idle_count

```pepper
var idle_count: ulong { get; }
```

The number of idle connections the session holds, for every host.

### Constructor

#### Session()

```pepper
construct(client: Client)
```

Creates a session with no connections yet; `client.session()` does
the same.

**Parameters**
- `client` — the client whose settings the session uses

### Methods

#### get

```pepper
get(url: String): io.IoResult<Response>
```

Sends a `GET` request for `url`, as `Client.get` does.

**Parameters**
- `url` — an absolute `http://` or `https://` URL

**Returns**
- the response; the errors of `Client.send`

#### post

```pepper
post(url: String, content_type: String, body: String): io.IoResult<Response>
```

Sends a `POST` request for `url` with `body` as a `Content-Type` of
`content_type`, as `Client.post` does.

**Parameters**
- `url` — an absolute `http://` or `https://` URL
- `content_type` — the body's media type, such as `application/json`
- `body` — the body

**Returns**
- the response; the errors of `Client.send`

#### send

```pepper
send(request: Request): io.IoResult<Response>
```

Sends `request` on an idle connection to its host if there is one,
and reads the response, body and all, as `Client.send` does. The
request keeps the connection open, so the client sends no
`Connection: close`.

**Parameters**
- `request` — the request; its `url` must be absolute

**Returns**
- the response; the errors of `Client.send`

#### open

```pepper
open(request: Request): io.IoResult<Response>
```

Sends `request` as `send` does and returns at the response's header
fields, as `Client.open` does. The connection goes back to the
session when the body has been read to its end; closing the
`BodyReader` early closes the connection.

**Parameters**
- `request` — the request; its `url` must be absolute

**Returns**
- the response with its body unread; the errors of `Client.open`

#### close

```pepper
close()
```

Closes every idle connection. The session stays usable: later
requests open new connections.

## BodyReader

```pepper
struct BodyReader
```

The body of a response from `Client.open`, read from the connection as it
arrives. It is an `io.Reader`: read it with `read`, `chunks` or `lines`,
or hand it to anything that takes a stream. It undoes the framing (a
`Content-Length`, chunks, or the rest of the connection) and ends where
the body ends, then closes the connection.

### Properties

#### is_done

```pepper
var is_done: bool { get; }
```

Reports whether the body has been read to its end, or the reader
closed.

### Constructor

#### BodyReader()

```pepper
construct(reader: _HttpReader, mode: int, length: ulong, reusable: bool)
```

Makes a reader of a body framed by `mode` on `reader`'s connection.
`Client.open` makes it; there is no other use.

**Parameters**
- `reader` — the connection's reader, positioned at the body
- `mode` — how the body is framed
- `length` — the body's length, for a `Content-Length` body
- `reusable` — whether the server keeps the connection open after the body

### Methods

#### read

```pepper
read(buffer: u8[], max: ulong): io.IoResult<ulong>
```

Waits until some of the body has arrived, then appends up to `max`
bytes of it to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read

**Returns**
- the number of bytes appended, 0 at the end of the body; an error when the connection fails, closes before the body ends, or the chunked framing is not valid

#### close

```pepper
close()
```

Stops reading the body and closes the connection. Reading then
returns 0, as at the end of the body. Closing a reader already done
does nothing.
