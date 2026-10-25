# Checks the tls module and HTTPS on a phone, for scripts/mobile-test.sh:
#
#   tls_check <ca.pem> <host> <port> [https-url]
#
# A TLS server on <host>:<port> presents a certificate for `localhost` and
# 127.0.0.1 that <ca.pem> issued, chooses `http/1.1` through ALPN and answers
# `GET /` (`openssl s_server -www`). With an <https-url>, a public host is
# fetched too, through the system's roots. Exits 0 when every check passes.

import async;
import http;
import io;
import text;
import tls;

const failures = async.Atomic<int>(0);

check(ok: bool, what: String) {
    print($"{ok ? "ok" : "FAIL"} {what}");
    if (!ok) {
        failures.fetch_add(1);
    }
}

# Sends `GET /` over a TLS connection to `name` and returns the reply.
fetch(connector: tls.TlsConnector, name: String, port: u16): io.IoResult<String> {
    var tcp = io.TcpStream.connect_host(name, port);
    if (tcp.is_err()) {
        return io.IoResult<String>.err(tcp.error());
    }
    # A read that waits for data already sent fails rather than hanging.
    tcp.value().set_read_timeout(10000);
    var stream = connector.connect(tcp.value(), name);
    if (stream.is_err()) {
        return io.IoResult<String>.err(stream.error());
    }
    var tls_stream = stream.value();
    check(tls_stream.protocol() == Optional<String>.Value("http/1.1"), $"ALPN chose http/1.1 ({name})");
    var sent = tls_stream.write_all("GET / HTTP/1.0\r\n\r\n");
    if (sent.is_err()) {
        return io.IoResult<String>.err(sent.error());
    }
    var reply = Array<u8>();
    while (true) {
        var r = tls_stream.read(reply, 4096);
        if (r.is_err()) {
            return io.IoResult<String>.err(r.error());
        }
        if (r.value() == 0) {
            break;
        }
    }
    return io.IoResult<String>.ok(text.Utf8.decode_lossy(reply));
}

main(args: String[]): int {
    if (args.count < 4) {
        print("usage: tls_check <ca.pem> <host> <port> [https-url]");
        return 2;
    }
    var ca = io.Path(args[1]);
    var host = args[2];
    var port = ushort.parse(args[3]).value();

    var connector = tls.TlsConnector.create().value();
    check(connector.add_root_certificate(ca).is_ok(), "add the test CA");
    connector.set_protocols(["h2", "http/1.1"]).value();
    for (var name in [host, "127.0.0.1"]) {
        var reply = fetch(connector, name, port);
        if (reply.is_err()) {
            check(false, $"GET / from {name}: {reply.error().message}");
        } else {
            check(reply.value().starts_with("HTTP/1.0 200"), $"GET / from {name}");
        }
    }

    # Without the test CA the server is not trusted.
    var untrusting = tls.TlsConnector.create().value();
    var refused = untrusting.connect_host(host, port);
    check(
        refused.is_err() && refused.error().message.starts_with("certificate verify failed"),
        $"an unknown CA is refused ({refused.is_err() ? refused.error().message : "connected"})"
    );

    # http.Client over the same connector.
    var client = http.Client(connector);
    var response = client.get($"https://{host}:{port}/");
    check(
        response.is_ok() && response.value().status == 200,
        $"http.Client GET ({response.is_err() ? response.error().message : "ok"})"
    );

    if (args.count > 4) {
        var public_response = http.Client().get(args[4]);
        check(
            public_response.is_ok() && public_response.value().status == 200,
            $"http.Client GET {args[4]} ({public_response.is_err() ? public_response.error().message : "ok"})"
        );
    }
    return failures.load() == 0 ? 0 : 1;
}
