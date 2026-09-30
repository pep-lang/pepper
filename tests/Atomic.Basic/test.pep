import async;

main(): int {
    # POD: load/store round-trip.
    var a = async.Atomic<int>(41);
    if (a.load() != 41) { return 1; }
    a.store(99);
    if (a.load() != 99) { return 2; }

    # fetch_add returns the previous value.
    var c = async.Atomic<long>(10);
    if (c.fetch_add(5) != 10) { return 3; }
    if (c.load() != 15) { return 4; }

    # compare_exchange: success and failure paths.
    var b = async.Atomic<int>(7);
    if (!b.compare_exchange(7, 8)) { return 5; }
    if (b.load() != 8) { return 6; }
    if (b.compare_exchange(99, 100)) { return 7; }
    if (b.load() != 8) { return 8; }

    # exchange returns the previous value.
    var e = async.Atomic<int>(1);
    if (e.exchange(2) != 1) { return 9; }
    if (e.load() != 2) { return 10; }

    # is_lock_free: every slot this fixture uses is a native atomic.
    if (!a.is_lock_free()) { return 11; }
    if (!c.is_lock_free()) { return 12; }
    return 0;
}
