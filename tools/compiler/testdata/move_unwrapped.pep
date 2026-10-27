import async;

struct Foo {
    var x: int;

    construct(x: int) {
        this.x = x;
    }
}

make(x: int): Result<Foo, String> {
    return Result<Foo, String>.ok(Foo(x));
}

maybe(x: int): Foo? {
    return Optional<Foo>.Value(Foo(x));
}

# What `?` or a pattern took from a call's result is the value's only
# reference when it is moved (#266): each count printed is 1.
from_try(c: async.Channel<Foo>): Result<void, String> {
    var f = make(1)?;
    print(__refcount<Foo>(f));
    c.send(move(f));
    return Result<void, String>.ok();
}

from_optional(c: async.Channel<Foo>): int? {
    var f = maybe(2)?;
    print(__refcount<Foo>(f));
    c.send(move(f));
    return Optional<int>.Value(0);
}

main(): int {
    var c = async.Channel<Foo>();
    from_try(c);
    from_optional(c);
    if (make(3) is Ok(f)) {
        print(__refcount<Foo>(f));
        c.send(move(f));
    }
    match (make(4)) {
        Ok(f) => {
            print(__refcount<Foo>(f));
            c.send(move(f));
        }
        Err(e) => {}
    }
    var total = 0;
    for (var i in 0..4) {
        var f = c.receive().value();
        total += f.x * __refcount<Foo>(f) as int;
    }
    print(total);
    return 0;
}
