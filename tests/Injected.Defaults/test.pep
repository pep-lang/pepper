# Each construct whose type the compiler injects, as a parameter default
# of a free function, a constructor and a method (pepper#103): a string
# literal, `+` on strings, an interpolated string, array and map literals,
# a tuple (also labeled), an `Optional` and a range.
total(r: Range<int>): int {
    var n = 0;
    for (var i in r) {
        n += i;
    }
    return n;
}

joined(tag: String = "g" + "en"): String {
    return tag;
}

numbered(tag: String = $"g{1}"): String {
    return tag;
}

all(
    text: String = "t",
    sum: String = "a" + "b" + $"{1}",
    shown: String = $"n{2}{true}",
    items: int[] = [1, 2, 3],
    map: HashMap<String, int> = ["k": 4],
    pair: (int, String) = (5, "p"),
    point: (x: int, y: int) = (x: 6, y: 7),
    maybe: int? = Optional<int>.Value(8),
    ranged: int = total(1..3)
): String {
    return $"{text} {sum} {shown} {items.count} {map["k"]} {pair.0}{pair.1} {point.x}{point.y} {maybe.value()} {ranged}";
}

struct Holder {
    var text: String;

    construct(text: String = "c" + $"{2}") {
        this.text = text;
    }

    get(suffix: String = $"m{3}" + "!", items: int[] = [9]): String {
        return $"{text}{suffix}{items[0]}";
    }
}

main(): int {
    if (joined() != "gen") {
        return 1;
    }
    if (numbered() != "g1") {
        return 2;
    }
    if (all() != "t ab1 n2true 3 4 5p 67 8 3") {
        return 3;
    }
    if (Holder().get() != "c2m3!9") {
        return 4;
    }
    return 0;
}
