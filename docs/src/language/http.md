# HTTP

The `http` module has an HTTP/1.1 client and server, over plain TCP or
[TLS](networking.md#tls). Both run in [tasks](tasks.md): a request that
waits parks only its task.

HTTP needs tasks and sockets, so it is not available on WebAssembly
(`--target wasm32-wasip1`, see [WebAssembly](platform-selection.md#webassembly)).

```pepper
{{#include ../../examples/http-basics.pep}}
```

## Messages

- A `Request` has a `method`, a `url`, `headers` and a body. For a client
  the `url` is absolute (`https://example.com/items?page=2`); a server
  handler gets the request target (`/items?page=2`). `uri()` parses either
  as a [`Uri`](#urls), and `path()` and `query()` return its parts.
- A `Response` has a `status`, a `reason`, `headers` and a body.
  `is_success()` tests for a 2xx status.
- `Headers` maps each field name to its values. Names ignore case (they are
  stored lowercased). `headers["Accept"]` reads the first value (`""` when
  there is none) and `headers["Accept"] = "text/html"` replaces the field;
  `get(name)` returns an optional, `add` keeps earlier values, `values(name)`
  returns them all, and `names()` lists the fields in no defined order.
- `set_text` and `set_body` fill a request or response and return it, so
  they chain. `body()` returns the bytes, for any body including binary
  ones; `text()` decodes them as UTF-8, replacing invalid bytes with U+FFFD.
- `set_reader(source)` gives a request or response a body streamed from any
  `io.Reader` (a file, a `compress.CompressReader`) instead of one held in
  memory; see [Streaming bodies](#streaming-bodies).

## URLs

`Uri` (in the prelude, so no import is needed) parses any URI reference
following RFC 3986: an absolute URI with any scheme (`https:`, `mailto:`,
`file:`) or a relative reference such as a request target. It splits the
text into `scheme`, `user_info`, `host`, `port`, `path`, `query` and
`fragment`; the parts that can be missing are optionals. Components keep
their percent-escapes, and `Uri.decode` turns one into text.
`base.resolve(reference)` resolves a relative reference against a base URI,
as a browser resolves a link (RFC 3986 section 5.2).

```pepper
{{#include ../../examples/http-uri.pep}}
```

## Client

- `Client()` trusts the system's root certificates for `https://` URLs.
  `Client(connector)` uses a `tls.TlsConnector` of your own, for instance
  one that trusts a private certificate authority.
- `get(url)`, `post(url, content_type, body)` and `send(request)` open a
  connection, send the request and read the whole response, up to
  `MAX_RESPONSE_BODY` (64 MiB). `open(request)` returns at the header
  fields and leaves the body to read as a stream (see
  [Streaming bodies](#streaming-bodies)). The client adds `Host`,
  `Content-Length` (or `Transfer-Encoding: chunked`) and
  `Connection: close`.
- Any status is a successful result: check `status`. An error means there
  was no response: the URL is not `http://` or `https://`
  (`is_invalid_input()`), the connection or TLS handshake failed, or the
  response was not valid HTTP.
- Redirects (301, 302, 303, 307, 308) are followed, up to
  `max_redirects` (10) per request, and `response.url` is where the
  response came from. A 303, and a 301 or 302 after a `POST`, becomes a
  `GET` without the body; a 307 or 308 repeats the method and body, except
  that a body from `set_reader` cannot be sent twice, so that redirect is
  returned. Leaving the origin drops `Authorization`,
  `Proxy-Authorization` and `Cookie`. `Client(0)` returns every redirect
  as it is.
- Every request from a `Client` uses a new connection; a `Session` keeps
  them open (see [Reusing connections](#reusing-connections)).

## Server

- `Server.bind(address)` listens for HTTP; `Server.bind_tls(address,
  acceptor)` serves HTTPS with a `tls.TlsAcceptor`'s certificate.
- `serve(handler)` accepts connections on every worker of `async.run` and
  serves each in a task of its own, calling `handler` for each request with
  the body read in full. It returns when `async.run` ends. The handler is a
  `shared (Request) => Response`, since every worker calls it.
- Connections stay open between requests unless the client asks to close
  or speaks HTTP/1.0. Chunked request bodies and `Expect: 100-continue` are
  understood.
- The server adds `Content-Length` to each response (or, for a body from
  `set_reader` of unknown length, `Transfer-Encoding: chunked`), and the
  standard reason phrase when `reason` is empty (`reason_phrase(status)`
  returns it).
- A request it cannot parse gets `400 Bad Request`, header fields over
  64 KiB get `431`, and a body over `MAX_REQUEST_BODY` (16 MiB) gets `413`.

## Streaming bodies

A body need not fit in memory. Both directions stream through `io.Reader`,
the trait of files, sockets and the `compress` readers:

- **Responses to a client:** `client.open(request)` returns the `Response`
  as soon as its header fields arrive. `response.reader()` is then a
  `BodyReader` that reads the body from the connection as it arrives, with
  no size limit, undoing chunked framing, and ends where the body ends.
  Read it with `read`, `chunks` or `lines`, or wrap it in a
  `compress.DecompressReader`. The connection closes at the end of the
  body, at `close()`, or when the last reference to the reader goes.
- **Requests from a client:** `request.set_reader(source)` sends the body
  chunked; `set_reader(source, length)` sends it with `Content-Length`.
- **Responses from a server:** a handler returns
  `Response(200).set_reader(source)`, sent chunked to an HTTP/1.1 client
  (or with `Content-Length` when a length is given). An HTTP/1.0 client
  gets the body unframed, and the connection closes after it.

```pepper
{{#include ../../examples/http-streaming.pep}}
```

## Reusing connections

`client.session()` returns a `Session`, which sends requests with the
client's settings and keeps each connection open after its response
(HTTP/1.1 keep-alive). The next request to the same scheme, host and port
uses it again, saving the TCP and TLS handshakes:

```pepper
{{#include ../../examples/http-session.pep}}
```

- A connection goes back to the session when its response body has been
  read to its end (`send` reads it; for `open`, read the `BodyReader` to
  its end), unless the server said `Connection: close`.
- `max_idle_per_host` (4) connections wait for each scheme, host and port;
  one idle longer than `idle_timeout` (90 seconds) is closed instead of
  used. `idle_count` says how many wait, and `close()` closes them.
- A request that finds its reused connection closed by the server goes
  again on a new one, unless its body came from `set_reader`.
- A `Session` is not `[Shared]`: use one per thread or task. A `Client` is
  shared, and connections, which belong to one thread, cannot be.

## Current status

- A server handler gets the request body read into memory in full, up to
  `MAX_REQUEST_BODY` (16 MiB).
- HTTP/2 is not supported yet.

The reference pages for [messages](../reference/http-message.md), the
[client](../reference/http-client.md), the
[server](../reference/http-server.md) and [`Uri`](../reference/uri.md)
document every method.
