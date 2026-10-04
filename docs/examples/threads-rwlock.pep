import async;

# A price list that many threads read and one thread now and then updates.
# A writer changes both prices together, so a reader never sees one updated
# and the other not.
[Shared]
struct Prices {
    const coffee: async.Atomic<long>;
    const tea: async.Atomic<long>;
    construct() {
        coffee = async.Atomic<long>(300);
        tea = async.Atomic<long>(250);
    }
}

const prices = async.RwLock<Prices>(Prices());
const mismatches = async.Atomic<long>(0);

check_prices() {
    var i = 0;
    while (i < 1000) {
        with (var p = prices.read()) {   # many readers at once
            if (p.coffee.load() - p.tea.load() != 50) {
                mismatches.fetch_add(1);
            }
        }
        i = i + 1;
    }
}

raise_prices() {
    var i = 0;
    while (i < 100) {
        with (var p = prices.write()) {   # no reader sees the middle
            p.coffee.fetch_add(10);
            p.tea.fetch_add(10);
        }
        i = i + 1;
    }
}

main(): int {
    var threads = Array<async.Thread>();
    var i = 0;
    while (i < 3) {
        threads.append(async.Thread.spawn(check_prices));
        i = i + 1;
    }
    threads.append(async.Thread.spawn(raise_prices));
    for (var thread in threads) {
        thread.join();
    }
    assert(mismatches.load() == 0, "no reader saw a half-done update");
    with (var p = prices.read()) {
        assert(p.coffee.load() == 1300, "every raise landed");
    }
    return 0;
}
