## The HTTP client: `Client` sends a `Request` over HTTP or HTTPS and
## returns the `Response`.

import io;
import tls;
import "message";
import "wire";

## The largest response body a `Client` reads: 64 MiB.
export const MAX_RESPONSE_BODY: ulong = 67108864;

## Sends HTTP/1.1 requests and reads their responses.
##
## Each request opens a new connection (plain TCP for `http://`, TLS for
## `https://`), sends the request with `Connection: close`, and reads the
## response: `send` reads the whole body into memory, and `open` returns
## once the header fields arrive, with the body to read as a stream.
## Redirects are returned as they are, not followed.
##
## A client is `[Shared]`: make one and use it from every thread and task.
## In a task, a request parks only the task while it waits.
##
## @example
##     import http;
##
##     main(): int {
##         var client = http.Client();
##         var response = client.get("https://example.com/").value();
##         print(to_string(response.status));   # 200
##         print(response.text());
##         return 0;
##     }
[Shared]
export struct Client {
    # Opens https:// connections: the system's roots, or the connector the
    # client was made with. Without `_secure`, TLS is not available.
    const _secure: bool;
    const _connector: tls.TlsConnector;

    ## Creates a client that trusts the system's root certificates for
    ## `https://` URLs. Where TLS is not available (Linux or macOS without
    ## OpenSSL 3), `http://` URLs still work and `https://` ones fail.
    construct() {
        var connector = tls.TlsConnector.create();
        _secure = connector.is_ok();
        if (_secure) {
            _connector = connector.value();
        } else {
            _connector = tls.TlsConnector(__null);
        }
    }

    ## Creates a client whose `https://` connections use `connector`, for
    ## instance one that trusts a private certificate authority.
    ##
    ## @param connector the TLS connector to open `https://` connections with
    construct(connector: tls.TlsConnector) {
        _secure = true;
        _connector = connector;
    }

    ## Sends a `GET` request for `url`.
    ##
    ## @param url an absolute `http://` or `https://` URL
    ## @returns the response; the errors of `send`
    get(url: String): io.IoResult<Response> {
        return send(Request("GET", url));
    }

    ## Sends a `POST` request for `url` with `body` as a
    ## `Content-Type` of `content_type`.
    ##
    ## @param url an absolute `http://` or `https://` URL
    ## @param content_type the body's media type, such as `application/json`
    ## @param body the body
    ## @returns the response; the errors of `send`
    post(url: String, content_type: String, body: String): io.IoResult<Response> {
        var request = Request("POST", url).set_text(body);
        request.headers["Content-Type"] = content_type;
        return send(request);
    }

    ## Sends `request` and reads the response, body and all.
    ##
    ## The client adds `Host`, `Content-Length` (when there is a body, or
    ## for `POST`, `PUT` and `PATCH`; `Transfer-Encoding: chunked` for a body
    ## from `Request.set_reader` of unknown length) and `Connection: close`,
    ## replacing any the request has.
    ##
    ## @param request the request; its `url` must be absolute
    ## @returns the response, whatever its status; an error with
    ##   `is_invalid_input()` for a URL that is not `http://` or `https://`,
    ##   the errors of `io.TcpStream.connect_host` and
    ##   `tls.TlsConnector.connect`, or an error when the response is not
    ##   valid HTTP/1.x or its body is larger than `MAX_RESPONSE_BODY`
    send(request: Request): io.IoResult<Response> {
        var opened = open(request);
        if (opened.is_err()) {
            return opened;
        }
        var response = opened.value();
        var source = response._source;
        var body = Array<u8>();
        while (true) {
            var read = source.read(body, 65536);
            if (read.is_err()) {
                return io.IoResult<Response>.err(read.error());
            }
            if (read.value() == 0) {
                break;
            }
            if (body.count > MAX_RESPONSE_BODY) {
                return io.IoResult<Response>.err(_http_too_large("the body is too large"));
            }
        }
        response.set_body(body);
        return io.IoResult<Response>.ok(response);
    }

    ## Sends `request` and returns the response as soon as its header fields
    ## arrive, with the body still to read: `response.reader()` returns it
    ## as a `BodyReader`, which reads it from the connection as it arrives,
    ## with no limit on its size. Use it for a large download, writing each
    ## chunk to a file or through a `compress.DecompressReader`.
    ##
    ## The connection closes when the body has been read to its end, when
    ## the `BodyReader` is closed, or when the last reference to it goes.
    ## The request goes out as for `send`.
    ##
    ## @param request the request; its `url` must be absolute
    ## @returns the response with its body unread; the errors of `send`,
    ##   except that the body may be any size. Errors reading the body come
    ##   from the `BodyReader`.
    ## @example
    ##     var response = client.open(http.Request("GET", "https://example.com/large.tar.gz")).value();
    ##     var archive = compress.DecompressReader(response.reader(), compress.Format.Gzip);
    ##     var file = io.File.create(io.Path("large.tar")).value();
    ##     for (var chunk in archive.chunks(65536)) {
    ##         file.write_all(chunk.value());
    ##     }
    open(request: Request): io.IoResult<Response> {
        var parsed = _http_parse_url(request.url);
        if (parsed.is_err()) {
            return io.IoResult<Response>.err(parsed.error());
        }
        var url = parsed.value();
        var tcp = io.TcpStream.connect_host(url._host, url._port);
        if (tcp.is_err()) {
            return io.IoResult<Response>.err(tcp.error());
        }
        var connection = _HttpConnection(tcp.value());
        if (url._secure) {
            if (!_secure) {
                var reason = tls.TlsConnector.create();
                return io.IoResult<Response>.err(reason.error());
            }
            var stream = _connector.connect(connection._tcp, url._host);
            if (stream.is_err()) {
                return io.IoResult<Response>.err(stream.error());
            }
            connection._use_tls(stream.value());
        }
        var result = _http_exchange(connection, request, url);
        if (result.is_err()) {
            connection._close();
        }
        return result;
    }
}

## The body of a response from `Client.open`, read from the connection as it
## arrives. It is an `io.Reader`: read it with `read`, `chunks` or `lines`,
## or hand it to anything that takes a stream. It undoes the framing (a
## `Content-Length`, chunks, or the rest of the connection) and ends where
## the body ends, then closes the connection.
export struct BodyReader {
    # The connection's reader, positioned at the body.
    var _reader: _HttpReader;
    # How the body is framed: `_BODY_LENGTH` with `_left` bytes to go,
    # `_BODY_CHUNKED` with `_left` bytes to go in the current chunk (and
    # `_chunks` read so far), `_BODY_TO_END`, or `_BODY_DONE`.
    var _mode: int;
    var _left: ulong;
    var _chunks: ulong;

    ## Makes a reader of a body framed by `mode` on `reader`'s connection.
    ## `Client.open` makes it; there is no other use.
    ##
    ## @param reader the connection's reader, positioned at the body
    ## @param mode how the body is framed
    ## @param length the body's length, for a `Content-Length` body
    construct(reader: _HttpReader, mode: int, length: ulong) {
        _reader = reader;
        _mode = mode;
        _left = length;
        _chunks = 0;
        if (_mode == _BODY_LENGTH && _left == 0) {
            close();
        }
    }

    ## Reports whether the body has been read to its end, or the reader
    ## closed.
    var is_done: bool {
        get {
            return _mode == _BODY_DONE;
        }
    }

    ## Waits until some of the body has arrived, then appends up to `max`
    ## bytes of it to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read
    ## @returns the number of bytes appended, 0 at the end of the body; an
    ##   error when the connection fails, closes before the body ends, or
    ##   the chunked framing is not valid
    read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        if (max == 0 || _mode == _BODY_DONE) {
            return io.IoResult<ulong>.ok(0);
        }
        if (_mode == _BODY_CHUNKED && _left == 0) {
            var next = _next_chunk();
            if (next.is_err()) {
                return io.IoResult<ulong>.err(next.error());
            }
            if (_mode == _BODY_DONE) {
                return io.IoResult<ulong>.ok(0);
            }
        }
        var want = max;
        if (_mode != _BODY_TO_END && _left < want) {
            want = _left;
        }
        var read = _reader._some(buffer, want);
        if (read.is_err()) {
            return read;
        }
        var got = read.value();
        if (got == 0) {
            if (_mode == _BODY_TO_END) {
                close();
                return read;
            }
            return io.IoResult<ulong>.err(_http_error("the connection closed before the whole body arrived"));
        }
        if (_mode != _BODY_TO_END) {
            _left = _left - got;
            if (_mode == _BODY_LENGTH && _left == 0) {
                close();
            }
        }
        return read;
    }

    ## Stops reading the body and closes the connection. Reading then
    ## returns 0, as at the end of the body. Closing a reader already done
    ## does nothing.
    close() {
        if (_mode != _BODY_DONE) {
            _mode = _BODY_DONE;
            _reader._connection._close();
        }
    }

    # Reads the CRLF that ends the previous chunk and the next size line;
    # at the last chunk, the trailer fields too, and the body is done.
    _next_chunk(): io.IoResult<void> {
        if (_chunks > 0) {
            var end = _reader._required_line(2);
            if (end.is_err()) {
                return io.IoResult<void>.err(end.error());
            }
        }
        var read = _reader._required_line(_HTTP_MAX_LINE);
        if (read.is_err()) {
            return io.IoResult<void>.err(read.error());
        }
        var line = read.value();
        var semicolon = line.find(";");
        if (semicolon >= 0) {
            line = line.substr_bytes(0, semicolon as ulong);
        }
        var size = _http_parse_hex(line.trim());
        if (size < 0) {
            return io.IoResult<void>.err(_http_error($"invalid chunk size: '{line}'"));
        }
        _chunks = _chunks + 1;
        if (size == 0) {
            # The trailer fields, which are dropped.
            var trailer = _http_read_headers(_reader, Headers());
            if (trailer.is_err()) {
                return trailer;
            }
            close();
            return io.IoResult<void>.ok();
        }
        _left = size as ulong;
        return io.IoResult<void>.ok();
    }
}

extend BodyReader with io.Reader;

# The framings of a `BodyReader`.
const _BODY_LENGTH: int = 0;
const _BODY_CHUNKED: int = 1;
const _BODY_TO_END: int = 2;
const _BODY_DONE: int = 3;

# Writes `request` to `connection` and reads the response's head, leaving
# its body to a `BodyReader`.
_http_exchange(connection: _HttpConnection, request: Request, url: _HttpUrl): io.IoResult<Response> {
    var headers = Headers();
    headers.add("Host", url._authority);
    for (var name in request.headers.names()) {
        match (name) {
            "host", "content-length", "transfer-encoding", "connection" => {}
            else => {
                for (var value in request.headers.values(name)) {
                    headers.add(name, value);
                }
            }
        }
    }
    var method = request.method;
    if (request._streamed) {
        if (request._length >= 0) {
            headers.add("Content-Length", to_string(request._length));
        } else {
            headers.add("Transfer-Encoding", "chunked");
        }
    } else {
        var sends_body = match (method) {
            "POST", "PUT", "PATCH" => true,
            else => request._body.count > 0,
        };
        if (sends_body) {
            headers.add("Content-Length", to_string(request._body.count));
        }
    }
    headers.add("Connection", "close");
    var out = Array<u8>();
    _http_write_head(out, $"{method} {url._target} HTTP/1.1", headers);
    var sent = connection._write_all(out);
    if (sent.is_err()) {
        return io.IoResult<Response>.err(sent.error());
    }
    if (request._streamed) {
        var body = _http_write_stream(connection, request._source, request._length, true);
        if (body.is_err()) {
            return io.IoResult<Response>.err(body.error());
        }
    } else if (request._body.count > 0) {
        var body = connection._write_all(request._body);
        if (body.is_err()) {
            return io.IoResult<Response>.err(body.error());
        }
    }

    var reader = _HttpReader(connection);
    while (true) {
        var read = _http_read_response(reader, method == "HEAD");
        if (read.is_err()) {
            return read;
        }
        var response = read.value();
        # Skip interim responses (100 Continue, 103 Early Hints).
        if (response.status >= 200 || response.status == 101) {
            return read;
        }
    }
    return io.IoResult<Response>.err(_http_error("no response"));
}

# Reads a status line and the fields, and gives the response a
# `BodyReader` for the body that follows.
_http_read_response(reader: _HttpReader, head: bool): io.IoResult<Response> {
    var status_line = reader._required_line(_HTTP_MAX_LINE);
    if (status_line.is_err()) {
        return io.IoResult<Response>.err(status_line.error());
    }
    var line = status_line.value();
    # HTTP/1.x SP code [SP reason]
    if (!line.starts_with("HTTP/1.") || line.size < 12) {
        return io.IoResult<Response>.err(_http_error($"not an HTTP/1.x response: '{line}'"));
    }
    var code = _http_parse_decimal(line.substr_bytes(9, 3));
    if (code < 100 || code > 999) {
        return io.IoResult<Response>.err(_http_error($"invalid status line: '{line}'"));
    }
    var response = Response(code as int);
    if (line.size > 13) {
        response.reason = line.substr_bytes(13, line.size - 13);
    }
    var fields = _http_read_headers(reader, response.headers);
    if (fields.is_err()) {
        return io.IoResult<Response>.err(fields.error());
    }
    if (response.status < 200) {
        return io.IoResult<Response>.ok(response);  # interim: no body
    }
    var mode = _BODY_TO_END;
    ulong length = 0;
    var empty = head || response.status == 204 || response.status == 304;
    var encoding = response.headers.get("Transfer-Encoding");
    var content_length = response.headers.get("Content-Length");
    if (empty) {
        mode = _BODY_LENGTH;
    } else if (encoding.is_value() && _http_contains_token(encoding.value(), "chunked")) {
        mode = _BODY_CHUNKED;
    } else if (content_length.is_value()) {
        var n = _http_parse_decimal(content_length.value());
        if (n < 0) {
            return io.IoResult<Response>.err(_http_error($"invalid Content-Length: '{content_length.value()}'"));
        }
        mode = _BODY_LENGTH;
        length = n as ulong;
    }
    response._streamed = true;
    response._source = BodyReader(reader, mode, length);
    return io.IoResult<Response>.ok(response);
}

# ── URLs ─────────────────────────────────────────────────────────────────────

# The parts of an absolute URL a request needs.
struct _HttpUrl {
    var _secure: bool;
    # The host without brackets, for connecting and for TLS.
    var _host: String;
    var _port: u16;
    # The host and port as the Host field gives them.
    var _authority: String;
    # The path and query, `/` at least.
    var _target: String;

    construct() {
        this._host = "";
        this._authority = "";
        this._target = "/";
    }
}

_http_invalid_url(url: String, why: String): io.IoResult<_HttpUrl> {
    return io.IoResult<_HttpUrl>.err(io.IoError(_http_code_invalid_input(), $"invalid URL '{url}': {why}"));
}

[Target(OS(Linux))]
_http_code_invalid_input(): io.ErrorCode { return 22; }

[Target(OS(Mac))]
_http_code_invalid_input(): io.ErrorCode { return 22; }

[Target(OS(Windows))]
_http_code_invalid_input(): io.ErrorCode { return 87; }

[Target(OS(Wasi))]
_http_code_invalid_input(): io.ErrorCode { return 28; }

_http_parse_url(url: String): io.IoResult<_HttpUrl> {
    var uri = Uri.parse(url);
    if (uri.is_err()) {
        return io.IoResult<_HttpUrl>.err(io.IoError(_http_code_invalid_input(), uri.error().message));
    }
    return _http_url_of(url, uri.value());
}

# The parts of `uri`, parsed from `url`, that a request needs. Any scheme
# parses; the client then takes only http and https.
_http_url_of(url: String, uri: Uri): io.IoResult<_HttpUrl> {
    var parsed = _HttpUrl();
    if (!uri.is_absolute() || uri.host.is_empty()) {
        return _http_invalid_url(url, "no scheme, such as 'https://'");
    }
    match (uri.scheme) {
        "http" => {
            parsed._port = 80;
        }
        "https" => {
            parsed._secure = true;
            parsed._port = 443;
        }
        else => {
            return _http_invalid_url(url, $"the scheme '{uri.scheme}' is not supported; use http or https");
        }
    }
    if (uri.user_info.is_value()) {
        return _http_invalid_url(url, "user information is not supported");
    }
    parsed._host = uri.host.value();
    if (parsed._host.size == 0) {
        return _http_invalid_url(url, "no host");
    }
    if (uri.port.is_value()) {
        if (uri.port.value() == 0) {
            return _http_invalid_url(url, "invalid port");
        }
        parsed._port = uri.port.value();
    }
    parsed._authority = uri.authority().value();
    parsed._target = uri.path_and_query();
    return io.IoResult<_HttpUrl>.ok(parsed);
}
