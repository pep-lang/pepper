struct Rect {
    var width: int;
    var height: int;
    var area: int;

    # `this.width = 1` declares a parameter that is stored straight into the
    # field `width`; `1` is its default when the caller leaves it out.
    construct(this.width = 1, this.height = 1) {
        area = width * height;
    }
}

struct Temperature {
    var celsius: float;

    # Ordinary parameters work too; write them `Type name`.
    construct(float fahrenheit = 32.0) {
        celsius = (fahrenheit - 32.0) * 5.0 / 9.0;
    }
}

main(): int {
    var r = Rect(3, 4);
    assert(r.width == 3 && r.height == 4, "arguments fill the fields");
    assert(r.area == 12, "the constructor body runs after the fields are set");

    var tall = Rect(2);
    assert(tall.width == 2 && tall.height == 1, "omitted arguments use their defaults");

    var unit = Rect();
    assert(unit.area == 1, "every parameter has a default, so Rect() works");

    var boiling = Temperature(212.0);
    assert(boiling.celsius == 100.0, "212 F is 100 C");
    assert(Temperature().celsius == 0.0, "the default is 32 F");
    return 0;
}
