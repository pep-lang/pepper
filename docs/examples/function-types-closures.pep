# Closure literals: anonymous functions that capture values.
struct Counter {
    int count;
    construct(this.count = 0) {}
    add(n: int) { count += n; }
}

apply(f: (int) => int, x: int): int {
    return f(x);
}

# A closure can outlive the function that made it: it keeps its own copy
# of 'n'.
make_adder(n: int): (int) => int {
    return (x) => x + n;
}

struct Scaler {
    int factor;
    construct(this.factor = 1) {}

    # Inside a method, a closure can use 'this' and the struct's members.
    scaler(): (int) => int {
        return (x) => x * factor;
    }
}

main(): int {
    # Parameter types written out: the closure's type is (int) => int.
    var double = (x: int) => x * 2;
    assert(double(21) == 42, "expression body");

    # With a function type to fill, the parameter types can be left out.
    var add: (int, int) => int = (a, b) => a + b;
    assert(add(40, 2) == 42, "types from the variable");
    assert(apply((x) => x * x, 5) == 25, "types from the parameter");

    # A block body, with the return type written after the parameters.
    var clamp = (x: int, low: int, high: int): int => {
        if x < low { return low; }
        if x > high { return high; }
        return x;
    };
    assert(clamp(7, 0, 5) == 5, "block body");

    # Captured values.
    var add_five = make_adder(5);
    assert(add_five(10) == 15, "captured parameter");
    var offset = 100;
    var shift = (x: int) => x + offset;
    assert(shift(1) == 101, "captured local");

    # A captured struct is shared, so the closure can change the object.
    var counter = Counter();
    var bump = () => counter.add(1);
    bump();
    bump();
    assert(counter.count == 2, "shared struct");

    var triple = Scaler(3).scaler();
    assert(triple(4) == 12, "captured this");

    # A closure can return a closure.
    var adder: (int) => (int) => int = (a) => (b) => a + b;
    assert(adder(2)(3) == 5, "curried");
    return 0;
}
