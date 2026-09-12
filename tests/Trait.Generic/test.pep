
trait Convert<T> {
    static this from(T t);
}

struct Foo {
    int x;

    new(this.x = 0) {}
}

struct Bar {
    int y;
    new(this.y = 42) {}
}

extend Foo with Convert<Bar> {
    static Foo from(Bar b) {
        return Foo(b.y);
    }
}

main(): int {
    var bar = Bar();
    var foo = Foo.from(bar);
    return foo.x - 42;
}
