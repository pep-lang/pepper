struct Test {
    int x = 0;
};

struct Foo {
    Test t;

    construct(Test z) {
        trace_ptr(this, "this".c_str());
        trace_ptr(z, "z".c_str());
        this.t = z;
        trace_ptr(this.t, "this.t".c_str());
    }
};

main(): int {
    var t = Test();
    trace_ptr(t, "t".c_str());
    const f = Foo(t);
    trace_ptr(f, "f".c_str());
    return !(f.t === t);
}
