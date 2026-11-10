# Releases chains that run through the Pepper library `chain`'s structs and
# the program's `Wrap` in turn, at the depth given, shallow and deep enough
# to overflow the stack if each release recursed into the next: `Box ->
# Wrap -> Box`, and `Box -> Pair -> Box -> Wrap -> Box`, which extends the
# library's own cycle. Prints whether each released every `Wrap`. It loads
# no runtime module beyond the prelude, which keeps its build short.

import chain;

struct Counter {
    var count: int = 0;
}

struct Wrap {
    var box: chain.Box;
    var released: Counter;

    construct(box: chain.Box, released: Counter) {
        this.box = box;
        this.released = released;
    }

    destruct {
        released.count += 1;
    }
}

extend Wrap with chain.Item {
    links(): int {
        return 1;
    }
}

# Builds the chain and releases it, at the local's scope exit.
wrap_chain(depth: int, released: Counter) {
    chain.Item item = chain.End();
    for (var i in 0..depth) {
        item = Wrap(chain.Box(item), released);
    }
}

pair_chain(depth: int, released: Counter) {
    chain.Item item = chain.End();
    for (var i in 0..depth) {
        item = Wrap(chain.Box(chain.Pair(chain.Box(item))), released);
    }
}

main(args: String[]): int {
    var depth = int.parse(args[1]).value();
    var wraps = Counter();
    wrap_chain(depth, wraps);
    var pairs = Counter();
    pair_chain(depth, pairs);
    print($"wrap chain released {wraps.count == depth}");
    print($"pair chain released {pairs.count == depth}");
    return 0;
}
