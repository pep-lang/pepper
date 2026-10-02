# A guard (`if condition`) after an arm's patterns: the arm runs only when a
# pattern matches and the guard holds; otherwise the next arm is tried.
enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Point,
}

describe(s: Shape): String {
    return match (s) {
        # The guard reads the names its patterns bind.
        Circle(r) if r > 10 => "a large circle",
        Circle => "a circle",
        Rect(w, h) if w == h => "a square",
        Rect => "a rectangle",
        Point => "a point",
    };
}

# A guarded arm handles nothing for the check that every value is handled,
# since its guard may fail: the `bool` match below still needs `false`.
toll(heavy: bool, axles: int): int {
    match (heavy) {
        true if axles > 4 => {
            return 30;
        }
        true => {
            return 20;
        }
        false => {
            return 10;
        }
    }
}

main(): int {
    assert(describe(Shape.Circle(20)) == "a large circle", "the guard holds");
    assert(describe(Shape.Circle(2)) == "a circle", "the guard fails, the next arm runs");
    assert(describe(Shape.Rect(3, 3)) == "a square", "equal sides");
    assert(describe(Shape.Rect(3, 4)) == "a rectangle", "unequal sides");
    assert(toll(true, 6) + toll(true, 2) + toll(false, 2) == 60, "each arm runs once");

    # Guards work on tuples too.
    var pair = (5, true);
    var kind = match (pair) {
        (n, true) if n > 3 => 1,
        (_, true) => 2,
        (_, false) => 3,
    };
    assert(kind == 1, "the first arm's guard holds");
    return 0;
}
