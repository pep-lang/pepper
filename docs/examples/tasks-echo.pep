import async;
import io;

# Echoes everything a client sends until it closes the connection.
serve(stream: io.TcpStream) {
    var buffer = Array<u8>();
    while (true) {
        var r = stream.read(buffer, 4096);   # parks this task until data arrives
        if (r.is_err() || r.value() == 0) {
            return;
        }
        stream.write_all(buffer);
        buffer.clear();
    }
}

main(): int {
    async.run(() => {
        var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var address = listener.local_address().value();
        var clients = 10;

        # The server: one task per connection, all on this thread.
        async.Task<void>.spawn_local(() => {
            while (true) {
                var accepted = listener.accept();
                if (accepted.is_err()) {
                    return;   # cancelled when the first task returns
                }
                var (stream, peer) = accepted.value();
                async.Task<void>.spawn_local(() => { serve(stream); });
            }
        });

        # The clients, as tasks on the same thread.
        var replies = Array<async.Task<ulong>>();
        var i = 0;
        while (i < clients) {
            var k = i;
            replies.append(async.Task<ulong>.spawn_local(() => {
                var stream = io.TcpStream.connect(address).value();
                var message = $"hello from {k}";
                stream.write_string(message);
                var buffer = Array<u8>();
                stream.read_exact(buffer, message.size());
                return buffer.count();
            }));
            i = i + 1;
        }
        for (var reply in replies) {
            assert(reply.join().value() > 0, "the server echoed the message");
        }
    });
    return 0;
}
