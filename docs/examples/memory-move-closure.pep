import async;

struct Counter {
    var n: int;

    construct(n: int) {
        this.n = n;
    }
}

repeat(times: int, f: () => void) {
    for (var _ in 0..times) {
        f();
    }
}

main(): int {
    var counters = async.Channel<Counter>();

    var a = Counter(0);
    {
        var bump = () => {
            a.n += 1;
        };
        bump();
    }
    # `bump` is gone with its block, so `a` holds the only reference.
    counters.send(move(a));

    var b = Counter(10);
    # `repeat` calls the closure but does not keep it.
    repeat(3, () => {
        b.n += 1;
    });
    counters.send(move(b));

    # var c = Counter(0);
    # var show = () => print($"{c.n}");
    # counters.send(move(c));   # error: 'show' also references its value

    print($"{counters.receive().value().n}");  # 1
    print($"{counters.receive().value().n}");  # 13
    return 0;
}
