# A value a closure captured can be moved once no closure that holds it
# is left: one that went out of scope, one in another function that
# returned, and one passed to a function that does not keep it (#173).
import async;
import [Channel] from async;

struct Box {
    var n: int;

    construct(n: int) {
        this.n = n;
    }
}

make(): Box {
    var b = Box(1);
    var bump = () => {
        b.n += 1;
    };
    bump();
    return b;
}

twice(f: () => void) {
    f();
    f();
}

main(): int {
    var c = Channel<Box>();
    var made = make();
    c.send(move(made));
    var scoped = Box(10);
    {
        var bump = () => {
            scoped.n += 1;
        };
        bump();
    }
    c.send(move(scoped));
    var passed = Box(20);
    twice(() => {
        passed.n += 1;
    });
    c.send(move(passed));
    for (var i in 0..3) {
        print($"{c.receive().value().n}");
    }
    return 0;
}
