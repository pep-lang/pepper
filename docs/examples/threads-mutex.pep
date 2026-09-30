import async;

# Each balance is an Atomic, but moving money changes both, and no thread
# may see it in neither account. A Mutex makes the pair of updates one step.
[Shared]
struct Accounts {
    const checking: async.Atomic<long>;
    const savings: async.Atomic<long>;
    construct(long checking = 0, long savings = 0) {
        this.checking = async.Atomic<long>(checking);
        this.savings = async.Atomic<long>(savings);
    }
}

const accounts = async.Mutex<Accounts>(Accounts(1000, 0));
const bad_totals = async.Atomic<long>(0);

move_to_savings() {
    var i = 0;
    while (i < 1000) {
        with (var a = accounts.lock()) {
            a.checking.fetch_sub(1);
            a.savings.fetch_add(1);
        }   # unlocked here, on every path out of the block
        i = i + 1;
    }
}

audit() {
    var i = 0;
    while (i < 1000) {
        with (var a = accounts.lock()) {
            if (a.checking.load() + a.savings.load() != 1000) {
                bad_totals.fetch_add(1);
            }
        }
        i = i + 1;
    }
}

main(): int {
    var mover = async.Thread.spawn(move_to_savings);
    var auditor = async.Thread.spawn(audit);
    mover.join();
    auditor.join();
    assert(bad_totals.load() == 0, "the auditor never saw money missing");

    # try_lock does not wait: the body runs if the lock was free, and the
    # else block runs if another thread held it.
    with (var a = accounts.try_lock()) {
        assert(a.savings.load() == 1000, "everything was moved");
    } else {
        assert(false, "no other thread holds the lock now");
    }
    return 0;
}
