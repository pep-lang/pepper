# HTTP/1.1 on the wire, shared by the client and the server: a connection
# that reads and writes a TcpStream or a TlsStream, a buffered reader over it, header and
# body parsing (Content-Length, chunked), and writing a message
# head.

import io;
import text;
import tls;
import "message";

# The most bytes a request or status line, or all the header fields of one
# message, may take.
const _HTTP_MAX_LINE: ulong = 8192;
const _HTTP_MAX_HEAD: ulong = 65536;

# EPROTO (ERROR_INVALID_DATA on Windows): the code of every HTTP error.
[Target(OS(Linux))]
_http_code_protocol(): io.ErrorCode { return 71; }

[Target(OS(Mac))]
_http_code_protocol(): io.ErrorCode { return 100; }

[Target(OS(Windows))]
_http_code_protocol(): io.ErrorCode { return 13; }

[Target(OS(Wasi))]
_http_code_protocol(): io.ErrorCode { return 65; }

_http_error(message: String): io.IoError {
    return io.IoError(_http_code_protocol(), message);
}

# EMSGSIZE (WSAEMSGSIZE on Windows): a message too large to accept, which a
# server answers with 431 (the head) or 413 (the body) rather than 400.
[Target(OS(Linux))]
_http_code_too_large(): io.ErrorCode { return 90; }

[Target(OS(Mac))]
_http_code_too_large(): io.ErrorCode { return 40; }

[Target(OS(Windows))]
_http_code_too_large(): io.ErrorCode { return 10040; }

[Target(OS(Wasi))]
_http_code_too_large(): io.ErrorCode { return 35; }

_http_too_large(message: String): io.IoError {
    return io.IoError(_http_code_too_large(), message);
}

# One connection: plain TCP, or TLS over it. Reads and writes go through
# `_reader` and `_writer`, which are the TLS stream once `_use_tls` is called
# and the TCP stream before.
struct _HttpConnection {
    var _tcp: io.TcpStream;
    var _tls: tls.TlsStream?;
    var _reader: io.Reader;
    var _writer: io.Writer;
    var _closed: bool;

    construct(tcp: io.TcpStream) {
        this._closed = false;
        this._tcp = tcp;
        this._tls = Optional<tls.TlsStream>.Empty;
        this._reader = tcp;
        this._writer = tcp;
    }

    # Reads and writes through `stream`, a TLS session over `_tcp`.
    _use_tls(stream: tls.TlsStream) {
        this._tls = Optional<tls.TlsStream>.Value(stream);
        this._reader = stream;
        this._writer = stream;
    }

    _read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        return this._reader.read(buffer, max);
    }

    _write_all(data: u8[]): io.IoResult<void> {
        return this._writer.write_all(data);
    }

    # Ends the connection: close_notify over TLS, then the socket. Again,
    # it does nothing.
    _close() {
        if (this._closed) {
            return;
        }
        this._closed = true;
        if (this._tls.is_value()) {
            this._tls.value().shutdown();
            this._tls.value().close();
        }
        this._tcp.close();
    }
}

# Reads lines and byte runs from a connection, keeping what arrived beyond
# them for the next read.
struct _HttpReader {
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
        return this._buffer.count - this._start;
    }

    # Reads more bytes; 0 at the end of the stream.
    _fill(): io.IoResult<ulong> {
        if (this._start > 0 && this._start == this._buffer.count) {
            this._buffer.clear();
            this._start = 0;
        }
        return this._connection._read(this._buffer, 16384);
    }

    # The next line without its CRLF (or LF). Empty when the stream ends
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
                    return io.IoResult<String?>.ok(Optional<String>.Value(line));
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
                    return io.IoResult<String?>.ok(Optional<String>.Empty);
                }
                return io.IoResult<String?>.err(_http_error("the connection closed in the middle of a line"));
            }
        }
        return io.IoResult<String?>.ok(Optional<String>.Empty);
    }

    # A line that must be there.
    _required_line(limit: ulong): io.IoResult<String> {
        var line = this._line(limit);
        if (line.is_err()) {
            return io.IoResult<String>.err(line.error());
        }
        if (line.value().is_empty()) {
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

    # Appends up to `max` bytes to `into`: what is buffered, or else what
    # one read of the connection gives. 0 at the end of the stream.
    _some(into: u8[], max: ulong): io.IoResult<ulong> {
        var take = this._available();
        if (take == 0) {
            if (this._start > 0) {
                this._buffer.clear();
                this._start = 0;
            }
            return this._connection._read(into, max);
        }
        if (take > max) {
            take = max;
        }
        into._append_raw(this._buffer._data + this._start, take);
        this._start = this._start + take;
        return io.IoResult<ulong>.ok(take);
    }
}

# Reads header fields up to the empty line into `headers`.
_http_read_headers(reader: _HttpReader, headers: Headers): io.IoResult<void> {
    ulong total = 0;
    while (true) {
        var read = reader._required_line(_HTTP_MAX_LINE);
        if (read.is_err()) {
            return io.IoResult<void>.err(read.error());
        }
        var line = read.value();
        if (line.size == 0) {
            return io.IoResult<void>.ok();
        }
        total = total + line.size;
        if (total > _HTTP_MAX_HEAD) {
            return io.IoResult<void>.err(_http_too_large("the header fields are too large"));
        }
        var colon = line.find(":");
        if (colon <= 0) {
            return io.IoResult<void>.err(_http_error($"a header field has no name: '{line}'"));
        }
        var name = line.substr_bytes(0, colon as ulong);
        var value = line.substr_bytes(colon as ulong + 1, line.size - colon as ulong - 1).trim();
        headers.add(name, value);
    }
    return io.IoResult<void>.ok();
}

# Reads a request body framed by `headers` into `into`: chunked or
# Content-Length; nothing otherwise.
_http_read_body(reader: _HttpReader, headers: Headers, into: u8[], limit: ulong): io.IoResult<void> {
    var encoding = headers.get("Transfer-Encoding");
    if (encoding.is_value()) {
        if (_http_contains_token(encoding.value(), "chunked")) {
            return _http_read_chunked(reader, into, limit);
        }
    }
    var length = headers.get("Content-Length");
    if (length.is_value()) {
        var n = _http_parse_decimal(length.value());
        if (n < 0) {
            return io.IoResult<void>.err(_http_error($"invalid Content-Length: '{length.value()}'"));
        }
        if (n as ulong > limit) {
            return io.IoResult<void>.err(_http_too_large("the body is too large"));
        }
        return reader._bytes(into, n as ulong);
    }
    return io.IoResult<void>.ok();
}

# A chunked body: hex size lines, data, and a trailer section.
_http_read_chunked(reader: _HttpReader, into: u8[], limit: ulong): io.IoResult<void> {
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
        if (into.count + size as ulong > limit) {
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

# Writes the body `source` gives to `connection`: exactly `length` bytes, or
# when `length` is -1 everything to its end, as chunks when `chunked` and
# unframed otherwise.
_http_write_stream(connection: _HttpConnection, source: io.Reader, length: long, chunked: bool): io.IoResult<void> {
    ulong left = 0;
    if (length >= 0) {
        left = length as ulong;
    }
    var data = Array<u8>(65536);
    while (length < 0 || left > 0) {
        data.clear();
        var want: ulong = 65536;
        if (length >= 0 && left < want) {
            want = left;
        }
        var read = source.read(data, want);
        if (read.is_err()) {
            return io.IoResult<void>.err(read.error());
        }
        var got = read.value();
        if (got == 0) {
            if (length >= 0) {
                return io.IoResult<void>.err(_http_error("the body ended before its Content-Length"));
            }
            break;
        }
        if (length >= 0) {
            left = left - got;
        }
        if (length < 0 && chunked) {
            var framed = Array<u8>(got + 16);
            _http_append(framed, $"{got:x}\r\n");
            framed.append_all(data);
            _http_append(framed, "\r\n");
            var sent = connection._write_all(framed);
            if (sent.is_err()) {
                return sent;
            }
        } else {
            var sent = connection._write_all(data);
            if (sent.is_err()) {
                return sent;
            }
        }
    }
    if (length < 0 && chunked) {
        var end = Array<u8>();
        _http_append(end, "0\r\n\r\n");
        return connection._write_all(end);
    }
    return io.IoResult<void>.ok();
}

# Why `headers` cannot be sent, or none: a field name that is not a token,
# or a value with CR, LF or NUL, would let it add fields or end the head
# (RFC 9110 §5.1, §5.5).
# It reads the fields in place: `names()` and `values()` would copy them.
_http_bad_fields(headers: Headers): String? {
    for (var (name, values) in headers._fields) {
        if (!_http_is_token(name)) {
            # Not quoted: a server's 500 shows this text, and the name may
            # come from the request.
            return Optional<String>.Value("a field name is not a token");
        }
        for (var value in values) {
            if (!_http_is_field_value(value)) {
                return Optional<String>.Value($"the value of the field '{name}' holds CR, LF or NUL");
            }
        }
    }
    return Optional<String>.Empty;
}

# Whether `text` is an RFC 9110 token: one or more letters, digits and
# "!#$%&'*+-.^_`|~".
_http_is_token(text: String): bool {
    if (text.size == 0) {
        return false;
    }
    ulong i = 0;
    while (i < text.size) {
        var c = text.byte_at(i);
        var alphanumeric = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
        if (!alphanumeric && (c >= 128 || !"!#$%&'*+-.^_`|~".contains(text.substr_bytes(i, 1)))) {
            return false;
        }
        i = i + 1;
    }
    return true;
}

# Whether `text` can be sent as a field value or reason phrase: it has no
# CR, LF or NUL.
_http_is_field_value(text: String): bool {
    ulong i = 0;
    while (i < text.size) {
        var c = text.byte_at(i);
        if (c == 0 || c == '\r' || c == '\n') {
            return false;
        }
        i = i + 1;
    }
    return true;
}

# Appends a start line, the fields and the empty line to `out`.
_http_write_head(out: u8[], start: String, headers: Headers) {
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
    if (String.length_of(unsafe_cast<__ptr<char>>(data), size) > 0) {
        return String(unsafe_cast<__ptr<char>>(data), size);
    }
    var bytes = Array<u8>(size);
    bytes._append_raw(data, size);
    return text.Utf8.decode_lossy(bytes);
}

_http_append(out: u8[], text: String) {
    out._append_raw(unsafe_cast<__ptr<u8>>(text.c_str()), text.size);
}

# ── Text ─────────────────────────────────────────────────────────────────────

# A non-negative decimal number, or -1.
_http_parse_decimal(text: String): long {
    var t = text.trim();
    if (t.size == 0 || t.size > 18) {
        return -1;
    }
    var p = unsafe_cast<__ptr<u8>>(t.c_str());
    long value = 0;
    ulong i = 0;
    while (i < t.size) {
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
_http_parse_hex(text: String): long {
    if (text.size == 0 || text.size > 15) {
        return -1;
    }
    var p = unsafe_cast<__ptr<u8>>(text.c_str());
    long value = 0;
    ulong i = 0;
    while (i < text.size) {
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
_http_contains_token(list: String, token: String): bool {
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
        rest = rest.substr_bytes(comma as ulong + 1, rest.size - comma as ulong - 1);
    }
    return false;
}
