struct Celsius {
    var degrees: double;

    # `[Implicit]` lets a `double` become a `Celsius` wherever one is expected.
    [Implicit]
    construct(double degrees) {
        this.degrees = degrees;
    }
}

struct Label {
    var text: String;

    # Without `[Implicit]`, callers write `Label("...")` themselves.
    construct(String text) {
        this.text = text;
    }
}

describe(t: Celsius): String {
    return (t.degrees > 30.0) ? "hot" : "mild";
}

main(): int {
    assert(describe(35.0) == "hot", "an argument converts");
    var today: Celsius = 21.5;            # a typed variable converts
    assert(describe(today) == "mild", "already a Celsius");

    var label = Label("kitchen");         # no conversion: call the constructor
    assert(label.text == "kitchen", "explicit constructor call");

    var n = 12.0;                         # no slot type: stays a double
    assert(n == 12.0, "untyped local");
    return 0;
}
