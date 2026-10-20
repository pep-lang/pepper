# The result of a call through a `shared` function value is new, so a
# `[Move]` parameter takes it, as it takes a named call's (#63).
import async;

struct Box {
    var n: int;

    construct(n: int) {
        this.n = n;
    }
}

make(): Box {
    return Box(1);
}

grow(b: Box): Box {
    b.n += 1;
    return b;
}

main(): int {
    var locals = async.ThreadLocal<Box>();
    shared () => Box app = make;
    shared (Box) => Box step = grow;
    locals.set(app());
    with (var b = locals.enter()) {
        print($"{b.n}");
    }
    locals.set(step(Box(5)));
    with (var b = locals.enter()) {
        print($"{b.n}");
    }
    return 0;
}
