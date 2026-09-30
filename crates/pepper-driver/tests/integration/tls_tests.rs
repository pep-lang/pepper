//! TLS (`runtime/tls/`): a client and a server over loopback, in tasks,
//! with a self-signed test certificate for `localhost` and `127.0.0.1`. The
//! harness writes the certificate and key to a directory of its own and
//! puts their paths into the program.
//!
//! OpenSSL 3 must be installed on Linux and macOS; Windows uses SChannel.
//! `tls_programs_compile_on_other_platforms` checks every platform's layer.

use crate::io_tests::{SIMULATED_HOSTS, assert_runs, with_codegen_as};
use crate::support;

/// A self-signed certificate (EC P-256, valid until 2126) for `localhost`
/// and `127.0.0.1`, and its key. For these tests only: the key is public.
const TEST_CERTIFICATE: &str = r"-----BEGIN CERTIFICATE-----
MIIBmzCCAUGgAwIBAgIURcyG8LECUkGDUQnq4wr2SyTfH8AwCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MDkzMDE2MDQwNloYDzIxMjYwOTA2
MTYwNDA2WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAAS6V7/9e1PZ6ah6/2Ej6VCR+fwGBGQ33SdVFy0ggLp4p0dlV9k0tvFT
yPJdkPr/sZ+5l02208ogHnk9sONf8/PVo28wbTAdBgNVHQ4EFgQUFl1HIAbN3VXx
j/en9RLR2QoN2PYwHwYDVR0jBBgwFoAUFl1HIAbN3VXxj/en9RLR2QoN2PYwGgYD
VR0RBBMwEYIJbG9jYWxob3N0hwR/AAABMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZI
zj0EAwIDSAAwRQIhAPw/RhZDgoHFZkEOEAzOQazJ4l3RoKVRNYS9XyrOkIceAiB3
IHZxDB0uoD4leOOsxQzN4uNXDZwjhLCJUHySFW9ctA==
-----END CERTIFICATE-----";
const TEST_KEY: &str = r"-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgZ9o1y2mmE2xdq/8M
DnvBSs61u+Getq5MzQ7gMuKHfZChRANCAAS6V7/9e1PZ6ah6/2Ej6VCR+fwGBGQ3
3SdVFy0ggLp4p0dlV9k0tvFTyPJdkPr/sZ+5l02208ogHnk9sONf8/PV
-----END PRIVATE KEY-----";

/// Clients in tasks talk to an echo server that accepts on every worker;
/// then the failures: an untrusted certificate, a name the certificate is
/// not for, a TLS client against a plain server. Checks for leaks.
const TLS_PROGRAM: &str = r##"
import async;
import io;
import tls;

certificate(): io.Path {
    return io.Path("CERT_PATH");
}

key(): io.Path {
    return io.Path("KEY_PATH");
}

# A task that sends `rounds` messages over TLS and checks each echo.
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
        if (stream.read_exact(echo, 1000).is_err()) {
            return false;
        }
        ulong j = 0;
        while (j < 1000) {
            if (echo[j] != message[j]) {
                return false;
            }
            j = j + 1;
        }
        round = round + 1;
    }
    stream.shutdown();
    var rest = Array<u8>();
    return stream.read(rest, 16).value() == 0;
}

main(): int {
    # Warm up lazily allocated state: the main thread's Thread, and the
    # OpenSSL functions the first connector loads.
    async.Thread.current();
    tls.TlsConnector.create();
    var before = _pep_live_allocs();
    async.run(() => {
        var listener = io.SharedTcpListener.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
        var port = listener.local_address().value().port();
        var acceptor = tls.TlsAcceptor.create(certificate(), key()).value();
        async.spawn_on_each_worker(() => {
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
        });

        var connector = tls.TlsConnector.create().value();
        var untrusted = connector.connect_host("localhost", port);
        assert(untrusted.is_err(), "a self-signed certificate is not trusted by default");
        assert(untrusted.error().message.contains("certificate verify failed"), "says why");
        assert(connector.add_root_certificate(certificate()).is_ok(), "trust the test certificate");

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
            assert(task.join().value(), "every client got its echoes");
        }

        var tcp = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
        var wrong = connector.connect(tcp, "example.com");
        assert(wrong.is_err() && wrong.error().message.contains("certificate verify failed"), "a name the certificate is not for");

        var missing = connector.add_root_certificate(io.Path("CERT_PATH.missing"));
        assert(missing.is_err(), "a missing root file");
        var bad = tls.TlsAcceptor.create(key(), key());
        assert(bad.is_err(), "a key is not a certificate");
    });
    assert(_pep_live_allocs() == before, "a run frees everything it allocated");
    return 0;
}
"##;

/// TLS_PROGRAM with the test certificate and key written to a directory of
/// this process's own.
fn tls_program() -> String {
    let dir = std::env::temp_dir().join(format!("pepper_tls_{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("create the certificate directory");
    let certificate = dir.join("cert.pem");
    let key = dir.join("key.pem");
    std::fs::write(&certificate, format!("{TEST_CERTIFICATE}\n")).expect("write the certificate");
    std::fs::write(&key, format!("{TEST_KEY}\n")).expect("write the key");
    // Forward slashes work on every platform and need no escaping.
    let slashes = |p: &std::path::Path| p.to_string_lossy().replace('\\', "/");
    TLS_PROGRAM.replace("CERT_PATH", &slashes(&certificate)).replace("KEY_PATH", &slashes(&key))
}

#[test]
fn tls_over_loopback() {
    assert_runs("tls_loopback", &tls_program());
}

/// Every platform's TLS layer type-checks and produces valid IR.
#[test]
fn tls_programs_compile_on_other_platforms() {
    let programs = [("loopback", TLS_PROGRAM)];
    let cases: Vec<_> = SIMULATED_HOSTS.iter().flat_map(|&host| programs.into_iter().map(move |p| (host, p))).collect();
    let failures: Vec<String> = support::parallel_map(&cases, |((os, arch), (name, source))| {
        with_codegen_as(os, arch, &format!("tls_{name}"), source, |generator, module| {
            generator.generate(module).map_err(|d| module.sources.render(&d))?;
            generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
            Ok(())
        })
        .err()
        .map(|e| format!("{os}/{arch} {name}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n\n"));
}
