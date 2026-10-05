import io;

# A read that gives up when the peer stays silent, and a connect with a
# limit of its own.
main(): int {
    var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
    var address = listener.local_address().value();

    # connect_timeout gives up after 2 seconds instead of the system's limit.
    var client = io.TcpStream.connect_timeout(address, 2000).value();
    var (server, peer) = listener.accept().value();

    # The server says nothing, so the read gives up after 100 milliseconds.
    client.set_read_timeout(100).value();
    var reply = Array<u8>();
    var silent = client.read(reply, 4096);
    assert(silent.is_err() && silent.error().is_timed_out(), "the read timed out");

    # The stream is still open: once the server answers, the read succeeds.
    server.write_all("pong");
    assert(client.read_exact(reply, 4).is_ok(), "read the late reply");
    return 0;
}
