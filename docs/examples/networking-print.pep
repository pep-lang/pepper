import io;

# Any stream that is an io.Reader: a File, a socket, or a TLS stream.
count_lines(source: io.Reader): int {
    var count = 0;
    for (var line in source.lines()) {
        if (line.is_err()) {
            break;
        }
        count += 1;
    }
    return count;
}

# `print` and `print_line` write a value's text to any io.Writer, the way the
# global `print` writes to standard output.
main(): int {
    var path = io.Directory.temp().join("networking-print.txt");
    var file = io.File.create(path).value();
    file.print("total: ");
    file.print_line(42);
    file.print_line((1, "two"));
    file.close();
    assert(io.File.read_to_string(path).value() == "total: 42\n(1, two)\n", "the file holds both lines");
    assert(count_lines(io.File.open(path).value()) == 2, "a File is a Reader");
    io.File.remove(path);

    # The same calls work on a TcpStream (and a UnixStream).
    var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
    var client = io.TcpStream.connect(listener.local_address().value()).value();
    var (server, peer) = listener.accept().value();
    client.print_line($"hello from {client.local_address().value()}");
    client.print_line("bye");
    client.shutdown_write();
    assert(count_lines(server) == 2, "a TcpStream is a Reader");
    return 0;
}
