import [Thread, ThreadLocal] from async;

# One variable, a separate value on every thread.
var calls = ThreadLocal<int>();
var totals = Atomic<long>(0);

record_call() {
    calls.set(calls.get() + 1);
}

work() {
    record_call();
    record_call();
    record_call();
    totals.fetch_add(calls.get());   # 3 on every thread
}

main(): int {
    record_call();
    var a = Thread.spawn(work);
    var b = Thread.spawn(work);
    a.join();
    b.join();
    assert(totals.load() == 6, "each thread counted its own calls");
    assert(calls.get() == 1, "the main thread's value is its own");
    return 0;
}
