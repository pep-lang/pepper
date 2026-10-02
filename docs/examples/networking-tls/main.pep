import async;
import io;
import tls;
import "test_certificate";

# A TLS server and client on this machine, in two tasks.
main(): int {
    var connector = tls.TlsConnector.create();
    if (connector.is_err()) {
        # On Windows, or where OpenSSL 3 is not installed.
        print(connector.error().message);
        return 0;
    }
    # A real server reads its certificate and key from files it was given.
    var certificate = io.Directory.temp().join("pepper-example-cert.pem");
    var key = io.Directory.temp().join("pepper-example-key.pem");
    io.File.write_text(certificate, test_certificate());
    io.File.write_text(key, test_private_key());

    async.run(
        () => {
            var acceptor = tls.TlsAcceptor.create(certificate, key).value();
            var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var port = listener.local_address().value().port();
            var server = async.Task<void>.spawn_local(() => {
                var (tcp, peer) = listener.accept().value();
                var stream = acceptor.accept(tcp).value();
                var request = Array<u8>();
                stream.read_exact(request, 4);
                stream.write_all("pong");
                stream.shutdown();
            });

            # The client trusts the test certificate as well as the system's.
            var client = connector.value();
            assert(client.add_root_certificate(certificate).is_ok(), "trust the test certificate");
            var stream = client.connect_host("localhost", port).value();
            stream.write_all("ping");
            var reply = Array<u8>();
            while (stream.read(reply, 4096).value() > 0) {}
            assert(reply.count == 4 && reply[0] == 'p' && reply[1] == 'o', "the reply is pong");
            server.join();
        }
    );
    io.File.remove(certificate);
    io.File.remove(key);
    return 0;
}
