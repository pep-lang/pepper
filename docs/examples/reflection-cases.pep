enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Point,
}

# `case.matches(value)` tests which case a value holds, and each of the
# case's `values` reads its value with `get`.
describe<E>(value: E): String {
    var out = "";
    static (out, value) {
        for (var case in reflect.cases<E>()) {
            if (case.matches(value)) {
                out = case.name;
                for (var item in case.values) {
                    out = out + $" {item.name}={item.get(value)}";
                }
            }
        }
    }
    return out;
}

# `case.get(values...)` makes a case; here, each value is `size`.
square<E>(name: String, size: int): E {
    var out: E;
    static (out, name, size) {
        for (var case in reflect.cases<E>()) {
            if (name == case.name) {
                if (case.values.count == 0) {
                    out = case.get();
                } else if (case.values.count == 1) {
                    out = case.get(size);
                } else if (case.values.count == 2) {
                    out = case.get(size, size);
                }
            }
        }
    }
    return out;
}

main(): int {
    assert(describe(Shape.Rect(3, 4)) == "Rect width=3 height=4", "a case's values");
    assert(describe(Shape.Point) == "Point", "a case without values");
    assert(describe(square<Shape>("Rect", 5)) == "Rect width=5 height=5", "a made case");
    assert(describe(square<Shape>("Circle", 2)) == "Circle radius=2", "one value");
    return 0;
}
