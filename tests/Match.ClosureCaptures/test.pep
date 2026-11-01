# A closure in a `match` arm's value or in a guard captures the names the
# arm binds, as it captures a `const` local, in a `match` expression and a
# `match` statement alike, nested closures included. The payloads hold
# reference-counted strings: each closure keeps its own reference.

apply(f: () => int): int {
    return f();
}

[Value]
enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
}

enum Named {
    Item(name: String, count: int),
    Nothing,
}

main(): int {
    var s = Shape.Rect(2, 3);
    # An arm's value.
    var area = match (s) {
        Rect(w, h) => apply(() => w * h),
        Circle(r) => apply(() => r * r * 3),
    };
    assert(area == 6, "a closure in an arm's value");

    # A guard, in a `match` expression and a statement.
    var big = match (s) {
        Rect(w, h) if (apply(() => w * h) > 5) => 1,
        else => 0,
    };
    assert(big == 1, "a closure in a guard of a match expression");
    var guarded = 0;
    match (s) {
        Rect(w, _) if (apply(() => w) == 2) => {
            guarded = 1;
        }
        else => {}
    }
    assert(guarded == 1, "a closure in a guard of a match statement");

    # A closure kept past the `match`, and one nested in another.
    var item = Named.Item("pears", 4);
    var label = match (item) {
        Item(name, count) => () => $"{count} {name}",
        Nothing => () => "none",
    };
    item = Named.Nothing;
    assert(label() == "4 pears", "the closure keeps the payload it read");
    var nested = match (Named.Item("figs", 2)) {
        Item(name, count) => apply(() => apply(() => name.size + count)),
        Nothing => 0,
    };
    assert(nested == 6, "a closure nested in a closure");
    return 0;
}
