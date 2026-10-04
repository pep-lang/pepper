<!-- Generated from runtime/http/client.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

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

Sends HTTP/1.1 requests and reads their responses.

Each request opens a new connection (plain TCP for `http://`, TLS for
`https://`), sends the request with `Connection: close`, and reads the
response: `send` reads the whole body into memory, and `open` returns
once the header fields arrive, with the body to read as a stream.

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
instance one that trusts a private certificate authority.

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
- the response after any redirects, whatever its status; an error with `is_invalid_input()` for a URL that is not `http://` or `https://`, the errors of `io.TcpStream.connect_host` and `tls.TlsConnector.connect`, or an error when the response is not valid HTTP/1.x, its body is larger than `MAX_RESPONSE_BODY`, or there are more than `max_redirects` redirects

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
construct(reader: _HttpReader, mode: int, length: ulong)
```

Makes a reader of a body framed by `mode` on `reader`'s connection.
`Client.open` makes it; there is no other use.

**Parameters**
- `reader` — the connection's reader, positioned at the body
- `mode` — how the body is framed
- `length` — the body's length, for a `Content-Length` body

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
