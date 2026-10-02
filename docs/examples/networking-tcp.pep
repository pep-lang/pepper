import io;

# A server and a client on this machine, taking turns on one thread: the
# system completes a connection before the server accepts it.
main(): int {
    # Port 0 asks the system for any free port.
    var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
    var address = listener.local_address().value();

    var client = io.TcpStream.connect(address).value();
    var (server, peer) = listener.accept().value();
    assert(peer == client.local_address().value(), "accept reports who connected");

    # The client sends a request and closes its sending side.
    assert(client.write_all("ping").is_ok(), "send the request");
    client.shutdown_write();

    # The server reads until the client is done: read returns 0 at the end.
    var request = Array<u8>();
    while (server.read(request, 4096).value() > 0) {
    }
    assert(request.count == 4, "the whole request arrived");

    # It answers, and the client reads exactly the bytes it expects.
    server.write_all("pong");
    var reply = Array<u8>();
    assert(client.read_exact(reply, 4).is_ok(), "read the reply");
    assert(reply[0] == 'p' && reply[1] == 'o', "the reply is pong");
    return 0;
}
