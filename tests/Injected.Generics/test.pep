# Each construct whose type the compiler injects, in a generic function's
# and a generic struct's defaults and field initializers, which reach the
# program through their specializations (pepper#103).
total(r: Range<int>): int {
    var n = 0;
    for (var i in r) {
        n += i;
    }
    return n;
}

shown<T>(
    value: T,
    sum: String = "a" + $"{1}",
    items: int[] = [1, 2],
    pair: (int, String) = (5, "t"),
    ranged: int = total(1..3)
): String {
    return $"{value} {sum} {items.count} {pair.0}{pair.1} {ranged} {(value, 1).0}";
}

struct Box<T> {
    var value: T;
    var sum: String = "a" + $"{2}";
    var items: int[] = [3];
    var pair: (int, String) = (5, "u");
    var made: String;

    construct(value: T, made: String = $"b{4}" + "!") {
        this.value = value;
        this.made = made;
    }

    get(suffix: String = $"m{5}" + "?"): String {
        return $"{value} {sum} {items.count} {pair.1} {made} {suffix}";
    }
}

main(): int {
    if (shown(7) != "7 a1 2 5t 3 7") {
        return 1;
    }
    if (shown("s") != "s a1 2 5t 3 s") {
        return 2;
    }
    if (Box<int>(8).get() != "8 a2 1 u b4! m5?") {
        return 3;
    }
    return 0;
}
