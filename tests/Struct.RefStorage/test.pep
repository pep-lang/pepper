struct Test {
    int x = 0;
};

struct Foo {
    Test t;

    construct(Test z) {
        _pep_trace_ptr(this, "this".c_str());
        _pep_trace_ptr(z, "z".c_str());
        this.t = z;
        _pep_trace_ptr(this.t, "this.t".c_str());
    }
};

main(): int {
    var t = Test();
    _pep_trace_ptr(t, "t".c_str());
    const f = Foo(t);
    _pep_trace_ptr(f, "f".c_str());
    return !(f.t === t);
}
