struct Vector {
    var x: int = 0;
    var y: int = 0;

    construct(this.x = 0, this.y = 0) {}

    # A method: name, parameters, then the return type after `:`.
    length_squared(): int {
        # Fields can be named directly inside a method...
        return x * x + y * y;
    }

    # ...or through `this`, the object the method was called on.
    dot(other: Vector): int {
        return this.x * other.x + this.y * other.y;
    }

    # Methods can change fields, and can call other methods.
    scale(factor: int) {
        x = x * factor;
        y = y * factor;
    }

    # The return type can also come first, C-style.
    bool is_zero() {
        return length_squared() == 0;
    }

    # A static method belongs to the type, not to one object: there is
    # no `this`. Call it on the type name.
    static unit_x(): Vector {
        return Vector(1, 0);
    }
}

main(): int {
    var v = Vector(3, 4);
    assert(v.length_squared() == 25, "method call");
    assert(v.dot(Vector(1, 1)) == 7, "method with an argument");

    v.scale(2);
    assert(v.x == 6 && v.y == 8, "a method can modify its object");

    assert(Vector().is_zero(), "methods can be called on a temporary");
    assert(Vector.unit_x().x == 1, "static method called on the type");
    return 0;
}
