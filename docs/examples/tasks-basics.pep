import async;

main(): int {
    var log = Array<String>();
    async.run(() => {
        # A task starts when the running task next waits.
        var worker = async.Task<int>.spawn_local(() => {
            log.append("worker starts");
            async.yield_now();
            log.append("worker ends");
            return 42;
        });
        log.append("first task");
        var answer = worker.join().value();   # waits; the worker runs
        assert(answer == 42, "join returns the body's value");
        log.append("joined");
    });
    assert(log[0] == "first task" && log[1] == "worker starts", "tasks take turns");
    assert(log[2] == "worker ends" && log[3] == "joined", "join waited");
    return 0;
}
