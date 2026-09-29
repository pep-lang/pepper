# Function values in fields, arrays, globals, and return values.
square(x: int): int { return x * x; }
negate(x: int): int { return -x; }
increment(x: int): int { return x + 1; }

struct Transform {
    var op: (int) => int;
    construct(this.op = square) {}
    run(x: int): int { return op(x); }
}

# Choose a function at run time and return it.
pick(squared: bool): (int) => int {
    if squared {
        return square;
    }
    return negate;
}

# A module-level function variable.
var handler = increment;

# A type alias can name a function type, even a generic one.
type Combine<T> = (T, T) => T;
add(a: int, b: int): int { return a + b; }
fold(values: int[], combine: Combine<int>, start: int): int {
    var total = start;
    for (var v in values) {
        total = combine(total, v);
    }
    return total;
}

# A function that returns nothing has the return type void.
var events = 0;
record(n: int) { events += n; }

main(): int {
    var t = Transform();
    assert(t.run(4) == 16, "the default op squares");
    t.op = negate;
    assert(t.op(4) == -4, "call through a field");

    var pipeline = Array<(int) => int>();
    pipeline.append(increment);
    pipeline.append(square);
    pipeline.append(negate);
    var value = 2;
    for (var step in pipeline) {
        value = step(value);
    }
    assert(value == -9, "-((2 + 1) * (2 + 1))");
    assert(pipeline[1](5) == 25, "call an array element");

    assert(pick(true)(5) == 25, "call a returned function directly");
    var chosen = pick(false);
    assert(chosen(5) == -5, "call a stored returned function");

    assert(handler(1) == 2, "global function value");
    handler = square;
    assert(handler(3) == 9, "reassigned global");

    var numbers = Array<int>();
    numbers.append(1);
    numbers.append(2);
    numbers.append(3);
    assert(fold(numbers, add, 10) == 16, "10 + 1 + 2 + 3");

    var callback: (int) => void = record;
    callback(2);
    callback(5);
    assert(events == 7, "void function values");
    return 0;
}
