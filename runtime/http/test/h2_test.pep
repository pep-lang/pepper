# HTTP/2 over loopback: an `http.Server`, which takes HTTP/2 with prior
# knowledge (h2c), and the client side of `h2.pep` on one connection,
# with requests on concurrent streams and bodies larger than the windows
# so that flow control has to work both ways. Then raw frames, for the
# connection rules a well-behaved client never breaks.

import async;
import http;
import io;
import os;
import tls;
import "../client";
import "../h2";
import "../hpack";
import "../wire";

# `count` bytes of a repeating pattern.
private pattern(count: ulong): u8[] {
    var bytes = Array<u8>(count);
    while (bytes.count < count) {
        bytes.append((bytes.count % 251) as u8);
    }
    return bytes;
}

private answer(request: http.Request): http.Response {
    var path = request.path();
    if (path == "/hello") {
        var hello = http.Response(200).set_text("hello " + request.query());
        hello.headers["Content-Type"] = "text/plain";
        hello.headers.add("X-Twice", "one");
        hello.headers.add("X-Twice", "two");
        return hello;
    }
    if (path == "/echo") {
        var echo = http.Response(200).set_body(request.body());
        echo.headers["X-Method"] = request.method;
        echo.headers["X-Host"] = request.headers["host"];
        return echo;
    }
    if (path == "/stream") {
        return http.Response(200).set_reader(io.ByteReader(pattern(1000000)));
    }
    if (path == "/redirect") {
        var moved = http.Response(302).set_text("moved");
        moved.headers["Location"] = "/hello?moved";
        return moved;
    }
    if (path == "/upgrade") {
        # An HTTP/2 stream cannot switch protocols.
        expect_false(request.can_upgrade());
        return http.Response().upgrade("echo", (connection) => {});
    }
    if (path == "/inject") {
        var injected = http.Response(303);
        injected.headers["Location"] = "/next\r\nSet-Cookie: admin=1";
        return injected;
    }
    if (path == "/slow") {
        async.sleep(os.Duration.from_milliseconds(50));
        return http.Response(200).set_text("slow");
    }
    return http.Response(404).set_text("no page at " + path);
}

# Starts a server in the running `async.run` and returns its port.
private start(): u16 {
    var server = http.Server.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
    var port = server.local_address().value().port();
    async.spawn<void>(() => {
        server.serve(answer);
    });
    return port;
}

# Opens an HTTP/2 connection to the server on `port`.
private connect(port: u16): _H2Connection {
    var tcp = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
    return _H2Connection.client(_HttpConnection(tcp)).value();
}

# Sends `request` on `connection` and reads the whole response.
private exchange(connection: _H2Connection, request: http.Request): http.Response {
    var url = _http_parse_url(request.url).value();
    var response = _h2_exchange(connection, request, url, false).value();
    var body = Array<u8>();
    while (response._source.read(body, 65536).value() > 0) {}
    return response.set_body(body);
}

[Test]
requests_share_one_connection() {
    async.run(
        () => {
            var port = start();
            var base = "http://127.0.0.1:" + to_string(port);
            var connection = connect(port);

            var hello = exchange(connection, http.Request("GET", base + "/hello?name=h2"));
            expect_equal(hello.status, 200);
            expect_equal(hello.reason, "OK");
            expect_equal(hello.text(), "hello name=h2");
            expect_equal(hello.headers["content-type"], "text/plain");
            expect_equal(hello.headers.values("x-twice").count, 2);
            expect_equal(hello.headers["content-length"], "13");

            var post = http.Request("POST", base + "/echo").set_text("payload");
            var echo = exchange(connection, post);
            expect_equal(echo.text(), "payload");
            expect_equal(echo.headers["x-method"], "POST");
            expect_equal(echo.headers["x-host"], "127.0.0.1:" + to_string(port));  # from :authority

            var missing = exchange(connection, http.Request("GET", base + "/nowhere"));
            expect_equal(missing.status, 404);

            var upgrade = exchange(connection, http.Request("GET", base + "/upgrade"));
            expect_equal(upgrade.status, 501);  # an upgrade on a stream is refused

            var injected = exchange(connection, http.Request("GET", base + "/inject"));
            expect_equal(injected.status, 500);  # a value with CR or LF is refused
            expect_false(injected.headers.has("location"));
            expect_equal(
                injected.text(), "the response cannot be sent: the value of the field 'location' holds CR, LF or NUL"
            );

            var head = exchange(connection, http.Request("HEAD", base + "/hello"));
            expect_equal(head.status, 200);
            expect_equal(head.body().count, 0);
            expect_equal(connection.active_count, 0);  # every stream ended and was dropped
        }
    );
}

[Test]
bodies_larger_than_the_windows() {
    async.run(
        () => {
            var port = start();
            var base = "http://127.0.0.1:" + to_string(port);
            var connection = connect(port);

            # 1 MB down: past the server's 64 KiB starting window for the client.
            var download = exchange(connection, http.Request("GET", base + "/stream"));
            expect_equal(download.body().count, 1000000);
            expect_true(download.body() == pattern(1000000));

            # 3 MB up: past the 1 MiB window the server gives, so the client
            # waits for WINDOW_UPDATEs; once as bytes, once from a reader.
            var up = exchange(connection, http.Request("PUT", base + "/echo").set_body(pattern(3000000)));
            expect_equal(up.body().count, 3000000);
            var streamed = http.Request("PUT", base + "/echo").set_reader(io.ByteReader(pattern(2500000)));
            expect_equal(exchange(connection, streamed).body().count, 2500000);
        }
    );
}

[Test]
concurrent_streams_interleave() {
    async.run(
        () => {
            var port = start();
            var base = "http://127.0.0.1:" + to_string(port);
            var connection = connect(port);
            var tasks = Array<async.Task<bool>>();
            var n = 0;
            while (n < 12) {
                var index = n;
                tasks.append(async.Task<bool>.spawn_local(() => {
                    var path = index % 3 == 0 ? "/slow" : (index % 3 == 1 ? "/stream" : "/echo");
                    var request = http.Request("POST", base + path).set_text("body " + to_string(index));
                    var response = exchange(connection, request);
                    return match (index % 3) {
                        0 => response.text() == "slow",
                        1 => response.body().count == 1000000,
                        else => response.text() == "body " + to_string(index),
                    };
                }));
                n += 1;
            }
            for (var task in tasks) {
                expect_true(task.join().value());
            }
            expect_equal(connection._next_id, 25);  # twelve streams, all on this connection
        }
    );
}

[Test]
streams_share_the_connection_handler() {
    async.run(
        () => {
            var server = http.Server.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
            var port = server.local_address().value().port();
            var made = async.Atomic<int>(0);
            async.spawn<void>(
                () => {
                    server.serve_each(
                        () => {
                            made.fetch_add(1);
                            var paths = Array<String>();
                            return (request) => {
                                paths.append(request.path());
                                var count = paths.count;
                                if (request.path() == "/slow") {
                                    async.sleep(os.Duration.from_milliseconds(20));  # other streams' calls run meanwhile
                                }
                                return http.Response(200).set_text(to_string(count));
                            };
                        }
                    );
                }
            );
            var base = "http://127.0.0.1:" + to_string(port);
            var connection = connect(port);
            var tasks = Array<async.Task<String>>();
            var n = 0;
            while (n < 6) {
                var path = n % 2 == 0 ? "/slow" : "/fast";
                tasks.append(async.Task<String>.spawn_local(() => {
                    return exchange(connection, http.Request("GET", base + path)).text();
                }));
                n += 1;
            }
            var counts = Array<String>();
            for (var task in tasks) {
                counts.append(task.join().value());
            }
            # One handler saw all six streams, each call adding one path.
            expect_equal(made.load(), 1);
            var i = 1;
            while (i <= 6) {
                expect_true(counts.contains(to_string(i)));
                i += 1;
            }
        }
    );
}

[Test]
closing_a_body_early_resets_only_its_stream() {
    async.run(() => {
        var port = start();
        var base = "http://127.0.0.1:" + to_string(port);
        var connection = connect(port);
        var url = _http_parse_url(base + "/stream").value();
        var response = _h2_exchange(connection, http.Request("GET", base + "/stream"), url, false).value();
        var some = Array<u8>();
        expect_true(response._source.read(some, 1000).value() > 0);
        (response._source as? _H2BodyReader).value().close();
        expect_equal(exchange(connection, http.Request("GET", base + "/hello")).text(), "hello ");
    });
}

# The frames the server sends until it closes the connection, as
# `type:flags:stream` words, after writing `bytes` raw.
private raw_frames(port: u16, bytes: u8[]): String[] {
    var tcp = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
    tcp.set_read_timeout(5000);
    var connection = _HttpConnection(tcp);
    connection._write_all(bytes);
    var h2 = _H2Connection(_HttpReader(connection), false);
    var seen = Array<String>();
    while (true) {
        var frame = h2._read_frame();
        if (frame.is_err()) {
            return seen;
        }
        var f = frame.value();
        seen.append($"{f.kind}:{f.flags}:{f.stream}");
        if (f.kind == _H2_GOAWAY) {
            seen.append("code " + to_string(_h2_number(f.payload, 4, 4)));
            return seen;
        }
        if (f.kind == _H2_PING && f.has(_H2_ACK)) {
            return seen;
        }
    }
    return seen;
}

# The client preface and an empty SETTINGS frame.
private preface(): u8[] {
    var out = Array<u8>();
    _http_append(out, _H2_PREFACE);
    _h2_append_head(out, 0, _H2_SETTINGS, 0, 0);
    return out;
}

[Test]
connection_rules_over_raw_frames() {
    async.run(
        () => {
            var port = start();

            # A PING is answered; the server's SETTINGS and window come first.
            var ping = preface();
            _h2_append_frame(ping, _H2_PING, 0, 0, pattern(8));
            var answered = raw_frames(port, ping);
            expect_equal(answered[0], "4:0:0");       # SETTINGS
            expect_equal(answered[1], "8:0:0");       # WINDOW_UPDATE
            expect_true(answered.contains("4:1:0"));  # our SETTINGS acknowledged
            expect_equal(answered[answered.count - 1], "6:1:0");

            # Anything but SETTINGS first is a PROTOCOL_ERROR.
            var unsettled = Array<u8>();
            _http_append(unsettled, _H2_PREFACE);
            _h2_append_frame(unsettled, _H2_PING, 0, 0, pattern(8));
            var refused = raw_frames(port, unsettled);
            expect_equal(refused[refused.count - 1], "code 1");

            # A stream with an even id, and a frame over 16384 bytes.
            var even = preface();
            var block = Array<u8>();
            _HpackEncoder().encode([_HpackField(":method", "GET")], block);
            _h2_append_frame(even, _H2_HEADERS, _H2_END_HEADERS | _H2_END_STREAM, 2, block);
            var bad_id = raw_frames(port, even);
            expect_equal(bad_id[bad_id.count - 1], "code 1");
            var big = preface();
            _h2_append_head(big, 20000, _H2_DATA, 0, 1);  # the head alone: unread bytes would reset the socket
            var oversized = raw_frames(port, big);
            expect_equal(oversized[oversized.count - 1], "code 6");

            # A request without ':path' is reset, and the connection goes on.
            var malformed = preface();
            var partial = Array<u8>();
            _HpackEncoder().encode([_HpackField(":method", "GET"), _HpackField(":scheme", "http")], partial);
            _h2_append_frame(malformed, _H2_HEADERS, _H2_END_HEADERS | _H2_END_STREAM, 1, partial);
            _h2_append_frame(malformed, _H2_PING, 0, 0, pattern(8));
            var reset = raw_frames(port, malformed);
            expect_true(reset.contains("3:0:1"));
            expect_equal(reset[reset.count - 1], "6:1:0");
        }
    );
}

# Starts an HTTPS server in the running `async.run` and returns its base
# URL; `bind_tls` offers HTTP/2 through ALPN.
private start_tls(): String {
    var acceptor = tls.TlsAcceptor.create(io.Path("tls/test/certificate.pem"), io.Path("tls/test/key.pem")).value();
    var server = http.Server.bind_tls(io.SocketAddress(io.IpAddress.loopback_v4(), 0), acceptor).value();
    var port = server.local_address().value().port();
    async.spawn<void>(() => {
        server.serve(answer);
    });
    return "https://localhost:" + to_string(port);
}

# A client that trusts the test certificate.
private trusting_client(): http.Client {
    var connector = tls.TlsConnector.create().value();
    connector.add_root_certificate(io.Path("tls/test/certificate.pem"));
    return http.Client(connector);
}

# Whether `response` came over HTTP/2.
private over_h2(response: http.Response): bool {
    return (response._source as? _H2BodyReader).is_value();
}

[Test]
clients_choose_http2_through_alpn() {
    # A TLS server is not supported on iOS yet (docs/src/language/mobile.md).
    [Target(OS(IOS))]
    {
        return;
    }
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var base = start_tls();
            var client = trusting_client();

            var hello = client.open(http.Request("GET", base + "/hello?over=h2")).value();
            expect_true(over_h2(hello));
            expect_equal(hello.status, 200);
            expect_equal(hello.reason, "OK");
            var reader = hello._source as? _H2BodyReader;
            expect_true(reader.value()._owner);  # outside a session, its own connection

            expect_equal(client.get(base + "/hello?over=h2").value().text(), "hello over=h2");
            var redirected = client.get(base + "/redirect").value();
            expect_equal(redirected.text(), "hello moved");
            expect_equal(redirected.url, base + "/hello?moved");
            var large = client.send(http.Request("PUT", base + "/echo").set_body(pattern(2000000))).value();
            expect_true(large.body() == pattern(2000000));

            # Plain http:// stays HTTP/1.1.
            var plain = client.open(http.Request("GET", "http://127.0.0.1:" + to_string(start()) + "/hello")).value();
            expect_false(over_h2(plain));
        }
    );
}

[Test]
sessions_share_one_http2_connection() {
    # A TLS server is not supported on iOS yet (docs/src/language/mobile.md).
    [Target(OS(IOS))]
    {
        return;
    }
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var base = start_tls();
            var session = trusting_client().session();
            expect_equal(session.get(base + "/hello?first").value().text(), "hello first");
            expect_equal(session.idle_count, 1);

            var tasks = Array<async.Task<bool>>();
            var n = 0;
            while (n < 10) {
                var index = n;
                tasks.append(async.Task<bool>.spawn_local(() => {
                    if (index % 2 == 0) {
                        return session.get(base + "/slow").value().text() == "slow";
                    }
                    var echo = session.post(base + "/echo", "text/plain", "task " + to_string(index)).value();
                    return echo.text() == "task " + to_string(index);
                }));
                n += 1;
            }
            for (var task in tasks) {
                expect_true(task.join().value());
            }
            expect_equal(session._pool._h2.count, 1);
            expect_equal(session._pool._take_h2(_http_origin_key(_http_parse_url(base).value())).value()._next_id, 23);

            session.close();
            expect_equal(session.idle_count, 0);
            expect_equal(session.get(base + "/hello?again").value().text(), "hello again");  # a new connection
        }
    );
}
