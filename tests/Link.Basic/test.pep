[Target(OS(Windows))] [Link("gdi32")] extern ulong GetStockObject(int objid);

[Target(!OS(Windows))] [Link("pthread")] extern long pthread_self();

main(): int {
    var r = -1;
    [Target(OS(Windows))] {
        # NULL_BRUSH (5) is a stock object with a nonzero handle on any
        # system, headless included.
        r = GetStockObject(5) != 0 ? 0 : 1;
    }
    [Target(!OS(Windows))] {
        # A live thread id is never zero.
        r = pthread_self() != 0 ? 0 : 1;
    }
    return r;
}
