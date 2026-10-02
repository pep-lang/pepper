struct Point {
    var x: int;
    var y: int;
    var label: String;
}

# One function describes any struct: the `static` block runs in the
# compiler, once per type `describe` is called with.
describe<T>(value: T): String {
    var out = StringBuilder();
    static (out, value) {
        out.append(reflect.name<T>());
        out.append("(");
        for (var field in reflect.properties<T>()) {
            # `field.name` is a compile-time string; `field.get(value)` reads
            # the field. Both statements use `out`, a captured runtime
            # value, so they are emitted once per field.
            out.append($"{field.name} = {field.get(value)}");
            if (!field.is_last) {
                out.append(", ");
            }
        }
    }
    out.append(")");
    return out.to_string();
}

main(): int {
    var p = Point();
    p.x = 3;
    p.y = 4;
    p.label = "corner";
    assert(describe(p) == "Point(x = 3, y = 4, label = corner)", "one line per field, in declaration order");
    return 0;
}
