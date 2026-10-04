# TLS over loopback, in tasks: clients talk to an echo server that accepts on
# every worker; then the failures: an untrusted certificate, a name the
# certificate is not for, a missing root file, a key given as a certificate.
#
# certificate.pem and key.pem beside this file are a self-signed certificate
# (EC P-256, valid until 2126) for `localhost` and `127.0.0.1`, and its key.
# They are for these tests only: the key is public. The http tests use them
# too. Each test first loads OpenSSL, which stays loaded for the program.

import async;
import io;
import tls;

certificate(): io.Path {
    return io.Path("tls/test/certificate.pem");
}

key(): io.Path {
    return io.Path("tls/test/key.pem");
}

# Starts an echo server that accepts on every worker of the running
# `async.run`, and returns its port. It stops when `async.run` ends.
start_echo_server(): u16 {
    var listener = io.SharedTcpListener.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
    var acceptor = tls.TlsAcceptor.create(certificate(), key()).value();
    async.spawn_on_each_worker(
        () => {
            while (true) {
                var accepted = listener.accept();
                if (accepted.is_err()) {
                    return;
                }
                var (tcp, peer) = accepted.value();
                # The connection belongs to this worker: serve it here.
                async.Task<void>.spawn_local(() => {
                    var handshake = acceptor.accept(tcp);
                    if (handshake.is_err()) {
                        return;
                    }
                    var stream = handshake.value();
                    var buffer = Array<u8>();
                    while (true) {
                        var r = stream.read(buffer, 4096);
                        if (r.is_err() || r.value() == 0) {
                            break;
                        }
                        stream.write_all(buffer);
                        buffer.clear();
                    }
                    stream.shutdown();
                });
            }
        }
    );
    return listener.local_address().value().port();
}

# Sends `rounds` messages over TLS and checks each echo.
client(connector: tls.TlsConnector, port: u16, host: String, rounds: int): bool {
    var tcp = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
    var stream = connector.connect(tcp, host).value();
    var message = Array<u8>();
    ulong i = 0;
    while (i < 1000) {
        message.append((i % 251) as u8);
        i = i + 1;
    }
    var round = 0;
    while (round < rounds) {
        if (stream.write_all(message).is_err()) {
            return false;
        }
        var echo = Array<u8>();
        if (stream.read_exact(echo, 1000).is_err() || echo != message) {
            return false;
        }
        round = round + 1;
    }
    stream.shutdown();
    var rest = Array<u8>();
    return stream.read(rest, 16).value() == 0;
}

[Test]
tls_echoes_over_loopback() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    async.run(
        () => {
            var port = start_echo_server();
            var connector = tls.TlsConnector.create().value();
            var untrusted = connector.connect_host("localhost", port);
            expect_true(untrusted.is_err());  # a self-signed certificate is not trusted by default
            expect_true(untrusted.error().message.contains("certificate verify failed"));
            expect_true(connector.add_root_certificate(certificate()).is_ok());

            var tasks = Array<async.Task<bool>>();
            var n = 0;
            while (n < 8) {
                # Half the clients name the server by its address.
                var by_address = n % 2 == 1;
                tasks.append(async.spawn<bool>(() => {
                    var host = "localhost";
                    if (by_address) {
                        host = "127.0.0.1";
                    }
                    return client(connector, port, host, 20);
                }));
                n = n + 1;
            }
            for (var task in tasks) {
                expect_true(task.join().value());  # every client got its echoes
            }

            var tcp = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
            var wrong = connector.connect(tcp, "example.com");
            expect_true(wrong.is_err());  # a name the certificate is not for
            expect_true(wrong.error().message.contains("certificate verify failed"));
        }
    );
}

[Test]
tls_reports_bad_certificate_files() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    var connector = tls.TlsConnector.create().value();
    expect_true(connector.add_root_certificate(io.Path("tls/test/missing.pem")).is_err());
    expect_true(tls.TlsAcceptor.create(key(), key()).is_err());  # a key is not a certificate
}
