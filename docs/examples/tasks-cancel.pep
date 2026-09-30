import async;

main(): int {
    var polls = Array<int>();
    async.run(() => {
        var poller = async.Task<void>.spawn_local(() => {
            while (!async.is_cancelled()) {
                polls.append(1);
                async.sleep(5);
            }
        });
        async.sleep(30);
        poller.cancel();
        var result = poller.join();
        assert(result.is_err() && result.error().is_cancelled(), "a cancelled task's join fails");

        # A task still running when the first task returns is cancelled too,
        # and run waits for it to finish.
        async.Task<void>.spawn_local(() => {
            async.sleep(1000000);   # returns at once when cancelled
        });
    });
    assert(polls.count() > 0, "the poller ran until cancelled");
    return 0;
}
