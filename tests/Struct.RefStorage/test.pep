struct Test {
    int x = 0;
};

struct Foo {
    Test t;

    new(Test z) {
        trace_ptr(this, @"this");
        trace_ptr(z, @"z");
        this.t = z;
        trace_ptr(this.t, @"this.t");
    }
};

main(): int {
    var t = Test();
    trace_ptr(t, @"t");
    const f = Foo(t);
    trace_ptr(f, @"f");
    return !(f.t === t);
}
