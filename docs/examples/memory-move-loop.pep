import async;

struct Counter {
    var n: int;

    construct(n: int) {
        this.n = n;
    }
}

main(): int {
    var counters = async.Channel<Counter>();

    var a = Counter(1);
    for (var i in 0..3) {
        counters.send(move(a));
        # A new value before the next pass, so `a` holds the only reference.
        a = Counter(i + 2);
    }

    # var last = Counter(0);
    # var b = Counter(1);
    # for (var i in 0..3) {
    #     counters.send(move(b));   # error: 'last' also references its value
    #     b = Counter(i + 2);
    #     last = b;                 # still there on the next pass
    # }

    var total = 0;
    for (var _ in 0..3) {
        total += counters.receive().value().n;
    }
    print($"{total}");  # 6
    return 0;
}
