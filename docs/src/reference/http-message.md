<!-- Generated from runtime/http/message.pep by `pep-doc reference`. Do not edit. -->

# Requests and responses

HTTP messages: `Headers`, `Request` and `Response`, the values a
`Client` sends and receives and a `Server` handler takes and returns.

Source: `runtime/http/message.pep`

## Headers

```pepper
struct Headers
```

HTTP header fields, by name. Names ignore ASCII case: they are stored
lowercased, so `Content-Type` and `content-type` are the same field. A
name may hold several values, kept in the order added. Different names
have no defined order, as HTTP allows.

**Example**
```pepper
var headers = http.Headers();
headers.add("Accept", "text/html");
headers["accept"] = "application/json";   # replaces it
assert(headers["ACCEPT"] == "application/json", "one value");
```

### Properties

#### count

```pepper
var count: ulong { get; }
```

The number of field names.

### Constructor

#### Headers()

```pepper
construct()
```

Creates an empty set of fields.

### Methods

#### names

```pepper
names(): String[]
```

Returns the field names, lowercased, in no defined order.

**Returns**
- a new array with one entry per name

#### values

```pepper
values(name: String): String[]
```

Returns every value of the field named `name`, in the order added.

**Parameters**
- `name` — the field name, in any case

**Returns**
- a new array of the values; empty when no field has that name

#### add

```pepper
add(name: String, value: String)
```

Adds a value to the field named `name`, keeping any it has.

**Parameters**
- `name` — the field name, in any case
- `value` — the field value

#### set

```pepper
set(name: String, value: String)
```

Replaces every value of the field named `name` with `value`.

**Parameters**
- `name` — the field name, in any case
- `value` — the field value

#### get

```pepper
get(name: String): String?
```

Returns the first value of the field named `name`.

**Parameters**
- `name` — the field name, in any case

**Returns**
- the value, or none when no field has that name

#### has

```pepper
has(name: String): bool
```

Reports whether a field is named `name`.

**Parameters**
- `name` — the field name, in any case

**Returns**
- true if a field has that name

#### remove

```pepper
remove(name: String)
```

Removes the field named `name` and all its values.

**Parameters**
- `name` — the field name, in any case

#### operator []

```pepper
[](name: String): String
```

Reads `headers[name]`: the first value of the field named `name`, or
an empty string when there is none. Use `get` to tell an empty value
from a missing field.

**Parameters**
- `name` — the field name, in any case

**Returns**
- the first value, or `""`

#### operator []

```pepper
[](name: String, value: String): String
```

Writes `headers[name] = value`: replaces every value of the field, as
`set` does.

**Parameters**
- `name` — the field name, in any case
- `value` — the field value

**Returns**
- `value`, the value of the assignment expression

## Request

```pepper
struct Request
```

An HTTP request.

A `Client` sends one: build it with a method and an absolute URL, then
add headers and a body. A `Server` handler receives one, with `url` set to
the target from the request line (`/path?query`) and the body read in
full.

**Example**
```pepper
var request = http.Request("POST", "http://localhost:8080/items").set_text("name=pepper");
request.headers["Content-Type"] = "application/x-www-form-urlencoded";
```

### Fields

#### method

```pepper
var method: String
```

The method, such as `GET` or `POST`.

#### url

```pepper
var url: String
```

For a client, the absolute URL (`https://host/path?query`); for a
server handler, the request target (`/path?query`).

#### headers

```pepper
var headers: Headers
```

The header fields. A client adds `Host`, `Content-Length` (or
`Transfer-Encoding`) and `Connection` itself.

### Constructor

#### Request()

```pepper
construct(method: String = "GET", url: String = "/")
```

Creates a request with no headers and no body.

**Parameters**
- `method` — the method, such as `GET`
- `url` — the absolute URL to send it to

### Methods

#### can_upgrade

```pepper
can_upgrade(): bool
```

Reports whether a `Server` handler may answer this request with
`Response.upgrade`: true for an HTTP/1.1 request, false for HTTP/1.0,
for a request on an HTTP/2 stream (which cannot switch protocols), and
for one a client builds.

**Returns**
- true when the connection can be taken over

#### set_text

```pepper
set_text(text: String): Request
```

Sets the body to the UTF-8 bytes of `text`.

**Parameters**
- `text` — the body

**Returns**
- this request

#### set_body

```pepper
set_body(data: u8[]): Request
```

Sets the body to `data`, which may be any bytes (see `body`).

**Parameters**
- `data` — the body's bytes

**Returns**
- this request

#### set_reader

```pepper
set_reader(source: io.Reader, length: long = -1): Request
```

Sets the body to the bytes `source` gives, read as the request is sent
rather than held in memory: a large file, or the output of a
`compress.CompressReader`. With a `length` the client sends
`Content-Length`; without one it sends the body chunked
(`Transfer-Encoding: chunked`), which every HTTP/1.1 server accepts.

The source is read once, so a client cannot send the request again
(to follow a redirect, for instance).

**Parameters**
- `source` — the stream the body is read from, to its end
- `length` — the number of bytes `source` gives, or -1 when it is not known

**Returns**
- this request

**Example**
```pepper
var file = io.File.open(io.Path("upload.bin")).value();
var request = http.Request("PUT", "http://localhost:8080/files/upload.bin").set_reader(file);
```

#### uri

```pepper
uri(): Result<Uri>
```

Parses `url` as a URI reference: an absolute URL for a request a
client sends, or the target (`/items?page=2`) for one a server
received.

**Returns**
- the parsed URL, or an error when `url` is not a valid URI reference (see `Uri.parse`)

#### path

```pepper
path(): String
```

Returns the path of `url`, with its percent-escapes: `/` when the path
is empty.

**Returns**
- the path, such as `/items`, or an empty string when `url` is not a valid URI reference

#### query

```pepper
query(): String
```

Returns the query of `url`: the text after `?`, with its
percent-escapes (see `Uri.decode`).

**Returns**
- the query without the `?`, or an empty string for none or when `url` is not a valid URI reference

#### body

```pepper
body(): u8[]
```

Returns the body's bytes, as they were sent or received: use it for a
binary body. The array is the body itself, not a copy. It is empty
when the body comes from `set_reader`.

**Returns**
- the body; empty for none

#### text

```pepper
text(): String
```

Returns the body as text, decoded as UTF-8. For a binary body, call
`body()` instead: here each byte that is not valid UTF-8 becomes
U+FFFD, the replacement character.

**Returns**
- the body's bytes decoded as a String

## Response

```pepper
struct Response
```

An HTTP response.

`Client.send` returns one with the body read in full; `Client.open`
returns one whose body is read as it arrives, through `reader()`. A
`Server` handler returns one: build it with a status, then add headers
and a body, in memory (`set_text`, `set_body`) or streamed
(`set_reader`). The server adds `Content-Length` (or
`Transfer-Encoding: chunked`) itself.

**Example**
```pepper
handle(request: http.Request): http.Response {
    var response = http.Response(200).set_text("hello");
    response.headers["Content-Type"] = "text/plain";
    return response;
}
```

### Fields

#### status

```pepper
var status: int
```

The status code, such as 200 or 404.

#### reason

```pepper
var reason: String
```

The reason phrase, such as `OK`; the server sends the standard one
for the status when this is empty.

#### headers

```pepper
var headers: Headers
```

The header fields.

#### url

```pepper
var url: String
```

For a response a `Client` returns, the URL it came from: the
request's, or after redirects the last one's. Empty otherwise.

### Constructor

#### Response()

```pepper
construct(status: int = 200)
```

Creates a response with no headers and no body.

**Parameters**
- `status` — the status code

### Methods

#### upgrade

```pepper
upgrade(protocol: String, takeover: (Connection) => void): Response
```

Makes this a `101 Switching Protocols` response that hands the
connection to `takeover`, for a protocol that starts as HTTP/1.1, such
as WebSocket. The server sends the status, `Upgrade: protocol`,
`Connection: Upgrade` and the other headers (no `Content-Length`, no
body), then calls `takeover` in the connection's task with the
connection, and serves no more HTTP on it. The connection closes when
`takeover` returns, or earlier at `Connection.close()`.

Only a request whose `can_upgrade()` is true can be upgraded: for
any other (HTTP/1.0, or an HTTP/2 stream) the server sends `501 Not
Implemented` instead and never calls `takeover`.

**Parameters**
- `protocol` — the `Upgrade` field: the protocol the connection switches to, such as `websocket`
- `takeover` — speaks the new protocol on the connection; bytes the client sent right after the request are the first it reads

**Returns**
- this response

**Example**
```pepper
echo(request: http.Request): http.Response {
    return http.Response().upgrade("echo", (connection) => {
        for (var chunk in connection.chunks(4096)) {
            connection.write_all(chunk.value());
        }
    });
}
```

#### set_text

```pepper
set_text(text: String): Response
```

Sets the body to the UTF-8 bytes of `text`.

**Parameters**
- `text` — the body

**Returns**
- this response

#### set_body

```pepper
set_body(data: u8[]): Response
```

Sets the body to `data`, which may be any bytes (see `body`).

**Parameters**
- `data` — the body's bytes

**Returns**
- this response

#### set_reader

```pepper
set_reader(source: io.Reader, length: long = -1): Response
```

Sets the body to the bytes `source` gives, which the server reads and
sends as it goes rather than holding them in memory. With a `length`
the server sends `Content-Length`; without one it sends the body
chunked to an HTTP/1.1 client, and to an HTTP/1.0 client sends it
unframed and closes the connection after it.

**Parameters**
- `source` — the stream the body is read from, to its end
- `length` — the number of bytes `source` gives, or -1 when it is not known

**Returns**
- this response

**Example**
```pepper
download(request: http.Request): http.Response {
    var file = io.File.open(io.Path("large.bin")).value();
    return http.Response(200).set_reader(file);
}
```

#### body

```pepper
body(): u8[]
```

Returns the body's bytes, as they were sent or received: use it for a
binary body. The array is the body itself, not a copy. It is empty for
a response from `Client.open`, whose body is read through `reader()`,
and for one whose body comes from `set_reader`.

**Returns**
- the body; empty for none

#### reader

```pepper
reader(): io.Reader
```

Returns the body as a stream. For a response from `Client.open` it is
the connection's `BodyReader`, which reads the body as it arrives and
ends where the body ends; read it once. For a response whose body
comes from `set_reader` it is that source, and otherwise an
`io.ByteReader` over `body()`.

**Returns**
- the stream of the body's bytes

**Example**
```pepper
var response = http.Client().open(http.Request("GET", url)).value();
var file = io.File.create(io.Path("download.bin")).value();
for (var chunk in response.reader().chunks(65536)) {
    file.write_all(chunk.value());
}
```

#### text

```pepper
text(): String
```

Returns the body as text, decoded as UTF-8. For a binary body, call
`body()` instead: here each byte that is not valid UTF-8 becomes
U+FFFD, the replacement character.

**Returns**
- the body's bytes decoded as a String

#### is_success

```pepper
is_success(): bool
```

Reports whether the status is 2xx.

**Returns**
- true for a status from 200 to 299
