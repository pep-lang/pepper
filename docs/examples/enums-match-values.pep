# `match` produces a value, `is` tests one case, and a `match` on an
# integer, character, `bool` or `String` compares with literals.
enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Point,
}

enum List {
    Empty,
    Cons(head: int, tail: List),
}

area(s: Shape): int {
    return match (s) {
        Circle(r) => 3 * r * r,
        Rect(w, h) => w * h,
        Point => 0,
    };
}

keyword(word: String): int {
    return match (word) {
        "import" => 1,
        "export", "extern" => 2,
        else => 0,
    };
}

main(): int {
    var total = area(Shape.Rect(2, 3)) + keyword("extern");

    # `is` binds only in the block of the `if` or `while` it is the
    # condition of.
    var s = Shape.Circle(1);
    if (s is Circle(r)) {
        total += r;
    }

    var list = List.Cons(1, List.Cons(2, List.Empty));
    while (list is Cons(head, tail)) {
        total += head;
        list = tail;
    }

    var point = Shape.Point is Point;
    if (point && !(s is Rect)) {
        total += 100;
    }

    # A `match` on an integer needs an `else`: literals cannot list every
    # value.
    var size = match (total) {
        0 => "none",
        1, 2, 3 => "few",
        else => "many",
    };
    assert(size == "many", "total is past three");
    assert(total == 6 + 2 + 1 + 3 + 100, "every step adds up");
    return 0;
}
