# HTTP over loopback, in tasks: a server and clients in one program. The
# protocol cases (keep-alive, chunked bodies, HEAD, Expect: 100-continue,
# malformed requests) talk to the server over a raw TcpStream. HTTPS uses
# the test certificate in runtime/tls/test. A test that makes an
# http.Client first loads OpenSSL, which stays loaded for the program.

import async;
import http;
import io;
import math;
import os;
import tls;

handle(request: http.Request): http.Response {
    var path = request.path();
    if (path == "/echo") {
        var response = http.Response(200).set_body(request.body());
        response.headers["Content-Type"] = "application/octet-stream";
        response.headers["X-Method"] = request.method;
        response.headers.add("X-Twice", "one");
        response.headers.add("x-twice", "two");
        return response;
    }
    if (path == "/hello") {
        var greeting = http.Response(200).set_text("hello " + request.query());
        greeting.headers["Content-Type"] = "text/plain";
        return greeting;
    }
    if (path == "/headers") {
        return http.Response(200).set_text(request.headers["x-test"]);
    }
    if (path == "/stream") {
        # A body of unknown length from a stream: sent chunked.
        return http.Response(200).set_reader(io.ByteReader(pattern(1000000)));
    }
    if (path == "/stream-length") {
        return http.Response(200).set_reader(io.ByteReader(pattern(100000)), 100000);
    }
    if (path.starts_with("/redirect/")) {
        # `/redirect/N` redirects N more times, then arrives.
        var left = math.parse_int(path.substr_bytes(10, path.size - 10)).value();
        if (left == 0) {
            return http.Response(200).set_text("arrived");
        }
        return redirect(302, "/redirect/" + to_string(left - 1));
    }
    if (path == "/to") {
        # `/to?STATUS%20LOCATION` redirects to LOCATION with that status.
        var parts = request.query().split("%20");
        return redirect(math.parse_int(parts[0]).value() as int, parts[1]);
    }
    if (path == "/cross") {
        # The same server under another host name: another origin.
        var port = request.headers["host"].substr_bytes(10, request.headers["host"].size - 10);
        return redirect(302, "http://localhost:" + port + "/auth");
    }
    if (path == "/auth") {
        return http.Response(200).set_text(
            request.headers["authorization"] + "|" + request.headers["cookie"] + "|" + request.headers["x-test"]
        );
    }
    if (path == "/upgrade") {
        # Takes the connection over and echoes every byte back.
        var upgraded = http.Response().upgrade("echo", (connection) => {
            for (var chunk in connection.chunks(4096)) {
                if (chunk.is_err() || connection.write_all(chunk.value()).is_err()) {
                    break;
                }
            }
        });
        upgraded.headers["X-Protocol"] = "echo";
        return upgraded;
    }
    if (path == "/inject") {
        # A field built from the query, as a redirect target often is.
        var injected = http.Response(303);
        var query = request.query();
        if (query == "cr") {
            injected.headers["Location"] = "/next\r\nSet-Cookie: admin=1";
        } else if (query == "lf") {
            injected.headers["Location"] = "/next\nSet-Cookie: admin=1";
        } else if (query == "name") {
            injected.headers["Set-Cookie: admin=1\r\nX"] = "y";
        } else {
            injected.reason = "See Other\r\nSet-Cookie: admin=1";
        }
        return injected;
    }
    if (path == "/framing") {
        var framing = request.headers["transfer-encoding"] + "|" + request.headers["content-length"];
        return http.Response(200).set_text(framing + "|" + to_string(request.body().count));
    }
    return http.Response(404).set_text("no page at " + path);
}

# Starts a server on a port of its own in the running `async.run`, and
# returns its base URL. It stops when `async.run` ends.
start_server(): String {
    var server = http.Server.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
    var port = server.local_address().value().port();
    async.spawn<void>(() => {
        server.serve(handle);
    });
    return "http://127.0.0.1:" + to_string(port);
}

# The port of a base URL `start_server` returned.
port_of(base: String): u16 {
    return Uri.parse(base).value().port.value();
}

# Sends `request` over a new raw connection, closes the sending side, and
# returns everything the server sent back.
raw(port: u16, request: String): String {
    return raw_bytes(port, request.bytes());
}

raw_bytes(port: u16, request: u8[]): String {
    var stream = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
    stream.write_all(request);
    stream.shutdown_write();
    var reply = Array<u8>();
    while (true) {
        var r = stream.read(reply, 4096);
        if (r.is_err() || r.value() == 0) {
            break;
        }
    }
    return String._from_bytes(reply);
}

redirect(status: int, location: String): http.Response {
    var response = http.Response(status).set_text("moved");
    response.headers["Location"] = location;
    return response;
}

# `count` bytes counting up from 0, wrapping at 251 so the pattern does
# not line up with any power-of-two chunk size.
pattern(count: ulong): u8[] {
    var bytes = Array<u8>(count);
    ulong i = 0;
    while (i < count) {
        bytes.append((i % 251) as u8);
        i = i + 1;
    }
    return bytes;
}

# Counts the occurrences of `needle` in `text`.
occurrences(text: String, needle: String): int {
    return text.split(needle).count as int - 1;
}

[Test]
get_put_and_head_over_loopback() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var base = start_server();
            var client = http.Client();

            var hello = client.get(base + "/hello?name=pepper").value();
            expect_equal(hello.status, 200);
            expect_equal(hello.reason, "OK");
            expect_equal(hello.text(), "hello name=pepper");                        # the handler saw the query
            expect_equal(hello.headers.get("content-type").value(), "text/plain");  # names ignore case
            expect_equal(hello.headers.get("Content-Length").value(), "17");        # the server adds it

            var missing = client.get(base + "/nowhere").value();
            expect_equal(missing.status, 404);
            expect_equal(missing.reason, "Not Found");
            expect_false(missing.is_success());

            var request = http.Request("PUT", base + "/echo").set_text("payload");
            request.headers["X-Test"] = "yes";
            var echoed = client.send(request).value();
            expect_equal(echoed.text(), "payload");
            expect_equal(echoed.headers["X-Method"], "PUT");
            # A repeated field keeps its values in order.
            var twice = echoed.headers.values("X-TWICE");
            expect_equal(twice.count, 2);
            expect_equal(twice[0], "one");
            expect_equal(twice[1], "two");
            # A missing field reads as empty.
            expect_equal(echoed.headers["x-missing"], "");
            expect_false(echoed.headers.has("x-missing"));
            var asking = http.Request("GET", base + "/headers");
            asking.headers["X-Test"] = "custom";
            expect_equal(client.send(asking).value().text(), "custom");

            var big = Array<u8>();
            ulong i = 0;
            while (i < 300000) {
                big.append((i % 256) as u8);
                i = i + 1;
            }
            var large = client.send(http.Request("POST", base + "/echo").set_body(big)).value();
            expect_equal(large.body().count, 300000);
            expect_equal(large.body()[299999], big[299999]);
            expect_true(large.text().size > 300000);  # text() replaces the bytes that are not UTF-8

            var head = client.send(http.Request("HEAD", base + "/hello")).value();
            expect_equal(head.status, 200);
            expect_equal(head.body().count, 0);
        }
    );
}

[Test]
many_clients_at_once() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var port = port_of(start_server());
            var tasks = Array<async.Task<bool>>();
            var n = 0;
            while (n < 16) {
                tasks.append(async.spawn<bool>(() => {
                    var c = http.Client();
                    var r = c.post("http://127.0.0.1:" + to_string(port) + "/echo", "text/plain", "task");
                    return r.is_ok() && r.value().text() == "task";
                }));
                n = n + 1;
            }
            for (var task in tasks) {
                expect_true(task.join().value());  # every client got its answer
            }
        }
    );
}

[Test]
keep_alive_and_chunked_requests() {
    async.run(
        () => {
            var port = port_of(start_server());
            # Two requests on one connection, the second asking to close.
            var both = raw(
                port,
                "GET /hello?one HTTP/1.1\r\nHost: localhost\r\n\r\n"
                    + "GET /hello?two HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
            );
            expect_equal(occurrences(both, "HTTP/1.1 200 OK"), 2);
            expect_true(both.contains("hello one"));
            expect_true(both.contains("hello two"));
            expect_true(both.find("hello one") < both.find("hello two"));
            expect_equal(occurrences(both.lower(), "connection: close"), 1);  # only the last one closes

            # A chunked request body, with 100-continue.
            var reply = raw(
                port,
                "POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n"
                    + "Expect: 100-continue\r\nConnection: close\r\n\r\n"
                    + "5\r\nhello\r\n7;name=value\r\n chunks\r\n0\r\nTrailer: ignored\r\n\r\n"
            );
            expect_true(reply.starts_with("HTTP/1.1 100 Continue"));
            expect_true(reply.contains("HTTP/1.1 200 OK"));
            expect_true(reply.contains("hello chunks"));  # the chunks joined
        }
    );
}

# Upgrades the connection `reader` and `writer` reach with `/upgrade`, and
# checks the 101 head and the echo of bytes sent with the request head and
# after the 101.
expect_upgrade_echoes(reader: io.Reader, writer: io.Writer) {
    # The first bytes of the new protocol travel with the request head.
    writer.write_all(
        "GET /upgrade HTTP/1.1\r\nHost: localhost\r\nUpgrade: echo\r\nConnection: Upgrade\r\n\r\nearly".bytes()
    );
    var reply = Array<u8>();
    while (!String._from_bytes(reply).ends_with("early")) {
        expect_true(reader.read(reply, 4096).value() > 0);
    }
    writer.write_all(" late".bytes());
    while (!String._from_bytes(reply).ends_with("early late")) {
        expect_true(reader.read(reply, 4096).value() > 0);
    }
    var text = String._from_bytes(reply);
    expect_true(text.starts_with("HTTP/1.1 101 Switching Protocols\r\n"));
    var lower = text.lower();
    expect_true(lower.contains("upgrade: echo\r\n"));
    expect_true(lower.contains("connection: upgrade\r\n"));
    expect_true(lower.contains("x-protocol: echo\r\n"));
    expect_false(lower.contains("content-length"));
    expect_true(text.ends_with("\r\n\r\nearly late"));  # raw bytes, not HTTP, after the head
}

[Test]
a_handler_takes_over_the_connection_after_101() {
    async.run(
        () => {
            var port = port_of(start_server());
            var stream = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
            expect_upgrade_echoes(stream, stream);
            # The client's end of the stream ends the handler's echo, and the
            # server closes the connection.
            stream.shutdown_write();
            expect_equal(stream.read(Array<u8>(), 4096).value(), 0);

            # HTTP/1.0 cannot switch protocols: the upgrade becomes a 501.
            expect_true(raw(port, "GET /upgrade HTTP/1.0\r\n\r\n").starts_with("HTTP/1.1 501 Not Implemented"));
        }
    );
}

[Test]
a_handler_takes_over_a_tls_connection_after_101() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var certificate = io.Path("tls/test/certificate.pem");
            var acceptor = tls.TlsAcceptor.create(certificate, io.Path("tls/test/key.pem")).value();
            var server = http.Server.bind_tls(io.SocketAddress(io.IpAddress.loopback_v4(), 0), acceptor).value();
            var port = server.local_address().value().port();
            async.spawn<void>(() => {
                server.serve(handle);
            });
            var connector = tls.TlsConnector.create().value();
            connector.add_root_certificate(certificate);
            # No ALPN offer, so the server speaks HTTP/1.1, which can upgrade.
            var tcp = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
            var stream = connector.connect(tcp, "localhost").value();
            expect_upgrade_echoes(stream, stream);
            stream.shutdown();
            stream.close();
        }
    );
}

[Test]
malformed_requests_get_an_error_status() {
    async.run(
        () => {
            var port = port_of(start_server());
            expect_true(raw(port, "NONSENSE\r\n\r\n").starts_with("HTTP/1.1 400 Bad Request"));
            # A field without a name.
            expect_true(raw(port, "GET / HTTP/1.1\r\n: no name\r\n\r\n").starts_with("HTTP/1.1 400 Bad Request"));
            # A field value in Latin-1 (obs-text) is not UTF-8: it is read with
            # U+FFFD in place of the byte, not refused.
            var latin = "GET /headers HTTP/1.1\r\nX-Test: caf".bytes();
            latin.append(233);
            latin.append_all("\r\nConnection: close\r\n\r\n".bytes());
            var latin_reply = raw_bytes(port, latin);
            expect_true(latin_reply.starts_with("HTTP/1.1 200 OK"));
            expect_true(latin_reply.ends_with("caf\u{FFFD}"));
            # Header fields over 64 KiB.
            var huge = "GET / HTTP/1.1\r\n";
            var field = 0;
            while (field < 20) {
                huge = huge + "X-Filler: " + "x".repeat(4000) + "\r\n";
                field = field + 1;
            }
            huge = huge + "\r\n";
            expect_true(raw(port, huge).starts_with("HTTP/1.1 431 Request Header Fields Too Large"));
        }
    );
}

[Test]
server_refuses_fields_that_would_split_the_response() {
    async.run(
        () => {
            var port = port_of(start_server());
            # The 500's body says what was wrong.
            var because = [
                "the value of the field 'location' holds CR, LF or NUL",
                "the value of the field 'location' holds CR, LF or NUL",
                "a field name is not a token",
                "the reason phrase holds CR, LF or NUL",
            ];
            ulong i = 0;
            for (var query in ["cr", "lf", "name", "reason"]) {
                var reply = raw(port, "GET /inject?" + query + " HTTP/1.1\r\nConnection: close\r\n\r\n");
                expect_true(reply.starts_with("HTTP/1.1 500 Internal Server Error"));
                expect_false(reply.lower().contains("set-cookie"));
                expect_true(reply.ends_with("\r\n\r\nthe response cannot be sent: " + because[i]));
                i += 1;
            }
        }
    );
}

[Test]
client_refuses_fields_that_would_split_the_request() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var base = start_server();
            var client = http.Client();
            var cr = http.Request("GET", base + "/headers");
            cr.headers["X-Test"] = "a\r\nSet-Cookie: admin=1";
            var lf = http.Request("GET", base + "/headers");
            lf.headers["X-Test"] = "a\nSet-Cookie: admin=1";
            var nul = http.Request("GET", base + "/headers");
            nul.headers["X-Test"] = "a" + String._from_bytes([0 as u8]) + "b";
            var name = http.Request("GET", base + "/headers");
            name.headers["X Test"] = "a";
            var method = http.Request("GET /x", base + "/headers");
            for (var request in [cr, lf, nul, name, method]) {
                var sent = client.send(request);
                expect_true(sent.is_err());
                expect_true(sent.error().is_invalid_input());
            }
            var fine = http.Request("GET", base + "/headers");
            fine.headers["X-Test"] = "a\tb";  # a tab is allowed
            expect_equal(client.send(fine).value().text(), "a\tb");
        }
    );
}

[Test]
client_checks_the_url() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var port = port_of(start_server());
            var client = http.Client();
            var bad_url = client.get("ftp://example.com/");
            expect_true(bad_url.is_err());
            expect_true(bad_url.error().is_invalid_input());
            expect_true(bad_url.error().message.contains("'ftp' is not supported"));
            var no_scheme = client.get("example.com/");
            expect_true(no_scheme.is_err());
            expect_true(no_scheme.error().is_invalid_input());
            var upper = client.get("HTTP://127.0.0.1:" + to_string(port) + "/hello");
            expect_true(upper.is_ok());  # schemes ignore case
            expect_equal(upper.value().status, 200);
            expect_true(client.get("http://127.0.0.1:1/").is_err());  # nothing listens on port 1
        }
    );
}

[Test]
https_over_loopback() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var certificate = io.Path("tls/test/certificate.pem");
            var acceptor = tls.TlsAcceptor.create(certificate, io.Path("tls/test/key.pem")).value();
            var server = http.Server.bind_tls(io.SocketAddress(io.IpAddress.loopback_v4(), 0), acceptor).value();
            var port = server.local_address().value().port();
            async.spawn<void>(() => {
                server.serve(handle);
            });
            var connector = tls.TlsConnector.create().value();
            connector.add_root_certificate(certificate);
            var secure = http.Client(connector);
            var r = secure.get("https://localhost:" + to_string(port) + "/hello?over=tls").value();
            expect_equal(r.status, 200);
            expect_equal(r.text(), "hello over=tls");
            var untrusted = http.Client().get("https://localhost:" + to_string(port) + "/");
            expect_true(untrusted.is_err());  # HTTPS checks the certificate
            expect_true(untrusted.error().message.contains("certificate verify failed"));
        }
    );
}

[Test]
streamed_bodies_both_ways() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var base = start_server();
            var client = http.Client();

            # A chunked response read as it arrives, in small reads.
            var opened = client.open(http.Request("GET", base + "/stream")).value();
            expect_equal(opened.status, 200);
            expect_equal(opened.headers["transfer-encoding"], "chunked");
            expect_false(opened.headers.has("content-length"));
            expect_equal(opened.body().count, 0);  # not read yet
            var source = opened.reader();
            var got = Array<u8>();
            while (true) {
                var read = source.read(got, 7777);
                expect_true(read.is_ok());
                if (read.value() == 0) {
                    break;
                }
            }
            expect_true(got == pattern(1000000));

            # A streamed response of known length gets Content-Length.
            var sized = client.open(http.Request("GET", base + "/stream-length")).value();
            expect_equal(sized.headers["content-length"], "100000");
            var total: ulong = 0;
            for (var chunk in sized.reader().chunks(4096)) {
                total = total + chunk.value().count;
            }
            expect_equal(total, 100000 as ulong);

            # send() still reads a streamed response in full.
            var whole = client.get(base + "/stream").value();
            expect_true(whole.body() == pattern(1000000));
            # reader() over an in-memory body.
            var again = Array<u8>();
            whole.reader().read(again, 10);
            expect_equal(again.count, 10 as ulong);

            # A request body from a stream: chunked without a length.
            var upload = client.send(
                http.Request("PUT", base + "/echo").set_reader(io.ByteReader(pattern(300000)))
            ).value();
            expect_true(upload.body() == pattern(300000));
            var chunked = client.send(
                http.Request("POST", base + "/framing").set_reader(io.ByteReader(pattern(10)))
            ).value();
            expect_equal(chunked.text(), "chunked||10");
            var sized_upload = http.Request("POST", base + "/framing").set_reader(io.ByteReader(pattern(10)), 10);
            expect_equal(client.send(sized_upload).value().text(), "|10|10");
            # A source shorter than its length fails the request.
            var short = http.Request("POST", base + "/framing").set_reader(io.ByteReader(pattern(5)), 10);
            expect_true(client.send(short).is_err());
        }
    );
}

[Test]
closing_a_streamed_body_early() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var base = start_server();
            var client = http.Client();
            var opened = client.open(http.Request("GET", base + "/stream")).value();
            var body = (opened.reader() as? http.BodyReader).value();
            var some = Array<u8>();
            expect_true(body.read(some, 100).value() > 0);
            expect_false(body.is_done);
            body.close();
            expect_true(body.is_done);
            expect_equal(body.read(some, 100).value(), 0 as ulong);  # reads as the end
            # The server is still serving.
            expect_equal(client.get(base + "/hello?after").value().text(), "hello after");
            # A body read to its end is done.
            var head = client.open(http.Request("HEAD", base + "/hello")).value();
            var empty = Array<u8>();
            expect_equal(head.reader().read(empty, 10).value(), 0 as ulong);
        }
    );
}

[Test]
streamed_responses_to_http_1_0() {
    async.run(
        () => {
            var port = port_of(start_server());
            # HTTP/1.0 has no chunks: the body goes unframed and the server closes.
            var reply = raw(port, "GET /stream HTTP/1.0\r\n\r\n");
            expect_true(reply.starts_with("HTTP/1.1 200 OK"));
            expect_false(reply.lower().contains("transfer-encoding"));
            expect_true(reply.lower().contains("connection: close"));
            var keep = raw(port, "GET /stream HTTP/1.1\r\nConnection: close\r\n\r\n");
            expect_true(keep.lower().contains("transfer-encoding: chunked"));
            expect_true(keep.ends_with("\r\n0\r\n\r\n"));
        }
    );
}

[Test]
follows_redirects() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var base = start_server();
            var client = http.Client();

            var chain = client.get(base + "/redirect/3").value();
            expect_equal(chain.status, 200);
            expect_equal(chain.text(), "arrived");
            expect_equal(chain.url, base + "/redirect/0");  # where it ended up
            # A relative Location resolves against the request's URL.
            var relative = client.get(base + "/to?302%20hello?near").value();
            expect_equal(relative.text(), "hello near");

            # 307 and 308 repeat the method and body.
            for (var status in [307, 308]) {
                var request = http.Request("PUT", base + "/to?" + to_string(status) + "%20/echo").set_text("again");
                var kept = client.send(request).value();
                expect_equal(kept.headers["x-method"], "PUT");
                expect_equal(kept.text(), "again");
            }
            # 303 becomes a GET without the body, and so do 301 and 302 after a POST.
            for (var status in [301, 302, 303]) {
                var posted = client.post(base + "/to?" + to_string(status) + "%20/echo", "text/plain", "gone").value();
                expect_equal(posted.headers["x-method"], "GET");
                expect_equal(posted.body().count, 0 as ulong);
            }
            # A 302 after a PUT keeps the method.
            var put = client.send(http.Request("PUT", base + "/to?302%20/echo").set_text("put")).value();
            expect_equal(put.headers["x-method"], "PUT");

            # A streamed body cannot be sent again: the 307 comes back.
            var streamed = http.Request("PUT", base + "/to?307%20/echo").set_reader(io.ByteReader("once".bytes()));
            expect_equal(client.send(streamed).value().status, 307);

            # Credentials go along within the origin, not to another.
            var same = http.Request("GET", base + "/to?302%20/auth");
            same.headers["Authorization"] = "Bearer secret";
            same.headers["Cookie"] = "a=1";
            same.headers["X-Test"] = "kept";
            expect_equal(client.send(same).value().text(), "Bearer secret|a=1|kept");
            var cross = http.Request("GET", base + "/cross");
            cross.headers["Authorization"] = "Bearer secret";
            cross.headers["Cookie"] = "a=1";
            cross.headers["X-Test"] = "kept";
            var crossed = client.send(cross).value();
            expect_true(crossed.url.starts_with("http://localhost:"));
            expect_equal(crossed.text(), "||kept");

            # A limit, and opting out.
            var looping = client.get(base + "/redirect/11");
            expect_true(looping.is_err());
            expect_true(looping.error().message.contains("too many redirects"));
            expect_equal(http.Client(11).get(base + "/redirect/11").value().text(), "arrived");
            var unfollowed = http.Client(0).get(base + "/redirect/1").value();
            expect_equal(unfollowed.status, 302);
            expect_equal(unfollowed.headers["location"], "/redirect/0");
            expect_equal(unfollowed.text(), "moved");
            # open() follows too, and streams the last body.
            var opened = client.open(http.Request("GET", base + "/redirect/2")).value();
            var arrived = Array<u8>();
            opened.reader().read(arrived, 100);
            expect_equal(String._from_bytes(arrived), "arrived");
        }
    );
}

# A raw HTTP server for connection reuse: it counts the connections it
# accepts and answers every request on them with `ok`. With `close_after`
# it closes each connection after one response without saying so, as a
# server that drops idle connections does; with `say_close` it sends
# `Connection: close` and closes.
struct CountingServer {
    var port: u16;
    var accepted: async.Atomic<int>;

    construct(port: u16, accepted: async.Atomic<int>) {
        this.port = port;
        this.accepted = accepted;
    }

    base(): String {
        return "http://127.0.0.1:" + to_string(port);
    }
}

start_counting_server(close_after: bool, say_close: bool): CountingServer {
    var listener = io.SharedTcpListener.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
    var port = listener.local_address().value().port();
    var accepted = async.Atomic<int>(0);
    async.spawn<void>(() => {
        while (true) {
            var next = listener.accept();
            if (next.is_err()) {
                return;
            }
            accepted.fetch_add(1);
            var (stream, peer) = next.value();
            async.Task<void>.spawn_local(() => {
                var pending = "";
                while (true) {
                    var data = Array<u8>();
                    var read = stream.read(data, 4096);
                    if (read.is_err() || read.value() == 0) {
                        return;
                    }
                    pending = pending + String._from_bytes(data);
                    while (pending.contains("\r\n\r\n")) {
                        var end = pending.find("\r\n\r\n") as ulong + 4;
                        pending = pending.substr_bytes(end, pending.size - end);
                        var extra = say_close ? "Connection: close\r\n" : "";
                        stream.write_all(("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n" + extra + "\r\nok").bytes());
                        if (close_after || say_close) {
                            stream.close();
                            return;
                        }
                    }
                }
            });
        }
    });
    return CountingServer(port, accepted);
}

[Test]
sessions_reuse_connections() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var server = start_counting_server(false, false);
            var session = http.Client().session();
            for (var i in 0..3) {
                expect_equal(session.get(server.base() + "/").value().text(), "ok");
            }
            expect_equal(server.accepted.load(), 1);  # one connection carried all three
            expect_equal(session.idle_count, 1 as ulong);
            # A streamed body gives its connection back once read to its end.
            var opened = session.open(http.Request("GET", server.base() + "/")).value();
            expect_equal(session.idle_count, 0 as ulong);  # in use
            var body = Array<u8>();
            while (opened.reader().read(body, 1).value() > 0) {}
            expect_equal(session.idle_count, 1 as ulong);
            # Closed early, it is not reused.
            var early = session.open(http.Request("GET", server.base() + "/")).value();
            (early.reader() as? http.BodyReader).value().close();
            expect_equal(session.idle_count, 0 as ulong);
            expect_equal(session.get(server.base() + "/").value().text(), "ok");
            expect_equal(server.accepted.load(), 2);
            session.close();
            expect_equal(session.idle_count, 0 as ulong);

            # A plain Client keeps nothing.
            var client = http.Client();
            client.get(server.base() + "/");
            client.get(server.base() + "/");
            expect_equal(server.accepted.load(), 4);

            # Requests that redirect within one origin share the connection.
            var base = start_server();
            var redirecting = http.Client().session();
            expect_equal(redirecting.get(base + "/redirect/3").value().text(), "arrived");
            expect_equal(redirecting.idle_count, 1 as ulong);
        }
    );
}

[Test]
sessions_drop_connections_the_server_closes() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            # The server says close: nothing is kept.
            var closing = start_counting_server(false, true);
            var session = http.Client().session();
            expect_equal(session.get(closing.base() + "/").value().text(), "ok");
            expect_equal(session.idle_count, 0 as ulong);

            # The server closes without saying so: the next request finds the
            # connection closed and is sent again on a new one.
            var dropping = start_counting_server(true, false);
            expect_equal(session.get(dropping.base() + "/").value().text(), "ok");
            expect_equal(session.idle_count, 1 as ulong);
            async.sleep(os.Duration.from_milliseconds(20));
            expect_equal(session.get(dropping.base() + "/").value().text(), "ok");
            expect_equal(dropping.accepted.load(), 2);
            # A streamed body cannot be sent again, so that request fails.
            async.sleep(os.Duration.from_milliseconds(20));
            var streamed = http.Request("PUT", dropping.base() + "/").set_reader(io.ByteReader("once".bytes()));
            expect_true(session.send(streamed).is_err());

            # An idle timeout and a limit of 0.
            var server = start_counting_server(false, false);
            var timed = http.Client().session();
            timed.idle_timeout = os.Duration.from_nanoseconds(1);
            timed.get(server.base() + "/");
            timed.get(server.base() + "/");
            expect_equal(server.accepted.load(), 2);
            var none = http.Client().session();
            none.max_idle_per_host = 0;
            none.get(server.base() + "/");
            expect_equal(none.idle_count, 0 as ulong);
        }
    );
}
