import async;

const WORKERS = 4;

# At most two workers use the printer at once.
const printer = async.Semaphore(2);
const printing = async.Atomic<long>(0);
const most_printing = async.Atomic<long>(0);

# Every worker finishes a step before any starts the next.
const step_done = async.Barrier(WORKERS);
const steps_led = async.Atomic<long>(0);

# The main thread waits until every worker has set up.
const ready = async.Latch(WORKERS);

work() {
    ready.count_down();
    var step = 0;
    while (step < 3) {
        with (printer.permit()) {
            var now = printing.fetch_add(1) + 1;
            if (now > most_printing.load()) {
                most_printing.store(now);
            }
            printing.fetch_sub(1);
        }   # the permit is given back here
        if (step_done.wait()) {
            steps_led.fetch_add(1);   # one leader per step
        }
        step = step + 1;
    }
}

main(): int {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < WORKERS) {
        workers.append(async.Thread.spawn(work));
        i = i + 1;
    }
    ready.wait();
    assert(ready.is_ready(), "every worker counted down");
    for (var worker in workers) {
        worker.join();
    }
    assert(most_printing.load() <= 2, "the semaphore let two in at most");
    assert(steps_led.load() == 3, "each step had exactly one leader");
    return 0;
}
