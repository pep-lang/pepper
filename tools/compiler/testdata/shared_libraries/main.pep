# Imports the Pepper shared libraries `base` and `top`. Prints `base`'s
# and `top`'s globals and its own, which `top`'s initializes before; the
# names a box `base` made, `top` filled and this program extended; how many
# times this thread called `base` (its thread-local is the thread's own);
# how many of `base`'s thread-locals the ended thread released; and
# whether `base` counts the allocations the program does, as one heap.

import [Thread] from async;
import base;
import top;

const AFTER: int = top.NEXT + 1;

work() {
    base.set_badge(7);
    base.count_call();
    base.count_call();
}

names(): String {
    var box = top.make();
    box.add("main");
    return ",".join(box.items);
}

main(): int {
    var listed = names();
    # One heap: `base` counts the same allocations as the program.
    var theirs = base.allocations();
    var ours = _pep_live_allocs();
    var thread = Thread.spawn(work);
    thread.join();
    print(
        $"{base.START} {top.NEXT} {AFTER} {listed} {base.count_call()} {base.released.load()} one heap {theirs == ours}"
    );
    return 0;
}
