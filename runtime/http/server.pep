## The HTTP server: `Server` accepts HTTP/1.1 and HTTP/2 connections on
## every worker of `async.run` and answers each request with a handler
## function.

import async;
import io;
import tls;
import "h2";
import "message";
import "wire";

## The largest request body a `Server` reads: 16 MiB. A larger one gets
## `413 Content Too Large`.
export const MAX_REQUEST_BODY: ulong = 16777216;

## An HTTP/1.1 and HTTP/2 server.
##
## `Server.bind` listens on an address (`Server.bind_tls` serves HTTPS);
## `serve` then accepts connections on every worker of the running
## `async.run` and serves each connection in a task of its own, calling the
## handler for every request. Connections are kept open between requests
## unless the client asks to close (or speaks HTTP/1.0).
##
## The handler gets the `Request` with its body read in full and returns the
## `Response`; the server adds `Content-Length` (and `Connection: close`
## when it will close). A request the server cannot parse gets `400 Bad
## Request`, one with header fields over 64 KiB `431 Request Header Fields
## Too Large`, and one with a body over `MAX_REQUEST_BODY` `413 Content Too
## Large`; the connection then closes.
##
## HTTP/2 is served to a client that chooses it through ALPN (see
## `bind_tls`) or that starts a plain TCP connection with the HTTP/2
## preface (prior knowledge): each stream is a request, answered by the same
## handler in a task of its own.
##
## @example
##     import async;
##     import http;
##     import io;
##
##     hello(request: http.Request): http.Response {
##         var response = http.Response(200).set_text("hello from " + request.path());
##         response.headers["Content-Type"] = "text/plain";
##         return response;
##     }
##
##     main(): int {
##         async.run(() => {
##             var server = http.Server.bind(io.SocketAddress.parse("0.0.0.0:8080").value()).value();
##             server.serve(hello);
##         });
##         return 0;
##     }
[Shared]
export struct Server {
    # The listening socket, and for HTTPS (`_secure`) the certificate.
    const _listener: io.SharedTcpListener;
    const _secure: bool;
    const _acceptor: tls.TlsAcceptor;

    ## Wraps a listening socket. Use `Server.bind` or `Server.bind_tls`.
    ##
    ## @param listener the listening socket
    ## @param secure whether to serve HTTPS with `acceptor`
    ## @param acceptor the certificate for HTTPS; ignored for HTTP
    construct(listener: io.SharedTcpListener, secure: bool, acceptor: tls.TlsAcceptor) {
        _listener = listener;
        _secure = secure;
        _acceptor = acceptor;
    }

    ## Listens for HTTP connections on `address`.
    ##
    ## @param address the local address (port 0 for any free port)
    ## @returns the server; the errors of `io.TcpListener.bind`
    static bind(address: io.SocketAddress): io.IoResult<Server> {
        var listener = io.SharedTcpListener.bind(address);
        if (listener.is_err()) {
            return io.IoResult<Server>.err(listener.error());
        }
        return io.IoResult<Server>.ok(Server(listener.value(), false, tls.TlsAcceptor(__null)));
    }

    ## Listens for HTTPS connections on `address`, presenting `acceptor`'s
    ## certificate. It sets the acceptor's ALPN protocols to `h2` and
    ## `http/1.1`, so clients that offer HTTP/2 get it.
    ##
    ## @param address the local address (port 0 for any free port)
    ## @param acceptor the certificate and key to serve with
    ## @returns the server; the errors of `io.TcpListener.bind`
    static bind_tls(address: io.SocketAddress, acceptor: tls.TlsAcceptor): io.IoResult<Server> {
        var listener = io.SharedTcpListener.bind(address);
        if (listener.is_err()) {
            return io.IoResult<Server>.err(listener.error());
        }
        acceptor.set_protocols(["h2", "http/1.1"]);
        return io.IoResult<Server>.ok(Server(listener.value(), true, acceptor));
    }

    ## Returns the address the server listens on, with the port the system
    ## chose for port 0.
    ##
    ## @returns the local address, or a platform error
    local_address(): io.IoResult<io.SocketAddress> {
        return _listener.local_address();
    }

    ## Serves connections until the task is cancelled (when `async.run`
    ## ends): accepts on every worker and serves each connection in a task
    ## on the worker that accepted it.
    ##
    ## @param handler answers one request; it runs in the connection's task,
    ##   so it may wait (on sockets, files, locks) without holding up other
    ##   connections
    ## @panics outside `async.run`
    serve(handler: shared (Request) => Response) {
        var server = this;
        var loops = async.spawn_on_each_worker(() => {
            while (true) {
                var accepted = server._listener.accept();
                if (accepted.is_err()) {
                    return;
                }
                var (tcp, peer) = accepted.value();
                async.Task<void>.spawn_local(() => {
                    _http_serve_connection(server, tcp, handler);
                });
            }
        });
        for (var loop in loops) {
            loop.join();
        }
    }
}

# Serves one connection until it closes, fails, or asks to close.
_http_serve_connection(server: Server, tcp: io.TcpStream, handler: shared (Request) => Response) {
    var connection = _HttpConnection(tcp);
    if (server._secure) {
        var stream = server._acceptor.accept(tcp);
        if (stream.is_err()) {
            tcp.close();
            return;
        }
        connection._use_tls(stream.value());
    }
    var reader = _HttpReader(connection);
    var chosen = connection._tls.is_value() ? connection._tls.value().protocol() : Optional<String>.Empty;
    if (chosen.is_value() && chosen.value() == "h2") {
        # HTTP/2 through ALPN: the client's preface comes first.
        var first = reader._line(_HTTP_MAX_LINE);
        if (first.is_ok() && first.value().is_value() && first.value().value() == "PRI * HTTP/2.0") {
            if (_http_finish_preface(reader)) {
                _h2_serve(reader, handler);
            }
        }
        connection._close();
        return;
    }
    while (true) {
        if (!_http_serve_one(reader, handler)) {
            break;
        }
    }
    connection._close();
}

# Reads one request and answers it; whether to keep the connection.
_http_serve_one(reader: _HttpReader, handler: shared (Request) => Response): bool {
    var first = reader._line(_HTTP_MAX_LINE);
    if (first.is_err()) {
        _http_refuse(reader, 400);
        return false;
    }
    if (first.value().is_empty()) {
        return false;  # the client closed between requests
    }
    var line = first.value().value();
    if (line == "PRI * HTTP/2.0") {
        # HTTP/2 with prior knowledge (h2c): the rest of the preface.
        if (_http_finish_preface(reader)) {
            _h2_serve(reader, handler);
        }
        return false;
    }
    # METHOD SP target SP HTTP/1.x
    var space = line.find(" ");
    var last = _http_last_space(line);
    if (space <= 0
        || last <= space
        || !line.substr_bytes(last as ulong + 1, line.size - last as ulong - 1).starts_with("HTTP/1.")) {
        _http_refuse(reader, 400);
        return false;
    }
    var method = line.substr_bytes(0, space as ulong);
    var target = line.substr_bytes(space as ulong + 1, (last - space - 1) as ulong);
    var version = line.substr_bytes(last as ulong + 1, line.size - last as ulong - 1);
    var request = Request(method, target);
    request._upgradable = version == "HTTP/1.1";
    var fields = _http_read_headers(reader, request.headers);
    if (fields.is_err()) {
        if (fields.error().code == _http_code_too_large()) {
            _http_refuse(reader, 431);
        } else {
            _http_refuse(reader, 400);
        }
        return false;
    }
    var keep = version == "HTTP/1.1";
    var connection_field = request.headers.get("Connection");
    if (connection_field.is_value()) {
        if (_http_contains_token(connection_field.value(), "close")) {
            keep = false;
        } else if (_http_contains_token(connection_field.value(), "keep-alive")) {
            keep = true;
        }
    }
    var expect = request.headers.get("Expect");
    if (expect.is_value()) {
        if (expect.value().lower() == "100-continue") {
            var go_on = Array<u8>();
            _http_append(go_on, "HTTP/1.1 100 Continue\r\n\r\n");
            reader._connection._write_all(go_on);
        }
    }
    var body = _http_read_body(reader, request.headers, request._body, MAX_REQUEST_BODY);
    if (body.is_err()) {
        if (body.error().code == _http_code_too_large()) {
            _http_refuse(reader, 413);
        } else {
            _http_refuse(reader, 400);
        }
        return false;
    }
    var response = handler(request);
    if (response._upgrade && !request._upgradable) {
        response = Response(501);  # HTTP/1.0 cannot switch protocols
    }
    var sent = _http_send_response(reader._connection, response, method == "HEAD", keep, version == "HTTP/1.1");
    if (response._upgrade) {
        if (sent) {
            response._takeover(Connection(reader));
        }
        return false;
    }
    return keep && sent;
}

# Reads the rest of the HTTP/2 client preface after its first line: an
# empty line, `SM`, and another empty line. Whether it was all there.
_http_finish_preface(reader: _HttpReader): bool {
    for (var expected in ["", "SM", ""]) {
        var line = reader._line(4);
        if (line.is_err() || line.value().is_empty() || line.value().value() != expected) {
            return false;
        }
    }
    return true;
}

# The position of the last space in `line`, or -1.
_http_last_space(line: String): long {
    var p = unsafe_cast<__ptr<u8>>(line.c_str());
    var i = line.size;
    while (i > 0) {
        i = i - 1;
        if (p[i] == ' ') {
            return i as long;
        }
    }
    return -1;
}

# Answers a request the server will not serve, and closes.
_http_refuse(reader: _HttpReader, status: int) {
    _http_send_response(reader._connection, Response(status), false, false, true);
}

# Writes `response`; whether the connection can serve another request. A
# streamed body of unknown length goes chunked when `chunked` (HTTP/1.1),
# and otherwise unframed, ending the connection.
_http_send_response(connection: _HttpConnection, response: Response, head: bool, keep: bool, chunked: bool): bool {
    var headers = Headers();
    for (var name in response.headers.names()) {
        match (name) {
            "content-length", "transfer-encoding", "connection" => {}
            else => {
                for (var value in response.headers.values(name)) {
                    headers.add(name, value);
                }
            }
        }
    }
    var status = response.status;
    if (response._upgrade) {
        headers.add("Connection", "Upgrade");
        var upgrade = Array<u8>();
        _http_write_head(upgrade, "HTTP/1.1 101 Switching Protocols", headers);
        return connection._write_all(upgrade).is_ok();
    }
    var bodiless = status < 200 || status == 204 || status == 304;
    var streamed = response._streamed && !bodiless;
    if (streamed) {
        if (response._length >= 0) {
            headers.add("Content-Length", to_string(response._length));
        } else if (chunked) {
            headers.add("Transfer-Encoding", "chunked");
        } else {
            keep = false;  # the end of the connection ends the body
        }
    } else if (!bodiless) {
        headers.add("Content-Length", to_string(response._body.count));
    }
    if (!keep) {
        headers.add("Connection", "close");
    }
    var reason = response.reason;
    if (reason.size == 0) {
        reason = reason_phrase(status);
    }
    var out = Array<u8>();
    _http_write_head(out, $"HTTP/1.1 {status} {reason}", headers);
    if (!head && !bodiless && !streamed) {
        out.append_all(response._body);
    }
    if (connection._write_all(out).is_err()) {
        return false;
    }
    if (streamed && !head) {
        if (_http_write_stream(connection, response._source, response._length, chunked).is_err()) {
            return false;
        }
    }
    return keep;
}

## A connection a `Server` handler took over by answering with
## `Response.upgrade`: the raw stream after the `101 Switching Protocols`
## head, TCP or (under `Server.bind_tls`) TLS, as an `io.Reader` and an
## `io.Writer`.
##
## Reads return first the bytes the server had already read past the
## request (a client may send its first message right after the request),
## then what arrives. Like the handler, it belongs to the connection's task.
##
## @example
##     upgraded(request: http.Request): http.Response {
##         return http.Response().upgrade("echo", (connection) => {
##             var data = Array<u8>();
##             while (connection.read(data, 4096).value() > 0) {
##                 connection.write_all(data);
##                 data.clear();
##             }
##         });
##     }
export struct Connection {
    # The connection's reader, holding the bytes read past the request.
    var _reader: _HttpReader;

    ## Wraps the connection `reader` reads. The server makes one for
    ## `Response.upgrade`.
    ##
    ## @param reader the connection and the bytes it buffered
    construct(reader: _HttpReader) {
        this._reader = reader;
    }

    ## Waits until some bytes are available, then appends up to `max` of
    ## them to `buffer`: the ones buffered past the request first.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read
    ## @returns the number of bytes appended, 0 at the end of the stream; an
    ##   error when the stream fails
    read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        return this._reader._some(buffer, max);
    }

    ## Writes what the stream takes in one call, which may be less than all
    ## of `data`.
    ##
    ## @param data the bytes to write
    ## @returns the number of bytes written; an error when the stream fails
    write(data: u8[]): io.IoResult<ulong> {
        return this._reader._connection._writer.write(data);
    }

    ## Writes all of `data`.
    ##
    ## @param data the bytes to write
    ## @returns an Ok result once every byte is written; an error when the
    ##   stream fails
    write_all(data: u8[]): io.IoResult<void> {
        return this._reader._connection._write_all(data);
    }

    ## Closes the connection, sending TLS close_notify first under TLS. The
    ## server also closes it when the `takeover` function returns; closing
    ## again does nothing.
    close() {
        this._reader._connection._close();
    }
}

extend Connection with io.Reader;

extend Connection with io.Writer;

## Returns the standard reason phrase for an HTTP status code.
##
## @param status the status code
## @returns the phrase, such as `Not Found` for 404; an empty string for a
##   code without one
export reason_phrase(status: int): String {
    return match (status) {
        100 => "Continue",
        101 => "Switching Protocols",
        200 => "OK",
        201 => "Created",
        202 => "Accepted",
        204 => "No Content",
        206 => "Partial Content",
        301 => "Moved Permanently",
        302 => "Found",
        303 => "See Other",
        304 => "Not Modified",
        307 => "Temporary Redirect",
        308 => "Permanent Redirect",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        408 => "Request Timeout",
        409 => "Conflict",
        410 => "Gone",
        413 => "Content Too Large",
        415 => "Unsupported Media Type",
        429 => "Too Many Requests",
        431 => "Request Header Fields Too Large",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        else => "",
    };
}
