struct Test {
    int x = 0;
};

struct Foo {
    Test t;

    construct(Test z) {
        this.t = z;
    }
};

main(): int {
    var t = Test();
    const f = Foo(t);
    return !(f.t === t);
}
