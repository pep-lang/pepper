# HTTP/1.1 on the wire, shared by the client and the server: a connection
# that is a TcpStream or a TlsStream, a buffered reader over it, header and
# body parsing (Content-Length, chunked, to the end), and writing a message
# head.

import io;
import text;
import tls;
import "message";

# The most bytes a request or status line, or all the header fields of one
# message, may take.
export const _HTTP_MAX_LINE: ulong = 8192;
export const _HTTP_MAX_HEAD: ulong = 65536;

# EPROTO (ERROR_INVALID_DATA on Windows): the code of every HTTP error.
[Target(OS(Linux))]
export _http_code_protocol(): io.ErrorCode { return 71; }

[Target(OS(Mac))]
export _http_code_protocol(): io.ErrorCode { return 100; }

[Target(OS(Windows))]
export _http_code_protocol(): io.ErrorCode { return 13; }

export _http_error(message: String): io.IoError {
    return io.IoError(_http_code_protocol(), message);
}

# EMSGSIZE (WSAEMSGSIZE on Windows): a message too large to accept, which a
# server answers with 431 (the head) or 413 (the body) rather than 400.
[Target(OS(Linux))]
export _http_code_too_large(): io.ErrorCode { return 90; }

[Target(OS(Mac))]
export _http_code_too_large(): io.ErrorCode { return 40; }

[Target(OS(Windows))]
export _http_code_too_large(): io.ErrorCode { return 10040; }

export _http_too_large(message: String): io.IoError {
    return io.IoError(_http_code_too_large(), message);
}

# One connection: plain TCP, or TLS over it.
export struct _HttpConnection {
    var _tcp: io.TcpStream;
    var _tls: tls.TlsStream?;

    construct(tcp: io.TcpStream) {
        this._tcp = tcp;
        this._tls = Optional<tls.TlsStream>.none();
    }

    _read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        if (this._tls.is_some()) {
            return this._tls.value().read(buffer, max);
        }
        return this._tcp.read(buffer, max);
    }

    _write_all(data: u8[]): io.IoResult<void> {
        if (this._tls.is_some()) {
            return this._tls.value().write_all(data);
        }
        return this._tcp.write_all(data);
    }

    # Ends the connection: close_notify over TLS, then the socket.
    _close() {
        if (this._tls.is_some()) {
            this._tls.value().shutdown();
            this._tls.value().close();
        }
        this._tcp.close();
    }
}

# Reads lines and byte runs from a connection, keeping what arrived beyond
# them for the next read.
export struct _HttpReader {
    var _connection: _HttpConnection;
    # Bytes read but not consumed start at `_start`.
    var _buffer: u8[];
    var _start: ulong;

    construct(connection: _HttpConnection) {
        this._connection = connection;
        this._buffer = Array<u8>();
        this._start = 0;
    }

    _available(): ulong {
        return this._buffer.count() - this._start;
    }

    # Reads more bytes; 0 at the end of the stream.
    _fill(): io.IoResult<ulong> {
        if (this._start > 0 && this._start == this._buffer.count()) {
            this._buffer.clear();
            this._start = 0;
        }
        return this._connection._read(this._buffer, 16384);
    }

    # The next line without its CRLF (or LF). None when the stream ends
    # before any byte of it; an error when it ends mid-line or the line is
    # longer than `limit`.
    _line(limit: ulong): io.IoResult<String?> {
        ulong scanned = 0;
        while (true) {
            var p = this._buffer._data;
            while (scanned < this._available()) {
                if (p[this._start + scanned] == '\n') {
                    var end = scanned;
                    if (end > 0) {
                        if (p[this._start + end - 1] == '\r') {
                            end = end - 1;
                        }
                    }
                    var line = _http_line_text(p + this._start, end);
                    this._start = this._start + scanned + 1;
                    return io.IoResult<String?>.ok(Optional<String>.some(line));
                }
                scanned = scanned + 1;
            }
            if (scanned > limit) {
                return io.IoResult<String?>.err(_http_error("line too long"));
            }
            var got = this._fill();
            if (got.is_err()) {
                return io.IoResult<String?>.err(got.error());
            }
            if (got.value() == 0) {
                if (this._available() == 0) {
                    return io.IoResult<String?>.ok(Optional<String>.none());
                }
                return io.IoResult<String?>.err(_http_error("the connection closed in the middle of a line"));
            }
        }
        return io.IoResult<String?>.ok(Optional<String>.none());
    }

    # A line that must be there.
    _required_line(limit: ulong): io.IoResult<String> {
        var line = this._line(limit);
        if (line.is_err()) {
            return io.IoResult<String>.err(line.error());
        }
        if (line.value().is_none()) {
            return io.IoResult<String>.err(_http_error("the connection closed early"));
        }
        return io.IoResult<String>.ok(line.value().value());
    }

    # Appends exactly `count` bytes to `into`.
    _bytes(into: u8[], count: ulong): io.IoResult<void> {
        ulong left = count;
        while (left > 0) {
            if (this._available() == 0) {
                var got = this._fill();
                if (got.is_err()) {
                    return io.IoResult<void>.err(got.error());
                }
                if (got.value() == 0) {
                    return io.IoResult<void>.err(_http_error("the connection closed before the whole body arrived"));
                }
            }
            var take = this._available();
            if (take > left) {
                take = left;
            }
            into._append_raw(this._buffer._data + this._start, take);
            this._start = this._start + take;
            left = left - take;
        }
        return io.IoResult<void>.ok();
    }

    # Appends everything until the stream ends, up to `limit` bytes.
    _to_end(into: u8[], limit: ulong): io.IoResult<void> {
        while (true) {
            var take = this._available();
            if (take > 0) {
                if (into.count() + take > limit) {
                    return io.IoResult<void>.err(_http_too_large("the body is too large"));
                }
                into._append_raw(this._buffer._data + this._start, take);
                this._start = this._start + take;
            }
            var got = this._fill();
            if (got.is_err()) {
                return io.IoResult<void>.err(got.error());
            }
            if (got.value() == 0) {
                return io.IoResult<void>.ok();
            }
        }
        return io.IoResult<void>.ok();
    }
}

# Reads header fields up to the empty line into `headers`.
export _http_read_headers(reader: _HttpReader, headers: Headers): io.IoResult<void> {
    ulong total = 0;
    while (true) {
        var read = reader._required_line(_HTTP_MAX_LINE);
        if (read.is_err()) {
            return io.IoResult<void>.err(read.error());
        }
        var line = read.value();
        if (line.size() == 0) {
            return io.IoResult<void>.ok();
        }
        total = total + line.size();
        if (total > _HTTP_MAX_HEAD) {
            return io.IoResult<void>.err(_http_too_large("the header fields are too large"));
        }
        var colon = line.find(":");
        if (colon <= 0) {
            return io.IoResult<void>.err(_http_error($"a header field has no name: '{line}'"));
        }
        var name = line.substr_bytes(0, colon as ulong);
        var value = line.substr_bytes(colon as ulong + 1, line.size() - colon as ulong - 1).trim();
        headers.add(name, value);
    }
    return io.IoResult<void>.ok();
}

# Reads a body framed by `headers` into `into`: chunked, Content-Length, or
# (when `to_end`) everything until the connection closes; nothing otherwise.
export _http_read_body(
    reader: _HttpReader, headers: Headers, into: u8[], to_end: bool, limit: ulong
): io.IoResult<void> {
    var encoding = headers.get("Transfer-Encoding");
    if (encoding.is_some()) {
        if (_http_contains_token(encoding.value(), "chunked")) {
            return _http_read_chunked(reader, into, limit);
        }
    }
    var length = headers.get("Content-Length");
    if (length.is_some()) {
        var n = _http_parse_decimal(length.value());
        if (n < 0) {
            return io.IoResult<void>.err(_http_error($"invalid Content-Length: '{length.value()}'"));
        }
        if (n as ulong > limit) {
            return io.IoResult<void>.err(_http_too_large("the body is too large"));
        }
        return reader._bytes(into, n as ulong);
    }
    if (to_end) {
        return reader._to_end(into, limit);
    }
    return io.IoResult<void>.ok();
}

# A chunked body: hex size lines, data, and a trailer section.
export _http_read_chunked(reader: _HttpReader, into: u8[], limit: ulong): io.IoResult<void> {
    while (true) {
        var read = reader._required_line(_HTTP_MAX_LINE);
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
        if (size == 0) {
            # The trailer fields, which are dropped.
            return _http_read_headers(reader, Headers());
        }
        if (into.count() + size as ulong > limit) {
            return io.IoResult<void>.err(_http_too_large("the body is too large"));
        }
        var data = reader._bytes(into, size as ulong);
        if (data.is_err()) {
            return data;
        }
        var end = reader._required_line(2);
        if (end.is_err()) {
            return io.IoResult<void>.err(end.error());
        }
    }
    return io.IoResult<void>.ok();
}

# Appends a start line, the fields and the empty line to `out`.
export _http_write_head(out: u8[], start: String, headers: Headers) {
    _http_append(out, start);
    _http_append(out, "\r\n");
    for (var name in headers.names()) {
        for (var value in headers.values(name)) {
            _http_append(out, name);
            _http_append(out, ": ");
            _http_append(out, value);
            _http_append(out, "\r\n");
        }
    }
    _http_append(out, "\r\n");
}

# The `size` bytes at `data` as a String. Field values may hold bytes that
# are not UTF-8 (obs-text, such as Latin-1): each of those becomes U+FFFD,
# so the String is valid and `find` still sees the ':' and the rest.
_http_line_text(data: __ptr<u8>, size: ulong): String {
    if (size == 0) {
        return "";
    }
    if (String.length_of(data as __ptr<char>, size) > 0) {
        return String(data as __ptr<char>, size);
    }
    var bytes = Array<u8>(size);
    bytes._append_raw(data, size);
    return text.Utf8.decode_lossy(bytes);
}

export _http_append(out: u8[], text: String) {
    out._append_raw(text.c_str() as __ptr<u8>, text.size());
}

# ── Text ─────────────────────────────────────────────────────────────────────

# A non-negative decimal number, or -1.
export _http_parse_decimal(text: String): long {
    var t = text.trim();
    if (t.size() == 0 || t.size() > 18) {
        return -1;
    }
    var p = t.c_str() as __ptr<u8>;
    long value = 0;
    ulong i = 0;
    while (i < t.size()) {
        var c = p[i];
        if (c < '0' || c > '9') {
            return -1;
        }
        value = value * 10 + (c - '0') as long;
        i = i + 1;
    }
    return value;
}

# A non-negative hexadecimal number, or -1.
export _http_parse_hex(text: String): long {
    if (text.size() == 0 || text.size() > 15) {
        return -1;
    }
    var p = text.c_str() as __ptr<u8>;
    long value = 0;
    ulong i = 0;
    while (i < text.size()) {
        var digit = _pep_hex_digit(p[i]);
        if (digit < 0) {
            return -1;
        }
        value = value * 16 + digit as long;
        i = i + 1;
    }
    return value;
}

# Whether the comma-separated `list` has `token`, ignoring case.
export _http_contains_token(list: String, token: String): bool {
    var wanted = token.lower();
    var rest = list;
    while (true) {
        var comma = rest.find(",");
        var item = rest;
        if (comma >= 0) {
            item = rest.substr_bytes(0, comma as ulong);
        }
        if (item.trim().lower() == wanted) {
            return true;
        }
        if (comma < 0) {
            return false;
        }
        rest = rest.substr_bytes(comma as ulong + 1, rest.size() - comma as ulong - 1);
    }
    return false;
}
