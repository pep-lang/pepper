## The HTTP server: `Server` accepts HTTP/1.1 connections on every worker of
## `async.run` and answers each request with a handler function.

import async;
import io;
import tls;
import "message";
import "wire";

## The largest request body a `Server` reads: 16 MiB. A larger one gets
## `413 Content Too Large`.
export const MAX_REQUEST_BODY: ulong = 16777216;

## An HTTP/1.1 server.
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
    ## certificate.
    ##
    ## @param address the local address (port 0 for any free port)
    ## @param acceptor the certificate and key to serve with
    ## @returns the server; the errors of `io.TcpListener.bind`
    static bind_tls(address: io.SocketAddress, acceptor: tls.TlsAcceptor): io.IoResult<Server> {
        var listener = io.SharedTcpListener.bind(address);
        if (listener.is_err()) {
            return io.IoResult<Server>.err(listener.error());
        }
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
        connection._tls = Optional<tls.TlsStream>.some(stream.value());
    }
    var reader = _HttpReader(connection);
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
    if (first.value().is_none()) {
        return false;  # the client closed between requests
    }
    var line = first.value().value();
    # METHOD SP target SP HTTP/1.x
    var space = line.find(" ");
    var last = _http_last_space(line);
    if (space <= 0
        || last <= space
        || !line.substr_bytes(last as ulong + 1, line.size() - last as ulong - 1).starts_with("HTTP/1.")) {
        _http_refuse(reader, 400);
        return false;
    }
    var method = line.substr_bytes(0, space as ulong);
    var target = line.substr_bytes(space as ulong + 1, (last - space - 1) as ulong);
    var version = line.substr_bytes(last as ulong + 1, line.size() - last as ulong - 1);
    var request = Request(method, target);
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
    if (connection_field.is_some()) {
        if (_http_contains_token(connection_field.value(), "close")) {
            keep = false;
        } else if (_http_contains_token(connection_field.value(), "keep-alive")) {
            keep = true;
        }
    }
    var expect = request.headers.get("Expect");
    if (expect.is_some()) {
        if (expect.value().lower() == "100-continue") {
            var go_on = Array<u8>();
            _http_append(go_on, "HTTP/1.1 100 Continue\r\n\r\n");
            reader._connection._write_all(go_on);
        }
    }
    var body = _http_read_body(reader, request.headers, request._body, false, MAX_REQUEST_BODY);
    if (body.is_err()) {
        if (body.error().code == _http_code_too_large()) {
            _http_refuse(reader, 413);
        } else {
            _http_refuse(reader, 400);
        }
        return false;
    }
    var response = handler(request);
    _http_send_response(reader._connection, response, method == "HEAD", keep);
    return keep;
}

# The position of the last space in `line`, or -1.
_http_last_space(line: String): long {
    var p = line.c_str() as __ptr<u8>;
    var i = line.size();
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
    _http_send_response(reader._connection, Response(status), false, false);
}

_http_send_response(connection: _HttpConnection, response: Response, head: bool, keep: bool) {
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
    var bodiless = status < 200 || status == 204 || status == 304;
    if (!bodiless) {
        headers.add("Content-Length", to_string(response._body.count()));
    }
    if (!keep) {
        headers.add("Connection", "close");
    }
    var reason = response.reason;
    if (reason.size() == 0) {
        reason = reason_phrase(status);
    }
    var out = Array<u8>();
    _http_write_head(out, $"HTTP/1.1 {status} {reason}", headers);
    if (!head && !bodiless) {
        out.append_all(response._body);
    }
    connection._write_all(out);
}

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
