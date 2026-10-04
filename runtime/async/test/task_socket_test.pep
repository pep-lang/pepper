# Sockets in tasks, on each I/O backend: an echo server with many clients on
# one thread, a large write that fills the send buffer, timeouts on accept,
# join and sleep, cancelling a task parked on a socket, and a refused
# connection.

import async;
import io;
import [best_backend, has_io_uring] from "backends";

serve(stream: io.TcpStream) {
    var buffer = Array<u8>();
    while (true) {
        var r = stream.read(buffer, 4096);
        if (r.is_err() || r.value() == 0) {
            return;
        }
        expect_true(stream.write_all(buffer).is_ok());
        buffer.clear();
    }
}

# Runs the checks on `backend`; returns the name of the backend they ran on.
sockets_park_their_task_on(backend: async.Backend): String {
    var used = Array<String>();
    async.run_with(
        async.RuntimeOptions().backend(backend),
        () => {
            used.append(async.current_backend().name());
            var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var address = listener.local_address().value();
            var clients = 40;

            # One server task per connection, all on this thread.
            var server = async.Task<void>.spawn_local(() => {
                var connections = Array<async.Task<void>>();
                var i = 0;
                while (i < clients) {
                    var (stream, peer) = listener.accept().value();
                    connections.append(async.Task<void>.spawn_local(() => {
                        serve(stream);
                    }));
                    i = i + 1;
                }
                for (var c in connections) {
                    c.join();
                }
            });
            var tasks = Array<async.Task<int>>();
            var n = 0;
            while (n < clients) {
                var k = n;
                tasks.append(async.Task<int>.spawn_local(() => {
                    var stream = io.TcpStream.connect(address).value();
                    var echoed = 0;
                    var round = 0;
                    while (round < 10) {
                        var message = $"message {k} {round}";
                        expect_true(stream.write_all(message).is_ok());
                        var buffer = Array<u8>();
                        expect_true(stream.read_exact(buffer, message.size).is_ok());
                        echoed = echoed + buffer.count as int;
                        async.yield_now();
                        round = round + 1;
                    }
                    return echoed;
                }));
                n = n + 1;
            }
            for (var t in tasks) {
                expect_true(t.join().value() > 0);
            }
            server.join();

            # A write far larger than the socket buffers waits for the reader.
            var big = Array<u8>();
            ulong size = 8388608;
            while (big.count < size) {
                big.append((big.count % 251) as u8);
            }
            var sender = async.Task<void>.spawn_local(() => {
                var (stream, peer) = listener.accept().value();
                expect_true(stream.write_all(big).is_ok());
            });
            var receiver = io.TcpStream.connect(address).value();
            var received = Array<u8>();
            expect_true(receiver.read_exact(received, size).is_ok());
            expect_equal(received[size - 1], big[size - 1]);
            sender.join();

            # Timeouts: accept gives up, join gives up (the task carries on), and
            # sleep returns early.
            with (var deadline = async.timeout(30)) {
                var accepted = listener.accept();
                expect_true(accepted.is_err() && accepted.error().is_timed_out());
                expect_true(deadline.is_expired());
            }
            var sleeper = async.Task<void>.spawn_local(() => {
                async.sleep(100000);
            });
            with (async.timeout(20)) {
                var joined = sleeper.join();
                expect_true(joined.error().is_timed_out());
                expect_false(joined.error().is_cancelled());
                # Returns at the limit.
                async.sleep(100000);
            }
            # The sleeper carries on.
            expect_false(sleeper.is_finished());
            sleeper.cancel();
            sleeper.join();

            # Nested timeouts: the outer one still applies after the inner ends.
            with (async.timeout(40)) {
                with (async.timeout(100000)) {
                    expect_true(listener.accept().error().is_timed_out());
                }
            }

            # Cancelling a task parked on a socket.
            var waiter = async.Task<bool>.spawn_local(() => {
                return listener.accept().error().is_cancelled();
            });
            async.yield_now();
            waiter.cancel();
            expect_true(waiter.join().is_err());
            expect_true(waiter.is_finished());

            # A refused connection fails like a blocking one.
            var closed = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var gone = closed.local_address().value();
            closed.close();
            expect_true(io.TcpStream.connect(gone).error().is_connection_refused());
        }
    );
    return used[0];
}

[Test]
sockets_park_their_task() {
    expect_equal(sockets_park_their_task_on(async.Backend.Automatic), best_backend());
}

# The portable poll() backend, the reference the others are checked against.
[Test]
sockets_park_their_task_with_poll() {
    expect_equal(sockets_park_their_task_on(async.Backend.Poll), "Poll");
}

[Test]
sockets_park_their_task_with_io_uring() {
    if (!has_io_uring()) {
        return;
    }
    expect_equal(sockets_park_their_task_on(async.Backend.IoUring), "IoUring");
}
