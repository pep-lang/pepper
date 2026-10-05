# Reads that wait on a stream in a task, on each I/O backend: a timeout (the
# task's or the stream's own) and a cancel end them (on io_uring once the kernel cancels its receive), the
# stream stays usable afterwards, and closing it from another task ends a
# waiting read.

import async;
import io;

[Target(OS(Linux))]
on_linux(): bool {
    return true;
}

[Target(!OS(Linux))]
on_linux(): bool {
    return false;
}

reads_end_on(backend: async.Backend) {
    async.run_with(
        async.RuntimeOptions().backend(backend),
        () => {
            var listener = io.TcpListener.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var address = listener.local_address().value();
            var quiet = io.TcpStream.connect(address).value();
            var (talker, talker_address) = listener.accept().value();

            with (async.timeout(30)) {
                var timed = quiet.read(Array<u8>(), 16);
                expect_true(timed.is_err() && timed.error().is_timed_out());
            }

            # The stream's own read timeout, then none again.
            quiet.set_read_timeout(30);
            var own = quiet.read(Array<u8>(), 16);
            expect_true(own.is_err() && own.error().is_timed_out());
            quiet.set_read_timeout(0);

            var reader = async.Task<bool>.spawn_local(() => {
                return quiet.read(Array<u8>(), 16).error().is_cancelled();
            });
            async.yield_now();
            reader.cancel();
            expect_true(reader.join().is_err());

            expect_true(talker.write_all("late".bytes()).is_ok());
            var late = Array<u8>();
            expect_true(quiet.read_exact(late, 4).is_ok());
            expect_true(late == "late".bytes());

            var closer = async.Task<bool>.spawn_local(() => {
                return quiet.read(Array<u8>(), 16).is_err();
            });
            async.yield_now();
            quiet.close();
            expect_true(closer.join().value());
            talker.close();
            listener.close();
        }
    );
}

[Test]
reads_end_on_the_default_backend() {
    reads_end_on(async.Backend.Automatic);
}

[Test]
reads_end_on_poll() {
    reads_end_on(async.Backend.Poll);
}

# Receives go through the ring here, so a cancel waits for the kernel's.
[Test]
reads_end_on_io_uring() {
    if (on_linux()) {
        reads_end_on(async.Backend.IoUring);
    }
}
