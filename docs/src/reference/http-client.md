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
whole response. Redirects are returned as they are, not followed.

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

### Constructors

#### Client()

```pepper
construct()
```

Creates a client that trusts the system's root certificates for
`https://` URLs. Where TLS is not available (Linux or macOS without
OpenSSL 3), `http://` URLs still work and `https://` ones fail.

#### Client()

```pepper
construct(connector: tls.TlsConnector)
```

Creates a client whose `https://` connections use `connector`, for
instance one that trusts a private certificate authority.

**Parameters**
- `connector` — the TLS connector to open `https://` connections with

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

Sends `request` and reads the response.

The client adds `Host`, `Content-Length` (when there is a body, or
for `POST`, `PUT` and `PATCH`) and `Connection: close`, replacing any
the request has.

**Parameters**
- `request` — the request; its `url` must be absolute

**Returns**
- the response, whatever its status; an error with `is_invalid_input()` for a URL that is not `http://` or `https://`, the errors of `io.TcpStream.connect_host` and `tls.TlsConnector.connect`, or an error when the response is not valid HTTP/1.x or its body is larger than `MAX_RESPONSE_BODY`
