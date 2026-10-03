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

## URLs

`Uri` (in the prelude, so no import is needed) parses any URI reference
following RFC 3986: an absolute URI with any scheme (`https:`, `mailto:`,
`file:`) or a relative reference such as a request target. It splits the
text into `scheme`, `user_info`, `host`, `port`, `path`, `query` and
`fragment`; the parts that can be missing are optionals. Components keep
their percent-escapes, and `Uri.decode` turns one into text.

```pepper
{{#include ../../examples/http-uri.pep}}
```

## Client

- `Client()` trusts the system's root certificates for `https://` URLs.
  `Client(connector)` uses a `tls.TlsConnector` of your own, for instance
  one that trusts a private certificate authority.
- `get(url)`, `post(url, content_type, body)` and `send(request)` open a
  connection, send the request and read the whole response. The client adds
  `Host`, `Content-Length` and `Connection: close`.
- Any status is a successful result: check `status`. An error means there
  was no response: the URL is not `http://` or `https://`
  (`is_invalid_input()`), the connection or TLS handshake failed, or the
  response was not valid HTTP.
- Redirects are returned, not followed, and every request uses a new
  connection.

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
- The server adds `Content-Length` to each response, and the standard
  reason phrase when `reason` is empty (`reason_phrase(status)` returns it).
- A request it cannot parse gets `400 Bad Request`, header fields over
  64 KiB get `431`, and a body over `MAX_REQUEST_BODY` (16 MiB) gets `413`.

## Current status

- Bodies are read into memory in full, up to 16 MiB for a request and
  `MAX_RESPONSE_BODY` (64 MiB) for a response; there is no streaming yet.
- HTTP/2, connection reuse in the client, and following redirects are not
  supported yet.

The reference pages for [messages](../reference/http-message.md), the
[client](../reference/http-client.md), the
[server](../reference/http-server.md) and [`Uri`](../reference/uri.md)
document every method.
