# Handle<T>: the release function runs exactly once, when the last
# reference goes away or at release(); detach() keeps it from running.

struct Counter {
    var n: int;

    construct(this.n = 0) {}
}

main(): int {
    var released = Counter();
    {
        var handle = Handle<int>(1, (value) => {
            released.n = released.n + value;
        });
        var copy = handle;
        if (!copy.is_owned()) { return 1; }
    }
    # Both references are gone: released once.
    if (released.n != 1) { return 2; }

    var early = Handle<int>(10, (value) => {
        released.n = released.n + value;
    });
    early.release();
    early.release();
    if (released.n != 11) { return 3; }
    if (early.is_owned()) { return 4; }
    if (early.value != 10) { return 5; }

    {
        var kept = Handle<int>(100, (value) => {
            released.n = released.n + value;
        });
        if (kept.detach() != 100) { return 6; }
    }
    # Detached: never released.
    if (released.n != 11) { return 7; }
    return 0;
}
