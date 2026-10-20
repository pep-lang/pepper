import async;
import http;
import io;
import text;

# `/shout` switches the connection to a made-up protocol that sends back
# every byte in upper case, until the client stops sending.
handle(request: http.Request): http.Response {
    if (!request.can_upgrade() || request.headers["upgrade"] != "shout") {
        return http.Response(400).set_text("send Upgrade: shout");
    }
    return http.Response().upgrade("shout", (connection) => {
        for (var chunk in connection.chunks(4096)) {
            connection.write_all(text.Utf8.decode_lossy(chunk.value()).upper().bytes());
        }
    });
}

main(): int {
    async.run(
        () => {
            var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var port = server.local_address().value().port();
            async.spawn<void>(() => {
                server.serve(handle);
            });
            var stream = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
            # The request head and the first bytes of the new protocol, together.
            stream.write_all(
                "GET /shout HTTP/1.1\r\nHost: localhost\r\nUpgrade: shout\r\nConnection: Upgrade\r\n\r\nhello".bytes()
            );
            stream.shutdown_write();
            var reply = Array<u8>();
            while (stream.read(reply, 4096).value() > 0) {}
            var reply_text = text.Utf8.decode_lossy(reply);
            assert(reply_text.starts_with("HTTP/1.1 101 Switching Protocols\r\n"), "switched");
            assert(reply_text.ends_with("\r\n\r\nHELLO"), "spoke the new protocol");
        }
    );
    return 0;
}
