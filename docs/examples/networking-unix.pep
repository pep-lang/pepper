import io;

# A server and a client over a Unix domain socket, taking turns on one
# thread, as in the TCP example.
main(): int {
    var path = io.Directory.temp().join("pepper-networking-unix.sock");
    # Binding fails if the socket file is still there from an earlier run.
    io.File.remove(path);
    var listener = io.UnixListener.bind(path).value();

    var client = io.UnixStream.connect(path).value();
    var server = listener.accept().value();

    assert(client.write_all("ping").is_ok(), "send the request");
    var request = Array<u8>();
    assert(server.read_exact(request, 4).is_ok(), "read the request");
    server.write_all("pong");
    var reply = Array<u8>();
    assert(client.read_exact(reply, 4).is_ok(), "read the reply");
    assert(reply[0] == 'p' && reply[1] == 'o', "the reply is pong");

    # Closing the listener leaves the socket file; remove it when done.
    listener.close();
    assert(io.File.remove(path).is_ok(), "remove the socket file");
    return 0;
}
