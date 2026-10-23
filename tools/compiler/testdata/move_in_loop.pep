import async;

struct Box {
    var n: int;

    construct(n: int) {
        this.n = n;
    }
}

# A loop may move a value it gives the variable again before the next pass,
# when nothing outside the body keeps what the body made from it.
main(): int {
    var c = async.Channel<Box>();
    var keep = Box(0);
    var b = Box(1);
    for (var i in 0..3) {
        c.send(move(b));
        b = Box(i);
        var local = b;
        local.n += 1;
        var bump = () => {
            local.n += 1;
        };
        bump();
        if (i == 1) {
            continue;
        }
        keep.n += 1;
    }
    int j = 0;
    while (j < 2) {
        j += 1;
        for (var k in 0..2) {
            c.send(move(b));
            b = Box(10);
        }
    }
    var total = 0;
    for (var i in 0..7) {
        total += c.receive().value().n;
    }
    print($"{total} {keep.n} {b.n}");
    return 0;
}
