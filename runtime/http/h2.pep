# HTTP/2 (RFC 9113) on the wire, shared by the client and the server: the
# frames, an `_H2Connection` that multiplexes streams over one
# `_HttpConnection` with flow control in both directions, a client exchange
# that sends one request as a stream, and a server loop that answers each
# stream in a task of its own.
#
# A connection's tasks all run on one worker (the server's `spawn_local`
# tasks, or the tasks of one thread sharing a client connection), so its
# state needs no locks. Two batons stand in for them: whoever finds
# `_reading` false reads and handles one frame, and whoever finds `_writing`
# false writes one run of frames. A task that finds one taken waits on a
# channel of its own until the holder hands the baton back, then looks at
# the state again. So every task that needs something from the peer (a
# response, body bytes, more window) may end up reading for all of them, and
# no task is needed just to read, which lets a client use HTTP/2 outside
# `async.run`.

import async;
import io;
import "client";
import "hpack";
import "message";
import "server";
import "wire";

# The client's connection preface, before its SETTINGS frame.
const _H2_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

# Frame types.
const _H2_DATA: u8 = 0;
const _H2_HEADERS: u8 = 1;
const _H2_PRIORITY: u8 = 2;
const _H2_RST_STREAM: u8 = 3;
const _H2_SETTINGS: u8 = 4;
const _H2_PUSH_PROMISE: u8 = 5;
const _H2_PING: u8 = 6;
const _H2_GOAWAY: u8 = 7;
const _H2_WINDOW_UPDATE: u8 = 8;
const _H2_CONTINUATION: u8 = 9;

# Frame flags.
const _H2_END_STREAM: u8 = 1;
const _H2_ACK: u8 = 1;
const _H2_END_HEADERS: u8 = 4;
const _H2_PADDED: u8 = 8;
const _H2_PRIORITY_FLAG: u8 = 32;

# Error codes.
const _H2_NO_ERROR: uint = 0;
const _H2_PROTOCOL_ERROR: uint = 1;
const _H2_INTERNAL_ERROR: uint = 2;
const _H2_FLOW_CONTROL_ERROR: uint = 3;
const _H2_STREAM_CLOSED: uint = 5;
const _H2_FRAME_SIZE_ERROR: uint = 6;
const _H2_REFUSED_STREAM: uint = 7;
const _H2_CANCEL: uint = 8;
const _H2_COMPRESSION_ERROR: uint = 9;
const _H2_ENHANCE_YOUR_CALM: uint = 11;

# Settings.
const _H2_SETTINGS_HEADER_TABLE_SIZE: uint = 1;
const _H2_SETTINGS_ENABLE_PUSH: uint = 2;
const _H2_SETTINGS_MAX_CONCURRENT_STREAMS: uint = 3;
const _H2_SETTINGS_INITIAL_WINDOW_SIZE: uint = 4;
const _H2_SETTINGS_MAX_FRAME_SIZE: uint = 5;
const _H2_SETTINGS_MAX_HEADER_LIST_SIZE: uint = 6;

# The window every stream and the connection start with, and the most a
# window may hold.
const _H2_DEFAULT_WINDOW: long = 65535;
const _H2_MAX_WINDOW: long = 2147483647;
# The window this side gives each stream and the connection.
const _H2_RECEIVE_WINDOW: long = 1048576;
# The largest frame payload either side sends by default; this side never
# asks for more.
const _H2_DEFAULT_FRAME: ulong = 16384;
# The most streams a server lets a client open at once.
const _H2_MAX_STREAMS: ulong = 100;
# The most bytes one header block may take before it is decoded.
const _H2_MAX_HEADER_BLOCK: ulong = 262144;

# The name of an error code, for messages.
_h2_error_name(code: uint): String {
    return match (code) {
        0 => "NO_ERROR",
        1 => "PROTOCOL_ERROR",
        2 => "INTERNAL_ERROR",
        3 => "FLOW_CONTROL_ERROR",
        4 => "SETTINGS_TIMEOUT",
        5 => "STREAM_CLOSED",
        6 => "FRAME_SIZE_ERROR",
        7 => "REFUSED_STREAM",
        8 => "CANCEL",
        9 => "COMPRESSION_ERROR",
        10 => "CONNECT_ERROR",
        11 => "ENHANCE_YOUR_CALM",
        12 => "INADEQUATE_SECURITY",
        13 => "HTTP_1_1_REQUIRED",
        else => $"error {code}",
    };
}

# The big-endian number in `size` bytes of `data` from `at`.
_h2_number(data: u8[], at: ulong, size: ulong): uint {
    uint value = 0;
    ulong index = 0;
    while (index < size) {
        value = (value << 8) | (data[at + index] as uint);
        index += 1;
    }
    return value;
}

# Appends `value` to `out` big-endian, in `size` bytes.
_h2_append_number(out: u8[], value: uint, size: ulong) {
    var shift = size * 8;
    while (shift > 0) {
        shift -= 8;
        out.append(((value >> (shift as uint)) & 0xff) as u8);
    }
}

# Appends a frame header to `out`.
_h2_append_head(out: u8[], length: ulong, kind: u8, flags: u8, stream: uint) {
    _h2_append_number(out, length as uint, 3);
    out.append(kind);
    out.append(flags);
    _h2_append_number(out, stream, 4);
}

# Appends a whole frame to `out`.
_h2_append_frame(out: u8[], kind: u8, flags: u8, stream: uint, payload: u8[]) {
    _h2_append_head(out, payload.count, kind, flags, stream);
    out.append_all(payload);
}

# One frame as read.
struct _H2Frame {
    var kind: u8;
    var flags: u8;
    var stream: uint;
    var payload: u8[];

    construct() {
        payload = Array<u8>();
    }

    has(flag: u8): bool {
        return (flags & flag) != 0;
    }
}

# A connection error: what goes in the GOAWAY, and the error the
# connection's streams then fail with.
struct _H2Failure {
    var code: uint;
    var message: String;

    construct(code: uint, message: String) {
        this.code = code;
        this.message = message;
    }
}

# One stream: what has arrived on it and what may still be sent.
struct _H2Stream {
    var id: uint;
    # The header fields of the request (server) or the final response
    # (client), once they have arrived.
    var fields: _HpackField[]?;
    # Body bytes received and not yet read, from `_start`.
    var data: u8[];
    var _start: ulong;
    # Whether each side has ended the stream (END_STREAM), and the error
    # that ended it early (a reset, or the connection failing).
    var remote_ended: bool;
    var local_ended: bool;
    var error: io.IoError?;
    # The bytes this side may still send, and those the peer may.
    var send_window: long;
    var receive_window: long;
    # Bytes read from `data` since the last WINDOW_UPDATE for the stream.
    var _unacknowledged: ulong;

    construct(id: uint, send_window: long) {
        this.id = id;
        fields = Optional<_HpackField[]>.Empty;
        data = Array<u8>();
        _start = 0;
        remote_ended = false;
        local_ended = false;
        error = Optional<io.IoError>.Empty;
        this.send_window = send_window;
        receive_window = _H2_RECEIVE_WINDOW;
        _unacknowledged = 0;
    }

    # The number of received bytes not yet read.
    var available: ulong {
        get {
            return data.count - _start;
        }
    }
}

# One HTTP/2 connection, a client's or a server's.
struct _H2Connection {
    var _reader: _HttpReader;
    var _server: bool;
    var _encoder: _HpackEncoder;
    var _decoder: _HpackDecoder;
    var _streams: HashMap<uint, _H2Stream>;
    # The next stream a client opens, and the last one the peer opened.
    var _next_id: uint;
    var _last_peer_id: uint;
    # Server: streams whose request head has arrived, not yet answered.
    var _accepted: _H2Stream[];
    # The connection's windows, and bytes read since its last WINDOW_UPDATE.
    var _send_window: long;
    var _receive_window: long;
    var _unacknowledged: ulong;
    # The peer's settings.
    var _peer_initial_window: long;
    var _peer_max_frame: ulong;
    var _peer_max_streams: ulong;
    var _got_settings: bool;
    # The batons, and the tasks waiting for the state to change.
    var _reading: bool;
    var _writing: bool;
    var _waiters: async.Channel<bool>[];
    # Why the connection can carry no more streams: an error, or a GOAWAY
    # (`_goaway_last` is the last stream the peer will still answer).
    var _failure: io.IoError?;
    var _going_away: bool;
    var _goaway_last: uint;

    construct(reader: _HttpReader, server: bool) {
        _reader = reader;
        _server = server;
        _encoder = _HpackEncoder();
        _decoder = _HpackDecoder();
        _streams = HashMap<uint, _H2Stream>();
        _next_id = 1;
        _last_peer_id = 0;
        _accepted = Array<_H2Stream>();
        _send_window = _H2_DEFAULT_WINDOW;
        _receive_window = _H2_RECEIVE_WINDOW;
        _unacknowledged = 0;
        _peer_initial_window = _H2_DEFAULT_WINDOW;
        _peer_max_frame = _H2_DEFAULT_FRAME;
        _peer_max_streams = 4294967295;
        _got_settings = false;
        _reading = false;
        _writing = false;
        _waiters = Array<async.Channel<bool>>();
        _failure = Optional<io.IoError>.Empty;
        _going_away = false;
        _goaway_last = 0;
    }

    # Starts a client connection over `connection`: sends the preface and
    # this side's settings.
    static client(connection: _HttpConnection): io.IoResult<_H2Connection> {
        var h2 = _H2Connection(_HttpReader(connection), false);
        var out = Array<u8>();
        _http_append(out, _H2_PREFACE);
        h2._append_settings(out);
        var sent = connection._write_all(out);
        if (sent.is_err()) {
            return io.IoResult<_H2Connection>.err(sent.error());
        }
        return io.IoResult<_H2Connection>.ok(h2);
    }

    # This side's SETTINGS, and the WINDOW_UPDATE that opens the
    # connection's window as wide as each stream's.
    _append_settings(out: u8[]) {
        var settings = Array<u8>();
        if (_server) {
            _h2_append_number(settings, _H2_SETTINGS_MAX_CONCURRENT_STREAMS, 2);
            _h2_append_number(settings, _H2_MAX_STREAMS as uint, 4);
        } else {
            _h2_append_number(settings, _H2_SETTINGS_ENABLE_PUSH, 2);
            _h2_append_number(settings, 0, 4);
        }
        _h2_append_number(settings, _H2_SETTINGS_INITIAL_WINDOW_SIZE, 2);
        _h2_append_number(settings, _H2_RECEIVE_WINDOW as uint, 4);
        _h2_append_number(settings, _H2_SETTINGS_MAX_HEADER_LIST_SIZE, 2);
        _h2_append_number(settings, _HTTP_MAX_HEAD as uint, 4);
        _h2_append_frame(out, _H2_SETTINGS, 0, 0, settings);
        var increment = Array<u8>();
        _h2_append_number(increment, (_H2_RECEIVE_WINDOW - _H2_DEFAULT_WINDOW) as uint, 4);
        _h2_append_frame(out, _H2_WINDOW_UPDATE, 0, 0, increment);
    }

    # ── Batons ──────────────────────────────────────────────────────────────

    # Waits until a task holding a baton hands it back.
    _wait() {
        var signal = async.Channel<bool>(1);
        _waiters.append(signal);
        signal.receive();
    }

    # Wakes every waiting task to look at the state again.
    _wake() {
        if (_waiters.count == 0) {
            return;
        }
        var waiting = _waiters;
        _waiters = Array<async.Channel<bool>>();
        for (var signal in waiting) {
            signal.send(true);
        }
    }

    _take_writing() {
        while (_writing) {
            _wait();
        }
        _writing = true;
    }

    _give_writing() {
        _writing = false;
        _wake();
    }

    # Writes `out` whole, taking the writing baton for it.
    _write(out: u8[]): io.IoResult<void> {
        _take_writing();
        var sent = _reader._connection._write_all(out);
        _give_writing();
        return sent;
    }

    # Moves the connection along: reads and handles one frame, or, when
    # another task is reading, waits until it has. An error means the
    # connection has failed, and every stream with it.
    _progress(): io.IoResult<void> {
        if (_failure.is_value()) {
            return io.IoResult<void>.err(_failure.value());
        }
        if (_reading) {
            _wait();
            return io.IoResult<void>.ok();
        }
        _reading = true;
        var handled = this._read_and_handle();
        _reading = false;
        if (handled.is_err()) {
            this._fail_all(handled.error());
        }
        _wake();
        if (handled.is_err()) {
            return io.IoResult<void>.err(handled.error());
        }
        return io.IoResult<void>.ok();
    }

    # Fails the connection: every stream ends with `error`.
    _fail_all(error: io.IoError) {
        if (_failure.is_empty()) {
            _failure = Optional<io.IoError>.Value(error);
        }
        for (var (id, stream) in _streams) {
            if (stream.error.is_empty() && !(stream.remote_ended && stream.local_ended)) {
                stream.error = Optional<io.IoError>.Value(error);
            }
        }
    }

    # Sends GOAWAY for `failure` and fails the connection with it.
    _fail_connection(failure: _H2Failure): io.IoError {
        var payload = Array<u8>();
        _h2_append_number(payload, _last_peer_id, 4);
        _h2_append_number(payload, failure.code, 4);
        _http_append(payload, failure.message);
        var out = Array<u8>();
        _h2_append_frame(out, _H2_GOAWAY, 0, 0, payload);
        _reader._connection._write_all(out);
        var error = _http_error($"HTTP/2 connection error ({_h2_error_name(failure.code)}): {failure.message}");
        _going_away = true;
        this._fail_all(error);
        return error;
    }

    # Whether new streams may still be opened.
    var is_usable: bool {
        get {
            return _failure.is_empty() && !_going_away && _next_id < 2147483647;
        }
    }

    # The number of streams not yet ended on both sides.
    var active_count: ulong {
        get {
            return _streams.count as ulong;
        }
    }

    # Ends the connection: GOAWAY, then the socket.
    close() {
        if (_failure.is_empty()) {
            var payload = Array<u8>();
            _h2_append_number(payload, _last_peer_id, 4);
            _h2_append_number(payload, _H2_NO_ERROR, 4);
            var out = Array<u8>();
            _h2_append_frame(out, _H2_GOAWAY, 0, 0, payload);
            this._write(out);
            this._fail_all(_http_error("the HTTP/2 connection is closed"));
        }
        _reader._connection._close();
    }

    # ── Reading ─────────────────────────────────────────────────────────────

    # Reads the next frame. An error when the connection ends, cleanly or
    # not, or the frame is larger than this side allows.
    _read_frame(): io.IoResult<_H2Frame> {
        if (_reader._available() == 0) {
            var got = _reader._fill();
            if (got.is_err()) {
                return io.IoResult<_H2Frame>.err(got.error());
            }
            if (got.value() == 0) {
                return io.IoResult<_H2Frame>.err(_http_error("the HTTP/2 connection closed"));
            }
        }
        var head = Array<u8>(9);
        var read = _reader._bytes(head, 9);
        if (read.is_err()) {
            return io.IoResult<_H2Frame>.err(read.error());
        }
        var frame = _H2Frame();
        var length = _h2_number(head, 0, 3) as ulong;
        frame.kind = head[3];
        frame.flags = head[4];
        frame.stream = _h2_number(head, 5, 4) & 0x7fffffff;
        if (length > _H2_DEFAULT_FRAME) {
            return io.IoResult<_H2Frame>.err(
                this._fail_connection(_H2Failure(_H2_FRAME_SIZE_ERROR, "a frame is larger than 16384 bytes"))
            );
        }
        var body = _reader._bytes(frame.payload, length);
        if (body.is_err()) {
            return io.IoResult<_H2Frame>.err(body.error());
        }
        return io.IoResult<_H2Frame>.ok(frame);
    }

    # Reads one frame and acts on it.
    _read_and_handle(): io.IoResult<void> {
        var read = this._read_frame();
        if (read.is_err()) {
            return io.IoResult<void>.err(read.error());
        }
        var frame = read.value();
        if (!_got_settings && frame.kind != _H2_SETTINGS) {
            return this._fault(_H2_PROTOCOL_ERROR, "the connection does not start with SETTINGS");
        }
        return match (frame.kind) {
            0 => this._on_data(frame),
            1 => this._on_headers(frame),
            2 => this._on_priority(frame),
            3 => this._on_reset(frame),
            4 => this._on_settings(frame),
            5 => this._fault(_H2_PROTOCOL_ERROR, "PUSH_PROMISE is not enabled"),
            6 => this._on_ping(frame),
            7 => this._on_goaway(frame),
            8 => this._on_window_update(frame),
            9 => this._fault(_H2_PROTOCOL_ERROR, "CONTINUATION without HEADERS"),
            else => io.IoResult<void>.ok(),  # unknown types are ignored
        };
    }

    # A connection error.
    _fault(code: uint, message: String): io.IoResult<void> {
        return io.IoResult<void>.err(this._fail_connection(_H2Failure(code, message)));
    }

    # Whether `id` names a stream that has never been opened.
    _is_idle(id: uint): bool {
        var peer_opens = (id % 2 == 1) == _server;
        if (peer_opens) {
            return id > _last_peer_id;
        }
        return id >= _next_id;
    }

    # The payload of a PADDED frame without its padding, starting `skip`
    # bytes after the pad length; none when the padding does not fit.
    _unpadded(frame: _H2Frame, skip: ulong): u8[]? {
        ulong start = 0;
        ulong pad = 0;
        if (frame.has(_H2_PADDED)) {
            if (frame.payload.count == 0) {
                return Optional<u8[]>.Empty;
            }
            pad = frame.payload[0] as ulong;
            start = 1;
        }
        if (start + skip + pad > frame.payload.count) {
            return Optional<u8[]>.Empty;
        }
        var size = frame.payload.count - start - skip - pad;
        var result = Array<u8>(size);
        result._append_raw(frame.payload._data + start + skip, size);
        return Optional<u8[]>.Value(result);
    }

    _on_data(frame: _H2Frame): io.IoResult<void> {
        if (frame.stream == 0) {
            return this._fault(_H2_PROTOCOL_ERROR, "DATA on stream 0");
        }
        if (this._is_idle(frame.stream)) {
            return this._fault(_H2_PROTOCOL_ERROR, $"DATA on stream {frame.stream}, which is not open");
        }
        # The whole frame, padding included, counts against the windows.
        var size = frame.payload.count;
        _receive_window -= size as long;
        if (_receive_window < 0) {
            return this._fault(_H2_FLOW_CONTROL_ERROR, "DATA beyond the connection's window");
        }
        var stream = _streams.get(frame.stream);
        var body = this._unpadded(frame, 0);
        if (body.is_empty()) {
            return this._fault(_H2_PROTOCOL_ERROR, "DATA with more padding than payload");
        }
        if (stream === __null || stream.remote_ended || stream.error.is_value()) {
            # A stream already closed or reset: its bytes still opened the
            # window, so give them back.
            return this._consumed(Optional<_H2Stream>.Empty, size);
        }
        stream.receive_window -= size as long;
        if (stream.receive_window < 0) {
            return this._reset(stream, _H2_FLOW_CONTROL_ERROR, "DATA beyond the stream's window");
        }
        stream.data.append_all(body.value());
        if (frame.has(_H2_END_STREAM)) {
            stream.remote_ended = true;
        }
        # Padding is never read, so its window goes back now. A server
        # buffers the whole request body (up to MAX_REQUEST_BODY), so it
        # gives the window back as the bytes arrive.
        var credit = size - body.value().count;
        if (_server) {
            credit = size;
        }
        if (credit == 0) {
            return io.IoResult<void>.ok();
        }
        return this._consumed(Optional<_H2Stream>.Value(stream), credit);
    }

    # Notes that `size` bytes received on `stream` (or on a stream gone)
    # were read, and sends WINDOW_UPDATEs once half a window has been.
    _consumed(stream: _H2Stream?, size: ulong): io.IoResult<void> {
        var out = Array<u8>();
        _unacknowledged += size;
        if (_unacknowledged as long >= _H2_RECEIVE_WINDOW / 2) {
            var increment = Array<u8>();
            _h2_append_number(increment, _unacknowledged as uint, 4);
            _h2_append_frame(out, _H2_WINDOW_UPDATE, 0, 0, increment);
            _receive_window += _unacknowledged as long;
            _unacknowledged = 0;
        }
        if (stream.is_value()) {
            var s = stream.value();
            s._unacknowledged += size;
            if (!s.remote_ended && s._unacknowledged as long >= _H2_RECEIVE_WINDOW / 2) {
                var increment = Array<u8>();
                _h2_append_number(increment, s._unacknowledged as uint, 4);
                _h2_append_frame(out, _H2_WINDOW_UPDATE, 0, s.id, increment);
                s.receive_window += s._unacknowledged as long;
                s._unacknowledged = 0;
            }
        }
        if (out.count == 0) {
            return io.IoResult<void>.ok();
        }
        return this._write(out);
    }

    _on_headers(frame: _H2Frame): io.IoResult<void> {
        if (frame.stream == 0) {
            return this._fault(_H2_PROTOCOL_ERROR, "HEADERS on stream 0");
        }
        ulong skip = 0;
        if (frame.has(_H2_PRIORITY_FLAG)) {
            skip = 5;
        }
        var fragment = this._unpadded(frame, skip);
        if (fragment.is_empty()) {
            return this._fault(_H2_PROTOCOL_ERROR, "HEADERS with more padding than payload");
        }
        var block = fragment.value();
        var ended = frame.has(_H2_END_HEADERS);
        while (!ended) {
            var next = this._read_frame();
            if (next.is_err()) {
                return io.IoResult<void>.err(next.error());
            }
            var more = next.value();
            if (more.kind != _H2_CONTINUATION || more.stream != frame.stream) {
                return this._fault(_H2_PROTOCOL_ERROR, "a header block is interrupted by another frame");
            }
            if (block.count + more.payload.count > _H2_MAX_HEADER_BLOCK) {
                return this._fault(_H2_ENHANCE_YOUR_CALM, "a header block is too large");
            }
            block.append_all(more.payload);
            ended = more.has(_H2_END_HEADERS);
        }
        # The block is decoded whatever happens to the stream, to keep the
        # tables in step.
        var decoded = _decoder.decode(block);
        if (decoded.is_err()) {
            return this._fault(_H2_COMPRESSION_ERROR, decoded.error().message);
        }
        var fields = decoded.value();
        var end_stream = frame.has(_H2_END_STREAM);
        if (_server) {
            return this._on_request_head(frame.stream, fields, end_stream);
        }
        return this._on_response_head(frame.stream, fields, end_stream);
    }

    # Server: a client opens a stream, or sends trailers on one.
    _on_request_head(id: uint, fields: _HpackField[], end_stream: bool): io.IoResult<void> {
        var stream = _streams.get(id);
        if (stream !== __null) {
            # Trailers, which are dropped; they must end the stream.
            if (!end_stream || stream.remote_ended) {
                return this._reset(stream, _H2_PROTOCOL_ERROR, "HEADERS in the middle of a stream");
            }
            stream.remote_ended = true;
            return io.IoResult<void>.ok();
        }
        if (id % 2 == 0 || id <= _last_peer_id) {
            if (id % 2 == 1) {
                return io.IoResult<void>.ok();  # a stream already answered and forgotten
            }
            return this._fault(_H2_PROTOCOL_ERROR, $"a client opened stream {id}, which is not a new odd number");
        }
        _last_peer_id = id;
        var opened = _H2Stream(id, _peer_initial_window);
        if (_going_away || _streams.count as ulong >= _H2_MAX_STREAMS) {
            _streams[id] = opened;
            return this._reset(opened, _H2_REFUSED_STREAM, "too many streams");
        }
        _streams[id] = opened;
        var headers = _h2_regular_fields(fields, [":method", ":scheme", ":authority", ":path"]);
        if (headers.is_err()) {
            return this._reset(opened, _H2_PROTOCOL_ERROR, headers.error().message);
        }
        for (var required in [":method", ":scheme", ":path"]) {
            if (_h2_pseudo(fields, required).is_empty()) {
                return this._reset(opened, _H2_PROTOCOL_ERROR, $"a request has no '{required}'");
            }
        }
        opened.fields = Optional<_HpackField[]>.Value(fields);
        opened.remote_ended = end_stream;
        _accepted.append(opened);
        return io.IoResult<void>.ok();
    }

    # Client: the response head (after any interim ones), or trailers.
    _on_response_head(id: uint, fields: _HpackField[], end_stream: bool): io.IoResult<void> {
        if (id % 2 == 0 || this._is_idle(id)) {
            return this._fault(_H2_PROTOCOL_ERROR, $"HEADERS on stream {id}, which the client did not open");
        }
        var stream = _streams.get(id);
        if (stream === __null || stream.error.is_value()) {
            return io.IoResult<void>.ok();  # a stream this side already closed
        }
        if (stream.fields.is_value()) {
            if (!end_stream || stream.remote_ended) {
                return this._reset(stream, _H2_PROTOCOL_ERROR, "HEADERS in the middle of a response");
            }
            stream.remote_ended = true;  # trailers, which are dropped
            return io.IoResult<void>.ok();
        }
        var status = _h2_status(fields);
        if (status < 100 || status > 999) {
            return this._reset(stream, _H2_PROTOCOL_ERROR, "a response has no valid ':status'");
        }
        if (status < 200) {
            if (end_stream) {
                return this._reset(stream, _H2_PROTOCOL_ERROR, "an interim response ends the stream");
            }
            return io.IoResult<void>.ok();  # 100 Continue, 103 Early Hints
        }
        stream.fields = Optional<_HpackField[]>.Value(fields);
        stream.remote_ended = end_stream;
        return io.IoResult<void>.ok();
    }

    _on_priority(frame: _H2Frame): io.IoResult<void> {
        if (frame.stream == 0) {
            return this._fault(_H2_PROTOCOL_ERROR, "PRIORITY on stream 0");
        }
        if (frame.payload.count != 5) {
            return this._fault(_H2_FRAME_SIZE_ERROR, "PRIORITY is not 5 bytes");
        }
        return io.IoResult<void>.ok();  # priorities are not used
    }

    _on_reset(frame: _H2Frame): io.IoResult<void> {
        if (frame.stream == 0) {
            return this._fault(_H2_PROTOCOL_ERROR, "RST_STREAM on stream 0");
        }
        if (frame.payload.count != 4) {
            return this._fault(_H2_FRAME_SIZE_ERROR, "RST_STREAM is not 4 bytes");
        }
        if (this._is_idle(frame.stream)) {
            return this._fault(_H2_PROTOCOL_ERROR, $"RST_STREAM on stream {frame.stream}, which is not open");
        }
        var stream = _streams.get(frame.stream);
        if (stream === __null) {
            return io.IoResult<void>.ok();
        }
        var code = _h2_number(frame.payload, 0, 4);
        var who = _server ? "client" : "server";
        if (stream.error.is_empty()) {
            stream.error = Optional<io.IoError>.Value(
                _http_error($"the {who} reset the HTTP/2 stream ({_h2_error_name(code)})")
            );
        }
        _streams.remove(frame.stream);
        return io.IoResult<void>.ok();
    }

    _on_settings(frame: _H2Frame): io.IoResult<void> {
        if (frame.stream != 0) {
            return this._fault(_H2_PROTOCOL_ERROR, "SETTINGS on a stream");
        }
        if (frame.has(_H2_ACK)) {
            if (frame.payload.count != 0) {
                return this._fault(_H2_FRAME_SIZE_ERROR, "a SETTINGS acknowledgement has a payload");
            }
            return io.IoResult<void>.ok();
        }
        if (frame.payload.count % 6 != 0) {
            return this._fault(_H2_FRAME_SIZE_ERROR, "SETTINGS is not a multiple of 6 bytes");
        }
        _got_settings = true;
        ulong at = 0;
        while (at < frame.payload.count) {
            var id = _h2_number(frame.payload, at, 2);
            var value = _h2_number(frame.payload, at + 2, 4);
            at += 6;
            if (id == _H2_SETTINGS_HEADER_TABLE_SIZE) {
                # This side's encoder never needs more than the default.
                var size = value as ulong;
                if (size > _HPACK_DEFAULT_TABLE_SIZE) {
                    size = _HPACK_DEFAULT_TABLE_SIZE;
                }
                if (size != _encoder._table.capacity) {
                    _encoder.resize(size);
                }
            } else if (id == _H2_SETTINGS_ENABLE_PUSH) {
                if (value > 1 || (!_server && value != 0)) {
                    return this._fault(_H2_PROTOCOL_ERROR, "invalid SETTINGS_ENABLE_PUSH");
                }
            } else if (id == _H2_SETTINGS_MAX_CONCURRENT_STREAMS) {
                _peer_max_streams = value as ulong;
            } else if (id == _H2_SETTINGS_INITIAL_WINDOW_SIZE) {
                if (value as long > _H2_MAX_WINDOW) {
                    return this._fault(_H2_FLOW_CONTROL_ERROR, "SETTINGS_INITIAL_WINDOW_SIZE is above 2^31-1");
                }
                # The change applies to every open stream's window.
                var delta = value as long - _peer_initial_window;
                _peer_initial_window = value as long;
                for (var (key, stream) in _streams) {
                    stream.send_window += delta;
                    if (stream.send_window > _H2_MAX_WINDOW) {
                        return this._fault(_H2_FLOW_CONTROL_ERROR, "a stream's window is above 2^31-1");
                    }
                }
            } else if (id == _H2_SETTINGS_MAX_FRAME_SIZE) {
                if (value < 16384 || value > 16777215) {
                    return this._fault(_H2_PROTOCOL_ERROR, "invalid SETTINGS_MAX_FRAME_SIZE");
                }
                _peer_max_frame = value as ulong;
            }
        }
        var out = Array<u8>();
        _h2_append_head(out, 0, _H2_SETTINGS, _H2_ACK, 0);
        return this._write(out);
    }

    _on_ping(frame: _H2Frame): io.IoResult<void> {
        if (frame.stream != 0) {
            return this._fault(_H2_PROTOCOL_ERROR, "PING on a stream");
        }
        if (frame.payload.count != 8) {
            return this._fault(_H2_FRAME_SIZE_ERROR, "PING is not 8 bytes");
        }
        if (frame.has(_H2_ACK)) {
            return io.IoResult<void>.ok();
        }
        var out = Array<u8>();
        _h2_append_frame(out, _H2_PING, _H2_ACK, 0, frame.payload);
        return this._write(out);
    }

    _on_goaway(frame: _H2Frame): io.IoResult<void> {
        if (frame.stream != 0) {
            return this._fault(_H2_PROTOCOL_ERROR, "GOAWAY on a stream");
        }
        if (frame.payload.count < 8) {
            return this._fault(_H2_FRAME_SIZE_ERROR, "GOAWAY is shorter than 8 bytes");
        }
        var last = _h2_number(frame.payload, 0, 4) & 0x7fffffff;
        var code = _h2_number(frame.payload, 4, 4);
        _going_away = true;
        _goaway_last = last;
        # Streams this side opened after `last` were not processed: they
        # fail, and may be sent again on another connection.
        var error = _http_error($"the HTTP/2 connection is going away ({_h2_error_name(code)})");
        for (var (id, stream) in _streams) {
            var ours = (id % 2 == 1) != _server;
            if (ours && id > last && stream.error.is_empty()) {
                stream.error = Optional<io.IoError>.Value(error);
            }
        }
        return io.IoResult<void>.ok();
    }

    _on_window_update(frame: _H2Frame): io.IoResult<void> {
        if (frame.payload.count != 4) {
            return this._fault(_H2_FRAME_SIZE_ERROR, "WINDOW_UPDATE is not 4 bytes");
        }
        var increment = (_h2_number(frame.payload, 0, 4) & 0x7fffffff) as long;
        if (frame.stream == 0) {
            if (increment == 0) {
                return this._fault(_H2_PROTOCOL_ERROR, "a WINDOW_UPDATE of 0");
            }
            _send_window += increment;
            if (_send_window > _H2_MAX_WINDOW) {
                return this._fault(_H2_FLOW_CONTROL_ERROR, "the connection's window is above 2^31-1");
            }
            return io.IoResult<void>.ok();
        }
        if (this._is_idle(frame.stream)) {
            return this._fault(_H2_PROTOCOL_ERROR, $"WINDOW_UPDATE on stream {frame.stream}, which is not open");
        }
        var stream = _streams.get(frame.stream);
        if (stream === __null) {
            return io.IoResult<void>.ok();
        }
        if (increment == 0) {
            return this._reset(stream, _H2_PROTOCOL_ERROR, "a WINDOW_UPDATE of 0");
        }
        stream.send_window += increment;
        if (stream.send_window > _H2_MAX_WINDOW) {
            return this._reset(stream, _H2_FLOW_CONTROL_ERROR, "the stream's window is above 2^31-1");
        }
        return io.IoResult<void>.ok();
    }

    # A stream error: sends RST_STREAM, and the stream ends with an error.
    # The connection carries on.
    _reset(stream: _H2Stream, code: uint, message: String): io.IoResult<void> {
        if (stream.error.is_empty()) {
            stream.error = Optional<io.IoError>.Value(
                _http_error($"HTTP/2 stream error ({_h2_error_name(code)}): {message}")
            );
        }
        _streams.remove(stream.id);
        var payload = Array<u8>();
        _h2_append_number(payload, code, 4);
        var out = Array<u8>();
        _h2_append_frame(out, _H2_RST_STREAM, 0, stream.id, payload);
        return this._write(out);
    }

    # ── Writing ─────────────────────────────────────────────────────────────

    # Client: opens a stream with the request head `fields`, ending it when
    # `end_stream`. Waits while the server's limit of streams is reached.
    _open(fields: _HpackField[], end_stream: bool): io.IoResult<_H2Stream> {
        while (_streams.count as ulong >= _peer_max_streams && this.is_usable) {
            var moved = this._progress();
            if (moved.is_err()) {
                return io.IoResult<_H2Stream>.err(moved.error());
            }
        }
        _take_writing();
        if (!this.is_usable) {
            _give_writing();
            var why = _failure.is_value() ? _failure.value() : _http_error("the HTTP/2 connection is going away");
            return io.IoResult<_H2Stream>.err(why);
        }
        # Ids go out in order: assigned while holding the writing baton.
        var stream = _H2Stream(_next_id, _peer_initial_window);
        _next_id += 2;
        stream.local_ended = end_stream;
        _streams[stream.id] = stream;
        var sent = this._send_head_held(stream.id, fields, end_stream);
        _give_writing();
        if (sent.is_err()) {
            this._fail_all(sent.error());
            return io.IoResult<_H2Stream>.err(sent.error());
        }
        return io.IoResult<_H2Stream>.ok(stream);
    }

    # Sends a header block on `stream`, split into HEADERS and CONTINUATION
    # frames. The block is encoded while holding the writing baton, so that
    # blocks reach the peer in the order the encoder's table saw them.
    _send_head(stream: _H2Stream, fields: _HpackField[], end_stream: bool): io.IoResult<void> {
        _take_writing();
        if (stream.error.is_value()) {
            _give_writing();
            return io.IoResult<void>.err(stream.error.value());
        }
        stream.local_ended = end_stream;
        var sent = this._send_head_held(stream.id, fields, end_stream);
        _give_writing();
        return sent;
    }

    _send_head_held(id: uint, fields: _HpackField[], end_stream: bool): io.IoResult<void> {
        var block = Array<u8>();
        _encoder.encode(fields, block);
        var out = Array<u8>();
        ulong at = 0;
        var first = true;
        while (first || at < block.count) {
            var size = block.count - at;
            if (size > _peer_max_frame) {
                size = _peer_max_frame;
            }
            u8 flags = 0;
            if (at + size == block.count) {
                flags = _H2_END_HEADERS;
            }
            var kind = _H2_CONTINUATION;
            if (first) {
                kind = _H2_HEADERS;
                if (end_stream) {
                    flags = flags | _H2_END_STREAM;
                }
            }
            _h2_append_head(out, size, kind, flags, id);
            out._append_raw(block._data + at, size);
            at += size;
            first = false;
        }
        return _reader._connection._write_all(out);
    }

    # Sends `data` on `stream` as DATA frames as the windows allow, waiting
    # for WINDOW_UPDATEs as needed; ends the stream after it when `end`.
    _send_data(stream: _H2Stream, data: u8[], end: bool): io.IoResult<void> {
        ulong at = 0;
        while (true) {
            if (stream.error.is_value()) {
                return io.IoResult<void>.err(stream.error.value());
            }
            if (_failure.is_value()) {
                return io.IoResult<void>.err(_failure.value());
            }
            var left = data.count - at;
            if (left == 0 && !end) {
                return io.IoResult<void>.ok();
            }
            _take_writing();
            var size = left;
            if (size > _peer_max_frame) {
                size = _peer_max_frame;
            }
            if (size as long > stream.send_window) {
                size = stream.send_window < 0 ? 0 : stream.send_window as ulong;
            }
            if (size as long > _send_window) {
                size = _send_window < 0 ? 0 : _send_window as ulong;
            }
            if (size == 0 && left > 0) {
                # No window: read until the peer opens some.
                _give_writing();
                var moved = this._progress();
                if (moved.is_err()) {
                    return moved;
                }
                continue;
            }
            u8 flags = 0;
            var last = end && at + size == data.count;
            if (last) {
                flags = _H2_END_STREAM;
                stream.local_ended = true;
            }
            var out = Array<u8>(9 + size);
            _h2_append_head(out, size, _H2_DATA, flags, stream.id);
            out._append_raw(data._data + at, size);
            stream.send_window -= size as long;
            _send_window -= size as long;
            var sent = _reader._connection._write_all(out);
            _give_writing();
            if (sent.is_err()) {
                this._fail_all(sent.error());
                return sent;
            }
            at += size;
            if (last) {
                this._forget_if_done(stream);
                return io.IoResult<void>.ok();
            }
        }
        return io.IoResult<void>.ok();
    }

    # Sends everything `source` gives on `stream`, then ends it.
    _send_reader(stream: _H2Stream, source: io.Reader): io.IoResult<void> {
        var chunk = Array<u8>(65536);
        while (true) {
            chunk.clear();
            var read = source.read(chunk, 65536);
            if (read.is_err()) {
                this._cancel(stream);
                return io.IoResult<void>.err(read.error());
            }
            if (read.value() == 0) {
                return this._send_data(stream, Array<u8>(), true);
            }
            var sent = this._send_data(stream, chunk, false);
            if (sent.is_err()) {
                return sent;
            }
        }
        return io.IoResult<void>.ok();
    }

    # Ends `stream` early with CANCEL, unless it has already ended.
    _cancel(stream: _H2Stream) {
        if (_streams.get(stream.id) === __null) {
            return;
        }
        this._reset(stream, _H2_CANCEL, "cancelled");
    }

    # Drops `stream` once both sides have ended it.
    _forget_if_done(stream: _H2Stream) {
        if (stream.local_ended && stream.remote_ended) {
            _streams.remove(stream.id);
            _wake();
        }
    }

    # Takes up to `max` received bytes of `stream` into `into`, giving the
    # window back; 0 when the stream has ended and nothing is left. Waits
    # for bytes to arrive.
    _receive(stream: _H2Stream, into: u8[], max: ulong): io.IoResult<ulong> {
        while (true) {
            var available = stream.available;
            if (available > 0 && max > 0) {
                var take = available < max ? available : max;
                into._append_raw(stream.data._data + stream._start, take);
                stream._start += take;
                if (stream._start == stream.data.count) {
                    stream.data.clear();
                    stream._start = 0;
                }
                var credited = this._consumed(Optional<_H2Stream>.Value(stream), take);
                if (credited.is_err()) {
                    return io.IoResult<ulong>.err(credited.error());
                }
                return io.IoResult<ulong>.ok(take);
            }
            if (stream.remote_ended || max == 0) {
                this._forget_if_done(stream);
                return io.IoResult<ulong>.ok(0);
            }
            if (stream.error.is_value()) {
                return io.IoResult<ulong>.err(stream.error.value());
            }
            var moved = this._progress();
            if (moved.is_err() && stream.available == 0 && !stream.remote_ended) {
                return io.IoResult<ulong>.err(moved.error());
            }
        }
        return io.IoResult<ulong>.ok(0);
    }
}

# The `:status` of a response head, or -1.
_h2_status(fields: _HpackField[]): long {
    for (var field in fields) {
        if (field.name == ":status") {
            if (field.value.size != 3) {
                return -1;
            }
            return _http_parse_decimal(field.value);
        }
    }
    return -1;
}

# Whether `name` is a field HTTP/2 forbids (RFC 9113 section 8.2.2).
_h2_is_connection_field(name: String): bool {
    return match (name) {
        "connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "host" => true,
        else => false,
    };
}

# Appends the fields of `headers` to `fields`, lowercased, leaving out the
# ones HTTP/2 forbids and those named in `skip`.
_h2_append_fields(fields: _HpackField[], headers: Headers, skip: String) {
    for (var name in headers.names()) {
        if (_h2_is_connection_field(name) || name == skip) {
            continue;
        }
        for (var value in headers.values(name)) {
            if (name == "te" && value.trim().lower() != "trailers") {
                continue;
            }
            fields.append(_HpackField(name, value));
        }
    }
}

# Checks the fields of a request or response head: lowercase names, the
# pseudo-fields first and no others. Returns the regular fields as
# `Headers`, or an error message.
_h2_regular_fields(fields: _HpackField[], allowed: String[]): Result<Headers> {
    var headers = Headers();
    var regular = false;
    for (var field in fields) {
        if (field.name.size == 0 || field.name != field.name.lower()) {
            return Result<Headers>.err($"the field name '{field.name}' is not lowercase");
        }
        if (field.name.starts_with(":")) {
            if (regular || !allowed.contains(field.name)) {
                return Result<Headers>.err($"misplaced or unknown pseudo-field '{field.name}'");
            }
            continue;
        }
        regular = true;
        if (_h2_is_connection_field(field.name) && field.name != "host") {
            return Result<Headers>.err($"the connection-specific field '{field.name}'");
        }
        headers.add(field.name, field.value);
    }
    return Result<Headers>.ok(headers);
}

# The value of the pseudo-field `name` in `fields`, or none.
_h2_pseudo(fields: _HpackField[], name: String): String? {
    for (var field in fields) {
        if (field.name == name) {
            return Optional<String>.Value(field.value);
        }
    }
    return Optional<String>.Empty;
}

# ── Client ───────────────────────────────────────────────────────────────────

# The body of a response that arrived over HTTP/2, read from its stream as
# it arrives: an `io.Reader`, like `BodyReader`. Closing it early resets the
# stream and leaves the connection open for other requests.
struct _H2BodyReader {
    var _connection: _H2Connection;
    var _stream: _H2Stream;
    var _done: bool;
    # Whether the connection is this response's alone (a `Client` request
    # outside a `Session`), and closes with its body.
    var _owner: bool;

    construct(connection: _H2Connection, stream: _H2Stream) {
        _connection = connection;
        _stream = stream;
        _done = false;
        _owner = false;
    }

    read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        if (_done) {
            return io.IoResult<ulong>.ok(0);
        }
        var read = _connection._receive(_stream, buffer, max);
        if (read.is_err() || (read.value() == 0 && max > 0)) {
            _done = true;
            if (_owner) {
                _connection.close();
            }
        }
        return read;
    }

    # Stops reading: resets the stream if the body has not ended.
    close() {
        if (_done) {
            return;
        }
        _done = true;
        _connection._cancel(_stream);
        if (_owner) {
            _connection.close();
        }
    }
}

extend _H2BodyReader with io.Reader;

# Sends `request` as a new stream on `connection` and waits for the
# response's head, leaving its body to an `_H2BodyReader`.
_h2_exchange(connection: _H2Connection, request: Request, url: _HttpUrl, secure: bool): io.IoResult<Response> {
    var method = request.method;
    var fields = Array<_HpackField>();
    fields.append(_HpackField(":method", method));
    fields.append(_HpackField(":scheme", secure ? "https" : "http"));
    fields.append(_HpackField(":authority", url._authority));
    fields.append(_HpackField(":path", url._target));
    _h2_append_fields(fields, request.headers, "content-length");
    var has_body = request._streamed || request._body.count > 0;
    if (request._streamed) {
        if (request._length >= 0) {
            fields.append(_HpackField("content-length", to_string(request._length)));
        }
    } else {
        var sends_length = match (method) {
            "POST", "PUT", "PATCH" => true,
            else => has_body,
        };
        if (sends_length) {
            fields.append(_HpackField("content-length", to_string(request._body.count)));
        }
    }
    var opened = connection._open(fields, !has_body);
    if (opened.is_err()) {
        return io.IoResult<Response>.err(opened.error());
    }
    var stream = opened.value();
    if (request._streamed) {
        var sent = connection._send_reader(stream, request._source);
        if (sent.is_err()) {
            return io.IoResult<Response>.err(sent.error());
        }
    } else if (has_body) {
        var sent = connection._send_data(stream, request._body, true);
        if (sent.is_err()) {
            return io.IoResult<Response>.err(sent.error());
        }
    }
    while (stream.fields.is_empty()) {
        if (stream.error.is_value()) {
            return io.IoResult<Response>.err(stream.error.value());
        }
        var moved = connection._progress();
        if (moved.is_err() && stream.fields.is_empty()) {
            return io.IoResult<Response>.err(moved.error());
        }
    }
    var head = stream.fields.value();
    var headers = _h2_regular_fields(head, [":status"]);
    if (headers.is_err()) {
        connection._reset(stream, _H2_PROTOCOL_ERROR, headers.error().message);
        return io.IoResult<Response>.err(_http_error($"malformed HTTP/2 response: {headers.error().message}"));
    }
    var response = Response(_h2_status(head) as int);
    response.reason = reason_phrase(response.status);
    response.headers = headers.value();
    response._streamed = true;
    response._source = _H2BodyReader(connection, stream);
    return io.IoResult<Response>.ok(response);
}

# ── Server ───────────────────────────────────────────────────────────────────

# Serves HTTP/2 on a connection whose client preface `reader` has just
# read, until the connection ends: each stream is answered in a task of its
# own on this worker.
_h2_serve(reader: _HttpReader, handler: shared (Request) => Response) {
    var connection = _H2Connection(reader, true);
    var out = Array<u8>();
    connection._append_settings(out);
    if (connection._write(out).is_err()) {
        return;
    }
    while (true) {
        var moved = connection._progress();
        while (connection._accepted.count > 0) {
            var stream = connection._accepted.remove_at(0);
            async.Task<void>.spawn_local(() => {
                _h2_answer(connection, stream, handler);
            });
        }
        if (moved.is_err()) {
            break;
        }
    }
    reader._connection._close();
}

# Reads the request on `stream`, calls `handler`, and sends the response.
_h2_answer(connection: _H2Connection, stream: _H2Stream, handler: shared (Request) => Response) {
    # `_on_request_head` checked the head.
    var head = stream.fields.value();
    var method = _h2_pseudo(head, ":method").value();
    var request = Request(method, _h2_pseudo(head, ":path").value());
    request.headers = _h2_regular_fields(head, [":method", ":scheme", ":authority", ":path"]).value();
    var authority = _h2_pseudo(head, ":authority");
    if (authority.is_value() && !request.headers.has("host")) {
        request.headers["Host"] = authority.value();
    }
    # The whole body, as HTTP/1.1 requests get it.
    while (!stream.remote_ended) {
        if (stream.error.is_value()) {
            return;
        }
        if (stream.data.count > MAX_REQUEST_BODY) {
            _h2_respond(connection, stream, Response(413), false);
            connection._cancel(stream);
            return;
        }
        if (connection._progress().is_err()) {
            return;
        }
    }
    if (stream.data.count > MAX_REQUEST_BODY) {
        _h2_respond(connection, stream, Response(413), false);
        return;
    }
    request.set_body(stream.data);
    var response = handler(request);
    _h2_respond(connection, stream, response, method == "HEAD");
}

# Sends `response` on `stream`: its head, then its body unless `head`.
_h2_respond(connection: _H2Connection, stream: _H2Stream, response: Response, head: bool) {
    var status = response.status;
    var bodiless = head || status == 204 || status == 304;
    var fields = Array<_HpackField>();
    fields.append(_HpackField(":status", to_string(status)));
    _h2_append_fields(fields, response.headers, "content-length");
    if (response._streamed) {
        if (response._length >= 0 && status != 204 && status != 304) {
            fields.append(_HpackField("content-length", to_string(response._length)));
        }
    } else if (status != 204 && status != 304) {
        fields.append(_HpackField("content-length", to_string(response._body.count)));
    }
    if (connection._send_head(stream, fields, bodiless).is_err()) {
        return;
    }
    if (bodiless) {
        connection._forget_if_done(stream);
        return;
    }
    if (response._streamed) {
        connection._send_reader(stream, response._source);
        return;
    }
    connection._send_data(stream, response._body, true);
}
