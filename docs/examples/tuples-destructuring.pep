struct Point {
    var x: int = 0;
    var y: int = 0;
}

min_max(values: Array<int>): (int, int) {
    var low = values[0];
    var high = values[0];
    for (var v in values) {
        if (v < low) {
            low = v;
        }
        if (v > high) {
            high = v;
        }
    }
    return (low, high);
}

main(): int {
    var values = Array<int>();
    values.append(4);
    values.append(-2);
    values.append(9);

    # Destructure the result into new variables.
    var (low, high) = min_max(values);
    assert(low == -2 && high == 9, "both ends");

    # `_` skips an element; a binding may state its type.
    var (_, top: long) = min_max(values);
    assert(top == 9, "only the maximum");

    # `const` makes every binding constant.
    const (first, last) = (values[0], values[2]);
    assert(first == 4 && last == 9, "constants");

    # Assign to existing places. The right side is evaluated first,
    # so this swaps.
    var a = 1;
    var b = 2;
    (a, b) = (b, a);
    assert(a == 2 && b == 1, "swapped");

    var p = Point();
    (p.x, p.y) = min_max(values);
    assert(p.x == -2 && p.y == 9, "fields are places too");
    return 0;
}
