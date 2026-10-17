# One socket read by one task while another task writes it, as an HTTP/2
# server does: on Windows each needs its own AFD poll, and the second must
# not leave the first waiting forever (the reader must see the close).

import async;
import io;

[Test]
reads_and_writes_one_socket_from_two_tasks() {
    async.run(() => {
        var listener = io.TcpListener.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
        var port = listener.local_address().value().port();
        var server = async.Task<ulong>.spawn_local(() => {
            var (socket, peer) = listener.accept().value();
            var reader = async.Task<ulong>.spawn_local(() => {
                var got = Array<u8>();
                ulong total = 0;
                while (true) {
                    got.clear();
                    var r = socket.read(got, 4096);
                    if (r.is_err() || r.value() == 0) {
                        return total;
                    }
                    total += r.value();
                }
                return total;
            });
            var chunk = Array<u8>(16393);
            while (chunk.count < 16393) {
                chunk.append(7);
            }
            var sent = 0;
            while (sent < 1000) {
                socket.write_all(chunk).value();
                sent += 1;
            }
            return reader.join().value();
        });
        var client = io.TcpStream.connect(io.SocketAddress(io.IpAddress.loopback_v4(), port)).value();
        var buffer = Array<u8>();
        ulong received = 0;
        ulong since = 0;
        while (received < 16393 * 1000) {
            buffer.clear();
            var r = client.read(buffer, 16384).value();
            received += r;
            since += r;
            if (since >= 262144) {
                since = 0;
                client.write_all("window update").value();
            }
        }
        client.close();
        expect_true(server.join().value() > 0);
    });
}
