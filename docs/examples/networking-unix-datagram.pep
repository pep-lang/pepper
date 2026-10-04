# Unix datagram sockets: a server bound to a path answers each datagram.
import io;

main(): int {
    # Linux and macOS only: Windows has no Unix datagram sockets.
    [Target(OS(Linux) || OS(Mac))]
    {
        var folder = io.Directory.temp().join("pepper-udgram-example");
        io.Directory.remove_all(folder);
        io.Directory.create_all(folder).value();
        var server_path = folder.join("server.sock");
        var client_path = folder.join("client.sock");

        var server = io.UnixDatagram.bind(server_path).value();
        var client = io.UnixDatagram.bind(client_path).value();
        client.send_to("ping".bytes(), server_path).value();

        # Each receive takes one whole datagram and names its sender.
        var request = Array<u8>();
        var (n, sender) = server.receive_from(request, 1024).value();
        assert(n == 4 && sender == client_path, "one datagram from the client");
        server.send_to("pong".bytes(), sender).value();

        var reply = Array<u8>();
        client.receive(reply, 1024).value();
        assert(reply.count == 4, "the reply");

        # A pair is two sockets already connected to each other.
        var (a, b) = io.UnixDatagram.pair().value();
        a.send("hi".bytes()).value();
        var got = Array<u8>();
        assert(b.receive(got, 16).value() == 2, "through the pair");

        # Closing leaves the socket files; remove them.
        io.Directory.remove_all(folder).value();
    }
    return 0;
}
