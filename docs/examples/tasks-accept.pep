import async;

import io;

const served = async.Atomic<int>(0);

main(): int {
    async.run_with(async.RuntimeOptions().workers(4), () => {
        var listener = io.SharedTcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var port = listener.local_address().value().port();

        # One accept loop per worker; each connection goes to one of them.
        async.spawn_on_each_worker(() => {
            while (true) {
                var accepted = listener.accept();
                if (accepted.is_err()) {
                    return;   # cancelled when the first task returns
                }
                var (stream, peer) = accepted.value();
                served.fetch_add(1);
                async.Task<void>.spawn_local(() => {
                    stream.write_all("hello").value();
                });
            }
        });

        var i = 0;
        while (i < 8) {
            var client = io.TcpStream.connect_host("127.0.0.1", port).value();
            var reply = Array<u8>();
            while (client.read(reply, 64).value() > 0) {
            }
            assert(reply.count == 5, "greeted");
            i = i + 1;
        }
    });
    assert(served.load() == 8, "every connection was accepted once");
    return 0;
}
