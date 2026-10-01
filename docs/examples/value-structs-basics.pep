# A value struct is stored inline and copied like a number.
[Value]
struct Span {
    var start: int;
    var end: int;

    construct(this.start = 0, this.end = 0) {}

    length(): int {
        return end - start;
    }

    # Assigns a field of `this`, so it changes the value it is called on.
    grow(by: int) {
        end = end + by;
    }
}

# A reference struct holding a value: the span is part of the line's object.
struct Line {
    var text: String;
    var span: Span;

    construct(this.text = "") {}
}

# The parameter is a copy: growing it does not change the caller's span.
grown(span: Span, by: int): Span {
    span.grow(by);
    return span;
}

main(): int {
    var a = Span(2, 5);
    var b = a;          # a copy
    b.grow(10);
    if (a.length() != 3 || b.length() != 13) {
        return 1;
    }

    var c = grown(a, 1);
    if (a.length() != 3 || c.length() != 4) {
        return 2;
    }

    # Through a reference, the change lands in the object's own span.
    var line = Line("hello");
    var same = line;
    line.span.grow(5);
    if (same.span.length() != 5) {
        return 3;
    }

    # An element read from an array is a copy: change it, then store it back.
    var spans = Array<Span>();
    spans.append(a);
    var first = spans[0];
    first.grow(1);
    spans[0] = first;
    if (spans[0].length() != 4) {
        return 4;
    }

    # Values compare field by field.
    if (a != Span(2, 5)) {
        return 5;
    }
    return 0;
}
