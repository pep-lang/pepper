# A labeled tuple keeps its labels as a type argument (pepper#118): an
# element read back through `Array`, `Optional`, a `HashMap` value, a user
# generic, or a nesting of them answers to its labels. Two labelings of one
# tuple shape share a specialization, and each keeps its own labels.
struct Box<T> {
    var value: T;

    construct(value: T) {
        this.value = value;
    }

    get(): T {
        return value;
    }
}

first(entries: Array<(name: String, count: int)>): int {
    return entries[0].count;
}

total(entries: (name: String, count: int)[]): int {
    var sum = 0;
    for (var entry in entries) {
        sum += entry.count;
    }
    return sum;
}

main(): int {
    var entries = Array<(name: String, count: int)>();
    entries.append((name: "a", count: 3));
    entries.append((name: "b", count: 4));
    if (first(entries) != 3 or total(entries) != 7 or entries[1].name != "b") {
        return 1;
    }
    var points: (x: int, y: int)[] = [(x: 1, y: 2)];
    var spans = Array<(start: int, end: int)>();
    spans.append((start: 5, end: 9));
    if (points[0].y != 2 or spans[0].end != 9) {
        return 2;
    }
    var maybe: (left: int, right: int)? = Optional<(left: int, right: int)>.Value((left: 5, right: 6));
    if (maybe.value().right != 6) {
        return 3;
    }
    var ranges = HashMap<String, (low: int, high: int)>();
    ranges["k"] = (low: 7, high: 8);
    if (ranges["k"].high != 8 or ranges.try_get("k").value().low != 7) {
        return 4;
    }
    var box = Box<(p: int, q: int)>((p: 9, q: 10));
    if (box.value.q != 10 or box.get().p != 9) {
        return 5;
    }
    var nested = Array<Box<(u: int, v: int)>?>();
    nested.append(Optional<Box<(u: int, v: int)>>.Value(Box<(u: int, v: int)>((u: 11, v: 12))));
    if (nested[0].value().get().v != 12) {
        return 6;
    }
    return 0;
}
