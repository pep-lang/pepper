# Sockets over loopback only: TCP on one thread (exchanging data, shutdown,
# closing, the errors, names, IPv6, incoming(), lines()), UDP, TCP between
# two threads, Unix domain sockets, and read, write and connect timeouts.

import async;
import io;
import os;
import process;

loopback(port: u16): io.SocketAddress {
    return io.SocketAddress(io.IpAddress.loopback_v4(), port);
}

text_of(bytes: u8[]): String {
    return String._from_bytes(bytes);
}

# The kernel completes a connection before `accept`, so a client and a server
# on one thread can take turns.
[Test]
tcp_exchanges_data_over_loopback() {
    var listener = io.TcpListener.bind(loopback(0)).value();
    expect_true(listener.is_open());
    var local = listener.local_address().value();
    expect_not_equal(local.port(), 0);  # the system chose a port
    expect_true(local.address() == io.IpAddress.loopback_v4());

    var client = io.TcpStream.connect(local).value();
    var (server, peer) = listener.accept().value();
    expect_true(peer == client.local_address().value());
    expect_true(client.peer_address().value() == local);
    expect_true(server.local_address().value() == local);
    expect_true(client.set_no_delay(true).is_ok());

    # write_all(String) / read_exact, then write / read appending
    expect_true(client.write_all("hello").is_ok());
    var buffer = Array<u8>();
    expect_true(server.read_exact(buffer, 5).is_ok());
    expect_equal(text_of(buffer), "hello");
    var reply = Array<u8>();
    reply.append('o');
    reply.append('k');
    expect_equal(server.write(reply).value(), 2);
    var got = Array<u8>();
    got.append('>');
    var n = client.read(got, 100).value();
    expect_true(n >= 1 && n <= 2);
    if (n < 2) {
        client.read_exact(got, 2 - n);
    }
    expect_equal(text_of(got), ">ok");
    expect_equal(client.read(got, 0).value(), 0);

    # A bigger write_all, in chunks on the other side.
    var big = Array<u8>();
    ulong i = 0;
    while (i < 20000) {
        big.append((i % 251) as u8);
        i = i + 1;
    }
    expect_true(client.write_all(big).is_ok());
    var received = Array<u8>();
    expect_true(server.read_exact(received, 20000).is_ok());
    expect_true(received == big);

    # shutdown_write: the peer reads what was sent, then 0.
    client.write_all("bye");
    expect_true(client.shutdown_write().is_ok());
    var tail = Array<u8>();
    expect_true(server.read_exact(tail, 3).is_ok());
    expect_equal(server.read(tail, 10).value(), 0);
    var short = server.read_exact(tail, 1);
    expect_true(short.is_err());
    expect_equal(short.error().message, "connection closed after 0 of 1 bytes");
    # The client can still read after shutting down its sending side.
    server.write_all("late");
    var late = Array<u8>();
    expect_true(client.read_exact(late, 4).is_ok());

    # Closing
    expect_true(server.close().is_ok());
    expect_false(server.is_open());
    expect_true(server.close().is_ok());
    expect_true(server.write_all("x").is_err());
    expect_true(server.read(tail, 1).is_err());
    expect_true(server.peer_address().is_err());
    expect_equal(client.read(late, 10).value(), 0);
    expect_false(io.TcpStream().is_open());
    expect_true(io.TcpListener().accept().is_err());
    listener.close();
    expect_true(listener.local_address().is_err());
}

[Test]
tcp_reports_address_in_use_refused_and_not_available() {
    # The port a closed listener had: nothing listens there now.
    var probe = io.TcpListener.bind(loopback(0)).value();
    var port = probe.local_address().value().port();
    var taken = io.TcpListener.bind(loopback(port));
    expect_true(taken.is_err());
    expect_true(taken.error().is_address_in_use());
    probe.close();
    var refused = io.TcpStream.connect(loopback(port));
    expect_true(refused.is_err());
    expect_true(refused.error().is_connection_refused());

    # 192.0.2.0/24 (TEST-NET-1) is never assigned to this machine.
    var foreign = io.TcpListener.bind(io.SocketAddress.parse("192.0.2.1:0").value());
    expect_true(foreign.is_err());
    expect_true(foreign.error().is_address_not_available());
}

[Test]
tcp_connects_by_name() {
    var listener = io.TcpListener.bind(loopback(0)).value();
    var port = listener.local_address().value().port();
    # "localhost" may list ::1 first; connect_host tries every address.
    var client = io.TcpStream.connect_host("localhost", port);
    expect_true(client.is_ok());
    var (server, peer) = listener.accept().value();
    expect_true(peer.address().is_loopback());
    var names = io.resolve("localhost", 80).value();
    expect_true(names.count >= 1);
    for (var address in names) {
        expect_equal(address.port(), 80);
        expect_true(address.address().is_loopback());
    }
    var missing = io.resolve("no-such-host.invalid", 80);
    expect_true(missing.is_err());
    expect_true(missing.error().is_not_found());
}

[Test]
tcp_over_ipv6_loopback() {
    # Skipped where the system has no IPv6 loopback.
    var bound = io.TcpListener.bind(io.SocketAddress(io.IpAddress.loopback_v6(), 0));
    if (bound.is_err()) {
        return;
    }
    var listener = bound.value();
    var local = listener.local_address().value();
    expect_true(local.is_v6());
    expect_true(local.address() == io.IpAddress.loopback_v6());
    var client = io.TcpStream.connect(local).value();
    var (server, peer) = listener.accept().value();
    expect_true(peer.is_v6());
    client.write_all("six");
    var buffer = Array<u8>();
    expect_true(server.read_exact(buffer, 3).is_ok());
    expect_equal(text_of(buffer), "six");
}

# A for loop over listener.incoming() takes connections until it breaks,
# and ends once the listener is closed.
[Test]
incoming_takes_connections_until_closed() {
    var listener = io.TcpListener.bind(loopback(0)).value();
    var local = listener.local_address().value();
    var first = io.TcpStream.connect(local).value();
    var second = io.TcpStream.connect(local).value();
    expect_true(first.write_all("a").is_ok());
    expect_true(second.write_all("b").is_ok());
    var received = Array<u8>();
    for (var connection in listener.incoming()) {
        expect_true(connection.is_ok());
        expect_true(connection.value().read_exact(received, 1).is_ok());
        if (received.count == 2) {
            break;
        }
    }
    expect_equal(text_of(received), "ab");  # both connections, in order
    expect_true(listener.close().is_ok());
    var steps = 0;
    for (var connection in listener.incoming()) {
        steps = steps + 1;
    }
    expect_equal(steps, 0);
}

# A TcpStream is an io.Reader: lines() reads until the peer shuts down.
[Test]
tcp_stream_reads_lines() {
    var listener = io.TcpListener.bind(loopback(0)).value();
    var client = io.TcpStream.connect(listener.local_address().value()).value();
    var (server, peer) = listener.accept().value();
    expect_true(client.write_all("first\r\nsecond\n").is_ok());
    expect_true(client.shutdown_write().is_ok());
    var got = Array<String>();
    for (var line in server.lines()) {
        got.append(line.value());
    }
    expect_equal(got.count, 2);
    expect_equal(got[0], "first");
    expect_equal(got[1], "second");
}

[Test]
udp_over_loopback() {
    var a = io.UdpSocket.bind(loopback(0)).value();
    var b = io.UdpSocket.bind(loopback(0)).value();
    var a_address = a.local_address().value();
    var b_address = b.local_address().value();
    expect_not_equal(a_address.port(), 0);
    expect_not_equal(a_address.port(), b_address.port());

    var message = Array<u8>();
    message.append(1);
    message.append(2);
    message.append(3);
    expect_equal(a.send_to(message, b_address).value(), 3);
    var buffer = Array<u8>();
    buffer.append(9);
    var (n, from) = b.receive_from(buffer, 100).value();
    expect_equal(n, 3);
    expect_equal(buffer.count, 4);  # receive_from appends
    expect_equal(buffer[1], 1);
    expect_equal(buffer[3], 3);
    expect_true(from == a_address);

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
    expect_equal(m, 4);
    expect_equal(cut.count, 4);
    expect_equal(cut[3], 3);

    # connect / send / receive
    expect_true(a.connect(b_address).is_ok());
    expect_true(b.connect(a_address).is_ok());
    expect_true(a.peer_address().value() == b_address);
    expect_equal(a.send(message).value(), 3);
    var got = Array<u8>();
    expect_equal(b.receive(got, 100).value(), 3);
    expect_true(got == message);

    expect_true(a.set_broadcast(true).is_ok());
    expect_true(a.close().is_ok());
    expect_false(a.is_open());
    expect_true(a.send(message).is_err());
    expect_true(io.UdpSocket().receive(got, 1).is_err());
}

# A client on another thread streams 4 MiB to a server on this thread, far
# more than the socket buffers hold, so both block and resume.
[Test]
tcp_between_threads() {
    var listener = io.TcpListener.bind(loopback(0)).value();
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
    server.write_all("ok");
    client.join();
    expect_equal(total, 4194304);
    expect_equal(sent.load(), 4194304);
    expect_equal(errors, 0);  # in order
}

closed([Move] listener: io.UnixListener): bool {
    return listener.close().is_ok();
}

# Android's SELinux refuses socket files to an `adb shell` program, which
# is how pep-test runs the tests there; so do the unix tests below.
[Test]
unix_socket_listener_and_stream() {
    [Target(OS(Android))]
    {
        return;
    }
    # A short folder name: a socket path must fit sockaddr_un (104 bytes on
    # macOS, 108 elsewhere), and the temporary folder's own path is long on
    # macOS and Windows.
    var folder = TempFolder("unix");
    var path = folder.path.join("s.sock");
    var listener = io.UnixListener.bind(path).value();
    expect_equal(listener.path().to_string(), path.to_string());
    var again = io.UnixListener.bind(path);
    expect_true(again.is_err());
    expect_true(again.error().is_address_in_use());

    var client = io.UnixStream.connect(path).value();
    var server = listener.accept().value();
    expect_true(client.write_all("ping").is_ok());
    client.shutdown_write();
    var request = Array<u8>();
    while (server.read(request, 4096).value() > 0) {}
    expect_equal(text_of(request), "ping");
    expect_true(server.write_all("pong").is_ok());
    var reply = Array<u8>();
    expect_true(client.read_exact(reply, 4).is_ok());
    expect_equal(text_of(reply), "pong");

    var too_long = io.UnixStream.connect(io.Path("x".repeat(200)));
    expect_true(too_long.is_err());
    expect_true(too_long.error().is_invalid_input());
    var empty = io.UnixListener.bind(io.Path(""));
    expect_true(empty.is_err());
    expect_true(empty.error().is_invalid_input());
    var missing = io.UnixStream.connect(folder.path.join("missing.sock"));
    expect_true(missing.is_err());
    expect_true(missing.error().is_not_found());
    # Moves while `path` is kept: the listener holds its own copy (#471).
    expect_true(closed(move(listener)));
    var refused = io.UnixStream.connect(path);
    expect_true(refused.is_err());
    expect_true(refused.error().is_connection_refused());
    expect_true(io.File.remove(path).is_ok());  # the socket file stays until removed
}

[Test]
unix_datagrams_by_path_pair_and_connect() {
    [Target((OS(Linux) || OS(Mac)) && !OS(Android))]
    {
        var folder = TempFolder("udgram");
        var path = folder.path.join("d.sock");
        var server = io.UnixDatagram.bind(path).value();
        expect_equal(server.path().to_string(), path.to_string());
        expect_true(io.UnixDatagram.bind(path).error().is_address_in_use());

        # From an unbound socket: the sender's path is empty.
        var anonymous = io.UnixDatagram.unbound().value();
        expect_equal(anonymous.send_to("ping".bytes(), path).value(), 4);
        var buffer = Array<u8>();
        var (n, from) = server.receive_from(buffer, 100).value();
        expect_equal(n, 4);
        expect_equal(text_of(buffer), "ping");
        expect_true(from.is_empty);

        # From a bound socket: the server sees its path and can reply.
        var client_path = folder.path.join("c.sock");
        var client = io.UnixDatagram.bind(client_path).value();
        client.send_to("one".bytes(), path);
        client.send_to("two!".bytes(), path);
        var first = Array<u8>();
        var (n1, sender) = server.receive_from(first, 2).value();  # cut to 2 bytes
        expect_equal(n1, 2);
        expect_equal(text_of(first), "on");
        expect_equal(sender.to_string(), client_path.to_string());
        var second = Array<u8>();
        expect_equal(server.receive(second, 100).value(), 4);  # datagrams stay whole
        expect_equal(text_of(second), "two!");
        server.send_to("pong".bytes(), sender);
        var reply = Array<u8>();
        expect_equal(client.receive(reply, 100).value(), 4);
        expect_equal(text_of(reply), "pong");

        # connect sets the default peer for send.
        expect_true(client.connect(path).is_ok());
        client.send("via connect".bytes());
        var connected = Array<u8>();
        server.receive(connected, 100);
        expect_equal(text_of(connected), "via connect");

        var (a, b) = io.UnixDatagram.pair().value();
        expect_equal(a.send("hi".bytes()).value(), 2);
        var paired = Array<u8>();
        expect_equal(b.receive(paired, 16).value(), 2);
        expect_equal(text_of(paired), "hi");
        expect_true(a.path().is_empty);

        # A short name: macOS holds a socket path to 103 bytes, and pep-test's
        # per-test temporary folder brings this one close.
        expect_true(anonymous.send_to("x".bytes(), folder.path.join("m.sock")).error().is_not_found());
        expect_true(anonymous.send_to("x".bytes(), io.Path("")).error().is_invalid_input());
        expect_true(server.close().is_ok());
        expect_true(server.close().is_ok());
        expect_true(server.receive(buffer, 10).is_err());
        expect_true(anonymous.send_to("x".bytes(), path).error().is_connection_refused());
        io.File.remove(path);
        io.File.remove(client_path);
    }
}

# The echo server's socket file: a function, since tasks on other threads
# cannot share a captured String.
echo_socket(): io.Path {
    return io.Directory.temp().join($"pepper_test_echo_{process.id()}.sock");
}

# An echo server accepting on every task worker, and 16 client tasks.
[Test]
unix_socket_echo_server_on_every_worker() {
    [Target(OS(Android))]
    {
        return;
    }
    io.File.remove(echo_socket());
    async.run(
        () => {
            var shared = io.SharedUnixListener.bind(echo_socket()).value();
            async.spawn_on_each_worker(
                () => {
                    while (true) {
                        var accepted = shared.accept();
                        if (accepted.is_err()) {
                            return;
                        }
                        var stream = accepted.value();
                        var buffer = Array<u8>();
                        while (true) {
                            # Cancelled when async.run ends.
                            var r = stream.read(buffer, 4096);
                            if (r.is_err() || r.value() == 0) {
                                break;
                            }
                            stream.write_all(buffer);
                            buffer.clear();
                        }
                    }
                }
            );
            var tasks = Array<async.Task<bool>>();
            var n = 0;
            while (n < 16) {
                tasks.append(async.spawn<bool>(() => {
                    var stream = io.UnixStream.connect(echo_socket()).value();
                    var round = 0;
                    while (round < 100) {
                        stream.write_all("0123456789");
                        var got = Array<u8>();
                        if (stream.read_exact(got, 10).is_err()) {
                            return false;
                        }
                        round = round + 1;
                    }
                    return true;
                }));
                n = n + 1;
            }
            for (var task in tasks) {
                expect_true(task.join().value());  # every client got its echoes
            }
        }
    );
    expect_true(io.File.remove(echo_socket()).is_ok());
}

# A connected pair of TCP streams over loopback.
tcp_pair(): (io.TcpStream, io.TcpStream) {
    var listener = io.TcpListener.bind(loopback(0)).value();
    var client = io.TcpStream.connect(listener.local_address().value()).value();
    var (server, peer) = listener.accept().value();
    return (client, server);
}

# Checks the timeouts on a stream whose peer neither reads nor writes: a
# read and a write each give up after their timeout, and the stream still
# works afterwards.
check_stream_timeouts(client: io.TcpStream, server: io.TcpStream) {
    expect_equal(client.read_timeout(), 0);
    expect_true(client.set_read_timeout(100).is_ok());
    expect_equal(client.read_timeout(), 100);
    var start = os.Instant.now();
    var buffer = Array<u8>();
    var silent = client.read(buffer, 16);
    expect_true(silent.is_err());
    expect_true(silent.error().is_timed_out());
    expect_true(start.elapsed().milliseconds() >= 90);
    expect_true(server.write_all("late").is_ok());
    expect_true(client.read_exact(buffer, 4).is_ok());  # still open
    expect_equal(text_of(buffer), "late");

    # The peer never reads, so the buffers fill and a send has to wait.
    expect_true(client.set_write_timeout(100).is_ok());
    expect_equal(client.write_timeout(), 100);
    var chunk = "x".repeat(65536).bytes();
    var stuck = io.IoResult<void>.ok();
    var rounds = 0;
    while (stuck.is_ok() && rounds < 10000) {
        stuck = client.write_all(chunk);
        rounds = rounds + 1;
    }
    expect_true(stuck.is_err());
    expect_true(stuck.error().is_timed_out());

    expect_true(client.set_read_timeout(0).is_ok());
    expect_equal(client.read_timeout(), 0);
    expect_true(client.set_read_timeout(4294967296).error().is_invalid_input());
}

[Test]
tcp_read_and_write_timeouts_outside_a_task() {
    var (client, server) = tcp_pair();
    check_stream_timeouts(client, server);
}

[Test]
tcp_read_and_write_timeouts_in_a_task() {
    async.run(() => {
        var (client, server) = tcp_pair();
        check_stream_timeouts(client, server);
    });
}

[Test]
unix_datagram_timeouts() {
    [Target(OS(Linux) || OS(Mac))]
    {
        var (a, b) = io.UnixDatagram.pair().value();
        expect_true(a.set_read_timeout(50).is_ok());
        expect_equal(a.read_timeout(), 50);
        var buffer = Array<u8>();
        expect_true(a.receive(buffer, 16).error().is_timed_out());
        b.send("hi".bytes());
        expect_equal(a.receive(buffer, 16).value(), 2);  # still open

        # Nobody receives on `a`, so `b`'s sends fill its queue. Then Linux
        # waits out the timeout, and macOS fails at once with ENOBUFS.
        expect_true(b.set_write_timeout(50).is_ok());
        expect_equal(b.write_timeout(), 50);
        var datagram = "x".repeat(1024).bytes();
        var sent = b.send(datagram);
        while (sent.is_ok()) {
            sent = b.send(datagram);
        }
        [Target(OS(Linux))]
        {
            expect_true(sent.error().is_timed_out());
        }
        [Target(OS(Mac))]
        {
            expect_equal(sent.error().code, 55);  # ENOBUFS
        }
        expect_true(b.set_write_timeout(4294967296).error().is_invalid_input());
        expect_true(b.close().is_ok());
        expect_true(b.set_read_timeout(10).is_err());  # closed
    }
}

[Test]
socket_timeouts_on_udp_unix_and_connect() {
    var socket = io.UdpSocket.bind(loopback(0)).value();
    expect_true(socket.set_read_timeout(50).is_ok());
    var buffer = Array<u8>();
    expect_true(socket.receive_from(buffer, 16).error().is_timed_out());
    var other = io.UdpSocket.bind(loopback(0)).value();
    other.send_to("hi".bytes(), socket.local_address().value());
    expect_equal(socket.receive(buffer, 16).value(), 2);  # still open

    [Target(!OS(Android))]
    {
        var folder = TempFolder("timeouts");
        var path = folder.path.join("t.sock");
        var listener = io.UnixListener.bind(path).value();
        var unix_client = io.UnixStream.connect(path).value();
        var unix_server = listener.accept().value();
        expect_true(unix_client.set_read_timeout(50).is_ok());
        expect_true(unix_client.read(buffer, 16).error().is_timed_out());
        unix_server.write_all("ok");
        expect_equal(unix_client.read(buffer, 16).value(), 2);
        expect_true(listener.close().is_ok());
        io.File.remove(path);
    }

    # A connection that is accepted in time; the timeout does not stay.
    var tcp = io.TcpListener.bind(loopback(0)).value();
    var stream = io.TcpStream.connect_timeout(tcp.local_address().value(), 2000).value();
    expect_equal(stream.write_timeout(), 0);
    expect_true(io.TcpStream.connect_timeout(tcp.local_address().value(), 4294967296).error().is_invalid_input());
    expect_true(stream.close().is_ok());
    expect_true(stream.set_read_timeout(10).is_err());  # closed
}
