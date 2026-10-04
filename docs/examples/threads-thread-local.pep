import async;

import [Thread] from async;

# A separate `depth` on every thread, each starting at 0.
[ThreadLocal]
var depth: int = 0;

const deepest = async.Atomic<int>(0);

descend(levels: int) {
    depth += 1;
    if (depth > deepest.load()) {
        deepest.store(depth);
    }
    if (levels > 1) {
        descend(levels - 1);
    }
    depth -= 1;
}

work() {
    descend(5);
}

main(): int {
    depth = 100;   # changes only the main thread's copy
    var a = Thread.spawn(work);
    var b = Thread.spawn(work);
    a.join();
    b.join();
    assert(deepest.load() == 5, "each thread counted from its own 0");
    assert(depth == 100, "the main thread's copy is its own");
    return 0;
}
