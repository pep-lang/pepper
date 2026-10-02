struct Span {
    var start: int = 0;
    var length: int = 0;

    # Constructors overload like functions: each takes its own parameters.
    construct(this.length = 0) {}

    construct(start: int, end: int) {
        this.start = start;
        length = end - start;
    }

    construct(text: String) {
        length = text.length as int;
    }
}

main(): int {
    assert(Span().length == 0, "no arguments");
    assert(Span(5).length == 5, "one int");

    var middle = Span(2, 7);
    assert(middle.start == 2 && middle.length == 5, "two ints");

    assert(Span("pepper").length == 6, "a String");

    # As a value, the expected function type picks the constructor.
    var make: (int, int) => Span = Span;
    assert(make(1, 4).length == 3, "the (int, int) constructor");
    return 0;
}
