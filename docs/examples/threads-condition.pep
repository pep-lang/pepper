import async;

# A baker makes pies and eaters take them. The eaters sleep on a Condition
# until there is a pie, or until the bakery closes.
[Shared]
struct Bakery {
    const pies: async.Atomic<long>;
    const closed: async.Atomic<int>;
    construct() {
        pies = async.Atomic<long>(0);
        closed = async.Atomic<int>(0);
    }
}

const bakery = async.Mutex<Bakery>(Bakery());
const changed = bakery.condition();
const eaten = async.Atomic<long>(0);

eat() {
    while (true) {
        with (var b = bakery.lock()) {
            # Wait in a loop: a wakeup can be spurious, and another eater
            # may take the pie first.
            while (b.pies.load() == 0 && b.closed.load() == 0) {
                changed.wait();   # unlocks, sleeps, locks again
            }
            if (b.pies.load() == 0) {
                return;   # closed and nothing left; the block unlocks
            }
            b.pies.fetch_sub(1);
        }
        eaten.fetch_add(1);
    }
}

main(): int {
    var eaters = Array<async.Thread>();
    var i = 0;
    while (i < 3) {
        eaters.append(async.Thread.spawn(eat));
        i = i + 1;
    }
    i = 0;
    while (i < 50) {
        with (var b = bakery.lock()) {
            b.pies.fetch_add(1);
            changed.notify_one();
        }
        i = i + 1;
    }
    with (var b = bakery.lock()) {
        b.closed.store(1);
        changed.notify_all();
    }
    for (var eater in eaters) {
        eater.join();
    }
    assert(eaten.load() == 50, "every pie was eaten once");
    return 0;
}
