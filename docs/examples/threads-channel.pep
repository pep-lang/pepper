import async;

# The main thread sends numbers to a pool of workers, and the workers send
# their squares back on a second channel.
const jobs = async.Channel<long>(16);    # bounded: send waits while 16 are queued
const results = async.Channel<long>();   # unbounded: send never waits

square_numbers() {
    # The loop ends once `jobs` is closed and empty.
    for (var n in jobs) {
        results.send(n * n);
    }
}

# A `shared` function value is thread-safe, so a channel can carry work.
const tasks = async.Channel<async.ThreadBody>();
const ran = Atomic<long>(0);

run_tasks() {
    for (var task in tasks) {
        task();
    }
}

main(): int {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(square_numbers));
        i = i + 1;
    }
    var n: long = 1;
    while (n <= 100) {
        jobs.send(n);
        n = n + 1;
    }
    jobs.close();   # no more work: each worker's loop ends
    for (var worker in workers) {
        worker.join();
    }
    results.close();

    var total: long = 0;
    for (var square in results) {
        total = total + square;
    }
    assert(total == 338350, "the sum of the first 100 squares");

    # receive() returns a Result: an error once the channel is closed and
    # empty. A closed channel refuses new values.
    assert(results.receive().is_err(), "nothing left");
    assert(!results.send(1), "closed");

    var runner = async.Thread.spawn(run_tasks);
    tasks.send(() => { ran.fetch_add(1); });
    tasks.send(() => { ran.fetch_add(10); });
    tasks.close();
    runner.join();
    assert(ran.load() == 11, "the runner ran both tasks");
    return 0;
}
