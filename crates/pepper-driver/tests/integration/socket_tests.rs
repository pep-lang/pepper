//! Sockets in the `io` module (`runtime/io/address.pep`, `socket.pep` and the
//! per-platform `socket_posix.pep` / `socket_windows.pep`): programs are
//! compiled, linked and run on the host, talking to themselves over
//! loopback only. Each program asserts internally and returns 0; the harness
//! reports its output on failure.
//!
//! `socket_programs_compile_on_other_platforms` pushes every program through
//! sema and LLVM codegen with the host simulated as each other platform, so
//! the Winsock and macOS layers type-check and produce valid IR on any host.

use crate::io_tests::{SIMULATED_HOSTS, assert_runs, with_codegen_as};
use crate::support;

/// Parsing and formatting of IP and socket addresses: pure Pepper, the same
/// on every platform.
const ADDRESS_PROGRAM: &str = r##"
import io;

ip(text: String): String {
    var r = io.IpAddress.parse(text);
    assert(r.is_ok(), "parses: " + text);
    return r.value().to_string();
}

bad_ip(text: String) {
    var r = io.IpAddress.parse(text);
    assert(r.is_err(), "rejects: " + text);
    assert(r.error().is_invalid_input(), "invalid input: " + text);
}

socket(text: String): String {
    var r = io.SocketAddress.parse(text);
    assert(r.is_ok(), "parses: " + text);
    return r.value().to_string();
}

bad_socket(text: String) {
    var r = io.SocketAddress.parse(text);
    assert(r.is_err(), "rejects: " + text);
    assert(r.error().is_invalid_input(), "invalid input: " + text);
}

main(): int {
    # IPv4
    assert(ip("0.0.0.0") == "0.0.0.0", "v4 zero");
    assert(ip("255.255.255.255") == "255.255.255.255", "v4 max");
    assert(ip("192.168.1.10") == "192.168.1.10", "v4");
    bad_ip("");
    bad_ip("256.1.1.1");
    bad_ip("1.2.3");
    bad_ip("1.2.3.4.5");
    bad_ip("01.2.3.4");
    bad_ip("1..2.3");
    bad_ip("1.2.3.");
    bad_ip(" 1.2.3.4");
    bad_ip("1.2.3.4 ");
    bad_ip("a.b.c.d");
    bad_ip("1.2.3.-4");
    bad_ip("1234.1.1.1");

    # IPv6, printed in the RFC 5952 form
    assert(ip("::") == "::", "v6 unspecified");
    assert(ip("::1") == "::1", "v6 loopback");
    assert(ip("1::") == "1::", "v6 trailing gap");
    assert(ip("0:0:0:0:0:0:0:1") == "::1", "v6 compressed");
    assert(ip("2001:DB8:0:0:8:800:200C:417A") == "2001:db8::8:800:200c:417a", "v6 lowercase");
    assert(ip("ff01:0:0:0:0:0:0:101") == "ff01::101", "v6 longest run");
    assert(ip("1:0:0:2:0:0:0:3") == "1:0:0:2::3", "v6 the longest run wins");
    assert(ip("1:0:0:2:0:0:3:4") == "1::2:0:0:3:4", "v6 the first of equal runs wins");
    assert(ip("1:0:3:4:5:6:7:8") == "1:0:3:4:5:6:7:8", "v6 one zero stays");
    assert(ip("0001:0002:0003:0004:0005:0006:0007:0008") == "1:2:3:4:5:6:7:8", "v6 leading zeros");
    assert(ip("1:2:3:4:5:6:7::") == "1:2:3:4:5:6:7:0", "v6 gap of one group");
    assert(ip("::ffff:192.0.2.1") == "::ffff:192.0.2.1", "v6 IPv4-mapped");
    assert(ip("64:ff9b::192.0.2.33") == "64:ff9b::c000:221", "v6 IPv4 tail");
    bad_ip(":::");
    bad_ip("1:::2");
    bad_ip("1::2::3");
    bad_ip("1:2:3:4:5:6:7:8:9");
    bad_ip("1:2:3:4:5:6:7");
    bad_ip("1:2:3:4:5:6:7:8::");
    bad_ip("12345::");
    bad_ip("g::");
    bad_ip(":1");
    bad_ip("1:");
    bad_ip("::1.2.3");
    bad_ip("1:2:3:4:5:6:7:1.2.3.4");
    bad_ip("[::1]");
    bad_ip("fe80::1%eth0");

    # Construction, equality, predicates
    var a = io.IpAddress.v4(10, 0, 0, 1);
    assert(a == io.IpAddress.parse("10.0.0.1").value(), "v4 equals parsed");
    assert(a != io.IpAddress.v4(10, 0, 0, 2), "v4 differs");
    assert(a.is_v4() && !a.is_v6(), "v4 family");
    assert(io.IpAddress.v6(8193, 3512, 0, 0, 0, 0, 0, 1).to_string() == "2001:db8::1", "v6 groups");
    assert(io.IpAddress.parse("::ffff:10.0.0.1").value() != a, "mapped v6 is not v4");
    assert(io.IpAddress.loopback_v4().is_loopback(), "127.0.0.1 loopback");
    assert(io.IpAddress.v4(127, 255, 0, 9).is_loopback(), "127/8 loopback");
    assert(io.IpAddress.loopback_v6().is_loopback(), "::1 loopback");
    assert(!a.is_loopback(), "10.0.0.1 not loopback");
    assert(io.IpAddress().is_unspecified() && io.IpAddress().is_v4(), "default is 0.0.0.0");
    assert(io.IpAddress.unspecified_v6().is_unspecified(), ":: unspecified");
    var bytes = a.to_bytes();
    assert(bytes.count() == 4 && bytes[0] == 10 && bytes[3] == 1, "v4 bytes");
    var bytes6 = io.IpAddress.loopback_v6().to_bytes();
    assert(bytes6.count() == 16 && bytes6[0] == 0 && bytes6[15] == 1, "v6 bytes");

    # Socket addresses
    assert(socket("1.2.3.4:0") == "1.2.3.4:0", "port 0");
    assert(socket("1.2.3.4:65535") == "1.2.3.4:65535", "port max");
    assert(socket("[::1]:8080") == "[::1]:8080", "v6 socket");
    assert(socket("[2001:DB8::1]:443") == "[2001:db8::1]:443", "v6 socket formatted");
    bad_socket("");
    bad_socket("1.2.3.4");
    bad_socket("1.2.3.4:");
    bad_socket("1.2.3.4:65536");
    bad_socket("1.2.3.4:123456");
    bad_socket("1.2.3.4:8a");
    bad_socket("::1:80");
    bad_socket("[::1]");
    bad_socket("[::1]:");
    bad_socket("[::1]80");
    bad_socket("[1.2.3.4]:80");
    bad_socket("[::1:80");
    var s = io.SocketAddress(io.IpAddress.loopback_v4(), 8080);
    assert(s.port() == 8080 && s.address() == io.IpAddress.loopback_v4(), "accessors");
    assert(s == io.SocketAddress.parse("127.0.0.1:8080").value(), "socket equals parsed");
    assert(s != io.SocketAddress(io.IpAddress.loopback_v4(), 8081), "ports differ");
    assert(io.SocketAddress().to_string() == "0.0.0.0:0", "default socket address");
    assert(io.SocketAddress.parse("[::1]:1").value().is_v6(), "v6 socket family");

    # A literal host resolves to itself without a lookup.
    var literal = io.resolve("192.0.2.7", 99).value();
    assert(literal.count() == 1 && literal[0].to_string() == "192.0.2.7:99", "literal host");
    var literal6 = io.resolve("::1", 7).value();
    assert(literal6[0].to_string() == "[::1]:7", "literal v6 host");
    assert(io.resolve("", 80).error().is_invalid_input(), "empty host");
    return 0;
}
"##;

/// TCP over IPv4 loopback on one thread: the kernel completes a connection
/// before `accept`, so a client and a server can take turns.
const TCP_PROGRAM: &str = r##"
import io;

loopback(port: u16): io.SocketAddress {
    return io.SocketAddress(io.IpAddress.loopback_v4(), port);
}

bytes_equal(buffer: u8[], text: String): bool {
    if (buffer.count() != text.size()) {
        return false;
    }
    var p = text.c_str() as __ptr<u8>;
    ulong i = 0;
    while (i < text.size()) {
        if (buffer[i] != p[i]) {
            return false;
        }
        i = i + 1;
    }
    return true;
}

exchange() {
    var listener = io.TcpListener.bind(loopback(0)).value();
    assert(listener.is_open(), "listener open");
    var local = listener.local_address().value();
    assert(local.port() != 0, "the system chose a port");
    assert(local.address() == io.IpAddress.loopback_v4(), "bound to loopback");

    var client = io.TcpStream.connect(local).value();
    var (server, peer) = listener.accept().value();
    assert(peer == client.local_address().value(), "accept reports the client's address");
    assert(client.peer_address().value() == local, "the client's peer is the listener");
    assert(server.local_address().value() == local, "the server side is on the listener's address");
    assert(client.set_no_delay(true).is_ok(), "no delay");

    # write_string / read_exact, then write / read appending
    assert(client.write_string("hello").is_ok(), "write_string");
    var buffer = Array<u8>();
    assert(server.read_exact(buffer, 5).is_ok(), "read_exact");
    assert(bytes_equal(buffer, "hello"), "read what was written");
    var reply = Array<u8>();
    reply.append('o');
    reply.append('k');
    assert(server.write(reply).value() == 2, "write");
    var got = Array<u8>();
    got.append('>');
    var n = client.read(got, 100).value();
    assert(n >= 1 && n <= 2, "read some");
    if (n < 2) {
        client.read_exact(got, 2 - n);
    }
    assert(bytes_equal(got, ">ok"), "read appends");
    assert(client.read(got, 0).value() == 0, "read 0 bytes");

    # A bigger write_all, in chunks on the other side.
    var big = Array<u8>();
    ulong i = 0;
    while (i < 20000) {
        big.append((i % 251) as u8);
        i = i + 1;
    }
    assert(client.write_all(big).is_ok(), "write_all");
    var received = Array<u8>();
    assert(server.read_exact(received, 20000).is_ok(), "read_exact big");
    assert(received == big, "big transfer intact");

    # shutdown_write: the peer reads what was sent, then 0.
    client.write_string("bye");
    assert(client.shutdown_write().is_ok(), "shutdown_write");
    var tail = Array<u8>();
    assert(server.read_exact(tail, 3).is_ok(), "read before end");
    assert(server.read(tail, 10).value() == 0, "end of stream");
    var short = server.read_exact(tail, 1);
    assert(short.is_err(), "read_exact past the end");
    assert(short.error().message == "connection closed after 0 of 1 bytes", "short read message");
    # The client can still read after shutting down its sending side.
    server.write_string("late");
    var late = Array<u8>();
    assert(client.read_exact(late, 4).is_ok(), "read after shutdown_write");

    # Closing
    assert(server.close().is_ok(), "close");
    assert(!server.is_open(), "closed");
    assert(server.close().is_ok(), "close twice");
    assert(server.write_string("x").is_err(), "write on closed");
    assert(server.read(tail, 1).is_err(), "read on closed");
    assert(server.peer_address().is_err(), "peer_address on closed");
    assert(client.read(late, 10).value() == 0, "peer closed");
    assert(!io.TcpStream().is_open(), "default stream closed");
    assert(io.TcpListener().accept().is_err(), "accept on a closed listener");
    listener.close();
    assert(listener.local_address().is_err(), "closed listener has no address");
}

errors() {
    # The port a closed listener had: nothing listens there now.
    var probe = io.TcpListener.bind(loopback(0)).value();
    var port = probe.local_address().value().port();
    var taken = io.TcpListener.bind(loopback(port));
    assert(taken.is_err() && taken.error().is_address_in_use(), "address in use");
    probe.close();
    var refused = io.TcpStream.connect(loopback(port));
    assert(refused.is_err(), "nothing listens");
    assert(refused.error().is_connection_refused(), "connection refused: " + refused.error().message);

    # 192.0.2.0/24 (TEST-NET-1) is never assigned to this machine.
    var foreign = io.TcpListener.bind(io.SocketAddress.parse("192.0.2.1:0").value());
    assert(foreign.is_err() && foreign.error().is_address_not_available(), "address not available");
}

by_name() {
    var listener = io.TcpListener.bind(loopback(0)).value();
    var port = listener.local_address().value().port();
    # "localhost" may list ::1 first; connect_host tries every address.
    var client = io.TcpStream.connect_host("localhost", port);
    assert(client.is_ok(), "connect_host localhost");
    var (server, peer) = listener.accept().value();
    assert(peer.address().is_loopback(), "from loopback");
    var names = io.resolve("localhost", 80).value();
    assert(names.count() >= 1, "localhost resolves");
    for (var address in names) {
        assert(address.port() == 80 && address.address().is_loopback(), "localhost is loopback");
    }
    var missing = io.resolve("no-such-host.invalid", 80);
    assert(missing.is_err() && missing.error().is_not_found(), "unknown host");
}

ipv6() {
    # Skipped where the system has no IPv6 loopback.
    var bound = io.TcpListener.bind(io.SocketAddress(io.IpAddress.loopback_v6(), 0));
    if (bound.is_err()) {
        return;
    }
    var listener = bound.value();
    var local = listener.local_address().value();
    assert(local.is_v6() && local.address() == io.IpAddress.loopback_v6(), "v6 listener");
    var client = io.TcpStream.connect(local).value();
    var (server, peer) = listener.accept().value();
    assert(peer.is_v6(), "v6 peer");
    client.write_string("six");
    var buffer = Array<u8>();
    assert(server.read_exact(buffer, 3).is_ok(), "v6 read");
    assert(bytes_equal(buffer, "six"), "v6 data");
}

main(): int {
    exchange();
    # Warm up (lazy runtime state, Winsock startup), then check that sockets
    # leave nothing behind.
    var before = _pep_live_allocs();
    exchange();
    errors();
    assert(_pep_live_allocs() == before, "sockets leak nothing");
    by_name();
    ipv6();
    return 0;
}
"##;

/// UDP over IPv4 loopback.
const UDP_PROGRAM: &str = r##"
import io;

main(): int {
    var loopback = io.SocketAddress(io.IpAddress.loopback_v4(), 0);
    var a = io.UdpSocket.bind(loopback).value();
    var b = io.UdpSocket.bind(loopback).value();
    var a_address = a.local_address().value();
    var b_address = b.local_address().value();
    assert(a_address.port() != 0 && a_address.port() != b_address.port(), "distinct ports");

    var message = Array<u8>();
    message.append(1);
    message.append(2);
    message.append(3);
    assert(a.send_to(message, b_address).value() == 3, "send_to");
    var buffer = Array<u8>();
    buffer.append(9);
    var (n, from) = b.receive_from(buffer, 100).value();
    assert(n == 3 && buffer.count() == 4 && buffer[1] == 1 && buffer[3] == 3, "receive_from appends");
    assert(from == a_address, "sender address");

    # A longer datagram is cut to max.
    var long = Array<u8>();
    ulong i = 0;
    while (i < 10) {
        long.append(i as u8);
        i = i + 1;
    }
    a.send_to(long, b_address);
    var cut = Array<u8>();
    var (m, _) = b.receive_from(cut, 4).value();
    assert(m == 4 && cut.count() == 4 && cut[3] == 3, "truncated to max");

    # connect / send / receive
    assert(a.connect(b_address).is_ok(), "connect");
    assert(b.connect(a_address).is_ok(), "connect back");
    assert(a.peer_address().value() == b_address, "peer_address");
    assert(a.send(message).value() == 3, "send");
    var got = Array<u8>();
    assert(b.receive(got, 100).value() == 3, "receive");
    assert(got == message, "received the datagram");

    assert(a.set_broadcast(true).is_ok(), "set_broadcast");
    assert(a.close().is_ok() && !a.is_open(), "close");
    assert(a.send(message).is_err(), "send on closed");
    assert(io.UdpSocket().receive(got, 1).is_err(), "receive on closed");
    return 0;
}
"##;

/// A client on another thread streams 4 MiB to a server on the main thread,
/// far more than the socket buffers hold, so both block and resume.
const THREADED_PROGRAM: &str = r##"
import async;
import io;

main(): int {
    var listener = io.TcpListener.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
    var port = listener.local_address().value().port();
    var sent = async.Atomic<long>(0);
    var client = async.Thread.spawn(() => {
        var stream = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
        var chunk = Array<u8>();
        ulong i = 0;
        while (i < 65536) {
            chunk.append((i % 256) as u8);
            i = i + 1;
        }
        var round = 0;
        while (round < 64) {
            assert(stream.write_all(chunk).is_ok(), "client write_all");
            sent.fetch_add(65536);
            round = round + 1;
        }
        stream.shutdown_write();
        var ack = Array<u8>();
        assert(stream.read_exact(ack, 2).is_ok(), "client reads the ack");
    });
    var (server, peer) = listener.accept().value();
    ulong total = 0;
    ulong errors = 0;
    var buffer = Array<u8>();
    while (true) {
        buffer.clear();
        var n = server.read(buffer, 100000).value();
        if (n == 0) {
            break;
        }
        ulong i = 0;
        while (i < n) {
            if (buffer[i] != ((total + i) % 256) as u8) {
                errors = errors + 1;
            }
            i = i + 1;
        }
        total = total + n;
    }
    server.write_string("ok");
    client.join();
    assert(total == 4194304 && sent.load() == 4194304, "every byte arrived");
    assert(errors == 0, "in order");
    return 0;
}
"##;

fn programs() -> Vec<(&'static str, &'static str)> {
    vec![("address", ADDRESS_PROGRAM), ("tcp", TCP_PROGRAM), ("udp", UDP_PROGRAM), ("threaded", THREADED_PROGRAM)]
}

#[test]
fn addresses_parse_and_format() {
    assert_runs("socket_address", ADDRESS_PROGRAM);
}

#[test]
fn tcp_over_loopback() {
    assert_runs("socket_tcp", TCP_PROGRAM);
}

#[test]
fn udp_over_loopback() {
    assert_runs("socket_udp", UDP_PROGRAM);
}

#[test]
fn tcp_between_threads() {
    assert_runs("socket_threaded", THREADED_PROGRAM);
}

/// Every platform's socket layer type-checks and produces valid IR that
/// calls that platform's functions.
#[test]
fn socket_programs_compile_on_other_platforms() {
    let cases: Vec<_> = SIMULATED_HOSTS.iter().flat_map(|&host| programs().into_iter().map(move |p| (host, p))).collect();
    let failures: Vec<String> = support::parallel_map(&cases, |((os, arch), (name, source))| {
        with_codegen_as(os, arch, &format!("socket_{name}"), source, |generator, module| {
            generator.generate(module).map_err(|d| module.sources.render(&d))?;
            generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
            if *name == "address" {
                return Ok(());
            }
            let ir = generator.module.to_string();
            let expect = match *os {
                "windows" => "@WSASocketW(",
                "linux" if *name == "tcp" => "@accept4(",
                "macos" if *name == "tcp" => "@fcntl(",
                _ => "@socket(",
            };
            if !ir.contains(expect) {
                return Err(format!("IR does not reference {expect}"));
            }
            Ok(())
        })
        .err()
        .map(|e| format!("{os}/{arch} {name}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
