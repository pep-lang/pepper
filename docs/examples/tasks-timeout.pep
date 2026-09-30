import async;
import io;

main(): int {
    async.run(() => {
        var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();

        # Nobody connects, so the accept gives up after 50 milliseconds.
        with (var deadline = async.timeout(50)) {
            var accepted = listener.accept();
            assert(accepted.is_err() && accepted.error().is_timed_out(), "accept timed out");
            assert(deadline.is_expired(), "the limit has passed");
        }

        # A join gives up too; the task itself carries on until cancelled.
        var slow = async.Task<int>.spawn_local(() => {
            async.sleep(1000000);
            return 42;
        });
        with (async.timeout(20)) {
            var result = slow.join();
            assert(result.error().is_timed_out(), "join timed out");
        }
        slow.cancel();
    });
    return 0;
}
