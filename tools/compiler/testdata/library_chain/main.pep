# Releases chains that run through the Pepper library `chain`'s structs and
# the program's `Wrap` in turn, at the depth given, shallow and deep enough
# to overflow the stack if each release recursed into the next: `Box ->
# Wrap -> Box`, and `Box -> Pair -> Box -> Wrap -> Box`, which extends the
# library's own cycle. Prints how many `Wrap`s each released.

import async;
import chain;
import process;

const released = async.Atomic<int>(0);

struct Wrap {
    var box: chain.Box;

    construct(box: chain.Box) {
        this.box = box;
    }

    destruct {
        released.fetch_add(1);
    }
}

extend Wrap with chain.Item {
    links(): int {
        return 1;
    }
}

wrap_chain(depth: int) {
    chain.Item item = chain.End();
    for (var i in 0..depth) {
        item = Wrap(chain.Box(item));
    }
}

pair_chain(depth: int) {
    chain.Item item = chain.End();
    for (var i in 0..depth) {
        item = Wrap(chain.Box(chain.Pair(chain.Box(item))));
    }
}

main(): int {
    var depth = int.parse(process.arguments()[1]).value();
    wrap_chain(depth);
    print($"wrap chain released {released.exchange(0) == depth}");
    pair_chain(depth);
    print($"pair chain released {released.exchange(0) == depth}");
    return 0;
}
