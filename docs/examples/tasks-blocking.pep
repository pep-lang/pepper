import async;

const ticks = async.Atomic<int>(0);

main(): int {
    async.run_with(async.RuntimeOptions().workers(1), () => {
        # Keeps running on the one worker while the blocking call waits.
        var ticker = async.Task<void>.spawn_local(() => {
            while (ticks.load() < 3) {
                async.sleep(5);
                ticks.fetch_add(1);
            }
        });
        var answer = async.run_blocking<int>(() => {
            async.Thread.sleep(50);   # blocks a pool thread, not the worker
            return 42;
        });
        assert(answer == 42, "the blocking call's result");
        assert(ticks.load() > 0, "the worker ran the ticker meanwhile");
        ticker.join();
    });
    return 0;
}
