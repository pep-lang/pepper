import async;

# A worker takes jobs from a queue, sleeping while it is empty.
const jobs = async.Mutex<Array<long>>(Array<long>());
const changed = jobs.condition();
const done = Atomic<long>(0);

work() {
    var taken = 0;
    while (taken < 5) {
        with (var queue = jobs.lock()) {
            # Waits while the predicate holds; spurious wakeups are handled.
            # The predicate is given the locked value: it cannot capture it.
            changed.wait_while((waiting: Array<long>): bool => waiting.count() == 0);
            done.fetch_add(queue.remove_at(0));
            taken = taken + 1;
        }
    }
}

main(): int {
    var worker = async.Thread.spawn(work);
    var i: long = 1;
    while (i <= 5) {
        with (var queue = jobs.lock()) {
            queue.append(i);
            changed.notify_all();
        }
        i = i + 1;
    }
    worker.join();
    assert(done.load() == 15, "every job was taken once");

    with (var queue = jobs.lock()) {
        # Gives up after 10 milliseconds: nothing is queued.
        var ready = changed.wait_while_for(10, (waiting: Array<long>): bool => waiting.count() == 0);
        assert(!ready, "the time ran out");
    }
    return 0;
}
