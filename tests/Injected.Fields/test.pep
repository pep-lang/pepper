# Each construct whose type the compiler injects, as a field initializer
# (pepper#103).
total(r: Range<int>): int {
    var n = 0;
    for (var i in r) {
        n += i;
    }
    return n;
}

struct Fields {
    var text: String = "t";
    var sum: String = "a" + "b" + $"{1}";
    var shown: String = $"n{2}";
    var items: int[] = [1, 2];
    var map: HashMap<String, int> = ["k": 4];
    var pair: (int, String) = (5, "p");
    var maybe: int? = Optional<int>.Value(6);
    var ranged: int = total(1..3);

    construct() {}
}

main(): int {
    var f = Fields();
    var text = $"{f.text} {f.sum} {f.shown} {f.items.count} {f.map["k"]} {f.pair.0}{f.pair.1} {f.maybe.value()} {f.ranged}";
    if (text != "t ab1 n2 2 4 5p 6 3") {
        return 1;
    }
    return 0;
}
