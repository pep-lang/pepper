import async;

struct Log {
    var lines: Array<String>;
    construct() {
        this.lines = Array<String>();
    }
}

const log = async.Mutex<Log>(Log());
const jobs = async.Channel<int>(2);

main(): int {
    # One worker: every task below shares one thread.
    async.run_with(async.RuntimeOptions().workers(1), () => {
        # The consumer parks in the channel until a value arrives.
        var consumer = async.Task<int>.spawn_local(() => {
            var total = 0;
            for (var job in jobs) {
                total = total + job;
            }
            return total;
        });
        # A task may hold the lock while it waits; the other task parks
        # until it is free.
        var writer = async.Task<void>.spawn_local(() => {
            with (var l = log.lock()) {
                l.lines.append("first");
                async.sleep(10);
                l.lines.append("second");
            }
        });
        async.yield_now();
        with (var l = log.lock()) {
            l.lines.append("third");
        }
        writer.join();

        # The producer parks while the bounded channel is full.
        var i = 1;
        while (i <= 5) {
            jobs.send(i);
            i = i + 1;
        }
        jobs.close();
        assert(consumer.join().value() == 15, "every job arrived");
    });
    with (var l = log.lock()) {
        assert(l.lines[2] == "third", "the lock waited for the writer");
    }
    return 0;
}
