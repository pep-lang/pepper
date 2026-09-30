//! HTTP (`runtime/http/`): a server and clients in one program over
//! loopback, in tasks. The protocol cases (keep-alive, chunked bodies,
//! `HEAD`, `Expect: 100-continue`, malformed requests) talk to the server
//! over a raw `TcpStream`. HTTPS uses the TLS tests' certificate and runs
//! where TLS does (Linux and macOS).

use crate::io_tests::{SIMULATED_HOSTS, assert_runs, with_codegen_as};
use crate::support;
use crate::tls_tests::with_test_certificate;

/// The server and client; `SECURE` is replaced with `true` where TLS runs.
const HTTP_PROGRAM: &str = r##"
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

# Sends `request` over a new raw connection, closes the sending side, and
# returns everything the server sent back.
raw(port: u16, request: u8[]): String {
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
    if (reply.count() == 0) {
        return "";
    }
    return String(reply._data as __ptr<char>, reply.count());
}

# Counts the occurrences of `needle` in `text`.
occurrences(text: String, needle: String): int {
    var count = 0;
    var rest = text;
    while (true) {
        var at = rest.find(needle);
        if (at < 0) {
            return count;
        }
        count = count + 1;
        rest = rest.substr_bytes(at as ulong + needle.size(), rest.size() - at as ulong - needle.size());
    }
    return count;
}

main(): int {
    async.Thread.current();
    tls.TlsConnector.create();
    var before = _pep_live_allocs();
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
        var port = server.local_address().value().port();
        async.spawn<void>(() => {
            server.serve(handle);
        });
        var base = "http://127.0.0.1:" + to_string(port);
        var client = http.Client();

        var hello = client.get(base + "/hello?name=pepper").value();
        assert(hello.status == 200 && hello.reason == "OK", "200 OK");
        assert(hello.text() == "hello name=pepper", "the handler saw the query");
        assert(hello.headers.get("content-type").value() == "text/plain", "header names ignore case");
        assert(hello.headers.get("Content-Length").value() == "17", "the server adds Content-Length");

        var missing = client.get(base + "/nowhere").value();
        assert(missing.status == 404 && missing.reason == "Not Found" && !missing.is_success(), "404");

        var request = http.Request("PUT", base + "/echo").set_text("payload");
        request.headers["X-Test"] = "yes";
        var echoed = client.send(request).value();
        assert(echoed.text() == "payload" && echoed.headers["X-Method"] == "PUT", "PUT with a body");
        var twice = echoed.headers.values("X-TWICE");
        assert(twice.count() == 2 && twice[0] == "one" && twice[1] == "two", "a repeated field keeps its values in order");
        assert(echoed.headers["x-missing"] == "" && !echoed.headers.has("x-missing"), "a missing field reads as empty");
        var asking = http.Request("GET", base + "/headers");
        asking.headers["X-Test"] = "custom";
        var custom = client.send(asking).value();
        assert(custom.text() == "custom", "request headers arrive");

        var big = Array<u8>();
        ulong i = 0;
        while (i < 300000) {
            big.append((i % 256) as u8);
            i = i + 1;
        }
        var large = client.send(http.Request("POST", base + "/echo").set_body(big)).value();
        assert(large.body().count() == 300000 && large.body()[299999] == big[299999], "a large binary body both ways");
        assert(large.text().size() > 300000, "text() replaces the bytes that are not UTF-8");

        var head = client.send(http.Request("HEAD", base + "/hello")).value();
        assert(head.status == 200 && head.body().count() == 0, "HEAD has no body");

        # Many clients at once.
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
            assert(task.join().value(), "every client got its answer");
        }

        # Keep-alive: two requests on one connection, the second asking to close.
        var two = Array<u8>();
        two.append_all("GET /hello?one HTTP/1.1\r\n".bytes());
        two.append_all("Host: localhost\r\n".bytes());
        two.append_all("\r\n".bytes());
        two.append_all("GET /hello?two HTTP/1.1\r\n".bytes());
        two.append_all("Host: localhost\r\n".bytes());
        two.append_all("Connection: close\r\n".bytes());
        two.append_all("\r\n".bytes());
        var both = raw(port, two);
        assert(occurrences(both, "HTTP/1.1 200 OK") == 2, "two responses on one connection");
        assert(both.contains("hello one") && both.contains("hello two"), "in order");
        assert(occurrences(both.lower(), "connection: close") == 1, "only the last one closes");

        # A chunked request body, with 100-continue.
        var chunked = Array<u8>();
        chunked.append_all("POST /echo HTTP/1.1\r\n".bytes());
        chunked.append_all("Host: localhost\r\n".bytes());
        chunked.append_all("Transfer-Encoding: chunked\r\n".bytes());
        chunked.append_all("Expect: 100-continue\r\n".bytes());
        chunked.append_all("Connection: close\r\n".bytes());
        chunked.append_all("\r\n".bytes());
        chunked.append_all("5\r\n".bytes());
        chunked.append_all("hello\r\n".bytes());
        chunked.append_all("7;name=value\r\n".bytes());
        chunked.append_all(" chunks\r\n".bytes());
        chunked.append_all("0\r\n".bytes());
        chunked.append_all("Trailer: ignored\r\n".bytes());
        chunked.append_all("\r\n".bytes());
        var reply = raw(port, chunked);
        assert(reply.starts_with("HTTP/1.1 100 Continue"), "100 Continue first");
        assert(reply.contains("HTTP/1.1 200 OK") && reply.contains("hello chunks"), "the chunks joined");

        var garbage = Array<u8>();
        garbage.append_all("NONSENSE\r\n".bytes());
        garbage.append_all("\r\n".bytes());
        assert(raw(port, garbage).starts_with("HTTP/1.1 400 Bad Request"), "a malformed request line");
        var unnamed = Array<u8>();
        unnamed.append_all("GET / HTTP/1.1\r\n".bytes());
        unnamed.append_all(": no name\r\n".bytes());
        unnamed.append_all("\r\n".bytes());
        assert(raw(port, unnamed).starts_with("HTTP/1.1 400 Bad Request"), "a field without a name");
        # A field value in Latin-1 (obs-text) is not UTF-8: it is read with
        # U+FFFD in place of the byte, not refused.
        var latin = "GET /headers HTTP/1.1\r\nX-Test: caf".bytes();
        latin.append(233);
        latin.append_all("\r\nConnection: close\r\n\r\n".bytes());
        var latin_reply = raw(port, latin);
        assert(latin_reply.starts_with("HTTP/1.1 200 OK"), "a Latin-1 field value");
        assert(latin_reply.ends_with("caf\u{FFFD}"), "the byte that is not UTF-8 becomes U+FFFD");
        var huge = Array<u8>();
        huge.append_all("GET / HTTP/1.1\r\n".bytes());
        var field = 0;
        while (field < 20) {
            huge.append_all(("X-Filler: " + "x".repeat(4000) + "\r\n").bytes());
            field = field + 1;
        }
        huge.append_all("\r\n".bytes());
        assert(raw(port, huge).starts_with("HTTP/1.1 431 Request Header Fields Too Large"), "header fields over 64 KiB");

        var bad_url = client.get("ftp://example.com/");
        assert(bad_url.is_err() && bad_url.error().is_invalid_input() && bad_url.error().message.contains("'ftp' is not supported"), "only http and https");
        var no_scheme = client.get("example.com/");
        assert(no_scheme.is_err() && no_scheme.error().is_invalid_input(), "a URL needs a scheme");
        var upper = client.get("HTTP://127.0.0.1:" + to_string(port) + "/hello");
        assert(upper.is_ok() && upper.value().status == 200, "schemes ignore case");
        var refused = client.get("http://127.0.0.1:1/");
        assert(refused.is_err(), "nothing listens on port 1");

        if (SECURE) {
            var secure_server = http.Server.bind_tls(io.SocketAddress(io.IpAddress.loopback_v4(), 0), tls.TlsAcceptor.create(io.Path("CERT_PATH"), io.Path("KEY_PATH")).value()).value();
            var secure_port = secure_server.local_address().value().port();
            async.spawn<void>(() => {
                secure_server.serve(handle);
            });
            var connector = tls.TlsConnector.create().value();
            connector.add_root_certificate(io.Path("CERT_PATH"));
            var secure = http.Client(connector);
            var r = secure.get("https://localhost:" + to_string(secure_port) + "/hello?over=tls").value();
            assert(r.status == 200 && r.text() == "hello over=tls", "HTTPS");
            var untrusted = client.get("https://localhost:" + to_string(secure_port) + "/");
            assert(untrusted.is_err() && untrusted.error().message.contains("certificate verify failed"), "HTTPS checks the certificate");
        } else {
            var no_tls = client.get("https://localhost/");
            assert(no_tls.is_err(), "no TLS here");
        }
    });
    assert(_pep_live_allocs() == before, "a run frees everything it allocated");
    return 0;
}
"##;

fn http_program() -> String {
    with_test_certificate("http", &HTTP_PROGRAM.replace("SECURE", "true"))
}

#[test]
fn http_over_loopback() {
    assert_runs("http_loopback", &http_program());
}

/// Every platform's build of the http module type-checks and produces valid
/// IR.
#[test]
fn http_program_compiles_on_other_platforms() {
    let source = HTTP_PROGRAM.replace("SECURE", "true");
    let failures: Vec<String> = support::parallel_map(&SIMULATED_HOSTS, |(os, arch)| {
        with_codegen_as(os, arch, "http_loopback", &source, |generator, module| {
            generator.generate(module).map_err(|d| module.sources.render(&d))?;
            generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
            Ok(())
        })
        .err()
        .map(|e| format!("{os}/{arch}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n\n"));
}
