import async;
import os;

main(): int {
    var order = Array<int>();
    async.run(() => {
        var tasks = Array<async.Task<void>>();
        var i = 0;
        while (i < 3) {
            var n = i;
            # The later a task starts, the shorter it sleeps.
            tasks.append(async.Task<void>.spawn_local(() => {
                async.sleep(os.Duration.from_milliseconds(((3 - n) * 20) as ulong));
                order.append(n);
            }));
            i = i + 1;
        }
        for (var task in tasks) {
            task.join();
        }
    });
    # All three slept at the same time, on one thread.
    assert(order[0] == 2 && order[1] == 1 && order[2] == 0, "shortest sleep first");
    return 0;
}
