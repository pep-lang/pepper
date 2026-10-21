# A labeled tuple keeps its labels as a type argument (pepper#118): an
# element read back through `Array`, `Optional`, a `HashMap` value, a user
# generic, a trait, or a nesting of them answers to its labels, and so does
# what a static method or an enum case called on the labeled type gives
# (pepper#134), and so does a generic function's result (pepper#140). Two
# labelings of one tuple shape share a specialization, and each keeps its
# own labels.
trait Source<T> {
    take(): T;
}

struct Box<T> {
    var value: T;

    construct(value: T) {
        this.value = value;
    }

    static make(value: T): Box<T> {
        return Box<T>(value);
    }

    get(): T {
        return value;
    }

    get(fallback: T): T {
        return fallback;
    }

    take(): T {
        return value;
    }
}

extend Box<T> with Source<T> {}

identity<T>(value: T): T {
    return value;
}

repeat<T>(value: T): Array<T> {
    var out = Array<T>();
    out.append(value);
    return out;
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
    var o = Optional<(left: int, right: int)>.Value((left: 5, right: 6));
    var made = Box<(p: int, q: int)>.make((p: 9, q: 10));
    var empty = Optional<(left: int, right: int)>.Empty;
    if (o.value().right != 6 or made.get().q != 10 or empty.is_value()) {
        return 7;
    }
    if (Optional<(left: int, right: int)>.Value((left: 5, right: 6)).value().left != 5) {
        return 8;
    }
    var source: Source<(m: int, n: int)> = Box<(m: int, n: int)>((m: 13, n: 14));
    var taken = source.take();
    if (taken.n != 14) {
        return 9;
    }
    if (made.get((p: 11, q: 12)).q != 12) {
        return 11;
    }
    # A generic function's result takes the labels of its type arguments,
    # written or inferred (pepper#140).
    var same = identity<(a: int, b: int)>((a: 3, b: 4));
    var inferred = identity(same);
    var listed = repeat<(x: int, y: int)>((x: 1, y: 2));
    if (same.b != 4 or same.1 != 4 or inferred.a != 3 or listed[0].y != 2) {
        return 10;
    }
    if (identity<(a: int, b: int)>((a: 5, b: 6)).b != 6) {
        return 12;
    }
    return 0;
}
