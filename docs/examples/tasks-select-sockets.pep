import async;
import io;

# What the select returns: bytes that arrived on one of the connections.
enum Event {
    Data(from: int, count: ulong),
}

# Reads `stream` until the peer closes it, sending the size of each read to
# `into`, then closes `into` so the select stops waiting on it.
forward(stream: io.TcpStream, into: async.Channel<ulong>) {
    var buffer = Array<u8>();
    while (true) {
        var r = stream.read(buffer, 4096);   # parks this task, not the others
        if (r.is_err() || r.value() == 0) {
            into.close();
            return;
        }
        into.send(r.value());
        buffer.clear();
    }
}

main(): int {
    async.run(() => {
        var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var address = listener.local_address().value();
        var first = io.TcpStream.connect(address).value();
        var (from_first, first_peer) = listener.accept().value();
        var second = io.TcpStream.connect(address).value();
        var (from_second, second_peer) = listener.accept().value();

        # One task per socket turns what it reads into channel messages.
        var first_bytes = async.Channel<ulong>();
        var second_bytes = async.Channel<ulong>();
        async.Task<void>.spawn_local(() => { forward(from_first, first_bytes); });
        async.Task<void>.spawn_local(() => { forward(from_second, second_bytes); });

        first.write_all("hello");
        first.shutdown_write();
        second.write_all("hi there");
        second.shutdown_write();

        # The select then waits on both sockets at once, through their channels.
        var select = async.Select<Event>();
        select.receive(first_bytes, (count: ulong): Event => Event.Data(0, count));
        select.receive(second_bytes, (count: ulong): Event => Event.Data(1, count));
        ulong first_total = 0;
        ulong second_total = 0;
        var running = true;
        while (running) {
            match (select.wait()) {
                Ok(event) => {
                    match (event) {
                        Data(from, count) => {
                            if (from == 0) {
                                first_total = first_total + count;
                            } else {
                                second_total = second_total + count;
                            }
                        }
                    }
                }
                Err(error) => {
                    running = false;   # both connections closed
                }
            }
        }
        assert(first_total == 5 && second_total == 8, "every byte arrived once");
    });
    return 0;
}
