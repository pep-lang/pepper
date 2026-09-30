import async;

main(): int {
    var a = async.Atomic<int>(41);
    assert(a.load() == 41, "the initial value");

    a.store(1);
    assert(a.load() == 1, "store replaces the value");

    # The fetch_ operations return the value from before the change.
    assert(a.fetch_add(5) == 1, "fetch_add returns the old value");
    assert(a.load() == 6, "1 + 5");
    assert(a.fetch_sub(2) == 6, "fetch_sub returns the old value");
    assert(a.load() == 4, "6 - 2");

    var flags = async.Atomic<uint>(12);          # 0b1100
    flags.fetch_and(10);                   # 0b1000
    assert(flags.load() == 8, "fetch_and");
    flags.fetch_or(1);                     # 0b1001
    assert(flags.load() == 9, "fetch_or");
    flags.fetch_xor(9);                    # 0b0000
    assert(flags.load() == 0, "fetch_xor");

    # compare_exchange stores only if the current value is the expected one.
    assert(a.compare_exchange(4, 10), "4 matched, so 10 is stored");
    assert(!a.compare_exchange(4, 20), "10 does not match 4");
    assert(a.load() == 10, "the failed exchange changed nothing");

    # exchange always stores, and returns what was there.
    assert(a.exchange(3) == 10, "exchange returns the old value");
    assert(a.load() == 3, "and stores the new one");

    assert(a.is_lock_free(), "an int fits a native atomic instruction");
    return 0;
}
