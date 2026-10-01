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
## whole response. Redirects are returned as they are, not followed.
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

    ## Sends `request` and reads the response.
    ##
    ## The client adds `Host`, `Content-Length` (when there is a body, or
    ## for `POST`, `PUT` and `PATCH`) and `Connection: close`, replacing any
    ## the request has.
    ##
    ## @param request the request; its `url` must be absolute
    ## @returns the response, whatever its status; an error with
    ##   `is_invalid_input()` for a URL that is not `http://` or `https://`,
    ##   the errors of `io.TcpStream.connect_host` and
    ##   `tls.TlsConnector.connect`, or an error when the response is not
    ##   valid HTTP/1.x or its body is larger than `MAX_RESPONSE_BODY`
    send(request: Request): io.IoResult<Response> {
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
        connection._close();
        return result;
    }
}

# Writes `request` to `connection` and reads the response.
_http_exchange(connection: _HttpConnection, request: Request, url: _HttpUrl): io.IoResult<Response> {
    var headers = Headers();
    headers.add("Host", url._authority);
    for (var name in request.headers.names()) {
        match (name) {
            "host", "content-length", "connection" => {}
            else => {
                for (var value in request.headers.values(name)) {
                    headers.add(name, value);
                }
            }
        }
    }
    var method = request.method;
    var sends_body = match (method) {
        "POST", "PUT", "PATCH" => true,
        else => request._body.count() > 0,
    };
    if (sends_body) {
        headers.add("Content-Length", to_string(request._body.count()));
    }
    headers.add("Connection", "close");
    var out = Array<u8>();
    _http_write_head(out, $"{method} {url._target} HTTP/1.1", headers);
    var sent = connection._write_all(out);
    if (sent.is_err()) {
        return io.IoResult<Response>.err(sent.error());
    }
    if (request._body.count() > 0) {
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

# Reads a status line, the fields and the body.
_http_read_response(reader: _HttpReader, head: bool): io.IoResult<Response> {
    var status_line = reader._required_line(_HTTP_MAX_LINE);
    if (status_line.is_err()) {
        return io.IoResult<Response>.err(status_line.error());
    }
    var line = status_line.value();
    # HTTP/1.x SP code [SP reason]
    if (!line.starts_with("HTTP/1.") || line.size() < 12) {
        return io.IoResult<Response>.err(_http_error($"not an HTTP/1.x response: '{line}'"));
    }
    var code = _http_parse_decimal(line.substr_bytes(9, 3));
    if (code < 100 || code > 999) {
        return io.IoResult<Response>.err(_http_error($"invalid status line: '{line}'"));
    }
    var response = Response(code as int);
    if (line.size() > 13) {
        response.reason = line.substr_bytes(13, line.size() - 13);
    }
    var fields = _http_read_headers(reader, response.headers);
    if (fields.is_err()) {
        return io.IoResult<Response>.err(fields.error());
    }
    var empty = head || response.status < 200 || response.status == 204 || response.status == 304;
    if (!empty) {
        var body = _http_read_body(reader, response.headers, response._body, true, MAX_RESPONSE_BODY);
        if (body.is_err()) {
            return io.IoResult<Response>.err(body.error());
        }
    }
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
    if (!uri.is_absolute() || uri.host.is_none()) {
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
    if (uri.user_info.is_some()) {
        return _http_invalid_url(url, "user information is not supported");
    }
    parsed._host = uri.host.value();
    if (parsed._host.size() == 0) {
        return _http_invalid_url(url, "no host");
    }
    if (uri.port.is_some()) {
        if (uri.port.value() == 0) {
            return _http_invalid_url(url, "invalid port");
        }
        parsed._port = uri.port.value();
    }
    parsed._authority = uri.authority().value();
    parsed._target = uri.path_and_query();
    return io.IoResult<_HttpUrl>.ok(parsed);
}
