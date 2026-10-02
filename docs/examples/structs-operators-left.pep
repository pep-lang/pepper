# A number on the left of an operator: `2 * v` with a struct `v`.
struct Vector {
    var x: double;
    var y: double;

    construct(this.x = 0.0, this.y = 0.0) {}

    # `v * 2.0` calls `v.*(2.0)`.
    *(scale: double): Vector {
        return Vector(x * scale, y * scale);
    }
}

# `2.0 * v` uses the operator of the left operand's type, so `double`
# declares it in an extension; `this` is the number.
extend double {
    *(v: Vector): Vector {
        return v * this;
    }
}

# `2` is an `int`, which needs its own.
extend int {
    *(v: Vector): Vector {
        return v * (this as double);
    }
}

main(): int {
    var v = Vector(1.0, 2.0);
    var a = v * 2.0;
    var b = 2.0 * v;
    var c = 2 * v;
    assert(a.x == 2.0 && b.x == 2.0 && c.y == 4.0, "both orders");
    # Numbers on both sides still use the built-in operator.
    assert(2 * 3 == 6, "built-in");
    return 0;
}
