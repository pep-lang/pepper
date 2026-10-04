# HTTP over loopback, in tasks: a server and clients in one program. The
# protocol cases (keep-alive, chunked bodies, HEAD, Expect: 100-continue,
# malformed requests) talk to the server over a raw TcpStream. HTTPS uses
# the test certificate in runtime/tls/test. A test that makes an
# http.Client first loads OpenSSL, which stays loaded for the program.

import async;
import http;
import io;
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
