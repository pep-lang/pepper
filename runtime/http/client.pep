## The HTTP client: `Client` sends a `Request` over HTTP or HTTPS and
## returns the `Response`.

import io;
import os;
import tls;
import "h2";
import "message";
import "wire";

## The largest response body a `Client` reads: 64 MiB.
export const MAX_RESPONSE_BODY: ulong = 67108864;

## Sends HTTP/1.1 and HTTP/2 requests and reads their responses.
##
## Each request opens a new connection (plain TCP for `http://`, TLS for
## `https://`), sends the request with `Connection: close`, and reads the
## response: `send` reads the whole body into memory, and `open` returns
## once the header fields arrive, with the body to read as a stream. To
## send requests on connections kept open between them, use a `Session`
## (`client.session()`).
##
## For `https://` the client offers HTTP/2 and HTTP/1.1 through ALPN and
## speaks the one the server chooses; the request and response are the same
## either way. Over HTTP/2 the response's `reason` is the standard phrase
## for its status. Plain `http://` uses HTTP/1.1.
##
## Redirects (301, 302, 303, 307 and 308 with a `Location`) are followed,
## up to `max_redirects` of them, as RFC 9110 describes: 303, and 301 or
## 302 after a `POST`, become a `GET` without the body; 307 and 308 repeat
## the method and body. A request whose body comes from
## `Request.set_reader` cannot be repeated, so its 307 or 308 is returned
## as it is. When a redirect leaves the origin (scheme, host and port),
## `Authorization`, `Proxy-Authorization` and `Cookie` are dropped. Make a
## client with `max_redirects` 0 to get every redirect back as it is.
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

    ## The most redirects one request follows; 0 follows none.
    const max_redirects: int;

    ## Creates a client that trusts the system's root certificates for
    ## `https://` URLs. Where TLS is not available (Linux or macOS without
    ## OpenSSL 3), `http://` URLs still work and `https://` ones fail.
    ##
    ## @param max_redirects the most redirects one request follows; 0
    ##   returns every redirect as it is
    construct(max_redirects: int = 10) {
        this.max_redirects = max_redirects;
        var connector = tls.TlsConnector.create();
        _secure = connector.is_ok();
        if (_secure) {
            _connector = connector.value();
            _connector.set_protocols(_http_protocols());
        } else {
            _connector = tls.TlsConnector(__null);
        }
    }

    ## Creates a client whose `https://` connections use `connector`, for
    ## instance one that trusts a private certificate authority. The client
    ## sets the connector's ALPN protocols to `h2` and `http/1.1`.
    ##
    ## @param connector the TLS connector to open `https://` connections with
    ## @param max_redirects the most redirects one request follows; 0
    ##   returns every redirect as it is
    construct(connector: tls.TlsConnector, max_redirects: int = 10) {
        this.max_redirects = max_redirects;
        _secure = true;
        _connector = connector;
        _connector.set_protocols(_http_protocols());
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
    ## @returns the response after any redirects, whatever its status; an
    ##   error with `is_invalid_input()` for a URL that is not `http://` or
    ##   `https://`, a method or field name that is not an RFC 9110 token, or
    ##   a field value holding CR, LF or NUL (which would split the request),
    ##   the errors of `io.TcpStream.connect_host` and
    ##   `tls.TlsConnector.connect`, or an error when the response is not
    ##   valid HTTP/1.x, its body is larger than `MAX_RESPONSE_BODY`, or there
    ##   are more than `max_redirects` redirects
    send(request: Request): io.IoResult<Response> {
        return _http_send(this, Optional<_HttpPool>.Empty, request);
    }

    ## Sends `request` and returns the response as soon as its header fields
    ## arrive, with the body still to read: `response.reader()` returns it
    ## as a `BodyReader`, which reads it from the connection as it arrives,
    ## with no limit on its size. Use it for a large download, writing each
    ## chunk to a file or through a `compress.DecompressReader`.
    ##
    ## The connection closes when the body has been read to its end, when
    ## the `BodyReader` is closed, or when the last reference to it goes.
    ## The request goes out, and redirects are followed, as for `send`.
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
        return _http_open(this, Optional<_HttpPool>.Empty, request);
    }

    ## Returns a new `Session` that sends requests with this client's
    ## settings and keeps their connections open for the requests after
    ## them.
    ##
    ## @returns the session, with no connections yet
    session(): Session {
        return Session(this);
    }

    # Opens a connection for `url`: TCP, and TLS over it for https.
    _connect(url: _HttpUrl): io.IoResult<_HttpConnection> {
        var tcp = io.TcpStream.connect_host(url._host, url._port);
        if (tcp.is_err()) {
            return io.IoResult<_HttpConnection>.err(tcp.error());
        }
        var connection = _HttpConnection(tcp.value());
        if (url._secure) {
            if (!_secure) {
                var reason = tls.TlsConnector.create();
                return io.IoResult<_HttpConnection>.err(reason.error());
            }
            var stream = _connector.connect(connection._tcp, url._host);
            if (stream.is_err()) {
                return io.IoResult<_HttpConnection>.err(stream.error());
            }
            connection._use_tls(stream.value());
        }
        return io.IoResult<_HttpConnection>.ok(connection);
    }
}

## A run of requests that share connections: each connection stays open
## after its response (HTTP/1.1 keep-alive) and the next request to the same
## scheme, host and port uses it again, saving the TCP and TLS handshakes.
## Make one with `client.session()`; it sends requests and follows redirects
## with that client's settings.
##
## A connection goes back to the session once its response body has been
## read to its end (which `send` does), unless the server asked to close it.
## Up to `max_idle_per_host` connections wait for each scheme, host and
## port; one idle for longer than `idle_timeout` is closed instead of used.
## A request that finds its reused connection closed by the server is sent
## again on a new one, unless its body came from `Request.set_reader`.
##
## Over HTTP/2 the session keeps one connection per origin, which every
## request to that origin shares at once on a stream of its own, so tasks
## started with `spawn_local` can send through one session concurrently.
##
## A session is not `[Shared]`: use it from one thread or task. Its
## connections close when the last reference to it (and to the
## `BodyReader`s it returned) goes, or at `close()`.
##
## @example
##     var session = http.Client().session();
##     for (var page in 1..>3) {
##         var response = session.get($"https://example.com/items?page={page}").value();
##         print(response.text());
##     }
##     # One connection carried all three requests.
export struct Session {
    ## The client whose settings the session uses: its TLS connector and
    ## `max_redirects`.
    var client: Client;
    # The idle connections.
    var _pool: _HttpPool;

    ## Creates a session with no connections yet; `client.session()` does
    ## the same.
    ##
    ## @param client the client whose settings the session uses
    construct(client: Client) {
        this.client = client;
        this._pool = _HttpPool();
    }

    ## How long a connection may wait unused before the session closes it
    ## rather than send on it: 90 seconds unless changed. Servers close idle
    ## connections too, often sooner.
    var idle_timeout: os.Duration {
        get {
            return _pool._idle_timeout;
        }
        set {
            _pool._idle_timeout = value;
        }
    }

    ## The most idle connections kept for one scheme, host and port: 4
    ## unless changed. 0 keeps none, so every request uses a new connection.
    var max_idle_per_host: ulong {
        get {
            return _pool._max_idle;
        }
        set {
            _pool._max_idle = value;
        }
    }

    ## The number of idle connections the session holds, for every host.
    var idle_count: ulong {
        get {
            return _pool._count();
        }
    }

    ## Sends a `GET` request for `url`, as `Client.get` does.
    ##
    ## @param url an absolute `http://` or `https://` URL
    ## @returns the response; the errors of `Client.send`
    get(url: String): io.IoResult<Response> {
        return send(Request("GET", url));
    }

    ## Sends a `POST` request for `url` with `body` as a `Content-Type` of
    ## `content_type`, as `Client.post` does.
    ##
    ## @param url an absolute `http://` or `https://` URL
    ## @param content_type the body's media type, such as `application/json`
    ## @param body the body
    ## @returns the response; the errors of `Client.send`
    post(url: String, content_type: String, body: String): io.IoResult<Response> {
        var request = Request("POST", url).set_text(body);
        request.headers["Content-Type"] = content_type;
        return send(request);
    }

    ## Sends `request` on an idle connection to its host if there is one,
    ## and reads the response, body and all, as `Client.send` does. The
    ## request keeps the connection open, so the client sends no
    ## `Connection: close`.
    ##
    ## @param request the request; its `url` must be absolute
    ## @returns the response; the errors of `Client.send`
    send(request: Request): io.IoResult<Response> {
        return _http_send(client, Optional<_HttpPool>.Value(_pool), request);
    }

    ## Sends `request` as `send` does and returns at the response's header
    ## fields, as `Client.open` does. The connection goes back to the
    ## session when the body has been read to its end; closing the
    ## `BodyReader` early closes the connection.
    ##
    ## @param request the request; its `url` must be absolute
    ## @returns the response with its body unread; the errors of
    ##   `Client.open`
    open(request: Request): io.IoResult<Response> {
        return _http_open(client, Optional<_HttpPool>.Value(_pool), request);
    }

    ## Closes every idle connection. The session stays usable: later
    ## requests open new connections.
    close() {
        _pool._close_all();
    }
}

# Idle connections by origin (`_http_origin_key`), each with the moment it
# went idle, oldest first.
struct _HttpPool {
    var _idle: HashMap<String, _HttpIdle[]>;
    # One HTTP/2 connection per origin, which every request to it shares.
    var _h2: HashMap<String, _H2Connection>;
    var _idle_timeout: os.Duration;
    var _max_idle: ulong;

    construct() {
        _idle = HashMap<String, _HttpIdle[]>();
        _h2 = HashMap<String, _H2Connection>();
        _idle_timeout = os.Duration.from_seconds(90);
        _max_idle = 4;
    }

    _count(): ulong {
        ulong total = 0;
        for (var (key, list) in _idle) {
            total = total + list.count;
        }
        for (var (key, connection) in _h2) {
            if (connection.active_count == 0) {
                total = total + 1;
            }
        }
        return total;
    }

    # The HTTP/2 connection for `key` that can still open streams, closing
    # one that cannot.
    _take_h2(key: String): _H2Connection? {
        var connection = _h2.get(key);
        if (connection === __null) {
            return Optional<_H2Connection>.Empty;
        }
        if (connection.is_usable) {
            return Optional<_H2Connection>.Value(connection);
        }
        _h2.remove(key);
        connection.close();
        return Optional<_H2Connection>.Empty;
    }

    # The most recently idle connection for `key` that has not timed out,
    # closing the ones that have.
    _take(key: String): _HttpConnection? {
        var list = _idle.get(key);
        if (list === __null) {
            return Optional<_HttpConnection>.Empty;
        }
        while (list.count > 0) {
            var idle = list.pop();
            if (idle._since.elapsed().nanoseconds() < _idle_timeout.nanoseconds()) {
                return Optional<_HttpConnection>.Value(idle._connection);
            }
            idle._connection._close();
        }
        return Optional<_HttpConnection>.Empty;
    }

    # Keeps `connection` for the next request to `key`, or closes it when
    # `key` already has `_max_idle`.
    _put(key: String, connection: _HttpConnection) {
        var list = _idle.get(key);
        if (list === __null) {
            list = Array<_HttpIdle>();
            _idle[key] = list;
        }
        if (list.count >= _max_idle) {
            connection._close();
            return;
        }
        list.append(_HttpIdle(connection));
    }

    _close_all() {
        for (var (key, list) in _idle) {
            for (var idle in list) {
                idle._connection._close();
            }
        }
        _idle = HashMap<String, _HttpIdle[]>();
        for (var (key, connection) in _h2) {
            connection.close();
        }
        _h2 = HashMap<String, _H2Connection>();
    }
}

struct _HttpIdle {
    var _connection: _HttpConnection;
    var _since: os.Instant;

    construct(connection: _HttpConnection) {
        _connection = connection;
        _since = os.Instant.now();
    }
}

# The pool key of `url`: its scheme, host and port.
_http_origin_key(url: _HttpUrl): String {
    var scheme = url._secure ? "https" : "http";
    var host = url._host.lower();
    return $"{scheme}://{host}:{url._port}";
}

# `Client.send` and `Session.send`: opens the response and reads its body.
_http_send(client: Client, pool: _HttpPool?, request: Request): io.IoResult<Response> {
    var opened = _http_open(client, pool, request);
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
            _http_close_body(response);
            return io.IoResult<Response>.err(_http_too_large("the body is too large"));
        }
    }
    response.set_body(body);
    return io.IoResult<Response>.ok(response);
}

# `Client.open` and `Session.open`: sends `request` and follows redirects.
_http_open(client: Client, pool: _HttpPool?, request: Request): io.IoResult<Response> {
    var current = request;
    var redirects = 0;
    while (true) {
        var opened = _http_open_once(client, pool, current);
        if (opened.is_err() || client.max_redirects <= 0) {
            return opened;
        }
        var response = opened.value();
        var next = _http_redirected(current, response);
        if (next.is_empty()) {
            return opened;
        }
        _http_close_body(response);
        if (redirects >= client.max_redirects) {
            return io.IoResult<Response>.err(_http_error($"too many redirects: more than {client.max_redirects}"));
        }
        redirects = redirects + 1;
        current = next.value();
    }
    return io.IoResult<Response>.err(_http_error("no response"));
}

# Sends `request` and reads the response's head: on an idle connection from
# `pool` if it has one for the URL's origin (and again on a new connection
# if that one turns out closed), else on a new connection.
_http_open_once(client: Client, pool: _HttpPool?, request: Request): io.IoResult<Response> {
    if (!_http_is_token(request.method)) {
        return io.IoResult<Response>.err(
            io.IoError(_http_code_invalid_input(), $"the method '{request.method}' is not a token")
        );
    }
    var bad = _http_bad_fields(request.headers);
    if (bad.is_value()) {
        return io.IoResult<Response>.err(io.IoError(_http_code_invalid_input(), bad.value()));
    }
    var parsed = _http_parse_url(request.url);
    if (parsed.is_err()) {
        return io.IoResult<Response>.err(parsed.error());
    }
    var url = parsed.value();
    var key = _http_origin_key(url);
    if (pool.is_value()) {
        var shared = pool.value()._take_h2(key);
        if (shared.is_value()) {
            var sent = _h2_exchange(shared.value(), request, url, url._secure);
            if (sent.is_ok()) {
                sent.value().url = request.url;
                return sent;
            }
            if (request._streamed || shared.value().is_usable) {
                return sent;
            }
            # The connection went away under the request: a new one follows.
            pool.value()._take_h2(key);
        }
        var idle = pool.value()._take(key);
        if (idle.is_value()) {
            var reused = _http_exchange(idle.value(), request, url, true);
            if (reused.is_ok()) {
                _http_pool_body(reused.value(), pool.value(), key);
                reused.value().url = request.url;
                return reused;
            }
            idle.value()._close();
            if (request._streamed) {
                return reused;  # its body is gone, so it cannot be sent again
            }
        }
    }
    var connected = client._connect(url);
    if (connected.is_err()) {
        return io.IoResult<Response>.err(connected.error());
    }
    var connection = connected.value();
    if (_http_chose_h2(connection)) {
        return _http_open_h2(connection, pool, key, request, url);
    }
    var result = _http_exchange(connection, request, url, pool.is_value());
    if (result.is_err()) {
        connection._close();
        return result;
    }
    if (pool.is_value()) {
        _http_pool_body(result.value(), pool.value(), key);
    }
    result.value().url = request.url;
    return result;
}

# The protocols a client offers through ALPN, HTTP/2 first.
_http_protocols(): String[] {
    return ["h2", "http/1.1"];
}

# Whether the TLS handshake on `connection` chose HTTP/2.
_http_chose_h2(connection: _HttpConnection): bool {
    if (connection._tls.is_empty()) {
        return false;
    }
    var chosen = connection._tls.value().protocol();
    return chosen.is_value() && chosen.value() == "h2";
}

# Sends `request` over HTTP/2 on a new `connection`, which joins `pool`
# when there is one and otherwise closes after the response's body.
_http_open_h2(
    connection: _HttpConnection, pool: _HttpPool?, key: String, request: Request, url: _HttpUrl
): io.IoResult<Response> {
    var started = _H2Connection.client(connection);
    if (started.is_err()) {
        connection._close();
        return io.IoResult<Response>.err(started.error());
    }
    var h2 = started.value();
    if (pool.is_value()) {
        pool.value()._h2[key] = h2;
    }
    var result = _h2_exchange(h2, request, url, url._secure);
    if (result.is_err()) {
        if (pool.is_empty()) {
            h2.close();
        }
        return result;
    }
    if (pool.is_empty()) {
        (result.value()._source as? _H2BodyReader).value()._owner = true;
    }
    result.value().url = request.url;
    return result;
}

# Has the `BodyReader` of `response` give its connection to `pool` at the
# end of the body.
_http_pool_body(response: Response, pool: _HttpPool, key: String) {
    var body = response._source as? BodyReader;
    if (body.is_value()) {
        body.value()._pool = Optional<_HttpPool>.Value(pool);
        body.value()._key = key;
    }
}

# The request that follows `response` to `request`, when it is a redirect
# the client follows; Empty to return `response` as it is.
_http_redirected(request: Request, response: Response): Request? {
    var status = response.status;
    if (status != 301 && status != 302 && status != 303 && status != 307 && status != 308) {
        return Optional<Request>.Empty;
    }
    var location = response.headers.get("Location");
    if (location.is_empty()) {
        return Optional<Request>.Empty;
    }
    var base = Uri.parse(request.url);
    var reference = Uri.parse(location.value().trim());
    if (base.is_err() || reference.is_err()) {
        return Optional<Request>.Empty;
    }
    var target = base.value().resolve(reference.value());
    if (reference.value().fragment.is_empty()) {
        target.fragment = base.value().fragment;  # RFC 9110 10.2.2
    }
    var text = target.to_string();
    var from = _http_parse_url(request.url);
    var to = _http_url_of(text, target);
    if (from.is_err() || to.is_err()) {
        return Optional<Request>.Empty;
    }
    var method = request.method;
    var keeps_body = true;
    if ((status == 303 && method != "HEAD") || ((status == 301 || status == 302) && method == "POST")) {
        method = "GET";
        keeps_body = false;
    }
    if (keeps_body && request._streamed) {
        return Optional<Request>.Empty;  # the body was read once and is gone
    }
    var next = Request(method, text);
    var same_origin = from.value()._secure == to.value()._secure
        && from.value()._host.lower() == to.value()._host.lower()
        && from.value()._port == to.value()._port;
    for (var name in request.headers.names()) {
        var dropped = match (name) {
            "authorization", "proxy-authorization", "cookie" => !same_origin,
            "content-type", "content-encoding", "content-language", "content-location" => !keeps_body,
            else => false,
        };
        if (!dropped) {
            for (var value in request.headers.values(name)) {
                next.headers.add(name, value);
            }
        }
    }
    if (keeps_body) {
        next.set_body(request._body);
    }
    return Optional<Request>.Value(next);
}

# Closes the connection of a response from `_http_open_once` whose body is not
# wanted.
_http_close_body(response: Response) {
    var body = response._source as? BodyReader;
    if (body.is_value()) {
        body.value().close();
        return;
    }
    var stream = response._source as? _H2BodyReader;
    if (stream.is_value()) {
        stream.value().close();
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
    # Whether the server keeps the connection open after the body, and the
    # session pool (with the origin's key) it then goes back to.
    var _reusable: bool;
    var _pool: _HttpPool?;
    var _key: String;

    ## Makes a reader of a body framed by `mode` on `reader`'s connection.
    ## `Client.open` makes it; there is no other use.
    ##
    ## @param reader the connection's reader, positioned at the body
    ## @param mode how the body is framed
    ## @param length the body's length, for a `Content-Length` body
    ## @param reusable whether the server keeps the connection open after
    ##   the body
    construct(reader: _HttpReader, mode: int, length: ulong, reusable: bool) {
        _reader = reader;
        _mode = mode;
        _left = length;
        _chunks = 0;
        _reusable = reusable && mode != _BODY_TO_END;
        _pool = Optional<_HttpPool>.Empty;
        _key = "";
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
        if (_mode == _BODY_LENGTH && _left == 0) {
            _finish();
        }
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
                _finish();
            }
        }
        return read;
    }

    # The body has ended: the connection goes back to the session that
    # opened it when the server keeps it open, and closes otherwise.
    _finish() {
        if (_mode == _BODY_DONE) {
            return;
        }
        if (_reusable && _pool.is_value() && _reader._available() == 0) {
            _mode = _BODY_DONE;
            _pool.value()._put(_key, _reader._connection);
            return;
        }
        close();
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
            _finish();
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
_http_exchange(connection: _HttpConnection, request: Request, url: _HttpUrl, keep: bool): io.IoResult<Response> {
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
    if (!keep) {
        headers.add("Connection", "close");
    }
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
    # HTTP/1.1 keeps the connection unless the server says close; HTTP/1.0
    # closes it unless the server says keep-alive.
    var reusable = line.starts_with("HTTP/1.1");
    var connection_field = response.headers.get("Connection");
    if (connection_field.is_value()) {
        if (_http_contains_token(connection_field.value(), "close")) {
            reusable = false;
        } else if (_http_contains_token(connection_field.value(), "keep-alive")) {
            reusable = true;
        }
    }
    response._streamed = true;
    response._source = BodyReader(reader, mode, length, reusable);
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
    if (parsed._host.contains(":")) {
        # An IPv6 address: its scope's `%` is escaped as `%25` (RFC 6874).
        var host = Uri.decode(parsed._host);
        if (host.is_err()) {
            return _http_invalid_url(url, "invalid host");
        }
        parsed._host = host.value();
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
