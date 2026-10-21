# Each construct whose type the compiler injects, in a module-scope
# constant's initializer (pepper#103). A `String` is not thread-safe, so
# the constants keep what the strings and collections measure.
total(r: Range<int>): int {
    var n = 0;
    for (var i in r) {
        n += i;
    }
    return n;
}

count_of(items: int[]): ulong {
    return items.count;
}

const SUM: ulong = ("a" + "b").length;
const SHOWN: ulong = $"n{1}{true}".length;
const ITEMS: ulong = count_of([1, 2, 3]);
const LISTED: ulong = [1, 2].count;
const MAP: ulong = ["k": 4].count;
const PAIR: (int, int) = (5, 6);
const MAYBE: int = Optional<int>.Value(7).value();
const RANGED: int = total(1..3);

main(): int {
    if ($"{SUM} {SHOWN} {ITEMS} {LISTED} {MAP} {PAIR.0}{PAIR.1} {MAYBE} {RANGED}" != "2 6 3 2 1 56 7 3") {
        return 1;
    }
    return 0;
}
