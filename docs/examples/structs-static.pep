# Static methods belong to the type; inside it, they are called by name.
struct Vector {
    var x: double = 0.0;
    var y: double = 0.0;
    construct(this.x = 0.0, this.y = 0.0) {}

    static unit_x(): Vector {
        return Vector(1.0, 0.0);
    }

    # A static method calls another by its bare name.
    static scaled_unit_x(factor: double): Vector {
        var unit = unit_x();
        return Vector(unit.x * factor, unit.y * factor);
    }
}

main(): int {
    var v = Vector.scaled_unit_x(3.0);
    assert(v.x == 3.0 && v.y == 0.0, "called on the type name outside it");
    return 0;
}
