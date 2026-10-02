import async;
import io;

main(): int {
    async.run_with(async.RuntimeOptions().workers(2), () => {
        var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var port = listener.local_address().value().port();
        var client = async.Task<ulong>.spawn_local(() => {
            var stream = io.TcpStream.connect_host("127.0.0.1", port).value();
            var reply = Array<u8>();
            while (stream.read(reply, 64).value() > 0) {
            }
            return reply.count;
        });

        var (stream, peer) = listener.accept().value();
        # A stream is not thread-safe; its transfer token is.
        var transfer = stream.into_transfer();
        var handler = async.spawn<void>(() => {
            var mine = io.TcpStream.adopt(transfer).value();
            mine.write_all("from any worker").value();
        });
        handler.join();
        assert(client.join().value() == 15, "the moved stream answered");
    });
    return 0;
}
